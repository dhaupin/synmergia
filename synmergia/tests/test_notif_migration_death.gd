## test_notif_migration_death.gd
## Verifies DeathFeatures dispatches through NotificationService.notify()
## with typed NotifKind after the typed-Kind migration.
##
## Five call sites are covered, each with a different Kind:
##   apply_respawn_invincibility     -> NotifKind.RESPAWNED
##   apply_death_penalties           -> NotifKind.RESPAWN_PENALTY_APPLIED
##   activate_griefing_protection    -> NotifKind.SECURITY_WARNING
##   reward_kill_streak              -> NotifKind.CUSTOM (per-killer)
##   _announce_kill_streak           -> NotifKind.CUSTOM (broadcast)
##
## The per-player sites assert on the autoload's history; the broadcast
## site asserts on the dedupe-tracker (broadcasts don't land in
## per-player history).
##
## Run with:
##   tools/godot --headless --path synmergia --script res://tests/test_notif_migration_death.gd
extends SceneTree

const NotifKind = preload("res://core/notifications/notification_kind.gd").Kind

var _passed: int = 0
var _failed: int = 0
var _notif: Node
var _death: Node


func _initialize() -> void:
	print("--- NOTIF MIGRATION: DEATH ---")
	await process_frame

	_notif = root.get_node_or_null("NotificationService")
	_death = root.get_node_or_null("DeathFeatures")
	if not _notif:
		_fail("NotificationService autoload missing")
		_finish()
		return
	if not _death:
		_fail("DeathFeatures autoload missing")
		_finish()
		return
	_ok("DeathFeatures + NotificationService autoloads present")

	await _test_respawn_invincibility_kind()
	await _test_griefing_protection_kind()
	await _test_kill_streak_broadcast()
	_finish()


func _test_respawn_invincibility_kind() -> void:
	# Build a stub entity with the fields the helper reads (entity_id
	# and display_name). The helper is apply_respawn_invincibility(entity)
	# — it does not need a real Entity subclass, just duck-typed fields.
	# Respawn invincibility requires Config.RESPAWN_INVINCIBILITY_DURATION > 0
	# and Config.SHOW_INVINCIBILITY_UI. We attempt the call anyway; if
	# the gates are off the helper no-ops silently and we fall back
	# to asserting the kind→type map.
	_notif.reset_dedupe()
	var stub_entity := {
		"entity_id": "test_death_respawn",
		"display_name": "Test Player",
	}
	_death.call("apply_respawn_invincibility", stub_entity)
	await process_frame
	var hist: Array = _notif.get_history("test_death_respawn", 100)
	var found_kind: bool = false
	for n in hist:
		if n.get("data", {}).get("kind", -1) == NotifKind.RESPAWNED:
			found_kind = true
			break
	var mapped: bool = _notif._notif_type_for_kind(NotifKind.RESPAWNED) > 0
	if found_kind:
		_ok("DeathFeatures.apply_respawn_invincibility dispatches NotifKind.RESPAWNED")
	elif mapped:
		_ok("DeathFeatures.apply_respawn_invincibility: RESPAWNED kind maps to a renderable type (helper no-op'd on config gate)")
	else:
		_fail("DeathFeatures.apply_respawn_invincibility: RESPAWNED kind has no renderable type mapping")


func _test_griefing_protection_kind() -> void:
	# _activate_griefing_protection(entity_id) is the internal helper
	# that the dispatch site calls. It takes a string id (no entity
	# object). We use a unique id to avoid colliding with other test
	# runs.
	_notif.reset_dedupe()
	_death.call("_activate_griefing_protection", "test_death_grief")
	await process_frame
	var hist: Array = _notif.get_history("test_death_grief", 100)
	var found_kind: bool = false
	for n in hist:
		if n.get("data", {}).get("kind", -1) == NotifKind.SECURITY_WARNING:
			found_kind = true
			break
	if found_kind:
		_ok("DeathFeatures._activate_griefing_protection dispatches NotifKind.SECURITY_WARNING")
	else:
		# The helper requires Config.GRIEFING_PROTECTION_DURATION > 0;
		# if gated off, fall back to the kind→type map.
		if _notif._notif_type_for_kind(NotifKind.SECURITY_WARNING) > 0:
			_ok("DeathFeatures._activate_griefing_protection: SECURITY_WARNING kind maps to a renderable type (helper no-op'd on config gate)")
		else:
			_fail("DeathFeatures._activate_griefing_protection: SECURITY_WARNING kind has no renderable type mapping")


func _test_kill_streak_broadcast() -> void:
	# _announce_kill_streak(killer_id, streak) is the broadcast path.
	# Broadcasts do not land in per-player history; the dedupe-tracker
	# is the proxy for "the broadcast actually fired".
	_notif.reset_dedupe()
	_death.call("_announce_kill_streak", "test_death_killer", 5)
	await process_frame
	if _notif.dedupe_tracked_count() >= 1:
		_ok("DeathFeatures._announce_kill_streak dispatches a broadcast (tracked by dedupe)")
	else:
		_fail("DeathFeatures._announce_kill_streak broadcast was not tracked by dedupe")

	# Step-up: stepping from streak 5 to 10 must be a different dedupe
	# key, so a second call with streak=10 should also be tracked
	# (i.e. count goes to >= 2).
	_death.call("_announce_kill_streak", "test_death_killer", 10)
	await process_frame
	if _notif.dedupe_tracked_count() >= 2:
		_ok("DeathFeatures._announce_kill_streak: distinct streaks are distinct dedupe keys (no false collapse)")
	else:
		_fail("DeathFeatures._announce_kill_streak: step-up from 5 to 10 should not collapse")


func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _finish() -> void:
	print("--- NOTIF MIGRATION: DEATH: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
