## Coverage gate: every quest objective TYPE used in game/data/quests/*.tres
## must have a live bridge in QuestService -- a call site that reaches
## update_quest_progress for that ObjectiveType. An unwired type is a dead
## counter a player can never advance, so authoring one must fail here
## rather than ship a silent dead end.
##
## Born from the 2026-11-29 drift: prd-quests.md still read "the remaining 7
## types have NO bridge" while the code had already wired RECORD_INSIGHT
## (11), SWIM (12) and GLIDE (13) alongside KILL/COLLECT/TALK/EXPLORE. This
## freezes the real invariant -- data types is a subset of bridged types --
## and also asserts the wired set stays honest (a bridge being deleted is
## caught by the coverage leg; the display-text switch does not count as a
## bridge).
##
## Run: godot --headless --path . --script res://tests/test_quest_bridge_coverage.gd

extends SceneTree

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	call_deferred("_run")

func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] ", msg)

func _fail(msg: String) -> void:
	_failed += 1
	print("  [FAIL] ", msg)

func _finish() -> void:
	print("--- QUEST BRIDGE COVERAGE: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


## ObjectiveType members in declaration order (index == enum value).
func _enum_members() -> Array:
	var out: Array = []
	var src := FileAccess.get_file_as_string("res://core/schemas/quest_data.gd")
	var start := src.find("enum ObjectiveType {")
	if start < 0:
		return out
	var body := src.substr(start)
	var close := body.find("}")
	if close >= 0:
		body = body.substr(0, close)
	for line in body.split("\n"):
		var t := line.strip_edges()
		if t.is_empty():
			continue
		var name := t.split("#")[0].strip_edges().trim_suffix(",")
		if name.is_empty() or name.contains("{") or name.contains("}") or name.contains(" "):
			continue
		if name == "enum":
			continue
		out.append(name)
	return out


## Every ObjectiveType the quest data actually authors.
func _data_types() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open("res://data/quests")
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var txt := FileAccess.get_file_as_string("res://data/quests/" + f)
			var re := RegEx.new()
			re.compile("\\\"type\\\"\\s*:\\s*([0-9]+)")
			for m in re.search_all(txt):
				out[int(m.get_string(1))] = true
		f = dir.get_next()
	return out


## ObjectiveTypes with a live bridge: a QuestService reference to the enum
## member that sits BEFORE the display-text switch. The `match obj_type:`
## block is presentation, not a credit path, so everything from it onward is
## excluded -- otherwise every type would look "wired" just by being printed.
func _wired_types() -> Dictionary:
	var out: Dictionary = {}
	var src := FileAccess.get_file_as_string("res://core/services/quest_service.gd")
	var cut := src.find("match obj_type:")
	var wiring := src if cut < 0 else src.substr(0, cut)
	for member in _enum_members():
		if wiring.contains("ObjectiveType.%s" % member):
			out[member] = true
	return out


func _run() -> void:
	print("--- QUEST BRIDGE COVERAGE ---")
	var members := _enum_members()
	if members.is_empty():
		_fail("could not parse the ObjectiveType enum from quest_data.gd")
		_finish()
		return
	_ok("ObjectiveType enum parsed (%d members)" % members.size())

	var data := _data_types()
	var used_names: Array = []
	for t in data:
		if t < 0 or t >= members.size():
			_fail("quest data uses objective type %d, outside the enum (0..%d)" % [t, members.size() - 1])
			continue
		used_names.append(members[t])
	used_names.sort()
	_ok("quest data uses %d objective types: %s" % [used_names.size(), ", ".join(used_names)])

	var wired := _wired_types()
	var wired_names: Array = []
	for name in wired:
		wired_names.append(name)
	wired_names.sort()
	_ok("QuestService bridges %d objective types: %s" % [wired_names.size(), ", ".join(wired_names)])

	# Floor: the heuristic must have seen the real wiring. If the cut marker
	# ever moves, `wiring` could match nothing and the coverage leg below
	# would pass vacuously -- this makes that failure loud instead.
	var floor := ["KILL", "COLLECT", "TALK", "EXPLORE"]
	var missing_floor: Array = []
	for name in floor:
		if not wired.has(name):
			missing_floor.append(name)
	if missing_floor.is_empty():
		_ok("core bridges present (KILL/COLLECT/TALK/EXPLORE)")
	else:
		_fail("core bridges missing from QuestService wiring: %s" % ", ".join(missing_floor))

	var uncovered: Array = []
	for name in used_names:
		if not wired.has(name):
			uncovered.append(name)
	if uncovered.is_empty():
		_ok("every objective type used in data has a live bridge")
	else:
		_fail("objective types used in data with NO bridge: %s" % ", ".join(uncovered))

	var unused: Array = []
	for name in wired_names:
		if not used_names.has(name):
			unused.append(name)
	if not unused.is_empty():
		print("  [info] bridged but unused by data: ", ", ".join(unused))

	_finish()
