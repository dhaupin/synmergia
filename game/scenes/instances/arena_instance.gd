# ArenaInstance - the S10 planar bout world (mode-agnostic controller).
#
# Built entirely in code (globe_world convention). Promises from
# InstanceContract: PLANAR -Y gravity at GRAVITY_FORCE (locked
# decision 3 -- radial gravity never reaches instances), spawns at the
# zone's spawn_points, and bout rules from bout_rules() rather than
# any hardcoded elimination assumption. The controller shape is ready
# for S11 duels: bout_started / bout_ended signals, team rosters,
# entity_died attribution, respawn loop for TEAM_DEATHMATCH.
#
# Headless-friendly: nothing here needs rendering; the probe drives
# join -> start -> eliminate -> win headless. Scene transitions
# (globe <-> instance) stay in GameManager's scene flow; this scene is
# the room, not the router.
extends Node3D

const Contract = preload("res://core/schemas/instance_contract.gd")
const FighterScript = preload("res://scenes/instances/arena_fighter.gd")
const InstancePropKit = preload("res://core/world/instance_prop_kit.gd")

signal bout_started(rules: Dictionary)
signal bout_ended(winner_team: int, stats: Dictionary)
signal fighter_down(fighter_id: String, killer_id: String, team_of_victim: int)
## S11: roster churn surface for ArenaRoomService's fighter index.
signal fighter_spawned(fighter_id: String, team_id: int)

## ZoneData for this arena (set before add_child by the join path).
var zone_data: Resource = null
## The ZoneManager instance id this room serves ("" = standalone probe).
var instance_id: String = ""

var _floor: StaticBody3D
var _rules: Dictionary = {}
var _fighters: Dictionary = {}  # fighter_id -> ArenaFighter
var _teams: Dictionary = {}     # team -> Array[String] of fighter ids
var _scores: Dictionary = {}    # team -> kill count (TDM)
var _started: bool = false
var _over: bool = false
var _bout_start_time: float = 0.0
# S11: last-activity (unix) per fighter id -- the AFK sweep's ledger.
var _last_activity: Dictionary = {}
# S11: every fighter leaves the way it came. Set (by the gateway or
# the lobby path) to the world-space position of the stone/gateway the
# fighter queued at; bout end + AFK kicks send them back there.
var origin_stones: Dictionary = {}  # fighter_id -> Vector3
# S11: real levels per fighter (bridged in from the live entities at
# spawn time; default 1 when the entity is not resolvable).
var _levels: Dictionary = {}  # fighter_id -> int
# S12: trial bout flag -- dummies + AFK sweep exemption + no ring out.
var _trial: bool = false
# S12: spectators in scope (permission-checked by the caller --
# LobbyService.request_spectate). They are cameras, never fighters:
# no seat, no streaks, no payout, no return map.
var spectators: Array = []
# S12 hardening: bouts are FINITE. The AFK sweep is exempt in trials,
# so the time limit does the capping there; everywhere else it is the
# backstop against squatters eating instance runtime (owner point 1).
# A bout that runs out the clock is a DRAW (stats keep the book).
var _time_limit: float = 0.0  # 0 = disabled (probe scratch rooms)
var _streaks: Dictionary = {}   # fighter_id -> current kill streak
var _best_streaks: Dictionary = {}  # fighter_id -> best streak this bout
## S13: honest per-bout kill ledger (Royale payout reads this; a
## streak resets on death, a kill count does not).
var kill_counts: Dictionary = {}  # fighter_id -> total kills this bout

## ---- S13 ROYALE storm (the fog wall) ------------------------------------
## The Sundered Valley's fog is a RULE: after storm_start_seconds the
## safe circle walks inward through the contract's phase ladder; the
## wall's teeth are DAMAGE (outside = dps grind). The draw clock stays
## as backstop. ROYALE is the reason the AFK sweep skips this room:
## the storm is the mode's own pressure. Fighter-side damage routes
## through the bridge (rooms hold bodies, not entities).
var _storm_plan: Dictionary = {}   # Contract.storm_plan(half) once armed
var _storm_armed: bool = false     # the wall is live
var _storm_damage_cooldown: Dictionary = {}  # fighter_id -> last hit (unix)
## Emitted per second while someone bleeds in the fog (UI reads the
## phase labels off the rules dict): fighter_id -> dps.
signal storm_damage_applied(fighter_id: String, dps: float)
## Emitted when the fog KILLS: (victim_id, fog_killer_team) -- the
## killer team is the LAST team still standing outside the fog
## (anti-fog-squat credit, owner rule 2026-09-29: dying in the fog
## against the last team hands THEM the kill, so hiding from the
## final squad cannot deny them credit). listener: ArenaCombatBridge
## forwards into CombatSystem.entity_died for kill books/achievements.
signal storm_kill_credited(victim_id: String, killer_team: int)
## Emitted when a shrink starts: new radius, phase index. The web/HUD
## layer turns this into the fog visuals.
signal storm_phase_advanced(radius: float, phase_index: int)
var _storm_last_phase: int = -1
## Wall-relative clock (set once when the fog arms).
var _storm_started_at: float = 0.0
## Room-owned damage source so storm kills credit the fog, not a
## ghost player (lazy-built on first bite; freed at bout end).
var _storm_entity = null

