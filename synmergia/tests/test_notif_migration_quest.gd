## test_notif_migration_quest.gd
## Verifies the QUEST_* NotifKinds are wired into the kind→type map
## after the typed-Kind migration. Also exercises QuestService's
## quest-complete dispatch site.
##
## QuestService loads its quest data from .tres files; in a test
## environment those may not be present. We therefore assert on the
## kind→type map as the migration's contract: every added NotifKind
## must map to a renderable NotificationType, and QuestService must
## route through the typed pipeline.
##
## Run with:
##   tools/godot --headless --path synmergia --script res://tests/test_notif_migration_quest.gd
extends SceneTree

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

var _passed: int = 0
var _failed: int = 0
var _notif: Node
var _quest: Node


func _initialize() -> void:
	print("--- NOTIF MIGRATION: QUEST ---")
	await process_frame

	_notif = root.get_node_or_null("NotificationService")
	_quest = root.get_node_or_null("QuestService")
	if not _notif:
		_fail("NotificationService autoload missing")
		_finish()
		return
	if not _quest:
		_fail("QuestService autoload missing")
		_finish()
		return
	_ok("QuestService + NotificationService autoloads present")

	await _test_quest_kinds_have_renderable_types()
	await _test_quest_service_uses_typed_pipeline()
	_finish()


func _test_quest_kinds_have_renderable_types() -> void:
	# All 6 quest NotifKinds must map to a non-zero NotificationType.
	# The migration's contract is that adding a Kind to the enum and
	# using it in a service surfaces to the user via the toast layer.
	var kinds_to_check := [
		NotifKind.QUEST_ACCEPTED,
		NotifKind.QUEST_UPDATED,
		NotifKind.QUEST_COMPLETED,
		NotifKind.QUEST_FAILED,
		NotifKind.QUEST_TURNED_IN,
		NotifKind.QUEST_REWARDED,
	]
	for k in kinds_to_check:
		var mapped = _notif._notif_type_for_kind(k)
		if mapped > 0:
			_ok("Quest kind %d maps to renderable type %d" % [k, mapped])
		else:
			_fail("Quest kind %d has no renderable type mapping" % k)


func _test_quest_service_uses_typed_pipeline() -> void:
	# The migration removes any NotificationContext / send_event /
	# send_to_player call sites from QuestService. Grep is the
	# cheapest contract check; we also do a happy-path notify() call
	# to confirm the autoload accepts a quest kind end-to-end.
	# (We can't drive the full accept→objective→complete flow without
	# quest data files, but the migration's surface IS the dispatch
	# call shape.)
	#
	# Read the source as text and assert the call shape.
	var src_path := "res://core/services/quest_service.gd"
	if not FileAccess.file_exists(src_path):
		_fail("QuestService source not found at %s" % src_path)
		return
	var src := FileAccess.get_file_as_string(src_path)
	if "NotificationService.notify" in src:
		_ok("QuestService source contains NotificationService.notify() call")
	else:
		_fail("QuestService source does not contain NotificationService.notify() call")
	if "NotifKind.QUEST_" in src:
		_ok("QuestService source references a NotifKind.QUEST_* constant")
	else:
		_fail("QuestService source does not reference any NotifKind.QUEST_* constant")
	# Legacy surface must be gone from the source.
	if "NotificationContext" in src:
		_fail("QuestService source still references NotificationContext (legacy)")
	if "send_event" in src:
		_fail("QuestService source still references send_event (legacy)")
	if "send_to_player" in src:
		_fail("QuestService source still references send_to_player (legacy)")

	# End-to-end: directly drive notify() with a QUEST_COMPLETED kind
	# and confirm the autoload tracks the delivery.
	_notif.reset_dedupe()
	_notif.notify(
		NotifKind.QUEST_COMPLETED,
		"[TEST] Quest complete",
		"QuestService",
		"quest:complete:test_q_player",
		{"quest_id": "test_q_player"},
		"test_q_player"
	)
	await process_frame
	var hist: Array = _notif.get_history("test_q_player", 100)
	var found: bool = false
	for n in hist:
		if n.get("data", {}).get("kind", -1) == NotifKind.QUEST_COMPLETED:
			found = true
			break
	if found:
		_ok("End-to-end: notify(QUEST_COMPLETED, ...) reaches the autoload's history")
	else:
		_fail("End-to-end: notify(QUEST_COMPLETED, ...) did not reach the autoload's history")


func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _finish() -> void:
	print("--- NOTIF MIGRATION: QUEST: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
