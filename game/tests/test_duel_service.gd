## DuelService tests.
## Covers: challenge lifecycle (challenge/accept/decline), duel flag
## stamping on both participants, no-loot death resolution, concede,
## out-of-range break, and pending-challenge replacement.
extends SceneTree

## Runtime load() -- see test_loot_rules.gd note on parse-time preload
## of autoload-referencing scripts in --script mode.
var _svc_script: GDScript = null

var _passed := 0
var _failed := 0


func _initialize() -> void:
	await process_frame
	_svc_script = load("res://core/services/duel_service.gd")
	_test_challenge_and_accept_stamps_flags()
	_test_decline()
	_test_no_pending_challenge()
	_test_rechallenge_replaces()
	_test_resolve_duel_death_ends_duel_and_clears_flags()
	_test_concede()
	_test_out_of_range_break()
	_test_in_duel_and_opponent_helpers()
	print("DuelService tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


# --- helpers ---------------------------------------------------------------

func _mk_svc() -> Node:
	var svc = _svc_script.new()
	root.add_child(svc)
	# Disable _process sweeps so time-based expiry does not race tests.
	svc.set_process(false)
	return svc


func _mk_player(id: String):
	var p = load("res://tests/support/reward_player_stub.gd").new()
	p.entity_id = id
	p.display_name = id
	root.add_child(p)
	return p


# --- tests -----------------------------------------------------------------

func _test_challenge_and_accept_stamps_flags() -> void:
	var svc := _mk_svc()
	var a = _mk_player("duel_a")
	var b = _mk_player("duel_b")
	svc.register_player(a)
	svc.register_player(b)

	var ch: String = svc.challenge_duel("duel_a", "duel_b")
	_assert(ch != "", "challenge creates a pending challenge")
	_assert(svc.is_in_duel("duel_a") == false, "no duel until accepted")

	var duel_id: String = svc.accept_duel("duel_b")
	_assert(duel_id != "", "accept starts a duel")
	_assert(svc.is_in_duel("duel_a") and svc.is_in_duel("duel_b"), "both duelists flagged in-duel")
	_assert(bool(a.get_meta("_duel_death")), "challenger stamped with _duel_death")
	_assert(bool(b.get_meta("_duel_death")), "challenger stamped with _duel_death")
	_assert(svc.get_duel_opponent("duel_a") == "duel_b", "opponent lookup correct")
	svc.free()
	a.free()
	b.free()


func _test_decline() -> void:
	var svc := _mk_svc()
	var a = _mk_player("dec_a")
	var b = _mk_player("dec_b")
	svc.register_player(a)
	svc.register_player(b)
	svc.challenge_duel("dec_a", "dec_b")
	_assert(svc.decline_duel("dec_b"), "decline returns true when a challenge exists")
	_assert(svc.accept_duel("dec_b") == "", "declined challenge cannot be accepted")
	_assert(not svc.is_in_duel("dec_a"), "declined -> no duel")
	svc.free()
	a.free()
	b.free()


func _test_no_pending_challenge() -> void:
	var svc := _mk_svc()
	var a = _mk_player("np_a")
	svc.register_player(a)
	_assert(svc.accept_duel("np_a") == "", "accept with nothing pending fails")
	_assert(svc.decline_duel("np_a") == false, "decline with nothing pending fails")
	_assert(svc.challenge_duel("np_a", "np_a") == "", "self-challenge rejected")
	svc.free()
	a.free()


func _test_rechallenge_replaces() -> void:
	var svc := _mk_svc()
	var a = _mk_player("rch_a")
	var b = _mk_player("rch_b")
	svc.register_player(a)
	svc.register_player(b)
	var first: String = svc.challenge_duel("rch_a", "rch_b")
	var second: String = svc.challenge_duel("rch_a", "rch_b")
	_assert(first != "" and second != "", "re-challenges allowed")
	_assert(svc._pending_challenges.size() == 1, "re-challenge replaces the earlier one")
	svc.free()
	a.free()
	b.free()


func _test_resolve_duel_death_ends_duel_and_clears_flags() -> void:
	var svc := _mk_svc()
	var a = _mk_player("kil_a")
	var b = _mk_player("kil_b")
	svc.register_player(a)
	svc.register_player(b)
	svc.challenge_duel("kil_a", "kil_b")
	svc.accept_duel("kil_b")

	_assert(svc.resolve_duel_death("kil_b", "kil_a"), "death of a duelist resolves as duel kill")
	_assert(not svc.is_in_duel("kil_a") and not svc.is_in_duel("kil_b"), "duel over after death")
	_assert(not a.has_meta("_duel_death"), "winner flag cleared")
	_assert(not b.has_meta("_duel_death"), "loser flag cleared")
	_assert(not svc.resolve_duel_death("kil_a", "kil_b"), "second death is no longer a duel kill")
	svc.free()
	a.free()
	b.free()


func _test_concede() -> void:
	var svc := _mk_svc()
	var a = _mk_player("con_a")
	var b = _mk_player("con_b")
	svc.register_player(a)
	svc.register_player(b)
	svc.challenge_duel("con_a", "con_b")
	svc.accept_duel("con_b")
	_assert(svc.concede_duel("con_a"), "concede works for an active duelist")
	_assert(not svc.is_in_duel("con_a"), "duel over after concede")
	_assert(not svc.concede_duel("con_a"), "concede without a duel fails")
	svc.free()
	a.free()
	b.free()


func _test_out_of_range_break() -> void:
	var svc := _mk_svc()
	var a = _mk_player("rng_a")
	var b = _mk_player("rng_b")
	# reward_player_stub extends Node3D (position-based); place far apart.
	a.position = Vector3(0, 0, 0)
	b.position = Vector3(500, 0, 500)
	svc.register_player(a)
	svc.register_player(b)
	svc.challenge_duel("rng_a", "rng_b")
	svc.accept_duel("rng_b")
	# Drive the same sweep _process uses.
	var ended := {}
	svc.duel_ended.connect(func(did, w, l, reason): ended["reason"] = reason)
	svc._process(0.016)
	_assert(str(ended.get("reason", "")) == "out_of_range", "duel breaks when duelists separate")
	_assert(not svc.is_in_duel("rng_a"), "flags cleared after range break")
	svc.free()
	a.free()
	b.free()


func _test_in_duel_and_opponent_helpers() -> void:
	var svc := _mk_svc()
	var a = _mk_player("hlp_a")
	var b = _mk_player("hlp_b")
	svc.register_player(a)
	svc.register_player(b)
	_assert(svc.get_duel_opponent("hlp_a") == "", "no opponent before duel")
	svc.challenge_duel("hlp_a", "hlp_b")
	svc.accept_duel("hlp_b")
	_assert(svc.get_duel_opponent("hlp_a") == "hlp_b", "opponent A->B")
	_assert(svc.get_duel_opponent("hlp_b") == "hlp_a", "opponent B->A")
	svc.free()
	a.free()
	b.free()


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: %s" % msg)
		print("FAIL: %s" % msg)