## Emitted when a bout closes: fighter_id -> return position (their
## origin stone). The GameManager scene flow listens and teleports.
signal bout_return_requested(return_map: Dictionary)
## Emitted per fighter when the AFK sweep ejects someone early.
signal fighter_afk_kicked(fighter_id: String, return_position: Vector3)
## S11 combat bridge: fired on start_bout with the level book so the
## bridge can apply capped power normalization (locked decision 5).
signal power_reference_ready(levels: Dictionary)

func _ready() -> void:
	# Rules BEFORE the room builds: cover placement reads the mode
	# (int(null) crashes -- 4.7.2 has no null->int constructor).
	_rules = Contract.bout_rules(zone_data)
	_build_room()
	# Self-register with the node-side room registry (probe scratch
	# rooms have no instance_id and stay off the books).
	var room_svc = _room_service()
	if room_svc != null:
		room_svc.register_room(self)
	# Seed score/roster state from spawn_points: team i uses spawn i
	# (two spawn points = two teams; ROYALE's four are reserved).
	var spawns: Array = []
	if zone_data != null and "spawn_points" in zone_data:
		spawns = zone_data.spawn_points
	for i in range(spawns.size()):
		_teams[i] = []
		_scores[i] = 0

func _exit_tree() -> void:
	var room_svc = _room_service()
	if room_svc != null and instance_id != "":
		room_svc.unregister_room(self)

## Place a fighter for a team at that team's spawn. Returns the node.
## The spawn position is SCATTERED (contract primitive) so fighters
## teleporting in together never stack on one point.
func spawn_fighter(id: String, team_id: int):
	var f := FighterScript.new()
	f.setup(id, team_id)
	if not _teams.has(team_id):
		_teams[team_id] = []
		_scores[team_id] = 0
	_teams[team_id].append(id)
	_fighters[id] = f
	_last_activity[id] = Time.get_unix_time_from_system()
	add_child(f)
	f.global_position = _scatter_for(team_id, _teams[team_id].size() - 1)
	# First spawn of a TDM bout also gets the shield.
	if _rules.get("spawn_shield_seconds", 0.0) > 0.0:
		f.apply_spawn_shield(float(_rules.get("spawn_shield_seconds")))
	fighter_spawned.emit(id, team_id)
	return f

## Seat one dummy (the marshal's trial bout): entity-FREE filler with
## trial-tuned health. Dummies never sit in the bridge's entity paths;
## the bridge resolves their deaths via effective_health().
func spawn_dummy_fighter(id: String, team_id: int) -> void:
	spawn_fighter(id, team_id)
	var f = _fighters.get(id)
	if f != null:
		f.trial_health = 45

## Bridge-facing book: the real level of a fighter (from their live
## entity). Consumed by power normalization at bout start.
func set_fighter_level(fighter_id: String, level: int) -> void:
	if _fighters.has(fighter_id):
		_levels[fighter_id] = maxi(level, 1)

func has_fighter(fighter_id: String) -> bool:
	return _fighters.has(fighter_id)

## Owner decision: every teleport into a bout scatters. TDM respawns
## re-scatter around the team's spawn center (index = arrival order
## in the roster so positions stay deterministic per roster state).
func _respawn_position_for(fighter_id: String) -> Vector3:
	var f = _fighters.get(fighter_id)
	var team_id: int = f.team if f != null else 0
	var roster: Array = _teams.get(team_id, [])
	var idx: int = roster.find(fighter_id)
	return _scatter_for(team_id, maxi(idx, 0))

## First member of a team spawns EXACT at the spawn point; the rest
## take a ring around it. Ring radius grows with the roster: 12
## fighters need more than 3 m of circumference to keep >= 1.5 m
## between neighbors (golden-angle worst case ~20 degrees apart).
func _scatter_for(team_id: int, index: int) -> Vector3:
	var center := _spawn_for_team(team_id)
	if index <= 0:
		return center
	var count: int = (_teams.get(team_id, []) as Array).size()
	var ring: float = maxf(3.0, 0.45 * float(maxi(count, 1)))
	return Contract.scatter_spawn(center, index - 1, ring)

