## Coverage gate: every achievement `target_type` authored in
## game/data/achievements/*.tres must be FED by some call site in game/
## (an AchievementService.track / unlock_event category literal). An
## authored category with no producer is a dead achievement: the player
## can do the deed and never see the counter move -- the achievement half
## of the quest dead-counter bug (test_quest_bridge_coverage.gd).
##
## Born 2026-11-29 alongside the quest coverage gate. The two services
## share the same failure shape: a string-keyed category/target that only
## data declares and only code can credit. A silent typo in either half
## (data "enemey", code "kill_streakh") is invisible until someone notices
## the achievement never fires.
##
## Producers are found by a paren-balanced scan of every .gd call site
## (tests excluded) -- nested calls like track(pid, "glide_distance",
## int(float(x))) must still be seen, so a naive "last literal" read would
## miss them.
##
## Run: godot --headless --path . --script res://tests/test_achievement_trigger_coverage.gd

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
	print("--- ACHIEVEMENT TRIGGER COVERAGE: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


## Every distinct target_type the achievement data authors (empty skipped:
## an empty target_type is a direct-unlock def, not a tracked category).
func _authored_types() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open("res://data/achievements")
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	var re := RegEx.new()
	re.compile("target_type\\s*=\\s*\"([a-z_][a-z0-9_]*)\"")
	while f != "":
		if f.ends_with(".tres"):
			var txt := FileAccess.get_file_as_string("res://data/achievements/" + f)
			for m in re.search_all(txt):
				out[m.get_string(1)] = true
		f = dir.get_next()
	return out


## Every string-literal category named in an achievement-feed call site.
## Walk every .gd under res:// (tests excluded) and, at each track/
## unlock_event call, read the paren-balanced argument window and collect
## its bare lowercase string literals.
func _produced_types() -> Dictionary:
	var out: Dictionary = {}
	var call_re := RegEx.new()
	call_re.compile("(?:AchievementService|\\bach\\b)\\.(?:track|unlock_event)\\s*\\(|(?:^|[^A-Za-z0-9_])(?:track|unlock_event|_track_event|_do_unlock_event)\\s*\\(")
	var lit_re := RegEx.new()
	lit_re.compile("\"([a-z_][a-z0-9_]*)\"")
	var files: Array = []
	_collect_gd("res://", files)
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		for m in call_re.search_all(src):
			var i: int = m.get_end()
			var depth := 1
			var buf := ""
			while i < src.length() and depth > 0:
				var c := src[i]
				if c == "(":
					depth += 1
				elif c == ")":
					depth -= 1
					if depth == 0:
						break
				buf += c
				i += 1
			for lm in lit_re.search_all(buf):
				out[lm.get_string(1)] = true
	return out


## Recursively collect .gd files, skipping the tests dir (a test that calls
## track() must not stand in as a producer of a category no game code feeds).
func _collect_gd(dir_path: String, acc: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if dir.current_is_dir():
			if f != "." and f != ".." and f != "tests":
				_collect_gd(dir_path.path_join(f), acc)
		elif f.ends_with(".gd"):
			acc.append(dir_path.path_join(f))
		f = dir.get_next()


func _run() -> void:
	print("--- ACHIEVEMENT TRIGGER COVERAGE ---")

	var authored := _authored_types()
	if authored.is_empty():
		_fail("no achievement target_types found in game/data/achievements")
		_finish()
		return
	var authored_names: Array = authored.keys()
	authored_names.sort()
	_ok("achievement data authors %d target_types: %s" % [authored_names.size(), ", ".join(authored_names)])

	var produced := _produced_types()

	# Floor: the scanner must have seen the real feed sites. If the call
	# pattern ever changes, `produced` could come back empty and the leg
	# below would pass vacuously -- this makes that loud instead.
	var floor := ["enemy", "item", "quest", "zone", "chat"]
	var missing_floor: Array = []
	for name in floor:
		if not produced.has(name):
			missing_floor.append(name)
	if missing_floor.is_empty():
		_ok("core feed categories present (enemy/item/quest/zone/chat)")
	else:
		_fail("core feed categories missing from the scan (parser drift?): %s" % ", ".join(missing_floor))

	var orphans: Array = []
	for name in authored_names:
		if not produced.has(name):
			orphans.append(name)
	if orphans.is_empty():
		_ok("every authored target_type is fed by a game call site")
	else:
		_fail("authored target_types with NO producer (dead achievements): %s" % ", ".join(orphans))

	var unfed: Array = []
	var produced_names: Array = produced.keys()
	produced_names.sort()
	for name in produced_names:
		if not authored.has(name):
			unfed.append(name)
	if not unfed.is_empty():
		print("  [info] fed categories with no achievement def: ", ", ".join(unfed))

	_finish()
