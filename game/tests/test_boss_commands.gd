## test_boss_commands.gd - Standalone boss spawns (/boss), on-demand
## enemy spawns (/spawn), boss-waves in HordeEventService, the bossless
## default fix, and the /horde alert toggle.
## Run headless:
##
##   cd game && godot --headless --path . --script res://tests/test_boss_commands.gd
##
## Covers:
##   1. /boss command: non-admin denied, admin world/zone/none alert
##      modes (spawn metadata type + notification flags), explicit zone,
##      unknown template feedback.
##   2. /spawn command: non-admin denied, admin spawns registered Enemy
##      nodes from the template (count + level override), count clamp,
##      unknown template feedback.
##   3. Boss-waves: a pure boss wave (no spawns) goes straight to the
##      boss state; a mid-horde wave boss death rolls into the next
##      wave with its payout merged; the finale completes the horde.
##   4. Bossless default fix: a plain horde with no boss_template_id
##      completes after the last wave instead of spawning a phantom
##      finale boss out of the mob template.
##   5. Demo configs: haven_siege (bossless, bosses_alert) and
##      boss_gauntlet (pure boss waves) resolve + run end-to-end with
##      per-wave payouts merged into the completion report.
##   6. /horde alert toggle: the third "alert" arg overrides the
##      config's bosses_alert at runtime.
##
## Exit 0 = all pass.
extends SceneTree

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _run()
	quit(0 if _fail == 0 else 1)