## Spawn position for a team: its spawn_points entry (fallback center).
func _spawn_for_team(team_id: int) -> Vector3:
	var spawns: Array = []
	if zone_data != null and "spawn_points" in zone_data:
		spawns = zone_data.spawn_points
	if team_id >= 0 and team_id < spawns.size():
		return spawns[team_id]
	return Vector3(0, 2, 0)

## Begin the bout: LOCKED from here (no more joins). Emits bout_started
## with the resolved rules so UI/lobby surfaces the same contract.
## Probe/tool seam: a non-negative override caps the host's start
## timer (script-mode tests cannot wait the zone's 60-90 s deadline).
## The host reads this once per bout; -1 = untouched.
var start_deadline_override: float = -1.0

func start_bout() -> void:
	if _started or _over:
		return
	_started = true
	_bout_start_time = Time.get_unix_time_from_system()
	# The clock owner asked for: every mode is finite. Trials count
	# their own (shorter) window from the zone's time limit.
	_time_limit = float(_rules.get("time_limit_seconds", 0.0))
	if _trial:
		_time_limit = minf(_time_limit if _time_limit > 0.0 else 300.0, 300.0)
	# S13 storm bookkeeping (ROYALE): arm at storm_start_seconds; a
	# negative value in the rules disables the wall for this bout.
	_storm_armed = false
	_storm_plan = {}
	_storm_damage_cooldown.clear()
	bout_started.emit(_rules)
	# Deferred so the bridge (and any other listener) can react to
	# bout_started before the power book lands.
	call_deferred("_emit_power_reference")

func _emit_power_reference() -> void:
	if _over:
		return
	# ROYALE drop (owner decision: classic sky drop + glide): the
	# moment the bout arms, every fighter is thrown into the sky over
	# a wide golden-angle ring around the map center -- the glider
	# (movement_glider) does the steering from there. Fighters above
	# floor contact never get affected by the planar settle.
	if int(_rules.get("mode")) == Contract.InstanceMode.ROYALE:
		_emit_royale_drop()
	var levels: Dictionary = {}
	for fid in _fighters:
		levels[fid] = int(_levels.get(fid, 1))
	power_reference_ready.emit(levels)

## The drop: index-stable wide ring (no stacking -- 30 fighters need
## ~2.2 m neighbors at r 21), height = 0.8 x room half (160 m over
## the valley's 400 m half), always inside the walls. With the glider
## contract armed the fighters' fall is a WING ride (planar bodies
## fall at the glider profile through ArenaFighter._glider_tick);
## without it they drop straight -- both land inside the ring.
const ROYALE_DROP_HEIGHT_RATIO: float = 0.8
const ROYALE_DROP_RING_RATIO: float = 0.35

func _emit_royale_drop() -> void:
	var half: float = 60.0
	if zone_data != null and "zone_radius" in zone_data:
		half = float(zone_data.zone_radius) * 0.5
	var ring: float = maxf(half * ROYALE_DROP_RING_RATIO, 3.0)
	var count: int = _fighters.size()
	if count > 1:
		ring = maxf(ring, 0.45 * float(count))
	var height: float = half * ROYALE_DROP_HEIGHT_RATIO
	# S13: the drop rides the WING (same GliderState primitive as the
	# globe path). Arm before the first physics frame so the fall
	# starts under glider rules; horizontal steering is the controls
	# seam (fighter bodies carry no input today).
	var gprof: Resource = load("res://data/movement_profiles/movement_glider.tres")
	var idx := 0
	for fid in _fighters:
		var f = _fighters.get(fid)
		if f == null:
			continue
		var drop := Contract.scatter_spawn(Vector3(0, height, 0), idx, ring)
		f.global_position = drop
		f.velocity = Vector3.ZERO
		if gprof != null and f.has_method("arm_glider"):
			f.arm_glider(gprof)
			f.drop_height_m = maxf(drop.y - 1.0, 0.0)
		idx += 1


## ---- S13 storm engine -----------------------------------------------------

