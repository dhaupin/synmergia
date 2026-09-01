## test_auto_response_signals.gd
## Verifies AutoResponseService emits action_taken and player_warned signals
## and that NotificationService is reachable from the same tree.
##
## Run with:
##   tools/godot --headless --path synmergia --script res://tests/test_auto_response_signals.gd
extends SceneTree

var _passed: int = 0
var _failed: int = 0
var _ars: Node
var _notif: Node


func _initialize() -> void:
	print("--- AUTO RESPONSE SIGNAL TEST ---")
	await process_frame

	_ars = root.get_node_or_null("AutoResponseService")
	if not _ars:
		_fail("AutoResponseService autoload missing")
		_finish()
		return
	_ok("AutoResponseService autoload present")

	_notif = root.get_node_or_null("NotificationService")
	if not _notif:
		_fail("NotificationService autoload missing (signal wiring cannot be verified)")
		_finish()
		return
	_ok("NotificationService autoload present (signal wiring target reachable)")

	_test_action_types_enum()
	_test_player_warned_on_first_spam()
	_test_action_taken_on_mute()
	_test_action_taken_on_ban()
	_test_action_taken_on_kick()
	_test_action_taken_signal_emits_without_crash()

	_finish()


func _test_action_types_enum() -> void:
	var values: Array = _ars.ActionType.values()
	if values.size() < 4:
		_fail("ActionType enum has %d values, expected at least 4 (WARN, MUTE, RESTRICT, KICK, BAN)" % values.size())
		return
	_ok("ActionType enum has %d values" % values.size())


func _test_player_warned_on_first_spam() -> void:
	var captured: Array = []
	_ars.player_warned.connect(
		func(player_id: String, exploit_type: String, message: String) -> void:
			captured.append({"player_id": player_id, "exploit_type": exploit_type, "message": message})
	)

	# _handle_spam(count=1) emits player_warned.
	_ars._handle_spam("p_test_warn", 1)
	if captured.size() != 1:
		_fail("player_warned should fire once on first spam, got %d" % captured.size())
		return
	if captured[0]["exploit_type"] != "spam":
		_fail("player_warned exploit_type should be 'spam', got '%s'" % captured[0]["exploit_type"])
		return
	_ok("player_warned fires on first spam (exploit_type=spam)")


func _test_action_taken_on_mute() -> void:
	var captured: Array = []
	_ars.action_taken.connect(
		func(player_id: String, action: int, exploit_type: String, reason: String) -> void:
			captured.append({"player_id": player_id, "action": action, "exploit_type": exploit_type, "reason": reason})
	)

	# _handle_spam(count>=2) emits action_taken with MUTE.
	_ars._handle_spam("p_test_mute", 5)
	var mute_found := false
	for entry in captured:
		if entry["action"] == _ars.ActionType.MUTE and entry["exploit_type"] == "spam":
			mute_found = true
			break
	if not mute_found:
		_fail("action_taken should fire with MUTE/spam on second+ spam offense")
		return
	_ok("action_taken fires with MUTE on second spam offense")


func _test_action_taken_on_ban() -> void:
	var captured: Array = []
	_ars.action_taken.connect(
		func(player_id: String, action: int, exploit_type: String, reason: String) -> void:
			captured.append({"action": action, "exploit_type": exploit_type, "reason": reason})
	)

	# _auto_ban always emits action_taken(BAN, exploit_type).
	_ars._auto_ban("p_test_ban", "test ban reason", "test_exploit")
	if captured.size() != 1:
		_fail("_auto_ban should emit action_taken once, got %d" % captured.size())
		return
	if captured[0]["action"] != _ars.ActionType.BAN:
		_fail("_auto_ban action should be BAN, got %d" % captured[0]["action"])
		return
	if captured[0]["exploit_type"] != "test_exploit":
		_fail("_auto_ban exploit_type should pass through, got '%s'" % captured[0]["exploit_type"])
		return
	_ok("_auto_ban emits action_taken(BAN, exploit_type=passed through)")


func _test_action_taken_on_kick() -> void:
	var captured: Array = []
	_ars.action_taken.connect(
		func(player_id: String, action: int, exploit_type: String, reason: String) -> void:
			if action == _ars.ActionType.KICK:
				captured.append({"exploit_type": exploit_type, "reason": reason})
	)
	_ars._auto_kick("p_test_kick", "test kick reason", "kick_exploit")
	if captured.size() != 1:
		_fail("_auto_kick should emit action_taken(KICK), got %d" % captured.size())
		return
	if captured[0]["exploit_type"] != "kick_exploit":
		_fail("_auto_kick exploit_type should pass through")
		return
	_ok("_auto_kick emits action_taken(KICK, exploit_type=passed through)")


func _test_action_taken_signal_emits_without_crash() -> void:
	# Smoke: emit a synthetic action_taken and ensure it propagates without
	# raising. Verifies the signal is observable to listeners (e.g. admin UI).
	var fired := [false]
	_ars.action_taken.connect(
		func(player_id: String, action: int, exploit_type: String, reason: String) -> void:
			fired[0] = true
	)
	_ars.action_taken.emit("p_smoke", _ars.ActionType.WARN, "smoke", "wiring check")
	if not fired[0]:
		_fail("action_taken.emit() did not propagate to listener")
		return
	_ok("action_taken.emit() propagates to listeners")


func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _finish() -> void:
	print("--- AUTO RESPONSE SIGNAL TEST: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
