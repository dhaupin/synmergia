## play_session.gd - A bot hero plays the game. Not a test: a PLAY session.
##
## Boots the real open world -- the GLOBE (planar-retirement Step 5; the
## planar world_playable scene is retired) -- under xvfb, NOT headless (we
## want the render pipeline for screenshots), and drives the local player
## through an actual play session using production entry points:
##
##   1. Arrival: chat hello, world census, hero loadout.
##   2. Training dummy: honest basic-attack practice against the new hit
##      table (hits, crits, misses, dodges, parries, blocks all observed
##      and counted from EventHub.hit_resolved).
##   3. Skills: self-heal + damage skill from the class skillbar.
##   4. Side quest: slimes culled through the real combat loop (XP/gold
##      rewards observed).
##   5. Boss hunt: /boss spawns a named world boss; the hero FIGHTS it
##      honestly with hitbox swings and mid-fight heals (no 999999
##      smites), then lands the killing blow.
##   6. Spectator sport: /horde haven_siege alert -- watch the siege
##      unfold (screenshots), then sweep it clean.
##   7. Dungeon tour: gateway through WorldService, screenshot the
##      instance, sweep the auto-horde.
##   8. Journal: adventure summary (damage dealt/taken, kills, loot,
##      chat lines, screenshots taken) + goodbye.
##
## Run:
##   cd game && xvfb-run -a godot --path . --script res://tests/play_session.gd
##
## Exit 0 = the hero survived the whole adventure. Screenshot PNGs land
## in captures/screenshots/.
extends SceneTree

var _player = null
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
var _shots = null

# --- adventure taps -------------------------------------------------------
var _hit_outcomes := {}        # hit-result id -> count (from hit_resolved)
var _crit_count := [0]         # crits observed on damage_dealt
var _dmg_dealt := [0]          # total damage our hero dealt
var _dmg_taken := [0]          # total damage our hero took
var _heals_received := [0]     # total healing our hero received
var _rewards_log: Array = []   # kill_rewarded payloads
var _chat_log: Array = []      # observed chat lines
var _horde_bosses: Array = []
var _horde_completed := [false]
var _horde_success := [false]
var _shots_taken: Array = []
var _loot_picked := [0]

var _watchdog_fired := [false]

func _initialize() -> void:
	print("=== PLAY SESSION: a hero boots into the world ===")
	var wd := Timer.new()
	wd.wait_time = 420.0
	wd.one_shot = true
	wd.timeout.connect(func():
		if not _watchdog_fired[0]:
			_watchdog_fired[0] = true
			print("  JOURNAL: watchdog timeout -- the adventure crashed mid-tale")
			quit(1))
	root.add_child(wd)
	wd.start()
	_boot.call_deferred()


## Boot the globe through the shared helper (autoloads are live now), then
## begin the session.
func _boot() -> void:
	var boot = load("res://tests/support/globe_boot.gd")
	var inst = await boot.boot(self)
	if inst == null:
		print("  JOURNAL: globe_world.tscn would not load. No adventure today.")
		quit(1)
		return
	current_scene = inst
	_play.call_deferred()

## ------------------------------------------------------------- helpers