## Arm the wall (called from _process when the clock says so). Builds
## the storm plan against the room half and announces phase 0's radius
## so UI can paint the fog ring before it moves.
func _arm_storm() -> void:
	var half: float = 60.0
	if zone_data != null and "zone_radius" in zone_data:
		half = float(zone_data.zone_radius) * 0.5
	_storm_plan = Contract.storm_plan(half)
	_storm_armed = true
	_storm_started_at = Time.get_unix_time_from_system()
	var phases: Array = _storm_plan.get("phases", [])
	if not phases.is_empty():
		storm_phase_advanced.emit(float(phases[0].get("radius", half)), 0)
		GameLog.info("ArenaInstance: the fog closes (storm armed, final r=%.0f)" % float(phases[-1].get("radius", 0.0)))


## The storm's per-frame beat: arm -> announce phases -> grind anyone
## outside the safe circle. Damage cadence is 1.0 s per fighter (dps),
## so a stuttering server never multi-ticks the wall. Storm time is
## WALL-RELATIVE (seconds since the wall armed) -- the plan's phase
## ladder starts at arm, not at bout start.
func _storm_tick() -> void:
	var now: float = Time.get_unix_time_from_system()
	var elapsed: float = now - _bout_start_time
	if not _storm_armed:
		if elapsed >= float(_rules.get("storm_start_seconds", Contract.DEFAULT_STORM_START_SECONDS)):
			_arm_storm()
		return
	var t: float = now - _storm_started_at
	# Phase announcements (once per shrink start) drive the fog UI.
	var phase_idx := _storm_phase_index(t)
	if phase_idx != _storm_last_phase and phase_idx >= 0:
		_storm_last_phase = phase_idx
		storm_phase_advanced.emit(_storm_safe_radius(t), phase_idx)
	# The grind: every living fighter outside the safe circle bleeds.
	var dps: float = Contract.storm_damage_at(_storm_plan, t)
	if dps <= 0.0:
		return
	var safe: float = _storm_safe_radius(t)
	for fid in _fighters.keys():
		var f = _fighters.get(fid)
		if f == null or not f.alive:
			continue
		var flat := Vector2(f.global_position.x, f.global_position.z)
		if flat.length() <= safe:
			continue
		var last: float = float(_storm_damage_cooldown.get(fid, 0.0))
		if now - last < 1.0:
			continue
		_storm_damage_cooldown[str(fid)] = now
		_damage_fighter(str(fid), int(ceilf(dps)))


## Which phase is the storm in (-1 = past the ladder).
func _storm_phase_index(elapsed: float) -> int:
	var phases: Array = _storm_plan.get("phases", [])
	for i in range(phases.size()):
		if elapsed < float(phases[i].get("end", 0.0)):
			return i
	return -1


## Safe radius right now (lerped inside a shrink). Pure read.
func _storm_safe_radius(elapsed: float) -> float:
	var half: float = 60.0
	if zone_data != null and "zone_radius" in zone_data:
		half = float(zone_data.zone_radius) * 0.5
	return Contract.storm_radius_at(_storm_plan, elapsed, half)


## Probe/UI surface: the live safe radius (0 = wall not armed yet).
func storm_safe_radius() -> float:
	if not _storm_armed:
		return 0.0
	return _storm_safe_radius(Time.get_unix_time_from_system() - _storm_started_at)


func storm_armed() -> bool:
	return _storm_armed


## The last living team (checked BEFORE this fighter's death books):
## fog kills credit them, never the fog itself.
func _last_standing_team(excluding: String) -> int:
	var found: int = -1
	var contested: bool = false
	for fid in _fighters:
		if str(fid) == excluding:
			continue
		var f = _fighters.get(fid)
		if f != null and f.alive:
			if found == -1:
				found = int(f.team)
			elif int(f.team) != found:
				contested = true
	return found if not contested else -1


## Route one fighter's storm damage to their live entity through the
## combat bridge (rooms hold bodies; entities live in the world).
## The source is a room-owned storm entity REGISTERED WITH
## CombatSystem, so a fog kill rides the same death relay as any
## fight kill and credits the fog by name. Missing bridge/entity
## (early-boot tool contexts) = no-op.
func _damage_fighter(fighter_id: String, amount: int) -> void:
	var ml := Engine.get_main_loop()
	var bridge = null
	if ml != null and (ml is SceneTree):
		bridge = (ml as SceneTree).root.get_node_or_null("ArenaCombatBridge")
	var ent = null
	if bridge != null:
		ent = bridge._entity_for(fighter_id)
	if ent == null:
		return
	if _storm_entity == null:
		_storm_entity = load("res://core/entities/entity.gd").new()
		_storm_entity.entity_id = "royale_storm"
		_storm_entity.display_name = "the closing fog"
		_storm_entity.level = 999
		if ml != null and (ml is SceneTree):
			var cs = (ml as SceneTree).root.get_node_or_null("CombatSystem")
			if cs != null and cs.has_method("register_entity"):
				cs.register_entity(_storm_entity)
	storm_damage_applied.emit(fighter_id, float(amount))
	# Anti-fog-squat credit (owner rule): a LETHAL fog hit is attributed
	# to the last team still standing (never the fog), so hiding from
	# the final squad cannot deny them the kill. Non-lethal bites stay
	# fog-attributed. The normal death relay does the booking.
	var source = _storm_entity
	var lethal: bool = "current_health" in ent and amount >= int(ent.current_health)
	if lethal:
		var last_team := _last_standing_team(fighter_id)
		if last_team >= 0:
			for fid in _fighters:
				var candidate = _fighters.get(fid)
				if candidate != null and candidate.alive and int(candidate.team) == last_team:
					var killer_ent = bridge._entity_for(str(fid)) if bridge != null else null
					if killer_ent != null:
						source = killer_ent
						storm_kill_credited.emit(fighter_id, last_team)
					break
	ent.take_damage(amount, source, "storm")

