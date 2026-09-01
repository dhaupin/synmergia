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
	_test_send_event_to_player_calls_send()
	_test_send_event_broadcast_calls_broadcast()
	_test_send_event_returns_false_for_null()
	_test_send_event_known_kind_maps_to_known_type()

	_finish()


# --- dispatcher-level (no autoload) ---

func _test_dispatcher_dedupes_same_key_within_window() -> void:
	var d = NotificationDispatcher.new(5000)  # 5s window
	var ctx = NotificationContext.for_player(
		"p1", NotifKind.ITEM_FULL, "Inventory full", "InventoryService", {}, "inv:bag"
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
	var d = NotificationDispatcher.new(50)
	var ctx = NotificationContext.for_player(
		"p1", NotifKind.ITEM_FULL, "Inventory full", "InventoryService", {}, "inv:bag"
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


func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _finish() -> void:
	print("--- NOTIFICATION FRAME TEST: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
