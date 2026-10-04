## test_full_boot_live.gd - FULL-BOOT live test: the game plays itself.
##
## Boots the REAL playable scene (world_playable.tscn, the same scene a
## player lands in) and then drives every system from the previous phases
## through their production entry points:
##
##   1. Boot: player registered, HUD alive, zone entered.
##   2. Training dummy: no AI, no aggro component, damage lands (armor
##     /resist measured), heal lands, death pays NOTHING (no kill
##      rewards, no loot drop) and the scene respawn cycle rebuilds it.
##   3. /spawn: admin spawns 3 slimes (+2 at level 5), one is killed
##      through the real combat loop (create_hitbox) and pays kill
##      rewards -> loot drop possible.
##   4. /boss open world: world alert boss spawns (WORLD_BOSS metadata,
##      server-wide scope), dies to the player.
##   5. World-boss timer: short-interval schedule spawns, dies, respawns
##      on the interval (death -> downtime -> live again).
##   6. Open-world horde: haven_siege with the alert toggle, swept to
##      completion, horde_completed(success=true).
##   7. Dungeon portal: gateway use through the real WorldService path,
##      auto-horde starts, player pinned to the instance scope, swept
##      to completion.
##
## Run under xvfb (NOT headless -- the point is the real boot):
##
##   cd game && xvfb-run -a godot --path . --script res://tests/test_full_boot_live.gd
##
## Exit 0 = every checkpoint observed. Failures print FAIL and exit 1.
extends SceneTree

var _pass := 0
var _fail := 0

var _rewards_log: Array = []      # kill_rewarded payloads
var _spawn_metas: Array = []      # entity_spawned metadata (non-null)
var _horde_bosses: Array = []     # nodes from horde_boss_spawned
var _horde_completed := [false]   # horde_completed event latch
var _horde_success := [false]     # success flag of the last completed horde

var _es = null
var _cs = null
var _ss = null
var _pm = null
var _zm = null
var _ws = null
var _horde = null
var _perm = null
var _hub = null
var _gls = null

var _watchdog_fired := [false]

func _initialize() -> void:
	print("=== FULL-BOOT LIVE TEST: booting the real playable scene ===")
	# Watchdog: a SCRIPT ERROR mid-run aborts the _run coroutine (quit()
	# never executes) and the process then ticks forever -- the exact hang
	# the first live run produced. Force-exit so the failure is reported.
	var wd := Timer.new()
	wd.wait_time = 300.0
	wd.one_shot = true
	wd.timeout.connect(func():
		if not _watchdog_fired[0]:
			_watchdog_fired[0] = true
			_fail += 1
			print("  FAIL: watchdog timeout (300s) - a phase crashed the run coroutine")
			quit(1))
	root.add_child(wd)
	wd.start()
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	if scene == null:
		print("  FAIL: could not load world_playable.tscn")
		quit(1)
		return
	var inst := scene.instantiate()
	root.add_child(inst)
	current_scene = inst
	_run.call_deferred()

## ------------------------------------------------------------- framework

func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS: %s %s" % [label, detail])
	else:
		_fail += 1
		print("  FAIL: %s %s" % [label, detail])

func _banner(what: String) -> void:
	print("--- phase: %s ---" % what)

