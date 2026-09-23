## test_world_boss_schedule.gd - Timed open-world world-boss respawn
## loop (WorldBossData + SpawnService schedules + /boss schedule).
## Run headless:
##
##   cd game && godot --headless --path . --script res://tests/test_world_boss_schedule.gd
##
## Covers:
##   1. Boot load: the demo .tres (forest_void_lord) loads at boot with
##      its config flattened from the schema.
##   2. First spawn: a short first_delay_s schedule spawns after the
##      delay, WORLD_BOSS metadata, server-wide scope, zone-entered.
##   3. Respawn-from-death: killing the boss rearms the timer to
##      interval_seconds (NOT first_delay); the boss is gone while down.
##   4. Announce=false mutes the spawn announcement (no scope).
##   5. window_seconds: an unclaimed boss despawns when its window
##      expires and the timer rearms from that despawn.
##   6. Schedule stop/start + run_now + unknown feedback.
##   7. /boss schedule command: non-admin denied, admin list/info/run
##      works against the live schedule.
##
## Exit 0 = all pass.
extends SceneTree

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _run()
	quit(0 if _fail == 0 else 1)

func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)

func _run() -> void:
	var ss = root.get_node_or_null("SpawnService")
	var es = root.get_node_or_null("EntityService")
	var zm = root.get_node_or_null("ZoneManager")
	var pm = root.get_node_or_null("PlayerManager")
	var cs = root.get_node_or_null("ChatService")
	var perm = root.get_node_or_null("PermissionManager")
	var hub = root.get_node_or_null("EventHub")
	_ok(ss != null and es != null and zm != null and pm != null, "core services present")
	_ok(cs != null and perm != null and hub != null, "chat/perm/hub present")
	if ss == null or es == null or zm == null or pm == null or cs == null or perm == null or hub == null:
		return _finish()

	# --- Players + admin seam ------------------------------------------------
	var PlayerScript = load("res://entities/player/player_controller.gd")
	var player: Node = PlayerScript.new()
	player.display_name = "BossTimerAdmin"
	player.entity_id = "wb_char"
	root.add_child(player)
	var helper: Node = PlayerScript.new()
	helper.display_name = "BossTimerHelper"
	helper.entity_id = "wb_helper"
	root.add_child(helper)
	await process_frame
	es.register_entity(player, null, "wb_char")
	es.register_entity(helper, null, "wb_helper")
	pm.set_local_player(player)
	await process_frame
	perm._validation_cache["wb_char"] = {"time": Time.get_ticks_msec(), "level": 100}
	perm._validation_cache["wb_helper"] = {"time": Time.get_ticks_msec(), "level": 0}

	# --- Zone ----------------------------------------------------------------
	var ZoneDataScript = load("res://core/schemas/zone_data.gd")
	var zone = ZoneDataScript.new()
	zone.id = "wb_zone"
	zone.zone_center = Vector3(0, 0, 0)
	zone.zone_radius = 100.0
	zm.register_zone(zone)
	zm._entity_zones["wb_char"] = "wb_zone"
	zm._entity_zones["wb_helper"] = "wb_zone"
	await process_frame

	# --- 1. Boot load ----------------------------------------------------------
	var ids: Array = ss.get_world_boss_schedule_ids()
	_ok(ids.has("forest_void_lord"), "demo schedule loaded at boot (forest_void_lord)")
	var demo: Dictionary = ss.get_world_boss_schedule_status("forest_void_lord")
	_ok(str(demo.get("boss_template_id", "")) == "void_lord" and str(demo.get("zone_id", "")) == "zone_forest_meadow",
			"demo schedule flattened from the schema (template + zone)")
	_ok(int(demo.get("interval_seconds", 0)) == 10800, "demo schedule keeps its 3h interval")

	# --- 2. First spawn ---------------------------------------------------------
	var spawn_meta: Array = []
	hub.entity_spawned.connect(func(entity, metadata): if metadata != null: spawn_meta.append(metadata))
	var started: String = ss.start_world_boss_schedule("test_lord", {
		"boss_template_id": "void_lord",
		"zone_id": "wb_zone",
		"display_name": "Test Devourer",
		"interval_seconds": 3.0,
		"first_delay_s": 0.5,
		"announce": true,
		"window_seconds": 0.0,
	})
	_ok(started != "", "short schedule starts")
	var boss = await _wait_live(ss, es, "test_lord", 10000)
	_ok(boss != null, "first spawn fires after first_delay_s")
	if boss != null:
		var md = _last_meta(spawn_meta, str(boss.entity_id))
		_ok(md != null and int(md.spawn_type) == 3, "scheduled boss carries WORLD_BOSS metadata")
		_ok(md != null and md.notification_enabled and not md.notification_scopes.is_empty()
				and bool(md.notification_scopes[0].is_server_wide),
				"announce=true announces server-wide")
		_ok(str(boss.display_name) == "Test Devourer", "display_name override lands")

	# --- 3. Respawn-from-death ---------------------------------------------------
	_ok(float(ss.get_world_boss_schedule_status("test_lord").get("time_left", -1)) == 0.0
			and str(ss.get_world_boss_schedule_status("test_lord").get("state", "")) == "live",
			"schedule reads live while the boss is up")
	if boss != null and is_instance_valid(boss):
		boss.take_damage(999999, player)
	var rearmed: bool = await _wait_time_left(ss, "test_lord", 3.0, 10000)
	_ok(rearmed, "death rearms the timer to interval_seconds (respawn-from-death)")
	_ok(ss.get_world_boss_schedule_status("test_lord").get("state", "") == "waiting",
			"schedule waits while the boss is down")
	await _wait_live(ss, es, "test_lord", 10000)
	_ok(true, "second spawn fires after the interval")

	# --- 4. announce=false ----------------------------------------------------------
	var quiet_id: String = ss.start_world_boss_schedule("quiet_lord", {
		"boss_template_id": "void_lord",
		"zone_id": "wb_zone",
		"interval_seconds": 60.0,
		"first_delay_s": 0.2,
		"announce": false,
		"window_seconds": 0.0,
	})
	_ok(quiet_id != "", "quiet schedule starts")
	var quiet_boss = await _wait_live(ss, es, "quiet_lord", 10000)
	_ok(quiet_boss != null, "quiet schedule spawns")
	if quiet_boss != null:
		var qmd = _last_meta(spawn_meta, str(quiet_boss.entity_id))
		_ok(qmd != null and not qmd.notification_enabled, "announce=false mutes the spawn announcement")
		if is_instance_valid(quiet_boss):
			quiet_boss.take_damage(999999, player)

	# --- 5. window_seconds despawn ---------------------------------------------------
	var window_id: String = ss.start_world_boss_schedule("window_lord", {
		"boss_template_id": "void_lord",
		"zone_id": "wb_zone",
		"interval_seconds": 5.0,
		"first_delay_s": 0.2,
		"announce": false,
		"window_seconds": 1.0,
	})
	_ok(window_id != "", "windowed schedule starts")
	var wb = await _wait_live(ss, es, "window_lord", 10000)
	_ok(wb != null, "windowed boss spawns")
	if wb != null:
		var gone: bool = await _wait_gone(ss, es, "window_lord", 8000)
		_ok(gone, "window_seconds despawns the unclaimed boss")
		var rearmed2: bool = await _wait_time_left(ss, "window_lord", 4.0, 10000)
		_ok(rearmed2, "despawn rearms the respawn timer")

	# --- 6. Stop / run_now / unknown ----------------------------------------------
	var run_boss = ss.run_world_boss_schedule_now("window_lord")
	_ok(run_boss != null, "run_now forces a spawn")
	if run_boss != null and is_instance_valid(run_boss):
		run_boss.take_damage(999999, player)
	await process_frame
	ss.stop_world_boss_schedule("window_lord", "test done")
	_ok(not ss.get_world_boss_schedule_ids().has("window_lord"), "stop drops the schedule")
	var nobody = ss.run_world_boss_schedule_now("window_lord")
	_ok(nobody == null, "run_now on a stopped schedule is a no-op")
	var bad_start: String = ss.start_world_boss_schedule("bad_lord", {
		"boss_template_id": "no_such_boss", "zone_id": "wb_zone",
		"interval_seconds": 5.0, "first_delay_s": 0.1,
	})
	_ok(bad_start == "", "unknown template rejected")
	var bad_start2: String = ss.start_world_boss_schedule("", {"boss_template_id": "void_lord", "zone_id": "wb_zone"})
	_ok(bad_start2 == "", "empty id rejected")

	# --- 7. /boss schedule command ----------------------------------------------------
	perm._validation_cache["wb_char"] = {"time": Time.get_ticks_msec(), "level": 100}
	perm._validation_cache["wb_helper"] = {"time": Time.get_ticks_msec(), "level": 0}
	var chat_fired: Array = []
	var ns = root.get_node_or_null("NotificationService")
	if ns != null and ns.has_signal("notification_sent"):
		ns.notification_sent.connect(func(player_id, notification):
			chat_fired.append(str(notification.get("message", "") if notification is Dictionary else notification)))
	chat_fired.clear()
	cs._handle_command("wb_helper", 9, "boss schedule list", "")
	# The denial line names the command ("[boss schedule] Admin permission
	# required."), so assert on the denial + absence of schedule data, not
	# on the command name itself.
	_ok(_said(chat_fired, "Admin permission required") and not _said(chat_fired, "test_lord"),
			"non-admin cannot list schedules")
	perm._validation_cache["wb_char"] = {"time": Time.get_ticks_msec(), "level": 100}
	chat_fired.clear()
	cs._handle_command("wb_char", 9, "boss schedule list", "")
	_ok(_said(chat_fired, "test_lord"), "admin lists live schedules")
	chat_fired.clear()
	cs._handle_command("wb_char", 9, "boss schedule info test_lord", "")
	_ok(_said(chat_fired, "template=void_lord"), "admin reads schedule info")
	chat_fired.clear()
	cs._handle_command("wb_char", 9, "boss schedule info no_such", "")
	_ok(_said(chat_fired, "Unknown schedule"), "unknown schedule id rejected")
	chat_fired.clear()
	cs._handle_command("wb_char", 9, "boss schedule run test_lord", "")
	_ok(_said(chat_fired, "spawned now") or _said(chat_fired, "failed to spawn"), "admin run answers")
	var forced = _live_boss(ss, es, "test_lord")
	if forced != null and is_instance_valid(forced):
		forced.take_damage(999999, player)
	await process_frame
	chat_fired.clear()
	cs._handle_command("wb_char", 9, "boss schedule stop test_lord", "")
	_ok(_said(chat_fired, "stopped"), "admin stops a schedule")
	_ok(not ss.get_world_boss_schedule_ids().has("test_lord"), "stopped schedule is gone")
	chat_fired.clear()
	# Restart exercises the real .tres reload path: forest_void_lord is
	# the boot-loaded demo (test_lord was started programmatically and
	# has no backing file).
	ss.stop_world_boss_schedule("forest_void_lord", "test done")
	_ok(not ss.get_world_boss_schedule_ids().has("forest_void_lord"), "demo schedule stopped")
	cs._handle_command("wb_char", 9, "boss schedule start forest_void_lord", "")
	_ok(_said(chat_fired, "started"), "admin restarts from the .tres")
	_ok(ss.get_world_boss_schedule_ids().has("forest_void_lord"), "restarted schedule is live")
	var restarted: Dictionary = ss.get_world_boss_schedule_status("forest_void_lord")
	_ok(str(restarted.get("boss_template_id", "")) == "void_lord" and int(restarted.get("interval_seconds", 0)) == 10800,
			"restarted schedule keeps its .tres config")
	ss.stop_world_boss_schedule("forest_void_lord", "test done")
	ss.stop_world_boss_schedule("test_lord", "test done")
	ss.stop_world_boss_schedule("quiet_lord", "test done")

	_finish()

