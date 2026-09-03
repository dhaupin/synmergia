## test_notif_migration_chat.gd
## Verifies ChatService._notify_player routes through
## NotificationService.notify() with NotifKind.SECURITY_BLOCKED after
## the typed-Kind migration.
##
## The three legacy call sites (restriction, validation block,
## rate-limit) all funnel through _notify_player, so exercising the
## helper directly covers all three. Dedupe is asserted so the dedupe
## key survives the migration.
##
## Run with:
##   tools/godot --headless --path synmergia --script res://tests/test_notif_migration_chat.gd
extends SceneTree

const NotifKind = preload("res://core/notifications/notification_kind.gd").Kind

var _passed: int = 0
var _failed: int = 0
var _notif: Node
var _chat: Node


func _initialize() -> void:
	print("--- NOTIF MIGRATION: CHAT ---")
	await process_frame

	_notif = root.get_node_or_null("NotificationService")
	_chat = root.get_node_or_null("ChatService")
	if not _notif:
		_fail("NotificationService autoload missing")
		_finish()
		return
	if not _chat:
		_fail("ChatService autoload missing")
		_finish()
		return
	_ok("ChatService + NotificationService autoloads present")

	await _test_notify_player_routes_to_kind()


func _test_notify_player_routes_to_kind() -> void:
	# Three call sites in ChatService collapse to one helper, _notify_player.
	# We hit it with the rate-limit message (the most common one in
	# production traffic) and assert the autoload sees SECURITY_BLOCKED.
	# Each subtest uses a unique entity id because NotificationService
	# history is per-entity and persists across reset_dedupe().
	_notif.reset_dedupe()
	_chat.call("_notify_player", "test_chat_basic", "Slow down! You are sending messages too fast.")
	await process_frame
	var hist: Array = _notif.get_history("test_chat_basic", 100)
	var found: bool = false
	for n in hist:
		if n.get("data", {}).get("kind", -1) == NotifKind.SECURITY_BLOCKED:
			found = true
			break
	if found:
		_ok("ChatService._notify_player dispatches NotifKind.SECURITY_BLOCKED")
	else:
		_fail("ChatService._notify_player did not produce NotifKind.SECURITY_BLOCKED")

	# SECURITY_BLOCKED is intentionally NOT deduped (see KIND_WINDOW_OVERRIDES
	# in notification_dispatcher.gd: ban/unban/rate-limit messages must always
	# surface). The migration's per-call dedupe key is therefore advisory for
	# this kind — the kind-level policy wins. Assert the call does NOT collapse
	# so a future refactor doesn't accidentally re-enable dedupe here and
	# silence rate-limit feedback.
	_notif.reset_dedupe()
	_chat.call("_notify_player", "test_chat_dedupe", "Slow down! You are sending messages too fast.")
	_chat.call("_notify_player", "test_chat_dedupe", "Slow down! You are sending messages too fast.")
	await process_frame
	var dedupe_hist: Array = _notif.get_history("test_chat_dedupe", 100)
	var deliveries: int = 0
	for n in dedupe_hist:
		if n.get("data", {}).get("kind", -1) == NotifKind.SECURITY_BLOCKED:
			deliveries += 1
	if deliveries == 2:
		_ok("ChatService._notify_player does not dedupe SECURITY_BLOCKED (rate-limit feedback must always show)")
	else:
		_fail("ChatService._notify_player delivered %d times (expected 2, since SECURITY_BLOCKED is intentionally not deduped)" % deliveries)

	# Different message should still surface (no false dedupe across
	# distinct messages).
	_notif.reset_dedupe()
	_chat.call("_notify_player", "test_chat_distinct", "You are muted and cannot send alliance messages.")
	await process_frame
	var distinct_hist: Array = _notif.get_history("test_chat_distinct", 100)
	var distinct: bool = false
	for n in distinct_hist:
		if n.get("data", {}).get("kind", -1) == NotifKind.SECURITY_BLOCKED:
			distinct = true
			break
	if distinct:
		_ok("ChatService._notify_player surfaces distinct messages (no false dedupe)")
	else:
		_fail("ChatService._notify_player dropped a distinct message")

	_finish()


func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _finish() -> void:
	print("--- NOTIF MIGRATION: CHAT: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
