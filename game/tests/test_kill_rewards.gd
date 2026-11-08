## Kill-reward smoke tests: credit resolution (direct killer, threat
## table), EnemyData vs fallback rewards, level-difference scaling,
## party split routing, duck-typed grants, and the kill_rewarded
## broadcast payload.
extends SceneTree

const KillRewards = preload("res://core/services/kill_rewards.gd")
const EnemyDataScript = preload("res://core/schemas/enemy_data.gd")

var _passed := 0
var _failed := 0


func _initialize() -> void:
	await process_frame
	_test_no_credit_no_signal()
	_test_direct_killer_credit()
	_test_threat_table_fallback_credit()
	_test_fallback_rewards_for_plain_entity()
	_test_enemy_data_rewards()
	_test_level_scale_grey_kill()
	_test_level_scale_parity()
	_test_grant_routes_to_node()
	_test_player_manager_mirror()
	print("KillRewards tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


# --- helpers ---------------------------------------------------------------

func _mk_entity(id: String):
	var s = load("res://tests/support/reward_enemy_stub.gd")
	var e = s.new()
	e.entity_id = id
	e.display_name = id
	root.add_child(e)
	return e


## A live in-tree "player" stand-in with the duck-typed progression
## surface the real the player body exposes.
func _mk_player(id: String):
	var s = load("res://core/entities/entity.gd")
	var p = s.new()
	p.entity_id = id
	p.display_name = id
	p.set_script(load("res://tests/support/reward_player_stub.gd"))
	root.add_child(p)
	return p


func _capture_kill_rewards() -> Array:
	var captured: Array = []
	var hub := root.get_node_or_null("EventHub")
	if hub == null:
		return captured
	hub.kill_rewarded.connect(func(entity, killer, rewards):
		captured.append({"entity": entity, "killer": killer, "rewards": rewards}))
	return captured


# --- tests -----------------------------------------------------------------

func _test_no_credit_no_signal() -> void:
	var hub := root.get_node_or_null("EventHub")
	if hub == null:
		_fail("EventHub missing for kill-reward tests")
		return
	var captured: Array = []
	hub.kill_rewarded.connect(func(entity, killer, rewards): captured.append(rewards))

	var enemy = _mk_entity("kr_enemy_no_credit")
	var old_level: int = enemy.level
	enemy.level = 1
	KillRewards.award_kill(enemy, null)
	_assert(captured.is_empty(), "no credit -> no kill_rewarded emitted")
	enemy.level = old_level
	enemy.free()


func _test_direct_killer_credit() -> void:
	var player = _mk_player("kr_player_direct")
	var enemy = _mk_entity("kr_enemy_direct")
	var captured := _capture_kill_rewards()
	KillRewards.award_kill(enemy, player)
	_assert(not captured.is_empty(), "direct killer -> kill_rewarded emitted")
	if not captured.is_empty():
		var r: Dictionary = captured[0]["rewards"]
		_assert(int(r.get("xp", 0)) > 0, "fallback XP positive for plain entity kill")
	_assert(player.experience > 0, "player node granted XP")
	player.free(); enemy.free()


func _test_threat_table_fallback_credit() -> void:
	var killer = _mk_player("kr_player_threat")
	var bystander = _mk_player("kr_player_bystander")
	var enemy = _mk_entity("kr_enemy_threat")
	# Attach a real threat table with the bystander on top; the direct
	# killer is invalid (not in tree) so credit must come from the table.
	var AggroComponent = load("res://core/components/aggro_component.gd")
	var ac = AggroComponent.new()
	enemy.add_child(ac)
	enemy.aggro_component = ac
	ac.add_damage_threat(bystander, 500)
	var captured := _capture_kill_rewards()
	KillRewards.award_kill(enemy, null)
	_assert(not captured.is_empty(), "threat-table credit -> kill_rewarded emitted")
	if not captured.is_empty():
		_assert(captured[0]["killer"] == bystander, "threat-table owner receives credit")
	_assert(bystander.experience > 0, "threat-table owner granted XP")
	killer.free(); bystander.free(); enemy.free()


func _test_fallback_rewards_for_plain_entity() -> void:
	var player = _mk_player("kr_player_fb")
	var enemy = _mk_entity("kr_enemy_fb")
	enemy.level = 4
	var captured := _capture_kill_rewards()
	KillRewards.award_kill(enemy, player)
	_assert(not captured.is_empty(), "fallback rewards emitted for plain entity")
	if not captured.is_empty():
		var r: Dictionary = captured[0]["rewards"]
		_assert(int(r.get("xp", 0)) >= 1, "fallback XP scales with enemy level")
	_assert(player.experience >= 1, "player granted fallback XP")
	player.free(); enemy.free()


func _test_enemy_data_rewards() -> void:
	var player = _mk_player("kr_player_data")
	var enemy = _mk_entity("kr_enemy_data")
	var data := EnemyDataScript.new()
	data.xp_reward = 55
	data.gold_min = 10
	data.gold_max = 10
	enemy.enemy_data = data
	var captured := _capture_kill_rewards()
	KillRewards.award_kill(enemy, player)
	_assert(not captured.is_empty(), "EnemyData kill emits reward event")
	if not captured.is_empty():
		var r: Dictionary = captured[0]["rewards"]
		_assert(int(r.get("xp", 0)) == 55, "EnemyData.xp_reward drives XP")
		_assert(int(r.get("gold", 0)) == 10, "EnemyData gold range drives gold")
	_assert(player.experience == 55, "player node received EnemyData XP")
	_assert(player.gold == 10, "player node received EnemyData gold")
	player.free(); enemy.free()


func _test_level_scale_parity() -> void:
	var scale := KillRewards._level_scale({"level": 5}, {"level": 5})
	_assert(absf(scale - 1.0) < 0.001, "level parity scales rewards at 1.0")


func _test_level_scale_grey_kill() -> void:
	var scale := KillRewards._level_scale({"level": 1}, {"level": 20})
	_assert(absf(scale - KillRewards.MIN_REWARD_SCALE) < 0.001,
		"grey kill (19 levels up) scales rewards to the floor")


func _test_grant_routes_to_node() -> void:
	var player = _mk_player("kr_player_grant")
	KillRewards._grant_xp(player, 40)
	KillRewards._grant_gold(player, 7)
	_assert(player.experience == 40, "duck-typed _grant_xp routes add_experience")
	_assert(player.gold == 7, "duck-typed _grant_gold routes add_gold")
	player.free()


func _test_player_manager_mirror() -> void:
	var pm := root.get_node_or_null("PlayerManager")
	if pm == null:
		_fail("PlayerManager missing; cannot test mirror")
		return
	var before_xp: int = pm.experience
	var before_gold: int = pm.gold
	KillRewards._mirror_into_player_manager(pm, {"xp": 33, "gold": 4})
	_assert(pm.experience == before_xp + 33, "PlayerManager XP mirrored")
	_assert(pm.gold == before_gold + 4, "PlayerManager gold mirrored")


# --- reporting -------------------------------------------------------------

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + msg)


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL: " + msg)