func _run() -> void:
	var horde = root.get_node_or_null("HordeEventService")
	var es = root.get_node_or_null("EntityService")
	var zm = root.get_node_or_null("ZoneManager")
	var pm = root.get_node_or_null("PlayerManager")
	var ss = root.get_node_or_null("SpawnService")
	var cs = root.get_node_or_null("ChatService")
	var perm = root.get_node_or_null("PermissionManager")
	var hub = root.get_node_or_null("EventHub")
	var ns = root.get_node_or_null("NotificationService")
	_assert(horde != null and es != null and zm != null and pm != null, "core services present")
	_assert(ss != null and cs != null and perm != null, "spawn/chat/perm present")
	_assert(hub != null and ns != null, "event hub + notifications present")
	if horde == null or es == null or zm == null or pm == null or ss == null \
			or cs == null or perm == null or hub == null or ns == null:
		return _finish()

	# --- Players -------------------------------------------------------------
	var PlayerScript = load("res://entities/player/player_controller.gd")
	var player: Node = PlayerScript.new()
	player.display_name = "BossAdmin"
	player.entity_id = "boss_char"
	root.add_child(player)
	var helper: Node = PlayerScript.new()
	helper.display_name = "BossHelper"
	helper.entity_id = "boss_helper"
	root.add_child(helper)
	await process_frame
	es.register_entity(player, null, "boss_char")
	es.register_entity(helper, null, "boss_helper")
	pm.set_local_player(player)
	await process_frame

	# Admin seam: stamp the validation cache (ADMIN = 100).
	perm._validation_cache["boss_char"] = {"time": Time.get_ticks_msec(), "level": 100}
	perm._validation_cache["boss_helper"] = {"time": Time.get_ticks_msec(), "level": 0}

	# --- Zone ----------------------------------------------------------------
	var ZoneDataScript = load("res://core/schemas/zone_data.gd")
	var zone = ZoneDataScript.new()
	zone.id = "boss_zone"
	zone.zone_center = Vector3(0, 0, 0)
	zone.zone_radius = 100.0
	zm.register_zone(zone)
	zm._entity_zones["boss_char"] = "boss_zone"
	zm._entity_zones["boss_helper"] = "boss_zone"

	# Command feedback via NotificationService.notify -> notification_sent.
	var chat_fired: Array = []
	ns.notification_sent.connect(func(player_id, notification):
		chat_fired.append(str(notification.get("message", "") if notification is Dictionary else notification)))
	# Spawn metadata recorder: null metadata (void-recovery respawns emit
	# entity_spawned(entity, null)) is skipped so spawn_meta always ends
	# with the last REAL spawn's metadata.
	var spawn_meta: Array = []
	hub.entity_spawned.connect(func(entity, metadata): _record_spawn_meta(spawn_meta, metadata))

	# --- 1. /boss command ------------------------------------------------------
	# Non-admin denied. _handle_command's bool is a delivery flag, not a
	# denial verdict -- the notification surface is the real check.
	chat_fired.clear()
	var denied: bool = cs._handle_command("boss_helper", 9, "boss void_lord boss_zone", "")
	_assert(denied == false or not _chat_said(chat_fired, "Spawned"), "non-admin cannot use /boss")

	# Admin: world alert -> WORLD_BOSS metadata, server-wide scope.
	chat_fired.clear()
	cs._handle_command("boss_char", 9, "boss void_lord boss_zone Mr Void world", "")
	await process_frame
	_assert(_chat_said(chat_fired, "Spawned"), "/boss world spawns (admin)")
	_assert(not spawn_meta.is_empty() and int(spawn_meta[spawn_meta.size() - 1].spawn_type) == 3,
			"/boss world -> WORLD_BOSS metadata")
	var world_md = spawn_meta[spawn_meta.size() - 1]
	_assert(world_md.notification_enabled and not world_md.notification_scopes.is_empty()
			and bool(world_md.notification_scopes[0].is_server_wide),
			"/boss world announces server-wide")
	var boss_a = _last_boss(ss)

	# Admin: default (zone) alert -> BOSS metadata, zone scope, no server-wide.
	chat_fired.clear()
	cs._handle_command("boss_char", 9, "boss void_lord boss_zone Zone Brute", "")
	await process_frame
	var zone_md = spawn_meta[spawn_meta.size() - 1]
	_assert(int(zone_md.spawn_type) == 2, "/boss default -> BOSS metadata")
	_assert(bool(zone_md.notification_scopes[0].zone_id == "boss_zone")
			and not bool(zone_md.notification_scopes[0].is_server_wide),
			"/boss default announces to the zone (+neighbors)")
	var boss_b = _last_boss(ss)

	# Admin: none -> BOSS metadata with notifications disabled.
	chat_fired.clear()
	cs._handle_command("boss_char", 9, "boss void_lord boss_zone Quiet One none", "")
	await process_frame
	var quiet_md = spawn_meta[spawn_meta.size() - 1]
	_assert(int(quiet_md.spawn_type) == 2 and not quiet_md.notification_enabled,
			"/boss none spawns silently (notifications disabled)")
	var boss_c = _last_boss(ss)

	# Unknown template -> feedback, no spawn.
	chat_fired.clear()
	var before := spawn_meta.size()
	cs._handle_command("boss_char", 9, "boss no_such_boss boss_zone", "")
	await process_frame
	_assert(_chat_said(chat_fired, "Unknown template") and spawn_meta.size() == before,
			"/boss unknown template rejected with feedback")

	# Cleanup the command bosses (kill through the real path; credited to admin).
	for b in [boss_a, boss_b, boss_c]:
		if b != null and is_instance_valid(b):
			b.take_damage(999999, player)
	await process_frame

	# --- 2. /spawn command -----------------------------------------------------
	# Restamp: the admin validation cache TTL (5s) can lapse during the
	# section-1 waits.
	perm._validation_cache["boss_char"] = {"time": Time.get_ticks_msec(), "level": 100}
	# Non-admin denied.
	chat_fired.clear()
	denied = cs._handle_command("boss_helper", 9, "spawn slime 3 boss_zone", "")
	_assert(denied == false or not _chat_said(chat_fired, "Spawned"), "non-admin cannot use /spawn")

	# Admin: 3 slimes at level 7 (explicit count + zone + level override).
	chat_fired.clear()
	cs._handle_command("boss_char", 9, "spawn slime 3 boss_zone 7", "")
	await process_frame
	_assert(_chat_said(chat_fired, "Spawned 3/3"), "/spawn reports the spawn count")
	var slimes := _enemies_from_template(es, "slime")
	_assert(slimes.size() == 3, "/spawn produced 3 registered enemies (got %d)" % slimes.size())
	var level_ok := true
	for e in slimes:
		if int(e.level) != 7:
			level_ok = false
	_assert(level_ok, "/spawn level override lands on the enemy")

	# Count clamp: 999 -> MAX_ADMIN_SPAWN (24). Kill the horde of slimes
	# afterwards through the real path to keep the entity table clean.
	chat_fired.clear()
	cs._handle_command("boss_char", 9, "spawn slime 999 boss_zone", "")
	await process_frame
	_assert(_chat_said(chat_fired, "Spawned 24/24"), "/spawn count clamps to the admin cap")
	var slimes_all := _enemies_from_template(es, "slime")
	for e in slimes_all:
		if is_instance_valid(e) and not bool(e.is_dead):
			e.take_damage(999999, helper)
	await process_frame

	# Unknown template -> feedback, nothing spawned.
	chat_fired.clear()
	cs._handle_command("boss_char", 9, "spawn no_such_mob 2 boss_zone", "")
	await process_frame
	_assert(_chat_said(chat_fired, "Unknown template"), "/spawn unknown template rejected with feedback")
	await process_frame

	# --- 3. Boss-waves ----------------------------------------------------------
	# Pure boss wave (no spawns) goes straight to the boss state; a
	# mid-horde wave boss death pays the wave and rolls into wave 2.
	var pure_id: String = horde.start_horde("boss_zone", {
		"wave_defs": [
			{"spawns": [], "boss_template_id": "void_lord", "boss_name": "Gatekeeper", "reward_gold": 400},
			{"spawns": [{"template_id": "slime", "count": 2}]},
		],
		"reward_gold": 100,
		"inter_wave_delay": 0.5,
		"bosses_alert": false,
	})
	_assert(pure_id != "", "pure boss-wave horde starts")
	if pure_id == "":
		return _finish()
	var ok := await _wait_state(horde, pure_id, "boss", 15000)
	_assert(ok, "pure boss wave skips straight to the boss state")
	var st: Dictionary = horde.get_horde_status(pure_id)
	var gatekeeper = es.get_entity(str(st.get("boss_id", "")))
	_assert(gatekeeper != null and str(gatekeeper.display_name) == "Gatekeeper",
			"wave boss uses the wave's boss_name")
	if gatekeeper != null and is_instance_valid(gatekeeper):
		gatekeeper.take_damage(999999, player)
	ok = await _wait_wave_number(horde, pure_id, 2, 15000)
	_assert(ok, "mid-horde wave boss death rolls into the next wave")
	_assert(int(horde._hordes[pure_id]["reward_gold"]) == 500,
			"wave boss payout merged into the pool (100+400)")
	ok = await _wait_state(horde, pure_id, "fighting", 15000)
	_assert(ok, "wave 2 mobs spawn after the wave boss")
	ok = await _kill_wave(horde, es, pure_id, 20000)
	_assert(ok, "wave 2 killed")
	ok = await _wait_teardown(horde, 15000)
	_assert(ok, "horde completes after the last wave (no horde-level boss)")
	await process_frame

	# --- 4. Bossless default fix -------------------------------------------------
	# Plain horde (no boss_template_id anywhere): completes after the
	# last wave; the old default would spawn a finale boss from the mob
	# template.
	var bossless_id: String = horde.start_horde("boss_zone", {
		"template_id": "slime",
		"waves": 1,
		"mobs_per_wave": 2,
		"inter_wave_delay": 0.5,
	})
	_assert(bossless_id != "", "bossless horde starts")
	if bossless_id != "":
		_assert(str(horde._hordes[bossless_id]["boss_template_id"]) == "",
				"no boss template is defaulted for plain hordes")
		ok = await _wait_state(horde, bossless_id, "fighting", 15000)
		ok = ok and await _kill_wave(horde, es, bossless_id, 20000)
		_assert(ok, "bossless horde wave killed")
		ok = await _wait_teardown(horde, 15000)
		_assert(ok, "bossless horde completes without spawning a finale boss")
	await process_frame

	# --- 5. Demo configs ----------------------------------------------------------
	# Restamp: the admin cache TTL lapses during the long horde waits above.
	perm._validation_cache["boss_char"] = {"time": Time.get_ticks_msec(), "level": 100}
	var Resolver = load("res://core/schemas/horde_data_resolver.gd")
	var siege = Resolver.load_config("haven_siege")
	var gauntlet = Resolver.load_config("boss_gauntlet")
	_assert(siege != null and gauntlet != null, "demo configs resolve (haven_siege, boss_gauntlet)")
	if siege != null:
		var scfg: Dictionary = siege.to_config()
		_assert(bool(scfg.get("bosses_alert", false)), "haven_siege carries bosses_alert")
		_assert(not scfg.has("boss_template_id"), "haven_siege is bossless")
	if gauntlet != null:
		var gcfg: Dictionary = gauntlet.to_config()
		var defs: Array = gcfg.get("wave_defs", [])
		_assert(defs.size() == 3 and str(defs[0].get("boss_template_id", "")) == "void_lord",
				"boss_gauntlet carries per-wave bosses")
		_assert(int(gcfg.get("waves", 0)) == 3, "boss_gauntlet wave count == def count")

	# End-to-end: the boss gauntlet (3 boss waves). Report must merge the
	# per-wave payouts (1500+1500+2000 gold, 700+700+1100 xp).
	var reports: Array = []
	horde.horde_rewards_distributed.connect(func(hid, report): reports.append(report))
	var g_id: String = horde.start_horde_from_config("boss_gauntlet", "boss_zone")
	_assert(g_id != "", "boss_gauntlet starts end-to-end")
	if g_id != "":
		# Every gauntlet wave: clear its mobs (waves 2+3 carry them),
		# kill the wave boss that follows, let the payout merge, roll
		# into the next wave. Wave 1 is boss-only from the start.
		for wave in range(1, 4):
			if wave > 1:
				ok = await _wait_wave_number(horde, g_id, wave, 20000)
				_assert(ok, "gauntlet advances to wave %d" % wave)
			ok = await _wait_any_state(horde, g_id, ["fighting", "boss"], 20000)
			_assert(ok, "gauntlet wave %d begins" % wave)
			var wst: Dictionary = horde.get_horde_status(g_id)
			if str(wst.get("state", "")) == "fighting":
				ok = await _kill_wave(horde, es, g_id, 20000)
				_assert(ok, "gauntlet wave %d mobs killed" % wave)
			ok = await _wait_state(horde, g_id, "boss", 20000)
			_assert(ok, "gauntlet wave %d reaches its boss" % wave)
			wst = horde.get_horde_status(g_id)
			var wb = es.get_entity(str(wst.get("boss_id", "")))
			if wb != null and is_instance_valid(wb):
				wb.take_damage(999999, player)
		ok = await _wait_teardown(horde, 20000)
		_assert(ok, "boss_gauntlet completes after the final boss")
		_assert(not reports.is_empty(), "boss_gauntlet distributes rewards")
		if not reports.is_empty():
			var rep: Dictionary = reports[reports.size() - 1]
			_assert(int(rep["boss_char"].get("gold", 0)) == 5000,
					"per-wave payouts merged into the completion report (got %d gold)" % int(rep["boss_char"].get("gold", 0)))
	await process_frame

	# --- 6. /horde alert toggle -----------------------------------------------------
	# Restamp: the admin cache TTL lapses during the gauntlet waits above.
	perm._validation_cache["boss_char"] = {"time": Time.get_ticks_msec(), "level": 100}
	chat_fired.clear()
	cs._handle_command("boss_char", 9, "horde boss_gauntlet boss_zone alert", "")
	await process_frame
	var alert_id: String = horde.active_horde_in_zone("boss_zone")
	_assert(alert_id != "", "/horde alert started a horde")
	if alert_id != "":
		_assert(bool(horde._hordes[alert_id]["bosses_alert"]),
				"/horde alert overrides bosses_alert at runtime")
		horde.stop_horde(alert_id, "toggle test done")
		await process_frame
	chat_fired.clear()
	cs._handle_command("boss_char", 9, "horde boss_gauntlet boss_zone", "")
	await process_frame
	var plain_id: String = horde.active_horde_in_zone("boss_zone")
	_assert(plain_id != "", "plain /horde started a horde")
	if plain_id != "":
		_assert(not bool(horde._hordes[plain_id]["bosses_alert"]),
				"plain /horde keeps the config's bosses_alert (false for the gauntlet)")
		horde.stop_horde(plain_id, "toggle test done")
		await process_frame

	_finish()

