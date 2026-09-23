## test_horde_configs.gd - HordeData configs, mixed waves, instance
## subtrees, /horde command, and the spawn_boss credit fixes.
## Run headless:
##
##   cd game && godot --headless --path . --script res://tests/test_horde_configs.gd
##
## Covers:
##   1. HordeDataResolver: convention path + prefixed variant + unknown.
##   2. start_horde_from_config: mixed templates per wave (real Enemy
##      nodes per template), wave totals, per-wave payout merge, boss
##      finale, completion with proportional rewards.
##   3. Instance-scoped horde: mobs + participants pinned under
##      /world/instances/<scope>/ (zone path untouched), snapshot_for_instance
##      reads it back, sweep releases the pin and unbinds the instance slot.
##   4. /horde command: non-admin denied, admin lists configs, starts,
##      status + stop work, unknown config rejected.
##   5. spawn_boss fixes: boss is in the tree, carries enemy_data, and
##      its death emits kill_rewarded (credited killer) + pays XP/gold.
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
	var proj = root.get_node_or_null("WorldStateProjection")
	var ss = root.get_node_or_null("SpawnService")
	var cs = root.get_node_or_null("ChatService")
	var perm = root.get_node_or_null("PermissionManager")
	var ds = root.get_node_or_null("DataService")
	_assert(horde != null, "HordeEventService present")
	_assert(es != null and zm != null and pm != null, "core services present")
	_assert(proj != null, "WorldStateProjection present")
	_assert(ss != null and cs != null and perm != null, "spawn/chat/perm present")
	if horde == null or es == null or zm == null or pm == null or proj == null \
			or ss == null or cs == null or perm == null:
		return _finish()

	# --- Players -------------------------------------------------------------
	var PlayerScript = load("res://entities/player/player_controller.gd")
	var player: Node = PlayerScript.new()
	player.display_name = "ConfigHero"
	player.entity_id = "cfg_char"
	root.add_child(player)
	var helper: Node = PlayerScript.new()
	helper.display_name = "ConfigHelper"
	helper.entity_id = "cfg_helper"
	root.add_child(helper)
	await process_frame
	es.register_entity(player, null, "cfg_char")
	es.register_entity(helper, null, "cfg_helper")
	pm.set_local_player(player)
	await process_frame

	# --- Admin seam: stamp the validation cache (ADMIN = 100) ----------------
	perm._validation_cache["cfg_char"] = {"time": Time.get_ticks_msec(), "level": 100}
	perm._validation_cache["cfg_helper"] = {"time": Time.get_ticks_msec(), "level": 0}
	_assert(perm.is_admin("cfg_char"), "admin seam: stamped player resolves ADMIN")
	_assert(not perm.is_admin("cfg_helper"), "admin seam: unstamped player is not admin")

	# --- Zones ---------------------------------------------------------------
	var ZoneDataScript = load("res://core/schemas/zone_data.gd")
	var zone_a = ZoneDataScript.new()
	zone_a.id = "cfg_zone"
	zone_a.zone_center = Vector3(0, 0, 0)
	zone_a.zone_radius = 100.0
	zm.register_zone(zone_a)
	zm._entity_zones["cfg_char"] = "cfg_zone"
	zm._entity_zones["cfg_helper"] = "cfg_zone"

	# --- 1. Resolver ---------------------------------------------------------
	var Resolver = load("res://core/schemas/horde_data_resolver.gd")
	var cfg = Resolver.load_config("trollmoot")
	_assert(cfg != null and cfg.has_method("to_config"), "resolver finds 'trollmoot' (convention path)")
	var cfg2 = Resolver.load_config("vault_seal")
	_assert(cfg2 != null, "resolver finds 'vault_seal'")
	_assert(Resolver.load_config("no_such_horde") == null, "resolver returns null on unknown id")
	var cfg_dict: Dictionary = cfg.to_config() if cfg != null else {}
	_assert(int(cfg_dict.get("reward_gold", 0)) == 1500, "to_config carries rewards")
	_assert(str(cfg_dict.get("instance_scope", "")) == "", "trollmoot is zone-scoped")
	_assert(not cfg_dict.get("wave_defs", []).is_empty(), "to_config carries wave_defs")
	var vault_dict: Dictionary = cfg2.to_config() if cfg2 != null else {}
	_assert(str(vault_dict.get("instance_scope", "")) == "dungeon", "vault_seal is instance-scoped")

	# --- 2. Mixed-template horde through the real pipeline -------------------
	var rewards_fired: Array = []
	horde.horde_rewards_distributed.connect(func(hid, report): rewards_fired.append([str(hid), report]))
	var horde_id: String = horde.start_horde_from_config("trollmoot", "cfg_zone")
	_assert(horde_id != "", "config horde starts")
	if horde_id == "":
		return _finish()

	var ok := await _wait_fighting(horde, horde_id, 8, 30000)
	_assert(ok, "wave 1 (8 slimes) reaches fighting")
	if not ok:
		return _finish()
	var wave1_ids: Array = horde._hordes[horde_id]["mobs_spawned_ids"]
	_assert(wave1_ids.size() == 8, "wave 1 tracked 8 mobs")
	var all_slime := true
	for eid in wave1_ids:
		var e = es.get_entity(str(eid))
		if e == null or e.enemy_data == null or str(e.enemy_data.id) != "slime":
			all_slime = false
	_assert(all_slime, "wave 1 mobs are all slimes (per-wave template)")

	ok = await _kill_wave(horde, es, horde_id, 30000)
	_assert(ok, "wave 1 killed through the real path")
	ok = await _wait_wave_number(horde, horde_id, 2, 30000)
	_assert(ok, "wave 2 begins")

	ok = await _wait_fighting(horde, horde_id, 10, 30000)
	_assert(ok, "wave 2 (6 slimes + 4 wolves) reaches fighting")
	var wave2_ids: Array = horde._hordes[horde_id]["mobs_spawned_ids"]
	var slime_count := 0
	var wolf_count := 0
	for eid in wave2_ids:
		var e = es.get_entity(str(eid))
		if e != null and e.enemy_data != null:
			if str(e.enemy_data.id) == "slime":
				slime_count += 1
			elif str(e.enemy_data.id) == "wolf":
				wolf_count += 1
	_assert(slime_count == 6 and wolf_count == 4,
			"wave 2 mixed templates (6 slime + %d wolf, got %d/%d)" % [wolf_count, slime_count, wolf_count])

	ok = await _kill_wave(horde, es, horde_id, 30000)
	_assert(ok, "wave 2 killed")
	ok = await _wait_wave_number(horde, horde_id, 3, 30000)
	_assert(ok, "wave 3 begins")
	ok = await _wait_fighting(horde, horde_id, 8, 30000)
	_assert(ok, "wave 3 (6 wolves + 2 elites) reaches fighting")
	var wave3_ids: Array = horde._hordes[horde_id]["mobs_spawned_ids"]
	var elite_count := 0
	for eid in wave3_ids:
		var e = es.get_entity(str(eid))
		if e != null and e.enemy_data != null and str(e.enemy_data.id) == "troll_elite":
			elite_count += 1
	_assert(elite_count == 2, "wave 3 carries 2 elites")

	ok = await _kill_wave(horde, es, horde_id, 30000)
	_assert(ok, "wave 3 killed")
	ok = await _wait_boss(horde, horde_id, 30000)
	_assert(ok, "boss finale (Trollmoot Chieftain) spawns")
	var st: Dictionary = horde.get_horde_status(horde_id)
	var boss = es.get_entity(str(st.get("boss_id", "")))
	_assert(boss != null and is_instance_valid(boss), "boss resolvable")
	if boss != null and is_instance_valid(boss):
		boss.take_damage(999999, player)
	ok = await _wait_teardown(horde, 30000)
	_assert(ok, "horde completes after boss death")
	_assert(rewards_fired.size() >= 1, "rewards distributed for config horde")
	if not rewards_fired.is_empty():
		var report: Dictionary = rewards_fired[0][1]
		_assert(report.has("cfg_char"), "credited player in config-horde report")
		_assert(int(report["cfg_char"].get("kills", 0)) >= 26,
				"kills accumulate across mixed waves (got %d)" % int(report["cfg_char"].get("kills", 0)))
	await process_frame

	# --- 3. Instance-scoped horde --------------------------------------------
	var vault_id: String = horde.start_horde_from_config("vault_seal", "cfg_zone")
	_assert(vault_id != "", "instance horde starts")
	if vault_id == "":
		return _finish()
	_assert(str(horde._hordes[vault_id]["instance_scope"]) == "dungeon", "instance scope recorded")
	var second: String = horde.start_horde_from_config("vault_seal", "cfg_zone")
	_assert(second == "", "second horde in the same instance rejected")

	ok = await _wait_fighting(horde, vault_id, 6, 30000)
	_assert(ok, "instance horde wave 1 reaches fighting")
	var inst_ids: Array = horde._hordes[vault_id]["mobs_spawned_ids"]
	var pinned_all := true
	for eid in inst_ids:
		if str(proj.get_entity_scope_override(str(eid))) != "instance:dungeon":
			pinned_all = false
	_assert(pinned_all, "instance horde mobs pinned to instance:dungeon")
	# Damage a mob -> the player participates -> player pin lands too.
	var mob0 = es.get_entity(str(inst_ids[0]))
	if mob0 != null and is_instance_valid(mob0):
		mob0.take_damage(5, player)
		await process_frame
		_assert(str(proj.get_entity_scope_override("cfg_char")) == "instance:dungeon",
				"participant pinned to the instance scope")
	# Flush and check the instance subtree in the tree + snapshot helper.
	proj.flush(true)
	await process_frame
	var inst_snapshot: Array = proj.snapshot_for_instance("dungeon")
	_assert(not inst_snapshot.is_empty(), "snapshot_for_instance reads instance subtree")
	var zone_snapshot: Array = proj.snapshot_for_zone("cfg_zone")
	var leaked := false
	for entry in zone_snapshot:
		if entry is Array and entry.size() >= 1 and str(entry[0]).contains("instances/"):
			leaked = true
	_assert(not leaked, "zone snapshot carries no instance entries")
	# Teardown: stop releases pins + the instance slot.
	horde.stop_horde(vault_id, "test teardown")
	await process_frame
	var pin_left := false
	for eid in inst_ids:
		if str(proj.get_entity_scope_override(str(eid))) != "":
			pin_left = true
	_assert(not pin_left, "sweep releases mob pins")
	_assert(str(proj.get_entity_scope_override("cfg_char")) == "", "sweep releases participant pins")
	_assert(proj.active_instance_scopes().is_empty(), "no instance scopes hold projected state after stop")

	# --- 4. /horde command ----------------------------------------------------
	# Re-stamp the admin seam: the permission cache TTL is 5s and the
	# horde runs above took longer, so the early stamp is stale by now.
	perm._validation_cache["cfg_char"] = {"time": Time.get_ticks_msec(), "level": 100}
	var chat_fired: Array = []
	# Feedback flows through NotificationService.notify -> notification_sent.
	var ns = root.get_node_or_null("NotificationService")
	if ns != null and ns.has_signal("notification_sent"):
		ns.notification_sent.connect(func(player_id, notification):
			chat_fired.append(str(notification.get("message", "") if notification is Dictionary else notification)))
	# Non-admin denied.
	var denied: bool = cs._handle_command("cfg_helper", 9, "horde trollmoot", "")
	_assert(denied == false or not _chat_said(chat_fired, "Started"), "non-admin cannot start a horde")
	# List.
	chat_fired.clear()
	cs._handle_command("cfg_char", 9, "horde", "")
	_assert(_chat_said(chat_fired, "trollmoot"), "/horde lists available configs")
	# Start with explicit zone.
	chat_fired.clear()
	cs._handle_command("cfg_char", 9, "horde vault_seal cfg_zone", "")
	_assert(_chat_said(chat_fired, "Started"), "admin starts a horde via /horde")
	var cmd_id: String = horde.active_horde_in_zone("cfg_zone")
	_assert(cmd_id != "" and str(horde._hordes[cmd_id]["instance_scope"]) == "dungeon",
			"/horde start produced a live instance horde")
	# Status.
	chat_fired.clear()
	cs._handle_command("cfg_char", 9, "horde status", "")
	_assert(_chat_said(chat_fired, "wave"), "/horde status reports the live horde")
	# Stop.
	chat_fired.clear()
	cs._handle_command("cfg_char", 9, "horde stop", "")
	_assert(_chat_said(chat_fired, "Stopped"), "/horde stop ends the horde")
	_assert(horde.active_horde_in_zone("cfg_zone") == "", "no horde active after /horde stop")
	# Unknown config.
	chat_fired.clear()
	cs._handle_command("cfg_char", 9, "horde no_such_horde cfg_zone", "")
	_assert(_chat_said(chat_fired, "Unknown config"), "unknown config rejected with the list")

	# --- 5. spawn_boss fixes ---------------------------------------------------
	# /horde not involved: direct pipeline check.
	var boss2 = ss.spawn_boss("void_lord", Vector3(0, 0, 0), "cfg_zone", "Probe Lord")
	_assert(boss2 != null, "spawn_boss produces a boss")
	if boss2 != null:
		_assert(boss2.is_inside_tree(), "boss is parented into the scene tree")
		_assert(boss2.enemy_data != null, "boss carries enemy_data (credit/projection surface)")
		var kr_fired: Array = []
		var hub = root.get_node_or_null("EventHub")
		hub.kill_rewarded.connect(func(e, k, r): kr_fired.append([r.get("player_id", ""), int(r.get("xp", 0)), int(r.get("gold", 0))]))
		var gold_before := int(player.gold)
		var xp_before := int(player.experience)
		boss2.take_damage(999999, player)
		await process_frame
		await process_frame
		_assert(kr_fired.size() >= 1, "boss death emits kill_rewarded")
		if not kr_fired.is_empty():
			_assert(str(kr_fired[0][0]) == "cfg_char", "boss kill credited to the killer")
			_assert(int(kr_fired[0][1]) > 0 and int(kr_fired[0][2]) > 0,
					"boss kill pays XP and gold from EnemyData")
		_assert(int(player.experience) - xp_before > 0, "boss XP landed on the player")
		_assert(int(player.gold) - gold_before > 0, "boss gold landed on the player")
	await process_frame

	_finish()

## ---------------------------------------------------------------------------

func _chat_said(fired: Array, needle: String) -> bool:
	for m in fired:
		if str(m).find(needle) != -1:
			return true
	return false

func _wait_fighting(horde, horde_id: String, expected_alive: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var st: Dictionary = horde.get_horde_status(horde_id)
		if st.is_empty():
			return false
		if str(st.get("state", "")) == "fighting" and int(st.get("remaining", -1)) == expected_alive:
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

func _wait_boss(horde, horde_id: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var st: Dictionary = horde.get_horde_status(horde_id)
		if st.is_empty():
			return false
		if str(st.get("state", "")) == "boss" and str(st.get("boss_id", "")) != "":
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
## path, batching per frame (16+ mobs can die in one tick; frames let
## signals and unregistrations settle).
func _kill_wave(horde, es, horde_id: String, timeout_ms: int) -> bool:
	var pm = root.get_node_or_null("PlayerManager")
	var killer = pm.local_player if pm != null and pm.local_player != null else null
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
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
	print("test_horde_configs: %d passed, %d failed" % [_pass, _fail])
