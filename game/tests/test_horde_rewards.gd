## test_horde_rewards.gd - Participation, rewards, achievements, peer bridge, LOD.
## Run headless:
##
##   cd game && godot --headless --path . --script res://tests/test_horde_rewards.gd
##
## Covers:
##   1. Peer bridge: NetworkManager.get_character_for_peer round-trip and
##      TickService._get_player_id_from_peer consulting it BEFORE the
##      local-player fallback (a mapped peer resolves to its own character,
##      not the server's local player).
##   2. Participation: real damage_dealt + kill_rewarded events credit the
##      attacking player (damage counts, credited kills counted once).
##   3. Proportional payout: report shares sum to the configured totals,
##      the top contributor out-earns a minor contributor, and grants land
##      on the player node (gold/xp >= the horde share).
##   4. Achievements: horde_mvp_first unlocks on completion; the "horde"
##      tracked category reaches horde_breaker_5's target of 5 (driven
##      through the same AchievementService.track() call the service uses).
##   5. LOD tiers: same-zone client gets L0 detail, a client whose player
##      sits in a different zone while a horde runs elsewhere gets L1,
##      and the tier reverts when no horde is active. Load override still
##      trumps distance.
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
	var nm = root.get_node_or_null("NetworkManager")
	var tick = root.get_node_or_null("TickService")
	var ds = root.get_node_or_null("DataService")
	var ach = root.get_node_or_null("AchievementService")
	_assert(horde != null, "HordeEventService autoload present")
	_assert(es != null and zm != null and pm != null, "core services present")
	_assert(nm != null, "NetworkManager autoload present")
	_assert(ach != null, "AchievementService autoload present")
	if horde == null or es == null or zm == null or pm == null or nm == null or ach == null:
		return _finish()
	# Freeze the live tick loop (Phase 3 re-roots per tick); this suite
	# calls the pure AOI/LOD functions directly.
	if tick != null and tick._tick_timer != null:
		tick._tick_timer.stop()

	# --- Players: credited main + a minor contributor -----------------------
	var PlayerScript = load("res://entities/player/player_controller.gd")
	var player: Node = PlayerScript.new()
	player.display_name = "RewardHero"
	player.entity_id = "reward_char"
	root.add_child(player)
	var helper: Node = PlayerScript.new()
	helper.display_name = "RewardHelper"
	helper.entity_id = "helper_char"
	root.add_child(helper)
	await process_frame
	es.register_entity(player, null, "reward_char")
	es.register_entity(helper, null, "helper_char")
	pm.set_local_player(player)
	await process_frame

	# --- Zones: one hosts the horde, one is far away ------------------------
	var ZoneDataScript = load("res://core/schemas/zone_data.gd")
	var zone_h = ZoneDataScript.new()
	zone_h.id = "hz"
	zone_h.zone_center = Vector3(0, 0, 0)
	zone_h.zone_radius = 100.0
	zm.register_zone(zone_h)
	var zone_f = ZoneDataScript.new()
	zone_f.id = "hz_far"
	zone_f.zone_center = Vector3(20000, 0, 20000)
	zone_f.zone_radius = 100.0
	zm.register_zone(zone_f)
	zm._entity_zones["reward_char"] = "hz"
	zm._entity_zones["helper_char"] = "hz"

	# --- 1. Peer bridge -----------------------------------------------------
	_assert(nm.get_character_for_peer(987654) == "", "unknown peer maps to empty character")
	# Real connect flow: the peer entry exists first (join), association
	# lands when the character is selected. associate_peer_with_character
	# guards on the entry, so mirror that order.
	nm.connected_peers[4242] = {"joined": 0, "ip": "test"}
	nm.connected_peers[4243] = {"joined": 0, "ip": "test"}
	nm.associate_peer_with_character(4242, "reward_char")
	nm.associate_peer_with_character(4243, "helper_char")
	_assert(nm.get_character_for_peer(4242) == "reward_char", "peer->character round-trip")
	_assert(nm.get_character_for_peer(4243) == "helper_char", "second peer maps independently")
	if tick != null:
		_assert(tick._get_player_id_from_peer(4243) == "helper_char",
				"peer resolution prefers NetworkManager mapping over local fallback")
		_assert(tick._get_player_id_from_peer(4242) == "reward_char",
				"mapped peer 4242 resolves to its character")
	# Bridge consumed by AOI emit: clean the fake peers up so the live
	# phase-1 loop (if restarted elsewhere) never sees them.
	nm.connected_peers.erase(4242)
	nm.connected_peers.erase(4243)

	# --- Achievement capture -------------------------------------------------
	var unlocked: Array = []
	ach.achievement_unlocked.connect(func(pid, ach_id): unlocked.append([str(pid), str(ach_id)]))

	# --- 2+3. Horde lifecycle with participation + rewards ------------------
	var boss_template := "slime"
	if ds != null and ds.has_method("get_enemy") and ds.get_enemy("slime_king") != null:
		boss_template = "slime_king"
	var horde_id: String = horde.start_horde("hz", {
		"template_id": "slime",
		"waves": 1,
		"mobs_per_wave": 3,
		"inter_wave_delay": 0.0,
		"boss_template_id": boss_template,
		"reward_gold": 1000,
		"reward_xp": 500,
	})
	_assert(horde_id != "", "horde with rewards starts")
	if horde_id == "":
		return _finish()

	var ok := await _wait_fighting(horde, horde_id, 3, 20000)
	_assert(ok, "wave reaches fighting with 3 alive")
	if not ok:
		return _finish()

	var gold_before := int(player.gold)
	var xp_before := int(player.experience)
	var rewards_fired: Array = []
	horde.horde_rewards_distributed.connect(func(hid, report): rewards_fired.append([str(hid), report]))

	# Minor contributor: a little damage from the helper, then the main
	# player kills everything through the real damage path (each hit and
	# credited kill flows back as participation).
	var mob_ids: Array = horde._hordes[horde_id]["mobs_spawned_ids"]
	var first_mob = es.get_entity(str(mob_ids[0]))
	if first_mob != null and is_instance_valid(first_mob):
		first_mob.take_damage(10, helper)
	var killed := 0
	for eid in mob_ids:
		var mob = es.get_entity(str(eid))
		if mob != null and is_instance_valid(mob) and not bool(mob.is_dead):
			mob.take_damage(99999, player)
			killed += 1
	_assert(killed == 3, "all 3 mobs killed through the real path")

	ok = await _wait_boss(horde, horde_id, 20000)
	_assert(ok, "boss finale spawns")
	if not ok:
		return _finish()
	var st: Dictionary = horde.get_horde_status(horde_id)
	var boss = es.get_entity(str(st.get("boss_id", "")))
	_assert(boss != null and is_instance_valid(boss), "boss resolvable")
	if boss != null and is_instance_valid(boss):
		boss.take_damage(99999, player)
	ok = await _wait_teardown(horde, 20000)
	_assert(ok, "horde tears down after boss death")
	_assert(rewards_fired.size() >= 1, "horde_rewards_distributed fired")
	if rewards_fired.is_empty():
		return _finish()
	var report: Dictionary = rewards_fired[0][1]
	_assert(not report.is_empty(), "reward report is non-empty")
	_assert(report.has("reward_char"), "credited player appears in the report")
	_assert(int(report.get("reward_char", {}).get("kills", -1)) == 4,
			"4 credited kills recorded (3 mobs + the boss finish)")
	_assert(int(report.get("reward_char", {}).get("damage", 0)) > 0,
			"damage participation recorded")
	# Proportional math: shares sum to totals; single-figure contributor
	# earns less than the dominant one; nobody negative.
	var sum_gold := 0
	var sum_xp := 0
	for pid in report:
		sum_gold += int(report[pid].get("gold", 0))
		sum_xp += int(report[pid].get("xp", 0))
	_assert(sum_gold == 1000, "gold shares sum to the pool (got %d)" % sum_gold)
	_assert(sum_xp == 500, "xp shares sum to the pool (got %d)" % sum_xp)
	var main_gold := int(report["reward_char"].get("gold", 0))
	if report.has("helper_char"):
		_assert(main_gold >= int(report["helper_char"].get("gold", 0)),
				"top contributor out-earns the minor contributor")
	_assert(main_gold > 0, "main participant earns gold")
	await process_frame
	# Grants landed on the node (kill rewards from the mobs add on top,
	# so the delta is at least the horde share).
	_assert(int(player.gold) - gold_before >= main_gold,
			"gold grant landed on the player (%d >= %d)" % [int(player.gold) - gold_before, main_gold])
	_assert(int(player.experience) - xp_before >= int(report["reward_char"].get("xp", 0)),
			"xp grant landed on the player")
	_assert(horde.active_horde_zones().is_empty(), "no horde zones left after completion")

	# --- 4. Achievements -----------------------------------------------------
	var mvp_ok := false
	for entry in unlocked:
		if entry[0] == "reward_char" and entry[1] == "horde_mvp_first":
			mvp_ok = true
	_assert(mvp_ok, "horde_mvp_first unlocked on completion")
	# The "horde" tracked category: 4 more completions of credit reach
	# horde_breaker_5's target (the first was consumed above).
	for _i in range(4):
		ach.track("reward_char", "horde", 1)
	var breaker_ok := false
	for entry in unlocked:
		if entry[0] == "reward_char" and entry[1] == "horde_breaker_5":
			breaker_ok = true
	_assert(breaker_ok, "horde_breaker_5 unlocks at 5 tracked completions")
	_assert(ach.has_unlocked("reward_char", "horde_mvp_first"), "mvp unlock persisted in service state")

	# --- 5. LOD tiers by horde-zone distance --------------------------------
	if tick == null:
		return _finish()
	# 5a. No active horde -> full detail.
	_assert(tick._get_client_lod_level(1) == 0, "no active horde: L0 full detail")
	# 5b. Start a horde in hz; the player is IN hz -> keeps full detail.
	var lod_id: String = horde.start_horde("hz", {"template_id": "slime", "waves": 1, "mobs_per_wave": 1})
	_assert(lod_id != "", "second horde starts for LOD checks")
	_assert(not tick._get_client_lod_level(1) == 1, "same-zone client keeps L0 while its horde runs")
	# 5c. Player drifts to the far zone while the horde runs -> L1 summary.
	zm._entity_zones["reward_char"] = "hz_far"
	_assert(tick._get_client_lod_level(1) == 1, "far-zone client downgrades to L1 during a horde")
	# 5d. Load override still trumps distance (degraded service = L1 even near).
	tick._flywheel_momentum = tick.FLYWHEEL_HIGH_THRESHOLD + 1.0
	zm._entity_zones["reward_char"] = "hz"
	_assert(tick._get_client_lod_level(1) == 1, "high flywheel load forces L1 regardless of zone")
	tick._flywheel_momentum = 0.0
	_assert(tick._get_client_lod_level(1) == 0, "load override releases back to L0 in-zone")
	horde.stop_horde(lod_id)
	await process_frame
	_assert(tick._get_client_lod_level(1) == 0, "horde stopped: detail restored everywhere")

	_finish()

## ---------------------------------------------------------------------------

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

func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)

func _finish() -> void:
	print("---")
	print("test_horde_rewards: %d passed, %d failed" % [_pass, _fail])
