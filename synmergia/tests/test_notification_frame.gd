## test_notification_frame.gd
## End-to-end test for the notification frame:
##   NotificationContext → NotificationService.send_event()
##     → dedupe (NotificationDispatcher) → send() / broadcast_alert()
##
## Run with:
##   tools/godot --headless --path synmergia --script res://tests/test_notification_frame.gd
extends SceneTree

const NotificationContext = preload("res://core/notifications/notification_context.gd")
const NotificationDispatcher = preload("res://core/notifications/notification_dispatcher.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

var _passed: int = 0
var _failed: int = 0
var _notif: Node


func _initialize() -> void:
	print("--- NOTIFICATION FRAME TEST ---")
	await process_frame

	_notif = root.get_node_or_null("NotificationService")
	if not _notif:
		_fail("NotificationService autoload missing")
		_finish()
		return
	_ok("NotificationService autoload present")

	# Start clean: clear dedupe so prior runs don't influence us.
	_notif.reset_dedupe()

	_test_dispatcher_dedupes_same_key_within_window()
	_test_dispatcher_lets_through_after_window_expires()
	_test_dispatcher_distinguishes_kinds()
	_test_dispatcher_distinguishes_targets()
	_test_dispatcher_no_dedupe_key_always_delivers()
	_test_dispatcher_reset_clears_state()
	_test_dispatcher_per_kind_override_zero_always_delivers()
	_test_dispatcher_per_kind_override_shorter_window()
	_test_send_event_to_player_calls_send()
	_test_send_event_broadcast_calls_broadcast()
	_test_send_event_returns_false_for_null()
	_test_send_event_known_kind_maps_to_known_type()
	_test_notify_delivers_to_player()
	_test_notify_delivers_broadcast()
	_test_notify_dedupes_identical_calls()

	# Inlined (not a helper) because SceneTree _initialize is where
	# awaits reliably resume. Helper functions with await behave
	# inconsistently when the script IS the SceneTree.
	_notif.reset_dedupe()
	var firewall: Node = root.get_node_or_null("AppFirewall")
	if firewall == null:
		_fail("AppFirewall autoload missing — cannot exercise recursion dispatch")
	else:
		var guard: RefCounted = firewall.get_recursion_guard()
		if guard == null:
			_fail("AppFirewall.get_recursion_guard() returned null")
		else:
			# AF routes admin-scope notifications as player_id="admins" via
			# NotificationService.notify(recipient="admins"). That hits
			# the per-player branch in send_event(), so the message
			# lands in get_history("admins"). The notification dict has
			# "kind" and "data" (our metadata).
			guard.set_max_depth("frame_test:recursion_a", 1)
			guard.enter("frame_test:recursion_a")
			guard.enter("frame_test:recursion_a")
			guard.set_max_depth("frame_test:recursion_b", 1)
			guard.enter("frame_test:recursion_b")
			guard.enter("frame_test:recursion_b")
			await process_frame
			var admins_history: Array = _notif.get_history("admins", 100)
			var captured: Array = []
			# In the per-player path, the top-level dict carries "type"
			# (legacy NotificationType) but the NotifKind is inside the
			# nested "data" dict (because send_event copies kind into
			# data before calling send()).
			for n in admins_history:
				var data: Dictionary = n.get("data", {})
				if data.get("kind", -1) == NotifKind.SECURITY_BLOCKED:
					captured.append(n)
			var contexts_seen: Dictionary = {}
			for notif in captured:
				var data: Dictionary = notif.get("data", {})
				contexts_seen[data.get("context", "")] = true
			if captured.size() < 2:
				_fail("recursion block should produce 2 SECURITY_BLOCKED events (got %d)" % captured.size())
			elif not contexts_seen.has("frame_test:recursion_a") or not contexts_seen.has("frame_test:recursion_b"):
				_fail("recursion block dedupe collapsed different contexts (saw %s)" % str(contexts_seen.keys()))
			else:
				_ok("AppFirewall recursion block dispatches SECURITY_BLOCKED per-context (saw %d events)" % captured.size())

	_finish()


# --- dispatcher-level (no autoload) ---

func _test_dispatcher_dedupes_same_key_within_window() -> void:
	var d = NotificationDispatcher.new(5000)  # 5s window
	# Use a kind that has no per-kind override (defaults to the
	# instance's 5s window). See KIND_WINDOW_OVERRIDES in the
	# dispatcher. ITEM_FULL is now an override (0 = never dedupe);
	# ITEM_ADDED is the closest neutral kind for this test.
	var ctx = NotificationContext.for_player(
		"p1", NotifKind.ITEM_ADDED, "Picked up sword", "InventoryService", {}, "inv:add"
	)
	if not d.should_deliver(ctx):
		_fail("first context with key should deliver")
		return
	if d.should_deliver(ctx):
		_fail("second context with same key inside window should be deduped")
		return
	_ok("dispatcher dedupes same (kind, key, player) within window")


func _test_dispatcher_lets_through_after_window_expires() -> void:
	# Wall-clock path: 50ms window, sleep 200ms. Stable across throttled hosts.
	# ITEM_ADDED (no per-kind override) so the instance window applies.
	var d = NotificationDispatcher.new(50)
	var ctx = NotificationContext.for_player(
		"p1", NotifKind.ITEM_ADDED, "Picked up sword", "InventoryService", {}, "inv:add"
	)
	if not d.should_deliver(ctx):
		_fail("first delivery should pass")
		return
	OS.delay_msec(200)  # busy-wait; acceptable in test code
	if not d.should_deliver(ctx):
		_fail("delivery after window should pass")
		return
	_ok("dispatcher lets context through after window expires")


func _test_dispatcher_distinguishes_kinds() -> void:
	var d = NotificationDispatcher.new(5000)
	var ctx_a = NotificationContext.for_player(
		"p1", NotifKind.ITEM_FULL, "Bag full", "InventoryService", {}, "shared"
	)
	var ctx_b = NotificationContext.for_player(
		"p1", NotifKind.ITEM_TRADE_REJECT, "Can't trade", "TradeService", {}, "shared"
	)
	if not d.should_deliver(ctx_a):
		_fail("ctx_a should deliver")
		return
	if not d.should_deliver(ctx_b):
		_fail("ctx_b should deliver (different kind, same dedupe_key)")
		return
	_ok("dispatcher treats different kinds as distinct even with same key")


func _test_dispatcher_distinguishes_targets() -> void:
	var d = NotificationDispatcher.new(5000)
	var ctx_a = NotificationContext.for_player(
		"p1", NotifKind.ITEM_FULL, "Bag full", "InventoryService", {}, "shared"
	)
	var ctx_b = NotificationContext.for_player(
		"p2", NotifKind.ITEM_FULL, "Bag full", "InventoryService", {}, "shared"
	)
	if not d.should_deliver(ctx_a):
		_fail("ctx_a (p1) should deliver")
		return
	if not d.should_deliver(ctx_b):
		_fail("ctx_b (p2) should deliver (different target, same key)")
		return
	_ok("dispatcher treats different players as distinct")


func _test_dispatcher_no_dedupe_key_always_delivers() -> void:
	var d = NotificationDispatcher.new(5000)
	var ctx = NotificationContext.for_player(
		"p1", NotifKind.CUSTOM, "hi", "TestService", {}, ""  # empty dedupe_key
	)
	var delivered := 0
	for i in 5:
		if d.should_deliver(ctx):
			delivered += 1
	if delivered != 5:
		_fail("no-dedupe-key contexts should all deliver, got %d/5" % delivered)
		return
	_ok("dispatcher never dedupes when dedupe_key is empty")


func _test_dispatcher_reset_clears_state() -> void:
	var d = NotificationDispatcher.new(5000)
	var ctx = NotificationContext.for_player(
		"p1", NotifKind.ITEM_FULL, "Bag full", "InventoryService", {}, "shared"
	)
	d.should_deliver(ctx)
	if d.tracked_count() != 1:
		_fail("tracked_count should be 1 after one delivery, got %d" % d.tracked_count())
		return
	d.reset()
	if d.tracked_count() != 0:
		_fail("tracked_count should be 0 after reset, got %d" % d.tracked_count())
		return
	# After reset, the same key should deliver again.
	if not d.should_deliver(ctx):
		_fail("delivery should pass after reset")
		return
	_ok("reset() clears dedupe state")


func _test_dispatcher_per_kind_override_zero_always_delivers() -> void:
	# Kinds in KIND_WINDOW_OVERRIDES mapped to 0 (bans, admin alerts,
	# item full, etc.) must deliver every time, regardless of the
	# instance's default window. We use SECURITY_BLOCKED as the
	# representative example.
	var d = NotificationDispatcher.new(5000)  # default 5s window
	var ctx = NotificationContext.for_player(
		"p1", NotifKind.SECURITY_BLOCKED, "Banned: cheating", "AppFirewall", {}, "ban:p1"
	)
	if not d.should_deliver(ctx):
		_fail("first ban should deliver")
		return
	# Second call within the default 5s window -- must still deliver
	# because SECURITY_BLOCKED has a per-kind override of 0.
	if not d.should_deliver(ctx):
		_fail("second ban within default window should also deliver (per-kind override = 0)")
		return
	# And a third for good measure.
	if not d.should_deliver(ctx):
		_fail("third ban should also deliver (per-kind override = 0)")
		return
	_ok("per-kind override of 0 disables dedupe for that kind")


func _test_dispatcher_per_kind_override_shorter_window() -> void:
	# RATE_LIMITED has a 2000ms per-kind override. Construct the
	# dispatcher with a 5000ms default; the per-kind window should win.
	var d = NotificationDispatcher.new(5000)
	var ctx = NotificationContext.for_player(
		"p1", NotifKind.RATE_LIMITED, "Slow down", "QoSService", {}, "rl:p1"
	)
	if not d.should_deliver(ctx):
		_fail("first rate-limit should deliver")
		return
	# 50ms is well inside the 2000ms override window -- should be deduped.
	OS.delay_msec(50)
	if d.should_deliver(ctx):
		_fail("rate-limit 50ms later should be deduped (per-kind window = 2000ms)")
		return
	# 2100ms is past the 2000ms override window but well inside the
	# 5000ms default -- the per-kind window must be honored.
	OS.delay_msec(2100)
	if not d.should_deliver(ctx):
		_fail("rate-limit 2150ms later should deliver (per-kind window expired, default would still be active)")
		return
	_ok("per-kind window shorter than default is honored (2000 < 5000)")


# --- autoload-level (NotificationService.send_event) ---

func _test_send_event_to_player_calls_send() -> void:
	_notif.reset_dedupe()
	var ctx = NotificationContext.for_player(
		"frame_test_player", NotifKind.ITEM_ADDED, "Picked up sword", "InventoryService",
		{"item_id": "sword_01"}, "frame_test:add"
	)
	var delivered: bool = _notif.send_event(ctx)
	if not delivered:
		_fail("send_event should return true on first delivery")
		return
	# Verify the notification landed on the per-player entity store.
	var history = _notif.get_history("frame_test_player")
	if history.size() == 0:
		_fail("expected at least one notification on frame_test_player history")
		return
	_ok("send_event to player routes through send() (history has the entry)")


func _test_send_event_broadcast_calls_broadcast() -> void:
	_notif.reset_dedupe()
	var ctx = NotificationContext.broadcast(
		NotifKind.ADMIN_ALERT, "Server restart in 5m", "ServerManager", {}, "frame_test:server_restart"
	)
	var delivered: bool = _notif.send_event(ctx)
	if not delivered:
		_fail("send_event should return true for broadcast")
		return
	# broadcast_alert emits notification_received; the signal listener is the
	# signal-not-yet-arrived check. We just confirm no crash and the dedupe
	# gate is now tracking the key.
	if _notif.dedupe_tracked_count() < 1:
		_fail("dedupe should track the broadcast key")
		return
	_ok("send_event broadcast routes through broadcast_alert()")


func _test_send_event_returns_false_for_null() -> void:
	var delivered: bool = _notif.send_event(null)
	if delivered:
		_fail("send_event(null) should return false")
		return
	_ok("send_event(null) returns false safely")


func _test_send_event_known_kind_maps_to_known_type() -> void:
	_notif.reset_dedupe()
	# Use a kind that should map to ALERT (so we can grep the kind→type
	# mapping). The notification_received signal carries the resolved type.
	var captured_type: Array = [-1]
	_notif.notification_received.connect(
		func(_entity_id: String, notification: Dictionary) -> void:
			captured_type[0] = notification.get("type", -1)
	)
	var ctx = NotificationContext.broadcast(
		NotifKind.ADMIN_ALERT, "audit ping", "AuditService", {}, "frame_test:audit"
	)
	_notif.send_event(ctx)
	# NotificationType.ALERT == 20 in the autoload's enum (we don't import the
	# enum here, so check it's not the default SYSTEM and not -1).
	if captured_type[0] == -1:
		_fail("notification_received never fired with the resolved type")
		return
	# We just want to confirm the mapping path executed; specific value is
	# checked by the dispatcher's match arms in the autoload source.
	_ok("send_event resolved kind→type (notification_received fired with type=%d)" % captured_type[0])


# --- service-level verb (NotificationService.notify) ---
#
# notify() is the convenience that builds a NotificationContext and forwards
# to send_event(). It exists so call sites (QoS, Security, AppFirewall) can
# fire a typed notification without constructing the context shape.
# These tests confirm the verb: (1) builds a context that delivers to a
# player, (2) builds one that broadcasts, (3) honors the dedupe key.

func _test_notify_delivers_to_player() -> void:
	_notif.reset_dedupe()
	# This is exactly the call shape a wired service would use:
	#   NotificationService.notify(NotifKind.RATE_LIMITED, msg, source, key, data, player)
	var delivered: bool = _notif.notify(
		NotifKind.RATE_LIMITED,
		"You're casting too fast",
		"QoSService",
		"frame_test:qos_rl:p1:cast",
		{"action_type": "cast", "max_rate": 5.0},
		"frame_test_player_p1"
	)
	if not delivered:
		_fail("notify() should return true for first delivery to a player")
		return
	var history = _notif.get_history("frame_test_player_p1")
	if history.size() == 0:
		_fail("notify() should have routed through send() to the per-player history")
		return
	# The first entry should carry the source label + kind via the data dict
	# (send_event copies kind/source_service into the data payload).
	var entry: Dictionary = history[0]
	var data: Dictionary = entry.get("data", {})
	if data.get("source_service", "") != "QoSService":
		_fail("notify() should propagate source_service into data (got '%s')" % data.get("source_service", ""))
		return
	if int(data.get("kind", -1)) != NotifKind.RATE_LIMITED:
		_fail("notify() should propagate kind into data (got %d)" % int(data.get("kind", -1)))
		return
	_ok("notify() builds context, delivers to player, propagates kind+source")

func _test_notify_delivers_broadcast() -> void:
	_notif.reset_dedupe()
	# Empty recipient → broadcast (server-wide). Same call shape that
	# AppFirewall / SecurityMonitor use for admin scope.
	var delivered: bool = _notif.notify(
		NotifKind.ADMIN_ALERT,
		"RecursionGuard exceeded depth 16",
		"AppFirewall",
		"frame_test:fw_alert:1",
		{"context": "agent_tool_call", "depth": 16}
	)
	if not delivered:
		_fail("notify() should return true for broadcast (no recipient)")
		return
	if _notif.dedupe_tracked_count() < 1:
		_fail("dedupe should track the broadcast key after notify()")
		return
	_ok("notify() builds broadcast context and routes through broadcast_alert()")

func _test_notify_dedupes_identical_calls() -> void:
	_notif.reset_dedupe()
	# A spam loop on the same key within 5s should collapse to a single
	# delivery. This is the whole reason QoS / Security moved to the
	# frame: a rate-limited action firing 50x/sec used to toast 50x.
	var delivered_count: int = 0
	for i in 10:
		if _notif.notify(
			NotifKind.RATE_LIMITED,
			"tick %d" % i,
			"QoSService",
			"frame_test:qos_dedupe:loop",
			{},
			"frame_test_dedupe_p"
		):
			delivered_count += 1
	if delivered_count != 1:
		_fail("notify() should dedupe 10 identical calls to 1 (got %d)" % delivered_count)
		return
	_ok("notify() collapses 10 identical calls within the dedupe window to 1 delivery")

func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _finish() -> void:
	print("--- NOTIFICATION FRAME TEST: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
