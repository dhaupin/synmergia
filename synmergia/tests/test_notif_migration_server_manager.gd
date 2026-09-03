## test_notif_migration_server_manager.gd
## Verifies ServerManager's broadcast sites route through
## NotificationService.notify() with NotifKind.ADMIN_ALERT after the
## typed-Kind migration.
##
## Five legacy call sites are covered:
##   cancel_restart, execute_restart, broadcast_restart_warning,
##   start_maintenance, end_maintenance.
## All use broadcast (recipient = "") + ADMIN_ALERT.
##
## Run with:
##   tools/godot --headless --path synmergia --script res://tests/test_notif_migration_server_manager.gd
extends SceneTree

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

var _passed: int = 0
var _failed: int = 0
var _notif: Node
var _test_sm: Node
var _saved_state


func _initialize() -> void:
	print("--- NOTIF MIGRATION: SERVER MANAGER ---")
	await process_frame

	_notif = root.get_node_or_null("NotificationService")
	_test_sm = root.get_node_or_null("ServerManager")
	if not _notif:
		_fail("NotificationService autoload missing")
		_finish()
		return
	if not _test_sm:
		_fail("ServerManager autoload missing")
		_finish()
		return
	_ok("ServerManager + NotificationService autoloads present")

	# Save the live state so we can restore it after the lifecycle
	# tests mutate it. The autoload is shared across tests.
	_saved_state = _test_sm.get("_state")

	await _test_cancel_restart()
	await _test_execute_restart()
	await _test_broadcast_restart_warning()
	await _test_start_maintenance()
	await _test_end_maintenance()
	await _test_source_uses_typed_pipeline()

	# Restore state and finish.
	_test_sm.set("_state", _saved_state)
	_finish()


func _test_cancel_restart() -> void:
	# cancel_restart() needs _restart_scheduled = true. Set it,
	# call, restore.
	_test_sm.set("_restart_scheduled", true)
	_test_sm.set("_restart_countdown_seconds", 60)
	_notif.reset_dedupe()
	_test_sm.call("cancel_restart")
	await process_frame
	if _notif.dedupe_tracked_count() >= 1:
		_ok("ServerManager.cancel_restart dispatches a broadcast (tracked by dedupe)")
	else:
		_fail("ServerManager.cancel_restart broadcast was not tracked by dedupe")


func _test_execute_restart() -> void:
	# execute_restart() emits restart_executed and broadcasts.
	_notif.reset_dedupe()
	_test_sm.call("execute_restart")
	await process_frame
	if _notif.dedupe_tracked_count() >= 1:
		_ok("ServerManager.execute_restart dispatches a broadcast (tracked by dedupe)")
	else:
		_fail("ServerManager.execute_restart broadcast was not tracked by dedupe")


func _test_broadcast_restart_warning() -> void:
	# broadcast_restart_warning(seconds_remaining) is the public helper
	# for the rolling countdown. Pick a unique value to avoid dedupe
	# collision with the other lifecycle tests.
	_notif.reset_dedupe()
	_test_sm.call("_broadcast_restart_warning", 314)  # tau; unlikely to collide
	await process_frame
	if _notif.dedupe_tracked_count() >= 1:
		_ok("ServerManager._broadcast_restart_warning dispatches a broadcast (tracked by dedupe)")
	else:
		_fail("ServerManager._broadcast_restart_warning broadcast was not tracked by dedupe")


func _test_start_maintenance() -> void:
	# start_maintenance(message, duration) flips the state. We save
	# the state, call, and rely on _test_sm.set in the outer _initialize
	# to restore it. (This test does the state transition; later
	# tests start from a known-clean state.)
	_notif.reset_dedupe()
	_test_sm.call("start_maintenance", "[TEST] Maintenance mode", 60)
	await process_frame
	if _notif.dedupe_tracked_count() >= 1:
		_ok("ServerManager.start_maintenance dispatches a broadcast (tracked by dedupe)")
	else:
		_fail("ServerManager.start_maintenance broadcast was not tracked by dedupe")


func _test_end_maintenance() -> void:
	# end_maintenance() requires the state to be MAINTENANCE. The
	# previous test put us there.
	_notif.reset_dedupe()
	_test_sm.call("end_maintenance")
	await process_frame
	if _notif.dedupe_tracked_count() >= 1:
		_ok("ServerManager.end_maintenance dispatches a broadcast (tracked by dedupe)")
	else:
		_fail("ServerManager.end_maintenance broadcast was not tracked by dedupe")


func _test_source_uses_typed_pipeline() -> void:
	# The migration's contract: ServerManager's broadcast sites must
	# use NotificationService.notify() (not send_to_player /
	# broadcast_all) and reference NotifKind constants (not raw
	# NotificationType/NotificationPriority enums).
	var src_path := "res://core/services/server_manager.gd"
	if not FileAccess.file_exists(src_path):
		_fail("ServerManager source not found at %s" % src_path)
		return
	var src := FileAccess.get_file_as_string(src_path)
	if "NotificationService.notify" in src:
		_ok("ServerManager source contains NotificationService.notify() call")
	else:
		_fail("ServerManager source does not contain NotificationService.notify() call")
	if "NotifKind.ADMIN_ALERT" in src:
		_ok("ServerManager source references NotifKind.ADMIN_ALERT")
	else:
		_fail("ServerManager source does not reference NotifKind.ADMIN_ALERT")
	# Legacy surface must be gone.
	if "broadcast_all" in src:
		_fail("ServerManager source still references broadcast_all (legacy)")
	if "send_to_player" in src:
		_fail("ServerManager source still references send_to_player (legacy)")


func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _finish() -> void:
	print("--- NOTIF MIGRATION: SERVER MANAGER: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
