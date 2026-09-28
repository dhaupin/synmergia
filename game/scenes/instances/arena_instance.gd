# ArenaInstance - the S10 planar bout world (mode-agnostic controller).
#
# Built entirely in code (globe_island convention). Promises from
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
func start_bout() -> void:
	if _started or _over:
		return
	_started = true
	_bout_start_time = Time.get_unix_time_from_system()
	bout_started.emit(_rules)
	# Deferred so the bridge (and any other listener) can react to
	# bout_started before the power book lands.
	call_deferred("_emit_power_reference")

func _emit_power_reference() -> void:
	if _over:
		return
	var levels: Dictionary = {}
	for fid in _fighters:
		levels[fid] = int(_levels.get(fid, 1))
	power_reference_ready.emit(levels)

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

# ---- Inspection surface (probe + future UI) -------------------------

func _room_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("ArenaRoomService")

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
	if int(_rules.get("mode")) == Contract.InstanceMode.ROYALE:
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

# ---- Room construction (code-built, globe_island convention) --------

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

	# Sand floor.
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
	_floor.add_child(floor_mesh)
	add_child(_floor)

	# Perimeter walls: keeps fighters inside the bounds (FALLS OFF
	# THE SAND never happen; the room is sealed by design).
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
		add_child(wall_body)

	# Cover rocks: TDM rooms get midfield slabs; elimination rooms get
	# their own perimeter pillar ring (different pattern, owner
	# request). Both are fair, symmetric, deterministic. ROYALE rooms
	# stay bare (terrain cover is reserved for S-royale).
	if int(_rules.get("mode")) != Contract.InstanceMode.ROYALE:
		_build_cover(half)

func _build_cover(half: float) -> void:
	# Per-mode silhouette: TDM slabs are wide/low (lane breakers),
	# elimination pillars are narrow/tall (colonnade feel, full-height
	# LOS blocks). Center stone tint differs so the two patterns read
	# apart at a glance.
	var elim_mode: bool = int(_rules.get("mode")) == Contract.InstanceMode.ELIMINATION
	var layout: Array = ELIM_COVER_LAYOUT if elim_mode else COVER_LAYOUT
	var rock_size := Vector3(3, 7, 3) if elim_mode else Vector3(6, 5, 3)
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.55, 0.52, 0.46) if elim_mode else Color(0.45, 0.42, 0.38)
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
