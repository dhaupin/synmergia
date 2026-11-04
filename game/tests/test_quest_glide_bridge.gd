## Regression test: the glide credit bridge (the sky roads' law).
##
## ThermalService accrues glide distance per body (record_glide_tick,
## fed by the glider physics tick) and emits glide_distance_reached
## each time cumulative distance crosses a GLIDE_QUEST_STEP (300 m)
## boundary. QuestService bridges that signal into GLIDE objectives
## whose target is the literal "glide_distance".
##
## Data contract under test: quest_wings_over_haven.tres is a GLIDE
## objective (type 13) targeting "glide_distance" -- before this the
## quest authored a KILL objective with the descriptive target
## "glide 300 meters", which no credit path could ever satisfy.
##
## Run: godot --headless --path . --script res://tests/test_quest_glide_bridge.gd

extends SceneTree

var _passed: int = 0
var _failed: int = 0
var _milestones: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root_node := get_root()
	var qs = root_node.get_node_or_null("QuestService")
	var thermal = root_node.get_node_or_null("ThermalService")
	if qs == null:
		_fail("QuestService autoload missing")
		_finish()
		return
	if thermal == null:
		_fail("ThermalService autoload missing")
		_finish()
		return
	_ok("QuestService + ThermalService autoloads present")

	# The connect is DEFERRED (ThermalService is a later autoload; the
	# insight/swim-bridge pattern) -- wait one flush before asserting.
	await process_frame
	if thermal.glide_distance_reached.is_connected(qs._on_glide_distance_reached):
		_ok("GLIDE bridge connected (glide_distance_reached)")
	else:
		_fail("GLIDE bridge not connected")
		_finish()
		return

	# --- The .tres shape: one-id law, no descriptive targets --------------
	var qdata = load("res://data/quests/quest_wings_over_haven.tres")
	if qdata == null:
		_fail("quest_wings_over_haven.tres failed to load")
		_finish()
		return
	var objs: Array = qdata.objectives
	if objs.size() == 1:
		var obj: Dictionary = objs[0]
		var shape: bool = int(obj.get("type", -1)) == qs.QuestData.ObjectiveType.GLIDE \
			and str(obj.get("target", "")) == "glide_distance" \
			and int(obj.get("count", 0)) == 1
		_ok("GLIDE objective targets glide_distance verbatim" if shape \
			else "GLIDE objective shape wrong: %s" % str(obj))
		if not shape:
			_failed += 1
	else:
		_fail("quest_wings_over_haven has %d objectives, expected 1" % objs.size())

	# --- The milestone signal fires at the 300 m boundary -----------------
	thermal.glide_distance_reached.connect(_on_milestone)
	var watcher := "glide_probe"
	thermal._glide_stats.erase(watcher)
	thermal._glide_milestones.erase(watcher)
	# A sub-300 m glide must NOT fire the milestone (299 ticks of 1 m each).
	for i in range(299):
		thermal.record_glide_tick(watcher, 1.0, 40.0)
	if _milestones.is_empty():
		_ok("299 m of glide distance does not cross the 300 m milestone")
	else:
		_fail("milestone fired early: %s" % str(_milestones))
	# The 300th meter crosses it exactly once.
	thermal.record_glide_tick(watcher, 1.0, 40.0)
	if _milestones.size() == 1 and is_equal_approx(float(_milestones[0]), 300.0):
		_ok("the 300th meter fires glide_distance_reached once")
	else:
		_fail("milestone at 300 m wrong: %s" % str(_milestones))

	# --- The real accept + credit path -----------------------------------
	var pid := "glide_bridge_tester"
	qs.load_player_quests(pid)
	if not qs.accept_quest(pid, "quest_wings_over_haven"):
		_fail("Wings Over Haven did not accept")
		_finish()
		return
	_ok("quest_wings_over_haven accepts")
	thermal._glide_stats.erase(pid)
	thermal._glide_milestones.erase(pid)
	for i in range(300):
		thermal.record_glide_tick(pid, 1.0, 55.0)
	var prog: Dictionary = qs.get_quest_progress(pid, "quest_wings_over_haven")
	var current := -1
	for o in (prog.get("objectives", []) as Array):
		if str(o.get("id", "")) == "glide_distance":
			current = int(o.get("current", 0))
	if current == 1:
		_ok("300 m of glide ticked the GLIDE objective 1/1")
	else:
		_fail("GLIDE objective current=%d, expected 1" % current)

	# One objective completes the quest.
	if str(prog.get("state", "")) == str(qs.QuestData.QuestState.COMPLETE) \
			or int(prog.get("state", -1)) == qs.QuestData.QuestState.COMPLETE:
		_ok("the glide quest completes at the milestone")
	else:
		_fail("glide quest state after milestone: %s" % str(prog.get("state", "?")))

	# --- No over-tick: extra distance stays 1/1 ---------------------------
	for i in range(400):
		thermal.record_glide_tick(pid, 1.0, 55.0)
	prog = qs.get_quest_progress(pid, "quest_wings_over_haven")
	var steady := -1
	for o in (prog.get("objectives", []) as Array):
		if str(o.get("id", "")) == "glide_distance":
			steady = int(o.get("current", 0))
	if steady == 1:
		_ok("further glide distance does not over-tick the objective")
	else:
		_fail("over-tick from continued gliding (current=%d)" % steady)

	# --- The UI text renders the meter count ------------------------------
	var rendered: Array = qs._format_objectives_text(prog.get("objectives", []))
	var text_ok := false
	for line in rendered:
		if str(line).find("Glide:") >= 0 and str(line).find("1/1 m") >= 0:
			text_ok = true
	_ok("GLIDE objective renders as a glide line" if text_ok \
		else "GLIDE objective text wrong: %s" % str(rendered))

	_finish()

func _on_milestone(player_id: String, meters: float) -> void:
	if player_id == "glide_probe":
		_milestones.append(meters)

func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] %s" % msg)

func _fail(msg: String) -> void:
	_failed += 1
	print("  [FAIL] %s" % msg)

func _finish() -> void:
	print("RESULTS: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