## Combat bridge entry: any SELF-initiated action (attack, skill cast,
## potion, self-buff) routes here. Fire-and-you-lose-it: breaks the
## spawn shield; received effects never call this (locked conduct).
func notify_action(fighter_id: String) -> void:
	if not _fighters.has(fighter_id):
		return
	note_activity(fighter_id)
	var f = _fighters.get(fighter_id)
	if f != null and f.alive and f.is_shielded():
		f.break_shield()

## The combat bridge calls this on CombatSystem.entity_died while the
## bout is live. Returns the surviving-team index when the bout ends,
## or -1 while it continues.
func report_death(victim_id: String, killer_id: String) -> int:
	if not _started or _over:
		return -1
	var victim = _fighters.get(victim_id)
	if victim == null or not victim.alive:
		return -1
	# TDM spawn shield: protected fighters cannot be eliminated.
	if victim.is_shielded():
		return -1
	victim.eliminate()
	fighter_down.emit(victim_id, killer_id, victim.team)
	_book_streaks(victim_id, killer_id)
	if _rules.get("respawn_allowed", false):
		_scores[victim.team] = int(_scores.get(victim.team, 0))
		# Credit the killer's team and respawn the victim under the
		# shield after the zone's respawn_timer.
		var killer = _fighters.get(killer_id)
		var killer_team: int = killer.team if killer != null else (1 - victim.team)
		_scores[killer_team] = int(_scores.get(killer_team, 0)) + 1
		_schedule_respawn(victim)
		_check_tdm_win()
	else:
		_check_elimination_win()
	return -1

func _schedule_respawn(victim) -> void:
	var delay: float = 5.0
	if zone_data != null and "respawn_timer" in zone_data:
		delay = float(zone_data.respawn_timer)
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func():
		if not _over and is_instance_valid(victim):
			var shield: float = float(_rules.get("spawn_shield_seconds", 0.0))
			victim.respawn_at(_respawn_position_for(victim.fighter_id), shield))

func _check_tdm_win() -> void:
	var target: int = int(_rules.get("kill_target", 0))
	if target <= 0:
		return
	for t in _scores:
		if int(_scores[t]) >= target:
			_end_bout(t)
			return

func _check_elimination_win() -> void:
	var living_teams := 0
	var last_team: int = -1
	for t in _teams:
		var any_alive := false
		for fid in _teams[t]:
			var f = _fighters.get(fid)
			if f != null and f.alive:
				any_alive = true
				break
		if any_alive:
			living_teams += 1
			last_team = t
	if living_teams <= 1 and _teams.size() > 1:
		_end_bout(last_team)

## Streak bookkeeping on every booked death (owner point 2): the
## killer's streak climbs, the victim's resets. Lives in the room so
## probes and the payout layer share one truth.
func _book_streaks(victim_id: String, killer_id: String) -> void:
	if killer_id == "" or killer_id == victim_id:
		_streaks[victim_id] = 0
		return
	if not (_fighters.has(killer_id) and _fighters.has(victim_id)):
		return
	_streaks[killer_id] = int(_streaks.get(killer_id, 0)) + 1
	_best_streaks[killer_id] = maxi(int(_best_streaks.get(killer_id, 0)), int(_streaks[killer_id]))
	kill_counts[killer_id] = int(kill_counts.get(killer_id, 0)) + 1
	_streaks[victim_id] = 0

func best_streak_for(fighter_id: String) -> int:
	return int(_best_streaks.get(fighter_id, 0))

