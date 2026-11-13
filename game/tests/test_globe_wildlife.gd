## test_globe_wildlife - PLANAR-RETIREMENT STEP 2 LIVES ON THE GLOBE.
##
## Before this, only world_playable spawned scene enemies and owned the
## combat/loot/quest HUD feedback; the planet the player actually plays
## (globe_world) had ZERO enemies and no combat feedback rows. This
## receipt proves the port:
##   1. BRIDGE: the shared CombatFeedbackBridge is installed by HudLayer
##      and answers the combat surface (damage float + log row) on the
##      globe boot; the same node the planar scene uses (one voice).
##   2. WILDLIFE: a real globe boot places the roster enemies under
##      world_root, each registered with EntityService (as an ENEMY) and
##      TargetingManager, carrying a live AI brain.
##   3. RESPAWN: killing a tracked enemy schedules a rebuild that lands a
##      fresh body at the SAME spawn point.
##   4. PLAYER REG: the local globe body is registered as a PLAYER so the
##      enemies can actually aggro it (EntityInterest.query_players).
##
## Run: godot --headless --path game --script res://tests/test_globe_wildlife.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING: String = "synmergia/world/planet_radius"

var _passed := 0
var _failed := 0


func _ok(msg: String) -> void:
	_passed += 1
	print("   PASS  %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	print("   FAIL  %s" % msg)


func _check(cond: bool, msg: String) -> bool:
	if cond:
		_ok(msg)
	else:
		_fail(msg)
	return cond


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- GLOBE WILDLIFE RECEIPT ---")
	await process_frame

	await _leg_boot_and_bridge()
	await _leg_respawn()

	print("=== GLOBE WILDLIFE RECEIPT: %d checks, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		print("GLOBE WILDLIFE RECEIPT PASSED")
		quit(0)
	else:
		print("GLOBE WILDLIFE RECEIPT FAILED")
		quit(1)


## LEG 1+2+4: boot the globe, drain the boot waves, and assert the
## wildlife, the player registration, and the shared combat bridge.
func _leg_boot_and_bridge() -> void:
	ProjectSettings.set_setting(RADIUS_SETTING, 100.0)
	var packed: PackedScene = load(GLOBE_SCENE)
	if not _check(packed != null and packed.can_instantiate(), "globe scene loads"):
		return
	var globe = packed.instantiate()
	root.add_child(globe)
	var deadline: int = Time.get_ticks_msec() + 60000
	while not globe.has_meta("boot_waves_done_ms") and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(globe.has_meta("boot_waves_done_ms"), "the boot waves finish (the world dresses)")
	var clipmap = globe.get("clipmap")
	var drain_deadline: int = Time.get_ticks_msec() + 60000
	while clipmap != null and clipmap._mesh_pending() > 0 and Time.get_ticks_msec() < drain_deadline:
		await process_frame
	await process_frame

	# WILDLIFE: the roster placed + tracked.
	var spawns: Array = globe.get("_globe_spawns")
	_check(spawns.size() >= 4, "the globe places the wildlife roster (%d tracked)" % spawns.size())

	var es = root.get_node_or_null("EntityService")
	var tm = root.get_node_or_null("TargetingManager")
	var world_root: Node = globe.get("world_root")
	var live_enemies := 0
	var with_ai := 0
	for child in world_root.get_children():
		if child.is_in_group("enemies"):
			live_enemies += 1
			if child.has_method("attach_ai") and child.get("_ai") != null:
				with_ai += 1
	_check(live_enemies >= 4, "the wildlife bodies are live under world_root (%d)" % live_enemies)
	_check(with_ai >= 3, "the fighters carry an AI brain (dummies skip it) (%d)" % with_ai)

	if es != null:
		var registered := 0
		for record in spawns:
			var eid: String = str(record.entity_id)
			if eid != "" and es.get_entity(eid) != null:
				registered += 1
		_check(registered >= 4, "every tracked enemy is registered with EntityService (%d)" % registered)
	if tm != null:
		var tid: String = ""
		for record in spawns:
			if str(record.entity_id) != "":
				tid = str(record.entity_id)
				break
		var ti = tm.get_targetable(tid) if tm.has_method("get_targetable") else null
		_check(ti != null, "the wildlife is registered as targetable (the Tab ring sees it)")

	# PLAYER REG: the local body is a registered PLAYER (enemies can aggro).
	var player = globe.get("player")
	if _check(player != null, "the globe has a local player body"):
		var pid: String = str(player.entity_id)
		if es != null:
			_check(es.get_entity(pid) != null, "the local body is registered with EntityService as %s" % pid)
		_check(int(player.entity_type) == 1, "the body carries EntityType.PLAYER")

	# BRIDGE: HudLayer installs the shared combat bridge (one voice).
	var hud = globe.get("hud")
	if _check(hud != null, "the globe mounts the playable HUD"):
		var bridge = hud.get_node_or_null("CombatFeedbackBridge")
		_check(bridge != null, "the shared CombatFeedbackBridge is installed on the HUD")
		if bridge != null:
			var hub = root.get_node_or_null("EventHub")
			_check(hub != null and hub.damage_dealt.is_connected(bridge._on_combat_damage),
				"the bridge listens for damage_dealt")
			# A real damage event draws a float + a log row with no crash.
			var target = null
			for child in world_root.get_children():
				if child.is_in_group("enemies"):
					target = child
					break
			if target != null:
				var before: int = _combat_log_rows(hud)
				hub.damage_dealt.emit(player, target, 7, "physical", false)
				await process_frame
				_check(_combat_log_rows(hud) > before, "a damage_dealt event writes a CombatLog row")

	globe.set_meta("_receipt_globe", true)


## LEG 3: kill a tracked enemy through its real take_damage path and
## prove a fresh body lands at the same spawn point after the timer.
func _leg_respawn() -> void:
	var globe := _find_globe()
	if globe == null:
		_fail("no globe for the respawn leg")
		return
	var spawns: Array = globe.get("_globe_spawns")
	if spawns.is_empty():
		_fail("no wildlife records for the respawn leg")
		return
	# Pick the first NON-dummy record (dummies skip loot/reward chains).
	var record = null
	for r in spawns:
		if str(r.template_id) != "training_dummy":
			record = r
			break
	if record == null:
		record = spawns[0]
	# Force a short respawn so the receipt does not wait a full minute.
	record.respawn_time = 0.5
	var old_id: String = str(record.entity_id)
	var spawn_pos: Vector3 = record.spawn_position
	var es = root.get_node_or_null("EntityService")
	var old = es.get_entity(old_id) if es != null else null
	if not _check(old != null, "the tracked enemy exists before the kill"):
		return
	var player = globe.get("player")
	var hub = root.get_node_or_null("EventHub")
	var hud = globe.get("hud")
	# Spy on the reward emit so we prove the player-credited payout fires
	# (the bridge's reward row rides the same signal).
	var rewards_seen: Array = []
	var spy := func(entity, killer, rewards): rewards_seen.append({"killer": killer, "rewards": rewards})
	hub.kill_rewarded.connect(spy)
	var rows_before: int = _combat_log_rows(hud)
	# Kill through the REAL damage path with the local player as source, so
	# _last_damager credits them (the same path a player swing takes).
	old.take_damage(999999, player)
	await process_frame
	_check(not is_instance_valid(old) or old.is_queued_for_deletion(),
		"the killed enemy leaves the world")
	if _check(not rewards_seen.is_empty(), "the kill emits kill_rewarded"):
		_check(rewards_seen[0].killer == player, "the reward is credited to the local player")
	_check(_combat_log_rows(hud) > rows_before, "the kill writes a reward row to the CombatLog")
	if hub.kill_rewarded.is_connected(spy):
		hub.kill_rewarded.disconnect(spy)
	# LOOT ROW: the bridge turns a pickup into a CombatLog loot line (the
	# planar world's loot feedback, now shared). Emit through the real signal.
	if hub != null and player != null:
		var rows_before_loot: int = _combat_log_rows(hud)
		var stub_item := {"display_name": "Wolf Pelt", "current_stack": 1}
		hub.ground_loot_picked_up.emit(player, "loot_receipt", [stub_item])
		await process_frame
		_check(_combat_log_rows(hud) > rows_before_loot, "a loot pickup writes a loot row")
	# Wait out the (shortened) respawn timer.
	var deadline: int = Time.get_ticks_msec() + 5000
	while record.respawn_pending and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	_check(not record.respawn_pending, "the respawn timer fired")
	var fresh = es.get_entity(str(record.entity_id)) if es != null else null
	if _check(fresh != null, "a fresh body is registered after the respawn"):
		var drift: float = fresh.global_position.distance_to(spawn_pos)
		_check(drift < 5.0, "the respawn lands at the original spawn point (%.2f m drift)" % drift)
	globe.queue_free()
	await process_frame


func _combat_log_rows(hud) -> int:
	var log = hud.get_node_or_null("CombatLog")
	if log == null or not log.has_method("get_message_count"):
		return 0
	return int(log.get_message_count())


func _find_globe() -> Node:
	for c in root.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("globe_world.gd"):
			return c
	return null
