## Regression test: the swim credit bridge (the Glow Cistern's law).
##
## OceanService emits water_entered exactly once per dry -> wet entry
## with the ocean volume's data id; QuestService swims that signal into
## SWIM objectives whose target is the ocean_ id verbatim. Before this
## bridge the underworld's cistern had water and a quest, but no one
## could ever credit the crossing.
##
## Data contract under test: quest_cross_the_cistern.tres targets
## ocean_deep_root_pool (SWIM) and npc_deep_warden (TALK turn-in).
##
## Run: godot --headless --path . --script res://tests/test_quest_swim_bridge.gd

extends SceneTree

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root_node := get_root()
	var qs = root_node.get_node_or_null("QuestService")
	var ocean = root_node.get_node_or_null("OceanService")
	if qs == null:
		_fail("QuestService autoload missing")
		_finish()
		return
	if ocean == null:
		_fail("OceanService autoload missing")
		_finish()
		return
	_ok("QuestService + OceanService autoloads present")

	# The connect is DEFERRED (OceanService is a later autoload; the
	# insight-bridge pattern) -- wait one flush before asserting.
	await process_frame
	if ocean.water_entered.is_connected(qs._on_water_entered_for_quest):
		_ok("SWIM bridge connected (water_entered)")
	else:
		_fail("SWIM bridge not connected")
		_finish()
		return

	# --- The .tres shape: one-id law, no candidate fallbacks -----------
	var qdata = load("res://data/quests/quest_cross_the_cistern.tres")
	if qdata == null:
		_fail("quest_cross_the_cistern.tres failed to load")
		_finish()
		return
	var objs: Array = qdata.objectives
	if objs.size() == 2:
		var swim_obj: Dictionary = objs[0]
		var talk_obj: Dictionary = objs[1]
		var swim_shape: bool = int(swim_obj.get("type", -1)) == qs.QuestData.ObjectiveType.SWIM \
			and str(swim_obj.get("target", "")) == "ocean_deep_root_pool" \
			and int(swim_obj.get("count", 0)) == 1
		_ok("SWIM objective targets ocean_deep_root_pool verbatim" if swim_shape \
			else "SWIM objective shape wrong: %s" % str(swim_obj))
		if not swim_shape:
			_failed += 1
		var talk_shape: bool = int(talk_obj.get("type", -1)) == qs.QuestData.ObjectiveType.TALK \
			and str(talk_obj.get("target", "")) == "npc_deep_warden"
		_ok("TALK turn-in targets the Warden verbatim" if talk_shape \
			else "TALK objective shape wrong: %s" % str(talk_obj))
		if not talk_shape:
			_failed += 1
	else:
		_fail("quest has %d objectives, expected 2" % objs.size())

	# --- The real accept path ---------------------------------------
	# quest_cross_the_cistern chains off quest_listen_to_the_deep, so seed the
	# prerequisite as turned in -- otherwise the (correct) chain gate refuses.
	var pid := "swim_bridge_tester"
	qs.load_player_quests(pid)
	qs._player_quests[pid]["quest_listen_to_the_deep"] = {
		"state": qs.QuestData.QuestState.REWARDED,
		"objectives": [],
		"data": load("res://data/quests/quest_listen_to_the_deep.tres")
	}
	if not qs.accept_quest(pid, "quest_cross_the_cistern"):
		_fail("the Warden's swim quest did not accept")
		_finish()
		return
	_ok("quest_cross_the_cistern accepts")

	# --- The crossing credits through the LIVE tick -----------------
	ocean.forget_swimmer(pid)
	# Standing in the dish below the waterline (the cistern's floor 2000,
	# surface 2002.4 -- a body at 2000.8 is 1.6 m down, SUBMERGED).
	var r: Dictionary = ocean.tick_swimmer(pid, Vector3(12, 2000.8, 0), 1.0 / 60.0)
	if r.has("state"):
		_ok("the cistern tick reads as water (state=%d)" % int(r["state"]))
	else:
		_fail("the cistern tick returned nothing")
	var prog: Dictionary = qs.get_quest_progress(pid, "quest_cross_the_cistern")
	var swim_current := -1
	for o in (prog.get("objectives", []) as Array):
		if str(o.get("id", "")) == "swim_the_pool":
			swim_current = int(o.get("current", 0))
	if swim_current == 1:
		_ok("one water_entered ticked the SWIM objective 1/1")
	else:
		_fail("SWIM objective current=%d, expected 1" % swim_current)

	# Frames of water after the entry emit NOTHING (the book holds the
	# credit flag: a pool crossing is 1, not 60).
	for i in range(10):
		ocean.tick_swimmer(pid, Vector3(12, 2000.8, 0), 1.0 / 60.0)
	prog = qs.get_quest_progress(pid, "quest_cross_the_cistern")
	var steady := -1
	for o in (prog.get("objectives", []) as Array):
		if str(o.get("id", "")) == "swim_the_pool":
			steady = int(o.get("current", 0))
	if steady == 1:
		_ok("10 more water frames do not over-tick")
	else:
		_fail("over-tick from steady water (current=%d)" % steady)

	# A DIFFERENT volume's entry must not credit the cistern target: a
	# fresh swimmer ticks ONLY the Haven Shelf and stays dry of credit.
	var pid2 := "shelf_only_swimmer"
	qs.load_player_quests(pid2)
	if qs.accept_quest(pid2, "quest_cross_the_cistern"):
		ocean.forget_swimmer(pid2)
		ocean.tick_swimmer(pid2, Vector3(3000, -10.0, 0), 1.0 / 60.0)
		var dry: Dictionary = qs.get_quest_progress(pid2, "quest_cross_the_cistern")
		var shelf_current := -1
		var swim_complete := false
		for o in (dry.get("objectives", []) as Array):
			if str(o.get("id", "")) == "swim_the_pool":
				shelf_current = int(o.get("current", 0))
				swim_complete = bool(o.get("completed", false))
		if shelf_current == 0 and not swim_complete:
			_ok("the Haven Shelf stays out of the cistern's count")
		else:
			_fail("cross-volume credit leaked (current=%d)" % shelf_current)

	# --- The turn-in: TALK closes the quest (COMPLETE) ---------------
	qs._on_dialogue_ended_for_quest("npc_deep_warden", "deep_warden_greeting")
	var final: Dictionary = qs.get_quest_progress(pid, "quest_cross_the_cistern")
	if int(final.get("state", -1)) == qs.QuestData.QuestState.COMPLETE:
		_ok("swim + report close the quest (COMPLETE)")
	else:
		_fail("quest not COMPLETE after the turn-in (state=%d)" % int(final.get("state", -1)))

	ocean.forget_swimmer(pid)
	_finish()

func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] ", msg)

func _fail(msg: String) -> void:
	_failed += 1
	print("  [FAIL] ", msg)

func _finish() -> void:
	print("--- QUEST SWIM BRIDGE: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