func _end_bout(winner_team: int) -> void:
	if _over:
		return
	_over = true
	var elapsed: float = Time.get_unix_time_from_system() - _bout_start_time
	var stats := {
		"elapsed_seconds": elapsed,
		"scores": _scores.duplicate(),
		"fighters": _fighters.size(),
	}
	# Owner decision: everyone goes home to the stone they queued at
	# (round-trip, no post-match stranding). The scene flow teleports;
	# the room only declares who goes where.
	var return_map: Dictionary = {}
	for fid in _fighters:
		return_map[fid] = origin_stones.get(fid, _spawn_for_team(0))
	bout_ended.emit(winner_team, stats)
	bout_return_requested.emit(return_map)
	spectators.clear()
	# The fog lifts: the room-owned storm source is unregistered from
	# CombatSystem (no freed-entity ref left in the kill relay) and
	# freed with the bout.
	if _storm_entity != null:
		if is_instance_valid(_storm_entity):
			var ml := Engine.get_main_loop()
			if ml != null and (ml is SceneTree):
				var cs = (ml as SceneTree).root.get_node_or_null("CombatSystem")
				if cs != null and cs.has_method("unregister_entity"):
					cs.unregister_entity(_storm_entity)
				_storm_entity.queue_free()
		_storm_entity = null

# ---- Inspection surface (probe + future UI) -------------------------

func _room_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("ArenaRoomService")

## Spectator bookkeeping (ScopeService drives the scope swap; the
## room records who watches for the permission + exclusion paths).
func add_spectator(spectator_id: String) -> void:
	if not spectators.has(spectator_id):
		spectators.append(spectator_id)

func remove_spectator(spectator_id: String) -> void:
	spectators.erase(spectator_id)

## Lobby/fight code pokes this on any self-driven action (attack,
## skill, move intent) so the AFK sweep sees life. Cheap on purpose.
func note_activity(fighter_id: String) -> void:
	if _fighters.has(fighter_id):
		_last_activity[fighter_id] = Time.get_unix_time_from_system()

## The AFK sweep: idle longer than the zone's kick window (contract
## default 90 s, 0 disables) gets returned to their origin stone and
## booked like a departure. Owner decision: the guy in the woods
## never stalls a bout again. ROYALE rooms skip it (drop pacing is
## the mode's own tension).
func _process(_delta: float) -> void:
	if not _started or _over:
		return
	# The clock (owner point 1): when the window runs out, the bout is
	# a DRAW -- a defensible resolution the book already supports.
	# Squatting buys you nothing; the instance frees on schedule.
	if _time_limit > 0.0 \
			and Time.get_unix_time_from_system() - _bout_start_time >= _time_limit:
		_end_bout(-1)
		return
	if int(_rules.get("mode")) == Contract.InstanceMode.ROYALE:
		_storm_tick()
		return
	# Trial bouts skip the AFK sweep: a nervous first-timer standing
	# still to read the room is not idling out of their lesson. The
	# time limit above is the trial's own cap instead.
	if _trial:
		return
	var window: float = Contract.afk_kick_seconds(zone_data)
	if window <= 0.0:
		return
	var now: float = Time.get_unix_time_from_system()
	for fid in _fighters.keys():
		var f = _fighters.get(fid)
		if f == null or not f.alive:
			note_activity(fid)  # dead men register no idle
			continue
		if now - float(_last_activity.get(fid, now)) > window:
			kick_fighter(str(fid))

## Eject one fighter to their origin stone (AFK path; the caller has
## already decided). Books the departure so elimination accounting
## stays truthful.
func kick_fighter(fighter_id: String) -> void:
	if not _fighters.has(fighter_id):
		return
	var f = _fighters.get(fighter_id)
	if f == null or not f.alive:
		return
	var back: Vector3 = origin_stones.get(fighter_id, _spawn_for_team(0))
	f.eliminate()
	fighter_afk_kicked.emit(fighter_id, back)
	if _rules.get("respawn_allowed", false):
		_schedule_respawn(f)
		_check_tdm_win()
	else:
		_check_elimination_win()

func bout_rules() -> Dictionary:
	return _rules

func is_over() -> bool:
	return _over

func is_started() -> bool:
	return _started

func score_for(team_id: int) -> int:
	return int(_scores.get(team_id, 0))

func alive_count(team_id: int) -> int:
	var n := 0
	for fid in _teams.get(team_id, []):
		var f = _fighters.get(fid)
		if f != null and f.alive:
			n += 1
	return n

# ---- Room construction (code-built, globe_world convention) --------

