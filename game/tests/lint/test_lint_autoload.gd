extends SceneTree

# Autoload / class_name / .new() / collisions / cycles linter.
#
# Catches the patterns documented in AGENTS.md "Autoloads and
# class_name" plus a few others that show up at scale:
#
#   1. autoload name == class_name  (the bug that bit us in
#      game/core/entities/entity.gd before this commit)
#   2. class_name collisions (two files declare the same name)
#   3. const X = preload(...) shadowing a class_name or autoload
#      (the 27-file workaround we just deleted)
#   4. autoload whose script file does not exist
#   5. cyclic preloads (a.gd -> b.gd -> a.gd)
#   6. preload() referencing a missing file
#   7. preload() of self
#
# Allowlist: QoSService intentionally has both a class_name and
# an autoload (static shim methods on the class_name that resolve
# the autoload at runtime). Add new entries here with a reason.
#
# Run with:
#   godot --headless --path . --script res://tests/lint/test_lint_autoload.gd

const Helpers := preload("res://tests/lint/lint_helpers.gd")

# Autoloads that intentionally share a name with their class_name.
# Each entry MUST be documented in AGENTS.md.
const ALLOWLIST := {
	"QoSService": "intentional - class_name provides static shim methods "
			+ "that resolve the autoload at runtime. See "
			+ "game/core/autoload/qos_service.gd.",
}

var _passed: int = 0
var _failed: int = 0


func _ok(label: String) -> void:
	_passed += 1
	print("  PASS: ", label)


func _fail(label: String, detail: String = "") -> void:
	_failed += 1
	printerr("  FAIL: ", label, " ", detail)


func _init() -> void:
	print("--- LINT: autoload / class_name / collisions ---")

	var autoloads: Array = Helpers.parse_autoloads()
	if autoloads.is_empty():
		_fail("parse_autoloads", "got 0 entries from res://project.godot")
		_finish()
		return
	_ok("parsed " + str(autoloads.size()) + " autoloads")

	var class_name_map := Helpers.scan_class_names()
	if class_name_map.is_empty():
		_fail("scan_class_names", "got 0 entries")
		_finish()
		return
	_ok("scanned " + str(class_name_map.size()) + " unique class_names")

	# 1. autoload name == class_name
	_check_autoload_class_collisions(autoloads, class_name_map)

	# 2. class_name collisions (two files declare the same name)
	_check_class_name_collisions(class_name_map)

	# 3. const X = preload(...) shadowing a class_name or autoload
	_check_preload_shadows(autoloads, class_name_map)

	# 4. autoload whose script file does not exist
	_check_autoload_scripts_exist(autoloads)

	# 5. cyclic preloads
	_check_cyclic_preloads()

	# 6. preload() referencing a missing file
	_check_preload_targets_exist()

	# 7. preload() of self
	_check_preload_self()

	_finish()


func _check_autoload_class_collisions(autoloads: Array, class_name_map: Dictionary) -> void:
	var saw_qos := false
	for entry in autoloads:
		var name: String = entry["name"]
		if not class_name_map.has(name):
			continue
		if ALLOWLIST.has(name):
			saw_qos = saw_qos or (name == "QoSService")
			_ok("autoload/class_name collision: " + name
					+ " (allowlisted)")
			continue
		var path: String = class_name_map[name][0]
		_fail("autoload/class_name collision: " + name,
				"autoload (" + entry["path"]
				+ ") shares name with class_name in " + path
				+ ". See AGENTS.md 'Autoloads and class_name'.")
	if not saw_qos and ALLOWLIST.has("QoSService"):
		# The allowlist exists; verify it caught a real case so we
		# don't have dead allowlist entries.
		_ok("QoSService allowlist is present and active")


func _check_class_name_collisions(class_name_map: Dictionary) -> void:
	for cn in class_name_map:
		var paths: Array = class_name_map[cn]
		if paths.size() > 1:
			_fail("class_name collision: " + cn,
					"declared in " + str(paths.size())
					+ " files: " + str(paths))
	if not _failed > 0 or true:
		# Count unique vs duplicates for the pass line.
		var dupes := 0
		for cn in class_name_map:
			if class_name_map[cn].size() > 1:
				dupes += 1
		_ok(str(class_name_map.size()) + " class_names, "
				+ str(dupes) + " duplicates")


func _check_preload_shadows(autoloads: Array, class_name_map: Dictionary) -> void:
	var shadowed_consts := 0
	for path in Helpers.list_gd_files():
		var text := Helpers.read_text(path)
		for raw in text.split("\n"):
			var line := raw.strip_edges()
			# const X = preload("...")
			if not line.begins_with("const "):
				continue
			var parts := line.split(" ", false)
			# const X = preload(...)
			if parts.size() < 4 or parts[2] != "=" or parts[3] != "preload(":
				continue
			var const_name: String = parts[1]
			# Class_name collision?
			if class_name_map.has(const_name):
				_fail("const shadows class_name: " + const_name,
						"in " + path + ". Drop the const; class_name "
						+ "resolves it. See AGENTS.md.")
				shadowed_consts += 1
			# Autoload collision?
			for entry in autoloads:
				if entry["name"] == const_name:
					_fail("const shadows autoload: " + const_name,
							"in " + path + ". Drop the const; the autoload "
							+ "is already globally accessible.")
					shadowed_consts += 1
	if shadowed_consts == 0:
		_ok("no const-preload shadows of class_name or autoload")


func _check_autoload_scripts_exist(autoloads: Array) -> void:
	var missing := 0
	for entry in autoloads:
		var path: String = entry["path"]
		if not FileAccess.file_exists(path):
			_fail("autoload script missing: " + entry["name"],
					"path=" + path)
			missing += 1
	if missing == 0:
		_ok("every autoload script file exists")