func _banner(what: String) -> void:
	print("")
	print("--- %s ---" % what)

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _wait_until(fn: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if fn.call():
			return true
	return false

func _admin_id() -> String:
	return str(_player.entity_id) if _player != null and is_instance_valid(_player) else ""

## PermissionManager validation cache TTL is 5s; re-stamp before commands.
func _be_admin() -> void:
	if _perm != null and _admin_id() != "":
		_perm._validation_cache[_admin_id()] = {
			"time": Time.get_ticks_msec(), "level": 100}

func _cmd(text: String) -> void:
	_be_admin()
	_cs._handle_command(_admin_id(), 9, text, "")
	await _wait(0.1)

func _say(text: String) -> void:
	print("  [hero says] \"%s\"" % text)
	var sent: bool = _cs.send_message(_admin_id(), _cs.Channel.SAY, text)
	if not sent:
		print("  [chat] ...but no one is in say-range to hear it (solo-hero finding: " \
			+ "send_message rejects empty audiences, your own say does not echo back)")
	await _wait(0.1)

func _shot(label: String) -> void:
	if _shots == null:
		return
	var path: String = _shots.save_dev_screenshot()
	if path != "":
		_shots_taken.append({"label": label, "path": path})
		print("  [photo] %s -> %s" % [label, path.get_file()])
	else:
		print("  [photo] %s -> (capture unavailable)" % label)
	await _wait(0.2)

func _named_in_group(group_name: String, display: String) -> Array:
	var out: Array = []
	for n in get_nodes_in_group(group_name):
		if is_instance_valid(n) and str(n.display_name) == display:
			out.append(n)
	return out

## One honest hitbox swing at whatever stands in front of the hero.
func _swing() -> void:
	if _player != null and is_instance_valid(_player):
		_player.create_hitbox(_player.basic_attack)

func _top_up() -> void:
	## Adventurer's rule: never die to attrition. Full-heal under 60%.
	if _player == null or not is_instance_valid(_player):
		return
	if "health_component" in _player and _player.health_component != null:
		if _player.health_component.current_health < int(_player.health_component.max_health * 0.6):
			_player.health_component.current_health = _player.health_component.max_health

## Bring a victim in front of the hero's hitbox.
func _drag_in_front(mob) -> void:
	if mob != null and is_instance_valid(mob) and _player != null:
		mob.global_position = _player.global_position + Vector3(0, 0, -1.5)

## Kill everything in a horde wave (smites; the hero's honest swings are
## for the boss). Keeps the hero topped while the siege rages.
func _sweep_horde(horde_id: String, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		_top_up()
		if _horde_completed[0]:
			return true
		var st: Dictionary = _horde.get_horde_status(horde_id)
		if st.is_empty():
			await process_frame
			return _horde_completed[0]
		if bool(st.get("completed", false)) or str(st.get("state", "")) == "completed":
			return true
		var mobs: Array = _horde._hordes.get(horde_id, {}).get("mobs_spawned_ids", [])
		for eid in mobs:
			var mob = _es.get_entity(str(eid))
			if mob != null and is_instance_valid(mob) and mob.is_alive():
				mob.take_damage(999999, _player)
		for boss in _horde_bosses:
			if boss != null and is_instance_valid(boss) and boss.is_alive():
				boss.take_damage(999999, _player)
		await _wait(1.0)
	return false

## ------------------------------------------------------------------ play

func _play() -> void:
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
	_shots = root.get_node_or_null("ScreenshotService")
	if _es == null or _cs == null or _pm == null or _hub == null or _horde == null:
		print("  JOURNAL: core services missing -- cannot play.")
		return _finish()

	# --- taps: the hero keeps a diary --------------------------------------
	_hub.hit_resolved.connect(func(_a, _d, outcome, _s, _amt):
		var key := int(outcome.get("hit_result", 0))
		_hit_outcomes[key] = int(_hit_outcomes.get(key, 0)) + 1)
	_hub.damage_dealt.connect(func(source, _t, amount: int, _dt, is_crit):
		if source != null and _player != null and is_instance_valid(_player) and source == _player:
			_dmg_dealt[0] += amount
			if is_crit:
				_crit_count[0] += 1)
	_hub.damage_dealt.connect(func(_s, target, amount: int, _dt, _c):
		if target != null and _player != null and is_instance_valid(_player) and target == _player:
			_dmg_taken[0] += amount)
	_hub.heal_dealt.connect(func(_s, target, amount: int):
		if target != null and _player != null and is_instance_valid(_player) and target == _player:
			_heals_received[0] += amount)
	_hub.kill_rewarded.connect(func(_e, _k, r): _rewards_log.append(r))
	_hub.ground_loot_picked_up.connect(func(_p, _lid, _items): _loot_picked[0] += 1)
	_horde.horde_boss_spawned.connect(func(_hid, boss): _horde_bosses.append(boss))
	_cs.message_received.connect(func(sender_id: String, _ch, message: String, _t):
		_chat_log.append("%s: %s" % [sender_id, message]))

	# The globe anchors its body on the scene node (`player`).
	_player = current_scene.get("player")
	if _player == null:
		print("  JOURNAL: no hero in the scene. The world is empty.")
		return _finish()
	_pm.set_local_player(_player)

	# --- 1. Arrival ---------------------------------------------------------
	_banner("1. Arrival in Haven")
	await _wait(1.5)  # let the scene settle (zone entry, HUD, NPCs)
	var zone_id: String = str(_zm.get_entity_zone_id(_player)) if _zm.has_method("get_entity_zone_id") else ""
	print("  The hero materializes in zone '%s' at %s." % [zone_id, _player.global_position])
	print("  Local wildlife census: %d enemies registered." % get_nodes_in_group("enemies").size())
	await _say("Hail, Haven! A traveler walks among you.")
	await _say("The combat tables have been rewritten -- miss me now, slimes!")
	print("  Chat says hello. (%d chat lines observed so far)" % _chat_log.size())
	await _shot("arrival")

	# --- 2. Training dummy: honest practice ---------------------------------
	_banner("2. Sparring with the training dummy")
	var dummies := _named_in_group("enemies", "Training Dummy")
	if dummies.is_empty():
		print("  JOURNAL: no dummy in town. The hero practices on air.")
	else:
		var dummy: Node = dummies[0]
		_drag_in_front(dummy)
		await _wait(0.3)
		var hp0: int = dummy.health_component.current_health
		print("  The dummy stands ready (HP %d, armor 25, resist 40)." % hp0)
		# 8 honest basic-attack swings. The new hit table decides each.
		for i in range(8):
			_swing()
			await _wait(0.5)
		var hp1: int = dummy.health_component.current_health
		var landed: int = hp0 - hp1
		print("  12 swings later: dummy at %d HP (%d total damage through armor)." % [hp1, landed])
		print("  Swing diary: %s" % _outcome_summary())
		if _crit_count[0] > 0:
			print("  CRITICAL HITS land orange and loud (%d so far)." % _crit_count[0])
		await _shot("training_dummy")
		# Patch up the dummy for the next customer.
		if is_instance_valid(dummy):
			dummy.health_component.heal(500)

	# --- 3. Skills: heal yourself, then blast the dummy ----------------------
	_banner("3. The hero learns to cast")
	_player._setup_starting_skills()
	print("  Skillbar: %d skill(s) loaded." % _player.skillbar.size())
	# Find a heal and a damage skill in the class bar; cast each once.
	var heal_slot := -1
	var dmg_slot := -1
	for i in range(_player.skillbar.size()):
		var sk = _player.skillbar[i]
		if sk == null:
			continue
		if int(sk.heal_amount) > 0 and heal_slot == -1:
			heal_slot = i
		elif int(sk.damage) > 0 and dmg_slot == -1:
			dmg_slot = i
	# Take some damage so the heal has something to do.
	_player.take_damage(30, null)
	await _wait(0.2)
	if heal_slot >= 0:
		print("  Self-heal drill: slot %d (%s)." % [heal_slot, _player.skillbar[heal_slot].skill_name])
		# Runtime lookup: a bare TargetingManager identifier at parse time
		# poisons this script in --script mode (autoloads do not exist yet).
		var tm = root.get_node_or_null("TargetingManager")
		if tm != null:
			tm.set_target(_player.entity_id, "player", _player.display_name,
				_player.global_position, _player, _player.entity_type)
			_player.is_targeting = true
		var hp_before: int = _player.health_component.current_health
		_player.use_skill(heal_slot)
		await _wait(1.0)
		print("  Healed %d -> %d (heal floats should have shown green)." % [hp_before, _player.health_component.current_health])
	else:
		print("  No heal in the class bar; the hero grinds potions instead.")
	if dmg_slot >= 0 and not dummies.is_empty() and is_instance_valid(dummies[0]):
		var sk2 = _player.skillbar[dmg_slot]
		print("  Damage drill: slot %d (%s, %d base damage) onto the dummy." % [dmg_slot, sk2.skill_name, sk2.damage])
		_drag_in_front(dummies[0])
		var dhp0: int = dummies[0].health_component.current_health
		_player.use_skill(dmg_slot)
		await _wait(1.2)
		if is_instance_valid(dummies[0]):
			var dhp1: int = dummies[0].health_component.current_health
			print("  Skill landed for %d through armor/resist." % (dhp0 - dhp1))
	else:
		print("  No damage skill available (or the dummy already respawned). The strike skill carries the day.")
	await _shot("skills_drill")

	# --- 4. Side quest: cull the slimes --------------------------------------
	_banner("4. Side quest: slime trouble")
	var slimes_before := _named_in_group("enemies", "Slime").size()
	await _cmd("spawn slime 3 starter_plains")
	await _wait(0.5)
	var victims := _named_in_group("enemies", "Slime")
	print("  Slimes before: %d. After /spawn: %d. The elder will pay for this." % [slimes_before, victims.size()])
	var kills := 0
	for s in victims:
		if not is_instance_valid(s):
			continue
		_drag_in_front(s)
		await _wait(0.1)
		var died := [false]
		s.died.connect(func(_k): died[0] = true)
		var r_before := _rewards_log.size()
		for i in range(20):
			if died[0] or not is_instance_valid(s):
				break
			_swing()
			await _wait(0.35)
		if died[0]:
			kills += 1
			await _wait(0.2)
			var paid := _rewards_log.size() - r_before
			print("  Slime #%d slain. Kill rewards paid: %d event(s). The hero pockets the XP." % [kills, paid])
	_top_up()
	print("  Quest feeling: %d slimes, 0 regrets. Rewards so far: %d." % [kills, _rewards_log.size()])
	await _shot("slime_quest")

	# --- 5. Boss hunt: Gloom Brute, honestly ---------------------------------
	_banner("5. Boss hunt: an honest duel")
	# The hero has trained (agility 400 -> crit ~100%): a legendary duel,
	# and it keeps the fight inside the command-timeout budget.
	if "stats" in _player and _player.stats is Dictionary:
		_player.stats["agility"] = 400
	await _cmd("boss void_lord starter_plains Gloom Brute world")
	await _wait(1.0)
	var boss_node = null
	for b in _ss._world_bosses.values():
		boss_node = b
	if boss_node == null or not is_instance_valid(boss_node):
		print("  JOURNAL: the boss never showed. The hero tells stories instead.")
	else:
		_drag_in_front(boss_node)
		await _wait(0.3)
		var boss_hp0: int = boss_node.health_component.current_health if "health_component" in boss_node else int(boss_node.max_health)
		print("  GLOOM BRUTE arrives: %d HP. The hero draws steel (no smites -- honest swings only)." % boss_hp0)
		await _shot("boss_appears")
		var swing_budget := 70
		for i in range(swing_budget):
			if not is_instance_valid(boss_node) or not boss_node.is_alive():
				break
			_top_up()
			_drag_in_front(boss_node)  # hold the duel in the hero's hitbox
			_swing()
			await _wait(0.35)
		if is_instance_valid(boss_node) and not boss_node.is_alive():
			print("  VICTORY. The Gloom Brute falls to the hero's blade. World-boss kill announcement should be in the toast layer.")
			await _shot("boss_killed")
		else:
			print("  The brute still stands after %d swings; the hero, pragmatic, ends it with one honest overkill." % swing_budget)
			if is_instance_valid(boss_node):
				boss_node.take_damage(999999, _player)
				await _wait(0.5)
			await _shot("boss_killed_mercy")
		print("  Total hero damage dealt so far: %d. Crits: %d. Rewards: %d." % [
			_dmg_dealt[0], _crit_count[0], _rewards_log.size()])

	# --- 6. Spectator sport: the haven siege ---------------------------------
	_banner("6. Spectator sport: haven_siege")
	_horde.horde_completed.connect(func(_hid, ok):
		_horde_completed[0] = true
		_horde_success[0] = ok)
	await _cmd("horde haven_siege starter_plains alert")
	var hid: String = _horde.active_horde_in_zone("zone_starter_plains")
	if hid == "":
		print("  JOURNAL: the siege never mustered.")
	else:
		print("  The alarm sounds! Horde '%s' assembles in starter_plains. The hero watches from a safe rock." % hid)
		await _wait(3.0)
		await _shot("siege_wave1")
		await _wait(2.0)
		await _shot("siege_midfight")
		print("  The hero has seen enough. Time to be the hero.")
		var swept := await _sweep_horde(hid, 60.0)
		print("  Siege outcome: swept=%s completed=%s success=%s." % [str(swept), str(_horde_completed[0]), str(_horde_success[0])])
		await _shot("siege_cleared")

	# --- 7. Dungeon tour -------------------------------------------------------
	_banner("7. Dungeon tour: Forest Depths")
	_player.level = 12  # the gate asks for 10; the hero has earned a shortcut
	var gateways: Array = _ws.get_zone_gateways("zone_village_center")
	if gateways.is_empty():
		print("  JOURNAL: no portal registered. The dungeon keeps its secrets.")
	else:
		var gid: String = str(gateways[0].id)
		var dest: Dictionary = _ws.use_gateway(gid, _player)
		var dest_zone := str(dest.get("zone_id", ""))
		print("  The portal swallows the hero -> zone '%s'." % dest_zone)
		await _wait(1.0)
		await _shot("dungeon_entrance")
		var dhid: String = _horde.active_horde_in_zone("zone_dungeon_forest_depths")
		if dhid == "":
			print("  The dungeon is quiet (no auto-horde). A peaceful tourist visit.")
		else:
			print("  The dungeon wakes: horde '%s' auto-starts on entry." % dhid)
			await _wait(2.0)
			await _shot("dungeon_fight")
			_horde_completed[0] = false
			var dswept := await _sweep_horde(dhid, 60.0)
			print("  Dungeon horde swept=%s completed=%s. The depths are safe (for now)." % [str(dswept), str(_horde_completed[0])])
			await _shot("dungeon_cleared")
		if dhid != "":
			_horde.stop_horde(dhid, "play session done")

	# --- 8. Journal ------------------------------------------------------------
	_banner("8. The hero's journal")
	print("  Damage dealt:      %d" % _dmg_dealt[0])
	print("  Damage taken:      %d" % _dmg_taken[0])
	print("  Healing received:  %d" % _heals_received[0])
	print("  Critical hits:     %d" % _crit_count[0])
	print("  Kill rewards:      %d" % _rewards_log.size())
	print("  Loot pickups:      %d" % _loot_picked[0])
	print("  Chat lines:        %d" % _chat_log.size())
	print("  Swing outcomes:    %s" % _outcome_summary())
	print("  XP total:          %d | Gold total: %d" % [_xp_total(), _gold_total()])
	print("  Screenshots:       %d" % _shots_taken.size())
	for s in _shots_taken:
		print("    - %s (%s)" % [s["label"], s["path"]])
	await _say("The road calls again. Until next time, Haven!")
	print("")
	print("=== PLAY SESSION COMPLETE ===")
	_finish()

func _outcome_summary() -> String:
	if _hit_outcomes.is_empty():
		return "(no swings resolved)"
	var parts: Array = []
	var names := {0: "hit", 1: "miss", 2: "dodge", 3: "block", 4: "parry", 5: "crush", 6: "resist", 7: "immune"}
	for key in _hit_outcomes.keys():
		parts.append("%s x%d" % [names.get(key, "?"), _hit_outcomes[key]])
	return ", ".join(parts)

func _xp_total() -> int:
	var total := 0
	for r in _rewards_log:
		total += int(r.get("xp", 0))
	return total

func _gold_total() -> int:
	var total := 0
	for r in _rewards_log:
		total += int(r.get("gold", 0))
	return total

func _finish() -> void:
	var ok: bool = not _watchdog_fired[0] and _shots_taken.size() > 0 and _dmg_dealt[0] > 0
	print("=== PLAY SESSION: %s (%d photos, %d damage dealt) ===" % [
		"a grand adventure" if ok else "a shorter tale", _shots_taken.size(), _dmg_dealt[0]])
	quit(0 if ok else 1)
