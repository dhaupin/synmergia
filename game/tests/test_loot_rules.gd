## Loot delegation + smart routing tests.
## Covers: party rule gates (FFA/ROUND_ROBIN/LEADER/MASTER_LOOTER),
## round-robin pointer advance on real pickups only, smart class
## routing for single-usable-member drops, guild locks, karma gates,
## and the credit-player-always-loots deadlock breaker.
extends SceneTree

## NOTE: runtime load(), not const preload(). Autoload-referencing
## service scripts fail to compile at parse time in --script mode
## (the autoload-identifier registry is not available that early);
## load() inside _initialize resolves them after the tree is live.
var _svc_script: GDScript = null

var _passed := 0
var _failed := 0


func _initialize() -> void:
	await process_frame
	_svc_script = load("res://core/services/loot_rules_service.gd")
	_test_ffa_is_open()
	_test_credit_player_always_loots()
	_test_outsider_blocked_under_leader_rule()
	_test_leader_rule_reserves_for_leader()
	_test_master_holds_but_class_route_overrides()
	_test_round_robin_rotates()
	_test_round_robin_does_not_advance_on_failed_attempt()
	_test_round_robin_advances_on_pickup()
	_test_guild_lock()
	_test_karma_gate()
	_test_build_enemy_drop_options()
	print("LootRules tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


# --- helpers ---------------------------------------------------------------

func _mk_svc() -> Node:
	var svc = _svc_script.new()
	root.add_child(svc)
	return svc


func _mk_party(party_id: String, leader_id: String, members: Array, rule: int) -> Dictionary:
	return {
		"party_id": party_id,
		"leader_id": leader_id,
		"members": members,
		"loot_rule": rule,
	}


func _mk_drop(drop_id: String, credit_id: String, items: Array = []) -> Dictionary:
	return {
		"id": drop_id,
		"credit_player_id": credit_id,
		"items": items,
		"owner_id": "",
	}


# --- tests -----------------------------------------------------------------

func _test_ffa_is_open() -> void:
	var svc := _mk_svc()
	svc._party_override["p1"] = _mk_party("party1", "p1", ["p1", "p2"], svc.Policy.FREE_FOR_ALL)
	var drop := _mk_drop("d1", "p1")
	_assert(svc.resolve_delegation(drop, "p2") == "", "FFA: any member may loot")
	_assert(svc.resolve_delegation(drop, "p9") == "", "FFA: even outsiders may loot (zone rules apply)")
	svc.queue_free()


func _test_credit_player_always_loots() -> void:
	var svc := _mk_svc()
	svc._party_override["p1"] = _mk_party("party1", "p1", ["p1", "p2"], svc.Policy.MASTER_LOOTER)
	var drop := _mk_drop("d2", "p1")
	_assert(svc.resolve_delegation(drop, "p1") == "", "credit player always loots their own kill")
	svc.queue_free()


func _test_outsider_blocked_under_leader_rule() -> void:
	var svc := _mk_svc()
	svc._party_override["p1"] = _mk_party("party1", "p1", ["p1", "p2"], svc.Policy.LEADER)
	var drop := _mk_drop("d3", "p1")
	_assert(svc.resolve_delegation(drop, "p2") != "", "non-leader member blocked under LEADER rule")
	_assert(svc.resolve_delegation(drop, "p1") == "", "leader loots")
	var outsider := _mk_drop("d4", "p1")
	_assert(svc.resolve_delegation(outsider, "p99") != "", "outsider blocked under LEADER rule")
	svc.queue_free()


func _test_leader_rule_reserves_for_leader() -> void:
	var svc := _mk_svc()
	svc._party_override["p1"] = _mk_party("party1", "p2", ["p1", "p2"], svc.Policy.LEADER)
	var drop := _mk_drop("d5", "p1")
	_assert(svc.resolve_delegation(drop, "p2") == "", "designated leader may loot")
	_assert(svc.resolve_delegation(drop, "p1") == "", "credit player (non-leader) may still loot own kill")
	svc.queue_free()


func _test_master_holds_but_class_route_overrides() -> void:
	var svc := _mk_svc()
	# All items class-locked to "warrior", warrior is a member, leader is not.
	var item = load("res://core/schemas/item.gd").new()
	item.required_class = "warrior"
	item.display_name = "Warrior Blade"
	svc._party_override["p1"] = _mk_party("party1", "p3", ["p1", "p2", "p3"], svc.Policy.MASTER_LOOTER)
	svc._class_override["p1"] = "warrior"
	svc._class_override["p2"] = "mage"
	svc._class_override["p3"] = "mage"
	var drop := _mk_drop("d6", "p1", [item])
	_assert(svc.resolve_delegation(drop, "p1") == "", "smart routing: sole usable member may loot")
	var drop2 := _mk_drop("d7", "p1", [item])
	_assert(svc.resolve_delegation(drop2, "p2") != "", "smart routing: wrong-class member blocked")
	# Universal item reverts to leader designation.
	var plain = load("res://core/schemas/item.gd").new()
	plain.required_class = ""
	plain.display_name = "Plain Rock"
	var drop3 := _mk_drop("d8", "p1", [plain])
	_assert(svc.resolve_delegation(drop3, "p3") == "", "universal item -> leader (master) may loot")
	_assert(svc.resolve_delegation(drop3, "p1") == "", "universal item -> credit player still loots")
	svc.queue_free()


func _test_round_robin_rotates() -> void:
	var svc := _mk_svc()
	svc._party_override["p1"] = _mk_party("party1", "p1", ["p1", "p2", "p3"], svc.Policy.ROUND_ROBIN)
	var drop := _mk_drop("d9", "p1")
	_assert(svc.resolve_delegation(drop, "p1") == "", "round robin: pointer starts at first member (p1)")
	var drop2 := _mk_drop("d10", "p1")
	_assert(svc.resolve_delegation(drop2, "p2") != "", "round robin: second member blocked until their turn")
	var drop3 := _mk_drop("d11", "p1")
	_assert(svc.resolve_delegation(drop3, "p3") != "", "round robin: third member blocked until their turn")
	svc.queue_free()


func _test_round_robin_does_not_advance_on_failed_attempt() -> void:
	var svc := _mk_svc()
	svc._party_override["p1"] = _mk_party("party1", "p1", ["p1", "p2"], svc.Policy.ROUND_ROBIN)
	var drop := _mk_drop("d12", "p1")
	_assert(svc.resolve_delegation(drop, "p9") != "", "failed attempt blocked")
	var drop2 := _mk_drop("d13", "p1")
	_assert(svc.resolve_delegation(drop2, "p1") == "", "pointer did NOT advance on the failed attempt")
	svc.queue_free()


func _test_round_robin_advances_on_pickup() -> void:
	var svc := _mk_svc()
	svc._party_override["p1"] = _mk_party("party1", "p1", ["p1", "p2"], svc.Policy.ROUND_ROBIN)
	var drop := _mk_drop("d14", "p1")
	_assert(svc.resolve_delegation(drop, "p1") == "", "first turn: p1 (also the credit player)")
	# Simulate the actual pickup by the designated member. The pointer
	# must advance even when the picker is the credit player.
	svc._on_drop_picked_up("d14", _mk_pickup_node("p1"), [])
	var drop2 := _mk_drop("d15", "p1")
	_assert(svc.resolve_delegation(drop2, "p2") == "", "after p1 pickup: pointer advanced to p2")
	_assert(svc.resolve_delegation(_mk_drop("d15b", "p1"), "p3") != "", "p3 blocked until their turn")
	# Credit player remains allowed on their own kills (deadlock breaker).
	_assert(svc.resolve_delegation(_mk_drop("d15c", "p1"), "p1") == "", "credit player always loots own kill")
	svc.queue_free()


func _test_guild_lock() -> void:
	var svc := _mk_svc()
	var drop := _mk_drop("d17", "")
	drop["owner_id"] = "guild:avadon"
	drop["items"] = [load("res://core/schemas/item.gd").new()]
	svc._guild_override["p1"] = "avadon"
	svc._guild_override["p2"] = "rival"
	_assert(svc.resolve_delegation(drop, "p1") == "", "guild member may loot guild drop")
	_assert(svc.resolve_delegation(drop, "p2") != "", "non-member blocked from guild drop")
	_assert(svc.resolve_delegation(drop, "p3") != "", "unguilded player blocked from guild drop")
	svc.queue_free()


func _test_karma_gate() -> void:
	var svc := _mk_svc()
	var drop := _mk_drop("d18", "")
	drop["karma_min"] = 0
	svc.karma_lookup = func(player_id: String) -> int:
		return 50 if player_id == "honorable" else -200
	_assert(svc.resolve_delegation(drop, "honorable") == "", "high karma passes the gate")
	_assert(svc.resolve_delegation(drop, "villain") != "", "low karma blocked by the gate")
	var open_drop := _mk_drop("d19", "")
	_assert(svc.resolve_delegation(open_drop, "villain") == "", "no karma_min -> gate inactive")
	svc.queue_free()


func _test_build_enemy_drop_options() -> void:
	var svc := _mk_svc()
	var base := {"source": "enemy"}
	var opts: Dictionary = svc.build_enemy_drop_options("p1", base)
	_assert(str(opts.get("credit_player_id", "")) == "p1", "credit player stamped into options")
	_assert(str(opts.get("source", "")) == "enemy", "base options preserved")
	var empty_opts: Dictionary = svc.build_enemy_drop_options("", {})
	_assert(not empty_opts.has("credit_player_id"), "no credit -> no stamp")
	svc.queue_free()


func _mk_pickup_node(player_id: String):
	# Entity-based stub so entity_id is a real property (Node.set on an
	# undeclared key is a silent no-op, which would break the picker check).
	var node = _svc_script_new_entity_stub()
	node.entity_id = player_id
	root.add_child(node)
	return node


func _svc_script_new_entity_stub():
	var entity_script = load("res://tests/support/reward_enemy_stub.gd")
	var node = entity_script.new()
	return node


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: %s" % msg)
		print("FAIL: %s" % msg)
