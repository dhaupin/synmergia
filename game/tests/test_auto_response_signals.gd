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
	_test_auto_kick_toasts_player_via_frame()
	_test_auto_mute_toasts_player_via_frame()
	_test_admin_alert_routes_through_frame()

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


func _test_auto_kick_toasts_player_via_frame() -> void:
	# When AutoResponseService auto-kicks a player, the player should
	# see a toast via the notification frame BEFORE the connection
	# drops. We hook the notification_sent signal (player-scoped path)
	# to capture the delivery to the kicked player.
	_notif.reset_dedupe()
	var captured: Array = []
	_notif.notification_sent.connect(
		func(entity_id: String, n: Dictionary) -> void:
			if entity_id == "p_test_kick_toast":
				captured.append(n)
	)
	_ars._auto_kick("p_test_kick_toast", "toast test reason", "speed_hack")
	if captured.size() != 1:
		_fail("_auto_kick should toast the player once via the frame, got %d" % captured.size())
		return
	var msg: String = captured[0].get("message", "")
	if msg.find("kicked") < 0:
		_fail("kick toast message should mention 'kicked', got '%s'" % msg)
		return
	# The kick reason should be in the message (clarity).
	if msg.find("toast test reason") < 0:
		_fail("kick toast should include the reason, got '%s'" % msg)
		return
	_ok("_auto_kick toasts player with reason via the frame")


func _test_auto_mute_toasts_player_via_frame() -> void:
	# The spam -> mute path should deliver exactly ONE player-facing
	# toast (with the duration included). AutoResponseService triggers
	# the mute via SecurityService.restrict_player, which is the
	# canonical source of the player toast -- we don't double-toast.
	_notif.reset_dedupe()
	var captured: Array = []
	_notif.notification_sent.connect(
		func(entity_id: String, n: Dictionary) -> void:
			if entity_id == "p_test_mute_toast":
				captured.append(n)
	)
	_ars._handle_spam("p_test_mute_toast", 5)
	if captured.size() != 1:
		_fail("auto-mute should deliver exactly one player toast, got %d" % captured.size())
		return
	var msg: String = captured[0].get("message", "")
	if msg.find("muted") < 0:
		_fail("auto-mute toast should mention 'muted', got '%s'" % msg)
		return
	# Clarity: include the duration in the toast. The 5-minute branch
	# in SecurityService._notify_player_restricted should match here.
	if msg.find("minutes") < 0 and msg.find("seconds") < 0:
		_fail("auto-mute toast should include a duration (minutes/seconds), got '%s'" % msg)
		return
	_ok("auto-mute delivers one clear player toast with the duration via the frame")


func _test_admin_alert_routes_through_frame() -> void:
	# The admin path for auto-mute should produce a notification via
	# the frame (server-wide broadcast, entity_id == ""), with
	# ADMIN_ALERT kind (highest priority, never deduped).
	_notif.reset_dedupe()
	var captured: Array = []
	_notif.notification_received.connect(
		func(entity_id: String, n: Dictionary) -> void:
			if entity_id == "":
				captured.append(n)
	)
	_ars._handle_spam("p_test_admin", 5)
	# We expect at least one broadcast (admin alert). Filter for the
	# AutoResponseService-sourced one to avoid coupling to other
	# services that may broadcast during test setup.
	var ars_alert_found := false
	for n in captured:
		if n.get("source_service", "") == "AutoResponseService":
			ars_alert_found = true
			break
	if not ars_alert_found:
		_fail("auto-mute should produce an admin alert via the frame, got %d broadcasts" % captured.size())
		return
	_ok("admin alert for auto-mute routes through the frame (source_service=AutoResponseService)")


func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _finish() -> void:
	print("--- AUTO RESPONSE SIGNAL TEST: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