## Deterministic mid-field cover for TDM rooms (owner decision: the
## sandpit gives both teams the same line-of-sight breaking rocks).
## Relative offsets of the room half-extent; spawn lanes (|z| > 0.6)
## stay clear. Wide slabs including two midfield stones on the z=0
## lane -- the flanking pattern.
const COVER_LAYOUT: Array = [
	[0.45, 0.35], [-0.45, 0.35], [0.45, -0.35], [-0.45, -0.35],
	[0.15, -0.45], [-0.15, 0.45], [0.30, 0.00], [-0.30, 0.00],
]

## Elimination rooms get a DIFFERENT pattern, per owner request: a
## perimeter pillar ring. Four columns near the walls (0.78 of half)
## and four at the diagonals (0.55 of half) -- the duel CENTER stays
## clean sand so the opening clash is never cover-camped, while
## disengages near the rim still break line-of-sight. Narrow tall
## pillars (arena colonnade) instead of TDM's low slabs.
const ELIM_COVER_LAYOUT: Array = [
	[0.78, 0.00], [0.00, 0.78], [-0.78, 0.00], [0.00, -0.78],
	[0.55, 0.55], [-0.55, 0.55], [0.55, -0.55], [-0.55, -0.55],
]

func _build_room() -> void:
	# Room size derives from the zone: half-extent = zone_radius * 0.5
	# (coliseum radius 120 -> 120 m square, the original room; sandpit
	# radius 220 -> 220 m square with room to flank).
	var half: float = 60.0
	if zone_data != null and "zone_radius" in zone_data:
		half = float(zone_data.zone_radius) * 0.5

	# Mode environment (the instance style law: rooms render in the
	# planet's own BiomeId palette so a room reads as a slice of the
	# world it fights in -- deserts for the coliseum, olive steppe for
	# the sandpit, rust badlands for the Sundered Valley).
	var env := _mode_env(int(_rules.get("mode")))

	# Ground: collision slab + colored plane with a seeded noise tint
	# (the same wobble law the surface terrain uses, so the floor is
	# not flat paint). Deterministic per mode.
	_floor = StaticBody3D.new()
	_floor.name = "ArenaFloor"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0 * half, 1, 2.0 * half)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	_floor.add_child(col)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0 * half, 2.0 * half)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = env["floor"]
	floor_mat.albedo_texture = _noise_tint(int(env["seed"]))
	floor_mat.uv1_scale = Vector3(8, 8, 1)
	floor_mat.roughness = 0.95
	floor_mesh.material_override = floor_mat
	_floor.add_child(floor_mesh)
	add_child(_floor)

	# Perimeter walls: keeps fighters inside the bounds (FALLS OFF
	# THE SAND never happen; the room is sealed by design). Now with a
	# visible stone face (alpine gray; the fog valley wears a darker
	# rust rim) so the seal reads from inside instead of being air.
	for wall in [
		[Vector3(0, 5, -half), Vector3(2.0 * half, 10, 2)],
		[Vector3(0, 5, half), Vector3(2.0 * half, 10, 2)],
		[Vector3(-half, 5, 0), Vector3(2, 10, 2.0 * half)],
		[Vector3(half, 5, 0), Vector3(2, 10, 2.0 * half)],
	]:
		var wall_body := StaticBody3D.new()
		var wall_col := CollisionShape3D.new()
		var wall_shape := BoxShape3D.new()
		wall_shape.size = wall[1]
		wall_col.shape = wall_shape
		wall_body.add_child(wall_col)
		wall_body.position = wall[0]
		var wall_mesh := MeshInstance3D.new()
		var wall_box := BoxMesh.new()
		wall_box.size = wall[1]
		wall_mesh.mesh = wall_box
		var wall_mat := StandardMaterial3D.new()
		wall_mat.albedo_color = env["wall"]
		wall_mat.roughness = 1.0
		wall_mesh.material_override = wall_mat
		wall_body.add_child(wall_mesh)
		add_child(wall_body)

	# Cover rocks: TDM rooms get midfield slabs; elimination rooms get
	# their own perimeter pillar ring (different pattern, owner
	# request). Both are fair, symmetric, deterministic. ROYALE rooms
	# stay bare (terrain cover is reserved for S-royale).
	if int(_rules.get("mode")) != Contract.InstanceMode.ROYALE:
		_build_cover(half)

	# ROOM DECORATION (the instance prop law, labs/prd-clipmap.md 11a):
	# a deterministic, seed-derived, mode-aware scatter over the flat floor.
	# Decoration only -- it never collides and never crowds the bout center,
	# a team spawn, or the solid cover, so the fight is unchanged; the room
	# just stops reading as a bare box.
	_build_room_props(half)