func _wait_until(fn: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if fn.call():
			return true
	return false

func _admin_id() -> String:
	return str(_player().entity_id) if _player() != null else ""

## The PermissionManager validation cache TTL is 5s; re-stamp right
## before every command phase (test seam, same as test_boss_commands).
func _be_admin() -> void:
	if _perm != null and _admin_id() != "":
		_perm._validation_cache[_admin_id()] = {
			"time": Time.get_ticks_msec(), "level": 100}

func _cmd(text: String) -> void:
	_be_admin()
	_cs._handle_command(_admin_id(), 9, text, "")
	await process_frame
	await process_frame

func _player() -> Node:
	return current_scene.get_node_or_null("Player")

func _named_in_group(group_name: String, display: String) -> Array:
	var out: Array = []
	for n in get_nodes_in_group(group_name):
		if is_instance_valid(n) and str(n.display_name) == display:
			out.append(n)
	return out

### Kill every live mob of a horde (and any wave boss) with the player as
## killer, repeatedly, until the horde reports completed or timeout.
## Keeps the bot player topped up (dungeon mobs fight back) and accepts
## completion either via the status dict OR the horde_completed event
## (the dict can be erased on completion before we observe it).
## Duck-typed throughout: horde wave bosses are bare Entities
## (take_damage + is_alive on the base class), while spawned mobs are
## Enemy nodes (take_damage routes through health_component).
func _sweep_horde(horde_id: String, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	var player := _player()
	while Time.get_ticks_msec() < deadline:
		await process_frame
		# The bot player must survive the sweep: heal to full each cycle.
		if player != null and is_instance_valid(player) \
				and "health_component" in player \
				and player.health_component != null \
				and not player.health_component.is_dead():
			player.health_component.current_health = player.health_component.max_health
		if _horde_completed[0]:
			return true
		var st: Dictionary = _horde.get_horde_status(horde_id)
		if st.is_empty():
			# Status gone: completion event decides (it may lag one frame).
			await process_frame
			return _horde_completed[0]
		if bool(st.get("completed", false)) or str(st.get("state", "")) == "completed":
			return true
		# Kill the wave's mobs.
		var mobs: Array = _horde._hordes.get(horde_id, {}).get("mobs_spawned_ids", [])
		for eid in mobs:
			var mob = _es.get_entity(str(eid))
			if mob != null and is_instance_valid(mob) and mob.is_alive():
				mob.take_damage(999999, player)
		# Kill any spawned wave boss (bare Entity or Enemy -- is_alive()
		# and take_damage exist on the base Entity class for both).
		for boss in _horde_bosses:
			if boss != null and is_instance_valid(boss) and boss.is_alive():
				boss.take_damage(999999, player)
		await create_timer(1.0).timeout
	return false

## ------------------------------------------------------------------ run

func _run() -> void:
	await process_frame
	await process_frame

	_es = root.get_node_or_null("EntityService")
	_cs = root.get_node_or_null("ChatService")
	_ss = root.get_node_or_null("SpawnService")
	_pm = root.get_node_or_null("PlayerManager")
	_zm = root.get_node_or_null("ZoneManager")
	_ws = root.get_node_or_null("WorldService")
	_horde = root.get_node_or_null("HordeEventService")
	_perm = root.get_node_or_null("PermissionManager")
	_hub = root.get_node_or_null("EventHub")
	_gls = root.get_node_or_null("GroundLootService")
	_ok("core services present", _es != null and _cs != null and _ss != null
		and _pm != null and _zm != null and _ws != null and _horde != null
		and _perm != null and _hub != null and _gls != null)
	if _es == null or _cs == null or _ss == null or _pm == null or _zm == null \
			or _ws == null or _horde == null or _perm == null or _hub == null \
			or _gls == null:
		return _finish()

	# Event taps for the whole run.
	_hub.kill_rewarded.connect(func(_e, _k, r): _rewards_log.append(r))
	_hub.entity_spawned.connect(func(_e, md):
		if md != null:
			_spawn_metas.append(md))
	_horde.horde_boss_spawned.connect(func(_hid, boss): _horde_bosses.append(boss))

	var player := _player()
	_ok("player node present", player != null)
	if player == null:
		return _finish()
	# Direct scene runs skip the login path: make sure the service layer
	# knows who the local player is (idempotent).
	_pm.set_local_player(player)

	# Park the player far from all scene aggro ranges so wandering
	# wildlife cannot interfere with the scripted phases. Enemies under
	# test get teleported next to the player when combat is needed.
	# (30,30) stays clear of the dungeon disc (center 0,0,0 r200 -> the
	# scene disc r50 overlaps it; deep corners of the scene disc flip-
	# flop the seam detector every physics tick).
	player.global_position = Vector3(30, 1.0, 30)

	# --- 1. Boot ------------------------------------------------------------
	_banner("1 boot")
	_ok("HudLayer present", current_scene.get_node_or_null("HudLayer") != null)
	var zone_id: String = str(_zm.get_entity_zone_id(player)) if _zm.has_method("get_entity_zone_id") else ""
	_ok("player entered a zone", zone_id != "", "(zone %s)" % zone_id)
	_ok("scene enemies active", get_nodes_in_group("enemies").size() >= 5,
		"(%d enemies)" % get_nodes_in_group("enemies").size())

	# --- 2. Training dummy ---------------------------------------------------
	_banner("2 training dummy")
	var dummies := _named_in_group("enemies", "Training Dummy")
	_ok("dummy placed in the scene", dummies.size() == 1)
	if dummies.is_empty():
		return _finish()
	var dummy: Node = dummies[0]
	var dummy_id := str(dummy.entity_id)
	_ok("dummy registered in EntityService",
		dummy_id != "" and _es.get_entity_metadata(dummy_id) != null, "(id %s)" % dummy_id)
	_ok("dummy has NO ai brain", dummy._ai == null)
	_ok("dummy has NO aggro component", dummy.aggro_component == null)
	_ok("dummy flagged is_dummy", dummy.is_training_dummy())

	# Bring the dummy to the (parked) player and measure the combat flow.
	dummy.global_position = player.global_position + Vector3(0, 0, -1.5)
	await physics_frame
	var hp0: int = dummy.health_component.current_health
	var raw: Resource = player.basic_attack
	_ok("player has basic attack", raw != null)
	for i in range(5):
		player.create_hitbox(raw)
		await physics_frame
	var hp1: int = dummy.health_component.current_health
	_ok("dummy took damage (armor/resist path ran)", hp1 < hp0,
		"(%d -> %d)" % [hp0, hp1])
	dummy.health_component.heal(50)
	var hp2: int = dummy.health_component.current_health
	_ok("dummy heals (heal flow works)", hp2 > hp1, "(+%d)" % (hp2 - hp1))

	# Death pays nothing: snapshot reward count + drop count, kill it.
	var rewards_before := _rewards_log.size()
	var drops_before: int = _gls._drops.size()
	var dummy_died := [false]
	dummy.died.connect(func(_k): dummy_died[0] = true)
	dummy.take_damage(999999, player)
	await process_frame
	await process_frame
	_ok("dummy died through the real death chain", dummy_died[0])
	_ok("dummy death paid NO kill rewards", _rewards_log.size() == rewards_before)
	_ok("dummy death dropped NO loot", _gls._drops.size() == drops_before)
	_ok("dummy unregistered after death", _es.get_entity_metadata(dummy_id) == null)

	# --- 3. /spawn + combat loop + loot --------------------------------------
	_banner("3 /spawn + combat loop")
	var slimes_before := _named_in_group("enemies", "Slime").size()
	await _cmd("spawn slime 3 starter_plains")
	var slimes_after := _named_in_group("enemies", "Slime").size()
	_ok("/spawn created 3 slimes", slimes_after == slimes_before + 3,
		"(%d -> %d)" % [slimes_before, slimes_after])
	await _cmd("spawn slime 2 starter_plains 5")
	var lvl5 := 0
	for s in _named_in_group("enemies", "Slime"):
		if int(s.level) == 5:
			lvl5 += 1
	_ok("/spawn level override applied", lvl5 >= 2, "(%d at level 5)" % lvl5)

	# Kill one spawned slime through the real combat entry point.
	# Boost the bot's crit chance to ~100% (agility drives get_crit_chance)
	# so this deterministic kill exercises the crit styling path: is_crit
	# rides the widened damage_dealt signal and fires the CRITICAL toast.
	var crit_tap := [{"n": 0}]
	_hub.damage_dealt.connect(func(_s, _t, _a, _dt, is_crit): crit_tap[0]["n"] += 1 if is_crit else 0)
	if "stats" in player and player.stats is Dictionary:
		player.stats["agility"] = 400
	var victim: Node = null
	for s in _named_in_group("enemies", "Slime"):
		if int(s.level) == 1:
			victim = s
			break
	_ok("slime victim found", victim != null)
	var loot_from_slime := false
	if victim != null:
		victim.global_position = player.global_position + Vector3(0, 0, -1.5)
		await physics_frame
		var died := [false]
		victim.died.connect(func(_k): died[0] = true)
		# Baseline BEFORE the kill: the death chain (loot -> KillRewards ->
		# died.emit) runs synchronously inside the lethal hitbox tick, so a
		# baseline taken after the loop already contains the reward event.
		var r_before := _rewards_log.size()
		for i in range(60):
			if died[0] or not is_instance_valid(victim):
				break
			player.create_hitbox(player.basic_attack)
			await physics_frame
		_ok("slime killed via combat loop", died[0])
		await process_frame
		await process_frame
		_ok("slime kill paid kill rewards", _rewards_log.size() > r_before,
			"(%d reward events)" % (_rewards_log.size() - r_before))
		_ok("crit flag rode damage_dealt", int(crit_tap[0]["n"]) >= 1,
			"(%d crits observed)" % int(crit_tap[0]["n"]))
		# Loot may or may not roll per table odds; a drop existing at all
		# proves the ground-loot path. Accept either but log it.
		loot_from_slime = _gls._drops.size() > drops_before
		print("  INFO: ground drop after slime kill: %s" % str(loot_from_slime))

	# --- 4. /boss open world --------------------------------------------------
	_banner("4 /boss open world")
	var bosses_before: int = _ss._world_bosses.size()
	await _cmd("boss void_lord starter_plains Gloom Brute world")
	var bosses_now: int = _ss._world_bosses.size()
	_ok("/boss world spawned a boss", bosses_now == bosses_before + 1,
		"(%d -> %d)" % [bosses_before, bosses_now])
	var world_md = _spawn_metas[_spawn_metas.size() - 1] if not _spawn_metas.is_empty() else null
	_ok("/boss world -> WORLD_BOSS metadata",
		world_md != null and int(world_md.spawn_type) == 3)
	_ok("/boss world announced server-wide",
		world_md != null and world_md.notification_enabled
		and not world_md.notification_scopes.is_empty()
		and bool(world_md.notification_scopes[0].is_server_wide))
	var boss_node = null
	for b in _ss._world_bosses.values():
		boss_node = b
	if boss_node != null and is_instance_valid(boss_node):
		var b_died := [false]
		boss_node.died.connect(func(_k): b_died[0] = true)
		boss_node.take_damage(999999, player)
		await process_frame
		await process_frame
		_ok("world boss died to the player", b_died[0])

	# --- 5. World-boss timer ---------------------------------------------------
	_banner("5 world-boss timer (4s interval)")
	var WBScript = load("res://core/schemas/world_boss_data.gd")
	var wb: Resource = WBScript.new()
	wb.id = "test_timer"
	wb.boss_template_id = "void_lord"
	wb.zone_id = "zone_starter_plains"
	wb.interval_seconds = 4.0
	wb.first_delay_s = 0.5
	wb.announce = false
	var sid: String = _ss.start_world_boss_schedule("test_timer", wb.to_config())
	_ok("schedule started", sid != "")
	var st: Dictionary = _ss.get_world_boss_schedule_status("test_timer")
	_ok("schedule first waits then lives", str(st.get("state", "")) == "waiting"
		or str(st.get("state", "")) == "live", "(state %s)" % str(st.get("state", "")))
	var live1 := await _wait_until(func():
		return str(_ss.get_world_boss_schedule_status("test_timer").get("state", "")) == "live", 8.0)
	_ok("timer spawned boss #1", live1)
	var boss1 = null
	for b in _ss._world_bosses.values():
		boss1 = b
	var id1 := str(boss1.entity_id) if boss1 != null and is_instance_valid(boss1) else ""
	if boss1 != null and is_instance_valid(boss1):
		boss1.take_damage(999999, player)
	var live2 := await _wait_until(func():
		return str(_ss.get_world_boss_schedule_status("test_timer").get("state", "")) == "live", 10.0)
	_ok("timer respawned boss #2 after the kill", live2)
	var boss2 = null
	for b in _ss._world_bosses.values():
		boss2 = b
	var id2 := str(boss2.entity_id) if boss2 != null and is_instance_valid(boss2) else ""
	_ok("respawn is a FRESH boss", id1 != "" and id2 != "" and id1 != id2,
		"(%s -> %s)" % [id1, id2])
	_ss.stop_world_boss_schedule("test_timer", "test done")
	_ok("schedule stopped", not _ss.get_world_boss_schedule_ids().has("test_timer"))

	# --- 6. Open-world horde ----------------------------------------------------
	_banner("6 open-world horde (haven_siege, alert)")
	_horde.horde_completed.connect(func(_hid, ok):
		_horde_completed[0] = true
		_horde_success[0] = ok)
	# Canonical zone id (data-naming law): the service stores zone_id
	# verbatim, so the legacy shorthand "starter_plains" here made the
	# canonical-id query below permanently mismatch (pre-dates the
	# headless world fix; it just could not fail louder before).
	await _cmd("horde haven_siege zone_starter_plains alert")
	var hid: String = _horde.active_horde_in_zone("zone_starter_plains")
	_ok("open-world horde started in the player's zone", hid != "")
	var fighting := await _wait_until(func():
		var s: Dictionary = _horde.get_horde_status(hid)
		return str(s.get("state", "")) == "fighting", 20.0)
	_ok("horde wave 1 reached fighting", fighting)
	var swept := await _sweep_horde(hid, 120.0)
	_ok("open-world horde completed", swept and _horde_completed[0] and _horde_success[0],
		"(swept=%s success=%s)" % [str(swept), str(_horde_success[0])])

	# --- 7. Dummy respawn cycle -------------------------------------------------
	_banner("7 training dummy respawn")
	_ok("dummy respawned by the scene cycle",
		_named_in_group("enemies", "Training Dummy").size() == 1,
		"(respawn_time 15s elapsed during horde phases)")

	# --- 8. Dungeon portal auto-horde --------------------------------------------
	_banner("8 dungeon portal auto-horde")
	player.level = 12  # dungeon gates at 10; give the hero the key
	# Reset the completion tap: phase 6 already fired it once.
	_horde_completed[0] = false
	var gateways: Array = _ws.get_zone_gateways("world_playable")
	_ok("portal gateway registered by the scene", gateways.size() >= 1)
	if gateways.is_empty():
		return _finish()
	var gid: String = str(gateways[0].id)
	var dest: Dictionary = _ws.use_gateway(gid, player)
	_ok("gateway teleported the player", str(dest.get("zone_id", "")) == "zone_dungeon_forest_depths",
		"(zone %s)" % str(dest.get("zone_id", "")))
	await process_frame
	var dhid: String = _horde.active_horde_in_zone("zone_dungeon_forest_depths")
	_ok("dungeon entry auto-started the horde", dhid != "")
	var dfighting := await _wait_until(func():
		var s: Dictionary = _horde.get_horde_status(dhid)
		return str(s.get("state", "")) == "fighting", 20.0)
	_ok("dungeon horde wave 1 reached fighting", dfighting)
	var proj = root.get_node_or_null("WorldStateProjection")
	if proj != null:
		proj.flush(true)
		await process_frame
		_ok("player pinned to the instance scope",
			str(proj.get_entity_scope_override(_admin_id())) == "instance:dungeon",
			"(override %s)" % str(proj.get_entity_scope_override(_admin_id())))
	var dswept := await _sweep_horde(dhid, 120.0)
	_ok("dungeon horde completed", dswept and _horde_completed[0],
		"(swept=%s)" % str(dswept))
	_horde.stop_horde(dhid, "boot test done")

	_finish()

func _finish() -> void:
	print("=== FULL-BOOT SUMMARY: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