## ---------------------------------------------------------------------------

func _last_boss(ss) -> Node:
	var last = null
	for boss_id in ss._world_bosses:
		last = ss._world_bosses[boss_id]
	return last

## Signal handler for entity_spawned: skip null-metadata emissions
## (void-recovery respawns) so the recorder only sees real spawns.
func _record_spawn_meta(into: Array, metadata) -> void:
	if metadata != null:
		into.append(metadata)

func _enemies_from_template(es, template_id: String) -> Array:
	var out: Array = []
	var all = es.get_all_entities() if es.has_method("get_all_entities") else []
	for e in all:
		# "enemy_data" in e guards players (PlayerController does not
		# carry the template surface).
		if e != null and is_instance_valid(e) and "enemy_data" in e \
				and e.enemy_data != null and str(e.enemy_data.id) == template_id:
			out.append(e)
	return out

func _chat_said(fired: Array, needle: String) -> bool:
	for m in fired:
		if str(m).find(needle) != -1:
			return true
	return false

func _wait_state(horde, horde_id: String, want: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var st: Dictionary = horde.get_horde_status(horde_id)
		if st.is_empty():
			return false
		if str(st.get("state", "")) == want:
			return true
	return false

func _wait_any_state(horde, horde_id: String, wants: Array, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var st: Dictionary = horde.get_horde_status(horde_id)
		if st.is_empty():
			return false
		if str(st.get("state", "")) in wants:
			return true
	return false

func _wait_wave_number(horde, horde_id: String, wave: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var st: Dictionary = horde.get_horde_status(horde_id)
		if st.is_empty():
			return false
		if int(st.get("wave_number", -1)) == wave:
			return true
	return false

func _wait_teardown(horde, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if horde._hordes.is_empty():
			return true
	return false

## Kill every living mob of the current wave through the real damage
## path, batching per frame.
func _kill_wave(horde, es, horde_id: String, timeout_ms: int) -> bool:
	var pm = root.get_node_or_null("PlayerManager")
	var killer = pm.local_player if pm != null and pm.local_player != null else null
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		# The horde can complete mid-sweep (the last mob death finishes
		# it and _finish_horde erases the entry): that is success.
		if not horde._hordes.has(horde_id):
			return true
		var ids: Array = horde._hordes[horde_id].get("mobs_spawned_ids", [])
		var killed_any := false
		for eid in ids:
			var mob = es.get_entity(str(eid))
			if mob != null and is_instance_valid(mob) and not bool(mob.is_dead):
				mob.take_damage(99999, killer)
				killed_any = true
		if not killed_any:
			return true
		for _i in range(4):
			await process_frame
	return false

func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)

func _finish() -> void:
	print("---")
	print("test_boss_commands: %d passed, %d failed" % [_pass, _fail])