func _build_cover(half: float) -> void:
	# Per-mode silhouette: TDM slabs are wide/low (lane breakers),
	# elimination pillars are narrow/tall (colonnade feel, full-height
	# LOS blocks). Center stone tint differs so the two patterns read
	# apart at a glance.
	var elim_mode: bool = int(_rules.get("mode")) == Contract.InstanceMode.ELIMINATION
	var env := _mode_env(int(_rules.get("mode")))
	var layout: Array = ELIM_COVER_LAYOUT if elim_mode else COVER_LAYOUT
	var rock_size := Vector3(3, 7, 3) if elim_mode else Vector3(6, 5, 3)
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = env["cover"]
	rock_mat.roughness = 1.0
	var rock_index := 0
	for spot in layout:
		var rock := StaticBody3D.new()
		var rock_col := CollisionShape3D.new()
		var rock_shape := BoxShape3D.new()
		rock_shape.size = rock_size
		rock_col.shape = rock_shape
		rock_col.position = Vector3(0, rock_size.y * 0.5, 0)
		rock.add_child(rock_col)
		var rock_mesh := MeshInstance3D.new()
		var rock_box := BoxMesh.new()
		rock_box.size = rock_size
		rock_mesh.mesh = rock_box
		rock_mesh.material_override = rock_mat
		rock_mesh.position = Vector3(0, rock_size.y * 0.5, 0)
		rock.add_child(rock_mesh)
		rock.position = Vector3(spot[0] * half, 0, spot[1] * half)
		# Unique name IN CODE: add_child renames conflicting siblings to
		# the CLASS name (@StaticBody3D@N), losing the prefix we probe
		# and UI code would look for.
		rock.name = "CoverRock_%d" % rock_index
		rock_index += 1
		add_child(rock)

func _build_room_props(half: float) -> void:
	var env := _mode_env(int(_rules.get("mode")))
	var keep: Array = []
	if zone_data != null and "spawn_points" in zone_data:
		for sp in zone_data.spawn_points:
			keep.append(Vector3(sp.x, 0.0, sp.z))
	if int(_rules.get("mode")) != Contract.InstanceMode.ROYALE:
		var layout: Array = ELIM_COVER_LAYOUT if int(_rules.get("mode")) == Contract.InstanceMode.ELIMINATION else COVER_LAYOUT
		for spot in layout:
			keep.append(Vector3(spot[0] * half, 0.0, spot[1] * half))
	var palette := {"tuft": env["tuft"], "bush": env["bush"], "stone": env["stone"]}
	InstancePropKit.new().build(self, half, int(_rules.get("mode")), int(env["seed"]), palette, keep)


## The instance style law: per-mode environment palette. Colors are
## read off TerrainGen.biome_color's palette so a room visually belongs
## to its zone's biome (coliseum/fringe desert, sandpit/steppe, the
## Sundered Valley/badlands rust). `seed` salts the floor noise tint.
## ROYALE keeps bare terrain (cover reserved) but shares floor+wall.
func _mode_env(mode: int) -> Dictionary:
	match mode:
		Contract.InstanceMode.ELIMINATION:
			return {"seed": 11, "floor": Color(0.80, 0.68, 0.42), "wall": Color(0.55, 0.53, 0.50), "cover": Color(0.55, 0.52, 0.46),
				"tuft": Color(0.55, 0.52, 0.30), "bush": Color(0.42, 0.45, 0.26), "stone": Color(0.52, 0.50, 0.46)}
		Contract.InstanceMode.ROYALE:
			return {"seed": 23, "floor": Color(0.55, 0.34, 0.26), "wall": Color(0.40, 0.26, 0.20), "cover": Color(0.55, 0.34, 0.26),
				"tuft": Color(0.42, 0.34, 0.24), "bush": Color(0.38, 0.30, 0.20), "stone": Color(0.40, 0.30, 0.24)}
		_:
			# TEAM_DEATHMATCH (the sandpit): olive steppe ground, warm
			# sand slabs.
			return {"seed": 7, "floor": Color(0.52, 0.52, 0.32), "wall": Color(0.55, 0.53, 0.50), "cover": Color(0.45, 0.42, 0.38),
				"tuft": Color(0.34, 0.44, 0.22), "bush": Color(0.26, 0.36, 0.18), "stone": Color(0.46, 0.44, 0.40)}

## Subtle seeded tint over a base albedo (biome albedo law): a small
## noise texture so floors do not read as one flat paint pour.
func _noise_tint(seed: int) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.08
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 64
	tex.height = 64
	tex.seamless = true
	return tex
