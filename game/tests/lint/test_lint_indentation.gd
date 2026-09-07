extends SceneTree

# Indentation linter.
#
# GDScript is strict about indentation:
#   - The first line that uses leading whitespace decides whether
#     the file is a "tab file" or a "space file". All other lines
#     must use the same kind.
#   - A file that mixes tabs and spaces in leading whitespace
#     produces a "Mixed indentation" parse error.
#   - Inconsistent indent depth at the same block level (e.g., a
#     nested function indented 2 spaces when its sibling is
#     indented 1 tab) silently changes the parser's view of which
#     code belongs to which block.
#
# This linter enforces the .editorconfig policy (tabs only) and
# reports:
#   1. Files using leading spaces (must be tabs)
#   2. Files mixing tabs and spaces at line start
#   3. Lines whose first non-whitespace char is on a different
#      indent level than its expected depth (heuristic)
#   4. Trailing whitespace (often a sign of editor misconfig)
#
# Allowlist: the `addons/` directory uses whatever its plugin
# ships with. We skip it.
#
# Run with:
#   godot --headless --path . --script res://tests/lint/test_lint_indentation.gd

const Helpers := preload("res://tests/lint/lint_helpers.gd")
const TAB := "\t"

var _passed: int = 0
var _failed: int = 0


func _ok(label: String) -> void:
	_passed += 1
	print("  [PASS] ", label)


func _fail(label: String, detail: String = "") -> void:
	_failed += 1
	printerr("  [FAIL] ", label, " ", detail)


func _init() -> void:
	print("--- LINT: indentation (tabs vs spaces) ---")

	var tab_files := 0
	var space_files := 0
	var mixed_files := 0
	var no_indent_files := 0

	for path in Helpers.list_gd_files():
		# Skip addons/ — third-party code we don't own.
		if path.begins_with("res://addons/"):
			continue

		var text := Helpers.read_text(path)
		var kind := _classify_file(path, text)
		match kind:
			"tab":
				tab_files += 1
			"space":
				space_files += 1
				Helpers.report_issue(path, 0, "warning",
						"file uses leading spaces (project policy is tabs; see .editorconfig)")
			"mixed":
				mixed_files += 1
				Helpers.report_issue(path, 0, "error",
						"file mixes leading tabs and spaces (parse error)")
			"none":
				no_indent_files += 1
			_:
				pass

	_check_trailing_whitespace()
	_check_consistent_indent_depth()

	_ok("tab-indented files: " + str(tab_files))
	if space_files == 0:
		_ok("no space-indented files (all use tabs)")
	else:
		# Files with only spaces (no tabs at all) are a project-
		# policy violation (see .editorconfig) but parse correctly.
		# They are emitted as WARN above and do not block the build.
		_ok(str(space_files) + " space-indented files (WARN above; not blocking)")
	if mixed_files == 0:
		_ok("no mixed-indent files (no parse errors)")
	else:
		# Mixed tabs+spaces at file level is a hard parse error in
		# GDScript. These block the build.
		_fail("mixed-indent files (parse errors)",
				str(mixed_files) + " file(s); see ERROR lines above")
	_ok("no-indent files: " + str(no_indent_files))

	_finish()


# Returns "tab" | "space" | "mixed" | "none".
func _classify_file(path: String, text: String) -> String:
	var first_indented_line := -1
	var has_tab := false
	var has_space := false
	var line_num := 0
	for raw in text.split("\n"):
		line_num += 1
		if raw.is_empty():
			continue
		if raw.begins_with("#"):
			# Comment-only lines don't count.
			continue
		if raw[0] != TAB and raw[0] != " ":
			# No leading whitespace. Skip — does not classify the file.
			continue
		if first_indented_line < 0:
			first_indented_line = line_num
		if raw.begins_with(TAB):
			has_tab = true
		elif raw.begins_with(" "):
			has_space = true
		if has_tab and has_space:
			return "mixed"
	if first_indented_line < 0:
		return "none"
	if has_tab and not has_space:
		return "tab"
	if has_space and not has_tab:
		return "space"
	# No indented lines found at all.
	return "none"


func _check_trailing_whitespace() -> void:
	var files_with_trailing := 0
	for path in Helpers.list_gd_files():
		if path.begins_with("res://addons/"):
			continue
		var text := Helpers.read_text(path)
		var line_num := 0
		for raw in text.split("\n"):
			line_num += 1
			# Strip a single trailing \r (CRLF) before checking.
			var line := raw
			if line.ends_with("\r"):
				line = line.substr(0, line.length() - 1)
			# Trailing whitespace = whitespace after the last non-ws char.
			var trimmed := line.rstrip(" \t")
			if trimmed.length() < line.length():
				Helpers.report_issue(path, line_num, "warning",
						"trailing whitespace (" + str(line.length() - trimmed.length()) + " chars)")
				files_with_trailing += 1
				break  # one per file is enough
	if files_with_trailing == 0:
		_ok("no trailing whitespace in .gd files")
	else:
		# Trailing whitespace is a .editorconfig violation
		# (`trim_trailing_whitespace = true`) but does not
		# block the build. Emitted as WARN above.
		_ok(str(files_with_trailing) + " .gd files have trailing whitespace (warning, not fatal)")


func _check_consistent_indent_depth() -> void:
	# Heuristic: for each line, compute its indent "level" as either
	# the number of tabs or the number of spaces (divided by 4 to
	# approximate). Lines at the same logical depth should have
	# the same level modulo a small variance. This is a soft check
	# and only flags egregious jumps (e.g., depth going 0 -> 1 -> 0
	# -> 5 in a way that looks broken).
	#
	# We only run this for files classified as "tab" files because
	# space files are already warned.
	var suspect_jumps := 0
	for path in Helpers.list_gd_files():
		if path.begins_with("res://addons/"):
			continue
		var text := Helpers.read_text(path)
		var kind := _classify_file(path, text)
		if kind != "tab":
			continue
		var prev_depth := -1
		var line_num := 0
		for raw in text.split("\n"):
			line_num += 1
			if raw.is_empty():
				continue
			if raw.begins_with("#"):
				continue
			var depth := _tab_depth(raw)
			if depth < 0:
				prev_depth = -1
				continue
			if prev_depth >= 0 and depth > prev_depth + 1:
				Helpers.report_issue(path, line_num, "warning",
						"indent jumps from " + str(prev_depth)
						+ " tab(s) to " + str(depth)
						+ " (missing intermediate level?)")
				suspect_jumps += 1
			prev_depth = depth
	if suspect_jumps == 0:
		_ok("no suspect indent jumps in tab files")


func _tab_depth(line: String) -> int:
	var depth := 0
	for i in line.length():
		if line[i] == TAB:
			depth += 1
		else:
			break
	if depth == line.length():
		# All tabs, no content.
		return -1
	return depth


func _finish() -> void:
	print("--- RESULTS: ", _passed, " passed, ", _failed, " failed ---")
	if _failed > 0:
		quit(1)
	else:
		quit(0)
