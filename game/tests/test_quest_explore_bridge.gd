## Regression test: EXPLORE quest bridge (player_entered_zone).
##
## "The Old Roads" (main_teachings) is the first EXPLORE-objective
## quest; before this bridge EXPLORE could never advance -- same
## failure class as the TALK/COLLECT gap fixed in
## test_quest_lore_bridges.gd. The bridge must credit zone entry
## under BOTH id conventions (ZoneData id "zone_starter_plains" and
## the species/faction convention "starter_plains"), and must not
## tick for unrelated zones.
##
## Run: godot --headless --path . --script res://tests/test_quest_explore_bridge.gd

extends SceneTree

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root_node := get_root()
	var qs = root_node.get_node_or_null("QuestService")
	var zm = root_node.get_node_or_null("ZoneManager")
	if qs == null:
		_fail("QuestService autoload missing")
		_finish()
		return
	if zm == null or not zm.has_signal("player_entered_zone"):
		_fail("ZoneManager.player_entered_zone missing")
		_finish()
		return
	_ok("QuestService + ZoneManager.player_entered_zone present")

	if not zm.player_entered_zone.is_connected(qs._on_player_entered_zone_for_quest):
		_fail("EXPLORE bridge not connected")
		_finish()
		return
	_ok("EXPLORE bridge connected (player_entered_zone)")

	var qdata = load("res://data/quests/main_teachings.tres")
	if qdata == null:
		_fail("main_teachings.tres failed to load")
		_finish()
		return
	_ok("main_teachings.tres loads (target=%s count=%d)" % [
		str(qdata.objectives[0]["target"]), int(qdata.objectives[0]["count"])])

	# Seed an in-progress Old Roads state exactly as the live accept
	# path would hold it (trimmed-convention target from the .tres).
	var pid := "explore_bridge_tester"
	qs._player_quests[pid] = {
		"main_teachings": {
			"quest_id": "main_teachings",
			"state": qs.QuestData.QuestState.IN_PROGRESS,
			"objectives": [
				{"id": "wake_waypoints", "type": qs.QuestData.ObjectiveType.EXPLORE,
				 "target": "starter_plains", "current": 0, "required": 3,
				 "completed": false}
			]
		}
	}

	# Real ZoneData so the .get("id") path behaves like the live emit.
	var zone = load("res://data/zones/zone_starter_plains.tres")
	var fake_player = load("res://core/entities/entity.gd").new()
	fake_player.entity_id = pid

	# Enter, leave, re-enter x3 (walking the old roads). ZoneData id is
	# "zone_starter_plains"; the bridge must credit the trimmed form.
	for i in range(3):
		zm.player_entered_zone.emit(fake_player, zone)
	var obj: Dictionary = qs._player_quests[pid]["main_teachings"]["objectives"][0]
	if obj["completed"] and int(obj["current"]) == 3:
		_ok("EXPLORE: 3 zone entries completed the trimmed target")
	else:
		_fail("EXPLORE: not completed (current=%d)" % int(obj["current"]))

	# Unrelated zone must not over-tick.
	var other = load("res://data/zones/zone_forest_meadow.tres")
	zm.player_entered_zone.emit(fake_player, other)
	if int(obj["current"]) == 3:
		_ok("EXPLORE: unrelated zone does not over-tick")
	else:
		_fail("EXPLORE: over-tick from unrelated zone")

	# A ZoneData-less payload must not crash the bridge.
	zm.player_entered_zone.emit(fake_player, null)
	_ok("EXPLORE: null zone payload tolerated")

	# Entity is RefCounted -- no manual free; let GC collect.
	_finish()

func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] ", msg)

func _fail(msg: String) -> void:
	_failed += 1
	print("  [FAIL] ", msg)

func _finish() -> void:
	print("--- QUEST EXPLORE BRIDGE: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