## ---------------------------------------------------------------------------

func _live_boss(ss, es, schedule_id: String):
	var st: Dictionary = ss.get_world_boss_schedule_status(schedule_id)
	if st.is_empty() or str(st.get("state", "")) != "live":
		return null
	return es.get_entity(str(st.get("boss_id", "")))

func _wait_live(ss, es, schedule_id: String, timeout_ms: int):
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var b = _live_boss(ss, es, schedule_id)
		if b != null and is_instance_valid(b):
			return b
	return null

func _wait_time_left(ss, schedule_id: String, min_value: float, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var st: Dictionary = ss.get_world_boss_schedule_status(schedule_id)
		if st.is_empty():
			return false
		if str(st.get("state", "")) == "waiting" and float(st.get("time_left", 0.0)) >= min_value * 0.8:
			return true
	return false

func _wait_gone(ss, es, schedule_id: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var st: Dictionary = ss.get_world_boss_schedule_status(schedule_id)
		if str(st.get("state", "")) == "waiting":
			return true
	return false

func _last_meta(into: Array, entity_id: String):
	for i in range(into.size() - 1, -1, -1):
		var m = into[i]
		if m != null and str(m.entity_id) == entity_id:
			return m
	return null

func _said(fired: Array, needle: String) -> bool:
	for m in fired:
		if str(m).find(needle) != -1:
			return true
	return false

func _finish() -> void:
	print("---")
	print("test_world_boss_schedule: %d passed, %d failed" % [_pass, _fail])