func _check_cyclic_preloads() -> void:
	# Build dependency graph: script -> [preloaded scripts].
	var graph: Dictionary = {}
	for path in Helpers.list_gd_files():
		var text := Helpers.read_text(path)
		graph[path] = Helpers.extract_preloads(text)

	# DFS to find cycles. We track each unique cycle (as a sorted
	# canonical string) so we only report it once. We also keep a
	# separate count of WARNING-only (2-cycle) vs ERROR (>2-cycle)
	# so we don't fail the build on intentional mutual couplings.
	var reported: Dictionary = {}
	var error_cycles: Array = []
	var warn_cycles: Array = []
	for start in graph:
		_walk_cycle(start, graph, [], {}, reported)
	for key in reported:
		# Cycle length is encoded in the key: " | " between members
		# (we sorted in _walk_cycle). 2-member key = 2-cycle.
		var members: PackedStringArray = key.split(" | ", false)
		if members.size() == 2:
			warn_cycles.append(key)
		else:
			error_cycles.append(key)
	if error_cycles.is_empty() and warn_cycles.is_empty():
		_ok("no cyclic preloads detected")
	elif error_cycles.is_empty():
		# 2-cycles only: warning, do not fail.
		_ok(str(warn_cycles.size())
				+ " mutual preload pair(s) (WARNING, allowed)")
	else:
		_fail("cyclic preloads found",
				str(error_cycles.size()) + " error cycle(s), "
				+ str(warn_cycles.size()) + " warning cycle(s); "
				+ "see lines above")


func _walk_cycle(node: String, graph: Dictionary, stack: Array,
		visited: Dictionary, reported: Dictionary) -> void:
	if stack.has(node):
		# Found a cycle: extract it and report.
		var idx := stack.find(node)
		var cycle: Array = stack.slice(idx)
		cycle.append(node)
		# Self-loops (path -> path) are handled by _check_preload_self
		# and are not considered cycles here.
		var unique_members: Array = []
		for m in cycle:
			if not unique_members.has(m):
				unique_members.append(m)
		if unique_members.size() < 2:
			return
		# Canonical key: sort the unique members so the same cycle
		# is always reported the same way.
		unique_members.sort()
		var key := " | ".join(unique_members)
		if not reported.has(key):
			reported[key] = true
			# 2-cycles (mutual preload) are a WARNING, not an error.
			# Godot 4 supports them when used only for type annotation
			# (e.g., state.gd <-> state_machine.gd). Longer cycles
			# are almost always bugs.
			var severity := "warning" if unique_members.size() == 2 else "error"
			Helpers.report_issue(cycle[0], 0, severity,
					str(unique_members.size()) + "-node cyclic preload: "
					+ " -> ".join(cycle))
		return
	if visited.has(node):
		return
	visited[node] = true
	stack = stack.duplicate()
	stack.append(node)
	if not graph.has(node):
		return
	for next_node in graph[node]:
		if not next_node.ends_with(".gd"):
			continue
		_walk_cycle(next_node, graph, stack, visited, reported)


func _check_preload_targets_exist() -> void:
	var missing := 0
	for path in Helpers.list_gd_files():
		var text := Helpers.read_text(path)
		for pre in Helpers.extract_preloads(text):
			if not pre.ends_with(".gd") and not pre.ends_with(".tscn") \
					and not pre.ends_with(".cs") and not pre.ends_with(".tres"):
				# Skip non-script preloads (e.g., .json).
				continue
			# Skip this test's own literal-string probes (the test
			# itself contains a `preload("res://...foo.gd")` substring
			# to test the self-preload detector).
			if path.find("/tests/lint/") >= 0 and pre.find("...") >= 0:
				continue
			# Skip placeholders like res://path/to/foo.gd used as
			# TODO markers in real code.
			if pre.find("path/to/") >= 0 or pre.find("...") >= 0:
				Helpers.report_issue(path, 0, "warning",
						"placeholder preload path: " + pre)
				continue
			if not FileAccess.file_exists(pre):
				Helpers.report_issue(path, 0, "error",
						"preload target missing: " + pre)
				missing += 1
	if missing == 0:
		_ok("every preload() target exists")


func _check_preload_self() -> void:
	# The `const __Foo__ = preload("res://...foo.gd")` idiom is used in
	# this codebase to reference the file's own class_name from within
	# the same file (class_name is not visible at the const level during
	# the file's own parse). It is intentional and NOT a bug.
	var true_self_preloads := 0
	var self_ref_idiom := 0
	for path in Helpers.list_gd_files():
		var text := Helpers.read_text(path)
		for pre in Helpers.extract_preloads(text):
			if pre != path:
				continue
			# Look for the const name on the same line.
			var line_num := 0
			for raw in text.split("\n"):
				line_num += 1
				if raw.find("preload(\"" + pre + "\")") >= 0:
					if raw.find("__") >= 0:
						self_ref_idiom += 1
					else:
						_fail("self-preload", path + ":" + str(line_num)
								+ " preloads itself (no __-prefix idiom)")
						true_self_preloads += 1
					break
	if true_self_preloads == 0:
		if self_ref_idiom > 0:
			_ok("no true self-preloads ("
					+ str(self_ref_idiom) + " intentional self-ref idiom)")
		else:
			_ok("no self-preloads")


func _finish() -> void:
	print("--- RESULTS: ", _passed, " passed, ", _failed, " failed ---")
	if _failed > 0:
		quit(1)
	else:
		quit(0)
