## Death progression-surface receipt: death penalties and kill-streak
## bonuses must move REAL XP/gold on the player node.
##
## The bug this locks: death_features.gd guarded its payout legs with
## has_method("get_xp"/"modify_xp"/"get_gold"/"modify_gold") -- methods
## no class in the repo declares -- so the enabled kill-streak bonus
## (thresholds [3,5,10,25,50]) silently granted nothing, and death
## penalties never applied. The zone read guarded a nonexistent
## get_zone_id, so every death-history row carried an empty zone.
##
## Legs:
##   1. The phantom methods really are absent (the old guards were dead).
##   2. The penalty helpers move XP/gold and clamp at zero.
##   3. A real kill streak at threshold 3 pays 30 XP + 30 gold, and the
##      reward mirrors into PlayerManager (the HUD's XP source).
##   4. The zone id resolves through ZoneManager, not the entity.
##
## Run with:
##   godot --headless --path game/ --script res://tests/test_death_progression_surface.gd
extends SceneTree

var _passed: int = 0
var _failed: int = 0
var _death: Node


func _initialize() -> void:
	print("--- DEATH PROGRESSION SURFACE ---")
	await process_frame

	_death = root.get_node_or_null("DeathFeatures")
	if _death == null:
		_fail("DeathFeatures autoload missing")
		_finish()
		return

	_test_no_phantom_methods()
	_test_penalty_helpers_move_xp_gold()
	_test_streak_reward_grants_xp_gold()
	_test_zone_id_resolves()
	_finish()


## The old guards probed methods no class declares. If these ever start
## returning true the guard story changes and this receipt is stale.
func _test_no_phantom_methods() -> void:
	var p = _mk_player("death_receipt_phantom")
	_assert(not p.has_method("get_xp"), "player has no get_xp (old penalty guard was dead)")
	_assert(not p.has_method("modify_xp"), "player has no modify_xp (old penalty guard was dead)")
	_assert(not p.has_method("get_gold"), "player has no get_gold (old penalty guard was dead)")
	_assert(not p.has_method("modify_gold"), "player has no modify_gold (old streak guard was dead)")
	_assert(not p.has_method("get_zone_id"), "player has no get_zone_id (old zone read was dead)")
	p.queue_free()


## Penalty helpers move XP/gold through the real fields and clamp at 0.
func _test_penalty_helpers_move_xp_gold() -> void:
	var p = _mk_player("death_receipt_penalty")
	p.experience = 1000
	p.gold = 200

	var ok_xp: Variant = _death.call("_spend_xp", p, 150)
	_assert(ok_xp == true, "_spend_xp reports a real XP move")
	_assert(int(p.experience) == 850, "XP penalty applied (1000 -> 850)")

	var ok_gold: Variant = _death.call("_spend_gold", p, 50)
	_assert(ok_gold == true, "_spend_gold reports a real gold move")
	_assert(int(p.gold) == 150, "gold penalty applied (200 -> 150)")

	# Clamp: a penalty larger than the balance never goes negative.
	_death.call("_spend_xp", p, 999999)
	_assert(int(p.experience) == 0, "XP penalty clamps at zero")

	# The public entry point runs without error even when the config
	# gates are off (XP_LOSS_PERCENT default 0) -- it must not crash on
	# the phantom-method path.
	var result: Variant = _death.call("apply_death_penalties", p)
	_assert(result is Dictionary, "apply_death_penalties returns a penalty report")
	p.queue_free()

	# The signed mirror the penalty path uses for the local player:
	# a negative delta must reduce PlayerManager, not be dropped.
	var pm = root.get_node_or_null("PlayerManager")
	var lp = _mk_player("death_receipt_penalty_local")
	if pm != null:
		pm.set_local_player(lp)
		pm.experience = 500
		pm.gold = 300
		_death.call("_mirror_progress_to_player_manager", lp, -150, -75)
		_assert(int(pm.experience) == 350, "signed mirror reduces PlayerManager XP (500 -> 350)")
		_assert(int(pm.gold) == 225, "signed mirror reduces PlayerManager gold (300 -> 225)")
		pm.set_local_player(null)
	lp.queue_free()


## A real streak at threshold 3 pays 30 XP + 30 gold (3 * 0.1 * 100 and
## 3 * 10) and mirrors into PlayerManager.
func _test_streak_reward_grants_xp_gold() -> void:
	var es = root.get_node_or_null("EntityService")
	var pm = root.get_node_or_null("PlayerManager")
	if es == null or pm == null:
		_fail("EntityService/PlayerManager autoload missing for streak leg")
		return

	var killer = _mk_player("death_receipt_killer")
	es.register_entity(killer, null, "death_receipt_killer")
	pm.set_local_player(killer)

	var pm_xp_before: int = int(pm.experience)
	var pm_gold_before: int = int(pm.gold)

	_death._kill_streaks.clear()
	_death.record_kill_for_streak("death_receipt_killer", "victim")
	_death.record_kill_for_streak("death_receipt_killer", "victim")
	_death.record_kill_for_streak("death_receipt_killer", "victim")

	_assert(int(killer.experience) == 30, "streak-3 bonus grants 30 XP to the killer node")
	_assert(int(killer.gold) == 30, "streak-3 bonus grants 30 gold to the killer node")
	# The streak-3 achievement (a separate reward system) also pays 10
	# gold into PlayerManager, so the mirror delta is >= the streak bonus.
	_assert(int(pm.experience) - pm_xp_before >= 30, "streak XP mirrors into PlayerManager")
	_assert(int(pm.gold) - pm_gold_before >= 30, "streak gold mirrors into PlayerManager")

	pm.set_local_player(null)
	killer.queue_free()


## The death-record zone resolves through ZoneManager's entity->zone map.
func _test_zone_id_resolves() -> void:
	var zm = root.get_node_or_null("ZoneManager")
	if zm == null:
		_fail("ZoneManager autoload missing for zone leg")
		return

	var e = _mk_player("death_receipt_zone")
	zm._entity_zones[e.entity_id] = "zone_receipt"
	var zid: Variant = _death.call("_zone_id_of", e)
	_assert(zid == "zone_receipt", "death zone id resolves from ZoneManager")
	e.queue_free()


# --- helpers ---------------------------------------------------------------

func _mk_player(id: String):
	var p = load("res://tests/support/reward_player_stub.gd").new()
	p.entity_id = id
	p.display_name = id
	root.add_child(p)
	return p


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [OK] %s" % msg)
	else:
		_failed += 1
		printerr("  [FAIL] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _finish() -> void:
	print("--- DEATH PROGRESSION SURFACE: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
