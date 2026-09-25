## Regression test: lore -> quest objective bridges.
##
## Before this fix only KILL objectives could advance: the TALK bridge
## (dialogue_ended) and the COLLECT bridge (item_picked_up) did not
## exist, so "The Awakening" (the game's first quest, a TALK objective)
## and the daily herb run (COLLECT) were permanently stuck.
##
## Run: godot --headless --path . --script res://tests/test_quest_lore_bridges.gd

extends SceneTree

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root_node := get_root()
	var qs = root_node.get_node_or_null("QuestService")
	var ds = root_node.get_node_or_null("DialogService")
	var eh = root_node.get_node_or_null("EventHub")
	if qs == null:
		_fail("QuestService autoload missing")
		_finish()
		return
	_ok("QuestService autoload present")
	if ds == null:
		_fail("DialogService autoload missing")
		_finish()
		return
	if eh == null or not eh.has_signal("item_picked_up"):
		_fail("EventHub.item_picked_up missing")
		_finish()
		return
	_ok("DialogService + EventHub.item_picked_up present")

	# Bridges connected at _ready.
	if not ds.dialogue_ended.is_connected(qs._on_dialogue_ended_for_quest):
		_fail("TALK bridge not connected")
	else:
		_ok("TALK bridge connected (dialogue_ended)")
	if not eh.item_picked_up.is_connected(qs._on_item_picked_up_for_quest):
		_fail("COLLECT bridge not connected")
	else:
		_ok("COLLECT bridge connected (item_picked_up)")

	# --- TALK: The Awakening, the game's first quest ---
	var pid := "lore_bridge_tester"
	var qdata = load("res://data/quests/quest_main_awakening.tres")
	if qdata == null:
		_fail("quest_main_awakening.tres failed to load")
		_finish()
		return
	qs._player_quests[pid] = {
		"quest_main_awakening": {
			"quest_id": "quest_main_awakening",
			"state": qs.QuestData.QuestState.IN_PROGRESS,
			"objectives": [
				{"id": "talk_elder", "type": qs.QuestData.ObjectiveType.TALK,
				 "target": "npc_village_elder", "current": 0, "required": 1,
				 "completed": false}
			]
		}
	}
	# dialogue_ended carries the NPCData id -- quest targets author the
	# same npc_ id verbatim, so the bridge credits it directly.
	ds.dialogue_ended.emit("npc_village_elder", "village_elder_greeting")
	var state: Dictionary = qs._player_quests[pid]["quest_main_awakening"]
	var obj: Dictionary = state["objectives"][0]
	if obj["completed"]:
		_ok("TALK: Awakening objective completed via dialogue_ended")
	else:
		_fail("TALK: objective not ticked (current=%d)" % int(obj["current"]))

	# Wrong npc must NOT tick a completed objective or another target.
	ds.dialogue_ended.emit("npc_alchemist", "alchemist_greeting")
	if obj["current"] == 1:
		_ok("TALK: unrelated npc does not over-tick")
	else:
		_fail("TALK: over-tick from unrelated npc")

	# --- COLLECT: daily herb gathering ---
	var cdata = load("res://data/quests/quest_herb_gathering.tres")
	if cdata == null:
		_fail("quest_herb_gathering.tres failed to load")
		_finish()
		return
	qs._player_quests[pid]["quest_herb_gathering"] = {
		"quest_id": "quest_herb_gathering",
		"state": qs.QuestData.QuestState.IN_PROGRESS,
		"objectives": [
			{"id": "collect_herbs", "type": qs.QuestData.ObjectiveType.COLLECT,
			 "target": "Moonpetal Flower", "current": 0, "required": 2,
			 "completed": false}
		]
	}
	# item_picked_up(entity, item) -- use real schema objects so the
	# property lookups behave exactly like the live path.
	var fake_player = load("res://core/entities/entity.gd").new()
	fake_player.entity_id = pid
	var fake_item = load("res://core/schemas/item.gd").new()
	fake_item.display_name = "Moonpetal Flower"
	eh.item_picked_up.emit(fake_player, fake_item)
	eh.item_picked_up.emit(fake_player, fake_item)
	var cstate: Dictionary = qs._player_quests[pid]["quest_herb_gathering"]
	var cobj: Dictionary = cstate["objectives"][0]
	if cobj["completed"] and int(cobj["current"]) == 2:
		_ok("COLLECT: herb objective completed after 2 pickups")
	else:
		_fail("COLLECT: not ticked (current=%d)" % int(cobj["current"]))
	# Different item must not tick.
	var other_item = load("res://core/schemas/item.gd").new()
	other_item.display_name = "Iron Ore"
	eh.item_picked_up.emit(fake_player, other_item)
	if int(cobj["current"]) == 2:
		_ok("COLLECT: unrelated item does not over-tick")
	else:
		_fail("COLLECT: over-tick from unrelated item")
	# Entity/Item are RefCounted -- no manual free; let GC collect.

	_finish()

func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] ", msg)

func _fail(msg: String) -> void:
	_failed += 1
	print("  [FAIL] ", msg)

func _finish() -> void:
	print("--- QUEST LORE BRIDGES: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
