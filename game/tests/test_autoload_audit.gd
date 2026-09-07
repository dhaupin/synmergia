extends SceneTree

# Autoload vs class_name audit.
#
# Rule: if a script is registered as an autoload AND has a class_name
# with the same name, you cannot call .new() on it (the autoload is a
# Node instance, not a Script). The fix is to either:
#   (a) Remove the autoload registration (if nothing uses it as a
#       singleton), OR
#   (b) Drop the class_name (if you need the autoload as a singleton).
#
# This test scans project.godot + the codebase and reports every
# autoload whose class_name is also defined.
#
# Allowlist: QoSService is an intentional exception. It has both a
# class_name and an autoload, but uses static methods that resolve
# the autoload at runtime via singleton(). Documented in AGENTS.md.
#
# Run with:
#   godot --headless --path . --script res://tests/test_autoload_audit.gd

var _passed: int = 0
var _failed: int = 0

# Autoloads that intentionally have a same-named class_name. Each
# entry should be documented in AGENTS.md with a clear reason.
const ALLOWLIST := {
	"QoSService": "intentional - class_name provides static shim methods "
			+ "that resolve the autoload at runtime. See "
			+ "game/core/autoload/qos_service.gd.",
}


func _ok(label: String, suffix: String = "", count: String = "") -> void:
	_passed += 1
	print("  PASS: ", label, " ", count, " ", suffix)


func _fail(label: String, detail: String = "") -> void:
	_failed += 1
	printerr("  FAIL: ", label, " ", detail)


func _init() -> void:
	print("--- AUTOLOAD vs class_name AUDIT ---")

	var autoloads := _parse_autoloads("res://project.godot")
	if autoloads.is_empty():
		_fail("parse project.godot", "no autoloads found")
		_finish()
		return
	_ok("parsed project.godot (" + str(autoloads.size()) + " autoloads)")

	var class_names := _build_class_name_map()
	_ok("scanned class_name declarations (" + str(class_names.size()) + " classes)")

	# For each autoload, check if the same name has a class_name.
	# If so, ensure it's in the allowlist.
	for autoload_name in autoloads:
		if not class_names.has(autoload_name):
			continue
		if ALLOWLIST.has(autoload_name):
			_ok(autoload_name + " (allowlisted: " + ALLOWLIST[autoload_name] + ")")
		else:
			_fail(autoload_name,
					"is BOTH an autoload AND a class_name. "
					+ "Either remove the autoload (if no singleton use) or "
					+ "drop the class_name (if singleton use is needed). "
					+ "Add to ALLOWLIST only with a documented reason.")

	# Bonus check: every class_name should be instantiable. If a class_name
	# shadows an autoload and someone calls .new() on it, that fails.
	# This is a static check; we cannot detect .new() calls here, but
	# we can report which class_names are in the danger zone.
	print("--- danger zone (class_name == autoload_name) ---")
	for autoload_name in autoloads:
		if class_names.has(autoload_name):
			print("  * ", autoload_name, " -> ", class_names[autoload_name])
	print("--- end danger zone ---")

	_finish()


# Returns { autoload_name: script_path }.
func _parse_autoloads(path: String) -> Dictionary:
	var out: Dictionary = {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var in_section := false
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			in_section = (line == "[autoload]")
			continue
		if not in_section or line.is_empty() or line.begins_with("#"):
			continue
		# Format: Name="*res://path.gd"  (the * marks a singleton)
		var eq := line.find("=")
		if eq < 0:
			continue
		var name := line.substr(0, eq).strip_edges()
		var val := line.substr(eq + 1).strip_edges()
		# Strip quotes
		if val.begins_with("\"") and val.ends_with("\""):
			val = val.substr(1, val.length() - 2)
		out[name] = val
	f.close()
	return out


# Returns { class_name: script_path } by scanning every .gd under res://.
func _build_class_name_map() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open("res://")
	if dir == null:
		return out
	_scan_dir(dir, out)
	return out


func _scan_dir(dir: DirAccess, out: Dictionary) -> void:
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
				_scan_dir(sub, out)
		elif entry.ends_with(".gd"):
			_extract_class_name(path, out)
		entry = dir.get_next()
	dir.list_dir_end()


func _extract_class_name(path: String, out: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	# First 20 lines should be enough to find the class_name.
	var lines_read := 0
	while not f.eof_reached() and lines_read < 20:
		var line := f.get_line().strip_edges()
		lines_read += 1
		if line.begins_with("class_name "):
			# class_name Foo
			# class_name Foo extends Bar
			var parts := line.split(" ", false)
			if parts.size() >= 2:
				out[parts[1]] = path
			break
	f.close()


func _finish() -> void:
	print("--- RESULTS: ", _passed, " passed, ", _failed, " failed ---")
	if _failed > 0:
		quit(1)
	else:
		quit(0)
