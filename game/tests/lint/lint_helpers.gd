extends RefCounted
class_name LintHelpers

# Shared utilities for static linter tests in tests/lint/.
#
# These tests run under `godot --headless --script res://tests/lint/...`
# with no autoloads. They scan .gd / .tscn / .godot files for common
# issues that the GDScript parser catches only at full project compile
# time. The goal is to surface those issues WITHOUT booting the
# project, so they can be run in CI without a working build.
#
# Conventions used by all lint tests:
# - Each test is a self-contained `extends SceneTree` script.
# - Each test prints "PASS: <name>" / "FAIL: <name>" lines.
# - Each test exits 0 on success, 1 on failure.
# - Each test lists issues with the format:
#     <file>:<line>: <severity>: <message>
# - Issues at warning severity do not fail the test by default;
#   each test has a list of patterns it considers fatal.

# Read a text file. Returns "" if missing.
static func read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


# Read a file as bytes. Returns PackedByteArray() if missing.
static func read_bytes(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return bytes


# List every .gd file under res://, recursively.
# Returns Array[String] of res:// paths.
static func list_gd_files(root: String = "res://") -> Array:
	var out: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	_list_gd_recursive(dir, out)
	return out


static func _list_gd_recursive(dir: DirAccess, out: Array) -> void:
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var path := dir.get_current_dir().path_join(entry)
		if dir.current_is_dir():
			var sub := DirAccess.open(path)
			if sub != null:
				_list_gd_recursive(sub, out)
		elif entry.ends_with(".gd"):
			out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()


# List every .tscn file under res://.
static func list_tscn_files(root: String = "res://") -> Array:
	var out: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	_list_ext_recursive(dir, out, ".tscn")
	return out


static func _list_ext_recursive(dir: DirAccess, out: Array, ext: String) -> void:
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var path := dir.get_current_dir().path_join(entry)
		if dir.current_is_dir():
			var sub := DirAccess.open(path)
			if sub != null:
				_list_ext_recursive(sub, out, ext)
		elif entry.ends_with(ext):
			out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()


# Parse a project.godot-ish [section] file. Returns Dictionary:
#   { "<section>": { "<key>": "<value>", ... }, ... }
# Comments (#) and blank lines are skipped. Keys are lowercased
# for stable lookups; section names are kept as-is (between brackets).
static func parse_ini_file(path: String) -> Dictionary:
	var out: Dictionary = {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var section := ""
	while not f.eof_reached():
		var raw := f.get_line()
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with(";"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			if not out.has(section):
				out[section] = {}
			continue
		if section == "":
			continue
		var eq := line.find("=")
		if eq < 0:
			continue
		var key := line.substr(0, eq).strip_edges()
		var val := line.substr(eq + 1).strip_edges()
		out[section][key] = val
	f.close()
	return out


# Parse the autoload list from project.godot.
# Returns Array of {name, path, is_singleton}.
static func parse_autoloads(project_path: String = "res://project.godot") -> Array:
	var out: Array = []
	var ini := parse_ini_file(project_path)
	if not ini.has("autoload"):
		return out
	for key in ini["autoload"]:
		var val: String = ini["autoload"][key]
		# Values are typically wrapped in double quotes. Strip those
		# first; the singleton marker is INSIDE the quotes.
		if val.begins_with("\"") and val.ends_with("\""):
			val = val.substr(1, val.length() - 2)
		# "*res://path.gd" marks a singleton (autoload). Bare "res://..."
		# is also valid: a non-singleton autoload whose script is instanced.
		var is_singleton := false
		if val.begins_with("*"):
			is_singleton = true
			val = val.substr(1)
		out.append({"name": key, "path": val, "is_singleton": is_singleton})
	return out


# Extract class_name declarations from a script's first 40 lines.
# Returns the class_name (String) or "" if none.
static func extract_class_name(text: String) -> String:
	# Find the first class_name declaration in the file.
	# Godot 4 allows it anywhere, but the project style (per
	# AGENTS.md) is: `extends X` then `class_name Y` (or just
	# `class_name Y` first if no parent). We scan up to the first
	# non-comment executable block (skipping a leading docstring
	# block of `## ...` lines) to keep the search bounded.
	#
	# Note: order is checked separately by
	# first_declaration_kind() and the syntax linter. This helper
	# just needs to return whatever class_name is declared.
	var lines := text.split("\n")
	var saw_executable := false
	for raw in lines:
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with("##"):
			continue
		if line.begins_with("class_name "):
			var parts := line.split(" ", false)
			if parts.size() >= 2:
				return parts[1]
			return ""
		# If we see a `const`/`var`/`func`/`enum` between extends and
		# class_name, keep looking -- those are not "real" code, they
		# are just data declarations.
		if line.begins_with("extends ") or line.begins_with("const ") \
				or line.begins_with("var ") or line.begins_with("enum "):
			saw_executable = true
			continue
		if line.begins_with("func ") or line.begins_with("signal ") \
				or line.begins_with("static "):
			# Real code; class_name would have had to be above.
			if saw_executable:
				return ""
			continue
		# Anything else (decorator, @onready, etc.) -- keep scanning.
		continue
	return ""


# Detect whether a script's first executable line is "extends X"
# or "class_name X". Returns "extends", "class_name", or "".
static func first_declaration_kind(text: String) -> String:
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with("##"):
			continue
		if line.begins_with("extends "):
			return "extends"
		if line.begins_with("class_name "):
			return "class_name"
		return ""
	return ""


# Build { class_name: [script_path, ...] } for the whole codebase.
# Multiple files declaring the same class_name is a collision.
static func scan_class_names(root: String = "res://") -> Dictionary:
	var out: Dictionary = {}
	for path in list_gd_files(root):
		var text := read_text(path)
		var cn := extract_class_name(text)
		if cn == "":
			continue
		if not out.has(cn):
			out[cn] = []
		out[cn].append(path)
	return out


# Find all `preload("res://...")` references in a script body.
# Returns Array[String] of res:// paths.
static func extract_preloads(text: String) -> Array:
	var out: Array = []
	# Naive but good-enough scan: any preload("...") literal.
	# We don't try to skip comments or strings, which can produce
	# false positives (e.g., preload("...") inside a string), but
	# the cost is one extra file probe, not a crash.
	var i := 0
	while i < text.length():
		var idx := text.find("preload(", i)
		if idx < 0:
			break
		var start_quote := idx + "preload(".length()
		if start_quote >= text.length():
			break
		var quote_char := text[start_quote]
		if quote_char != "\"" and quote_char != "'":
			i = idx + 1
			continue
		var end_quote := text.find(quote_char, start_quote + 1)
		if end_quote < 0:
			break
		var path := text.substr(start_quote + 1, end_quote - start_quote - 1)
		out.append(path)
		i = end_quote + 1
	return out


# Issue printer used by the lint tests. Keeps a uniform format.
# `kind` is one of: "error" | "warning" | "info".
static func report_issue(file: String, line: int, kind: String, message: String) -> void:
	var prefix := ""
	match kind:
		"error":
			prefix = "  ERROR"
		"warning":
			prefix = "  WARN "
		"info":
			prefix = "  INFO "
		_:
			prefix = "  ?    "
	var where := file
	if line > 0:
		where += ":" + str(line)
	print(prefix + " " + where + ": " + message)


# Tab character used in all "tab-based" indentation tests.
const TAB := "\t"
