# probe_arena_instance.gd - S10 probe: planar instance room + bout
# controller. Script-mode SceneTree test; runs the whole chain
# headless: room builds from zone data, fighters spawn at spawn_points
# with PLANAR contract gravity, elimination resolves a winner,
# TEAM_DEATHMATCH respawns and reaches the kill target, bout rules
# come from bout_rules() (never hardcoded).
#
# Conventions: no parse-time Entity refs (script mode), probe asserts
# via _check, exit 0/1. Registered in DEFAULT_SET.
extends SceneTree

const ContractPath = "res://core/schemas/instance_contract.gd"

var _fails: int = 0

func _init() -> void:
	# Let autoloads finish (script mode still mounts them as nodes).
	call_deferred("_run")

func _run() -> void:
	var Contract = load(ContractPath)
	var zm = root.get_node_or_null("ZoneManager")
	_check("ZoneManager present", zm != null)
	if zm == null:
		quit(1)
		return
	zm.load_zones()

	var arena: Resource = zm.get_zone("zone_arena_coliseum")
	_check("coliseum zone loaded", arena != null)
	var sandpit: Resource = zm.get_zone("zone_arena_sandpit")
	_check("sandpit zone loaded", sandpit != null)

	# ---- A. Room construction from zone data ------------------------
	var ArenaScene = load("res://scenes/instances/arena_instance.gd")
	var room = ArenaScene.new()
	room.zone_data = arena
	room.instance_id = "probe_instance_1"
	root.add_child(room)

	_check("rules served from bout_rules (not hardcoded)", \
		int(room.bout_rules().get("mode")) == Contract.InstanceMode.ELIMINATION)
	_check("room is planar by contract", \
		Contract.bout_rules(null).get("respawn_allowed") == false)
	var spawns: Array = arena.spawn_points
	_check("zone provides two team spawns", spawns.size() == 2)

	# ---- B. Elimination bout: spawn, fight, resolve -----------------
	var f1 = room.spawn_fighter("blue_one", 0)
	var f2 = room.spawn_fighter("red_one", 1)
	var f3 = room.spawn_fighter("red_two", 1)
	_check("fighters spawn on team spawns", \
		f1.global_position.distance_to(spawns[0]) < 1.0 and \
		f2.global_position.distance_to(spawns[1]) < 1.0)
	_check("fighter gravity is contract force", \
		abs(f1.gravity_force - Contract.GRAVITY_FORCE) < 0.0001)

	var started := [false]
	room.bout_started.connect(func(_r): started[0] = true)
	room.start_bout()
	_check("bout_started emitted", started[0])

	# Gravity settles fighters onto the floor (planar contact).
	await _settle(1.5)
	_check("fighters land on planar floor", \
		f1.is_on_floor() and f2.is_on_floor() and f3.is_on_floor())
	_check("floor contact near sand height", \
		f1.global_position.y < 2.5)
	# S11 owner decision: every teleport into a bout scatters. Index 0
	# lands exact; the second red fighter rides the ring (radius >= 3).
	_check("first fighter spawns exact", \
		Vector2(f1.global_position.x, f1.global_position.z) \
			.distance_to(Vector2(spawns[0].x, spawns[0].z)) < 0.01)
	_check("team members scatter apart (no stacking)", \
		f3.global_position.distance_to(spawns[1]) > 2.0 \
		and f3.global_position.distance_to(f2.global_position) > 2.0)

	var ended: Array = []
	room.bout_ended.connect(func(w, _s): ended.append(w))
	# Red loses two, then blue loses one: red eliminated first.
	room.report_death("red_one", "blue_one")
	room.report_death("red_two", "blue_one")
	_check("red team wiped -> bout over", room.is_over())
	_check("blue wins elimination", ended.size() == 1 and ended[0] == 0)
	_check("fighter_down signalled", room.alive_count(1) == 0)
	_check("elimination respects shield=null zone (none)", \
		not bool(room.bout_rules().get("respawn_allowed")))

	room.queue_free()
	await process_frame

	# ---- C. TEAM_DEATHMATCH bout on the sandpit ---------------------
	var room2 = ArenaScene.new()
	room2.zone_data = sandpit
	root.add_child(room2)
	var sp_rules: Dictionary = room2.bout_rules()
	_check("sandpit rules: TDM respawn", bool(sp_rules.get("respawn_allowed")))
	_check("sandpit rules: kill target 20 from zone", \
		int(sp_rules.get("kill_target")) == 20)

	var g1 = room2.spawn_fighter("tdm_blue", 0)
	var g2 = room2.spawn_fighter("tdm_red", 1)
	_check("TDM first spawn shielded", g1.is_shielded() and g2.is_shielded())
	room2.start_bout()

	# Room grew with the zone (radius 220 -> 220 m square) and carries
	# deterministic cover; the elimination room above carries its OWN
	# pattern (perimeter pillar ring), same rock-count family.
	var rock_count: int = _room_rock_count(room2)
	_check("TDM room has cover rocks", rock_count == 8)
	# Fresh elimination room for the pattern split (the first room was
	# freed after its bout; freed rooms cannot be inspected).
	var room3 = ArenaScene.new()
	room3.zone_data = arena
	root.add_child(room3)
	var elim_rocks: int = _room_rock_count(room3)
	_check("elimination room has its own cover", elim_rocks == 8)
	_check("elim rocks are tall pillars, TDM rocks low slabs", \
		_room_rock_size(room3) == Vector3(3, 7, 3) \
		and _room_rock_size(room2) == Vector3(6, 5, 3))
	_check("elim ring keeps the duel center clean", not _room_center_blocked(room3))
	# The instance style law (2026-10-15): every room renders in the
	# planet's BiomeId palette with a visible wall face, and ROYALE
	# stays bare (terrain cover reserved for the valley itself).
	var elim_floor: Color = _room_env_floor(room3)
	_check("elim room wears desert sand (coliseum biome)", \
		elim_floor.r > 0.7 and elim_floor.g > 0.6)
	_check("TDM room wears olive steppe (sandpit biome)", \
		absf(_room_env_floor(room2).r - 0.52) < 1e-3)
	_check("every elim wall shows its stone face", _room_wall_faces(room3) == 4)
	var room_r = ArenaScene.new()
	room_r.zone_data = zm.get_zone("zone_royale_valley")
	root.add_child(room_r)
	_check("royale zone loaded", room_r.zone_data != null)
	_check("royale room stays bare (cover reserved)", _room_rock_count(room_r) == 0)
	var roy_floor: Color = _room_env_floor(room_r)
	_check("royale room wears badlands rust (valley biome)", \
		roy_floor.r > 0.5 and roy_floor.g < 0.4)
	_check("royale walls show the darker rust rim", _room_wall_faces(room_r) == 4)
	_check("rooms carry a seeded floor tint (no flat paint)", \
		_room_floor_tinted(room3) or _room_floor_tinted(room2))
	room_r.queue_free()
	room3.queue_free()
	await process_frame

	# Shield blocks the kill.
	var first_try: int = room2.report_death("tdm_blue", "tdm_red")
	_check("spawn shield blocks elimination", first_try == -1 and g1.alive)

	# Fire-and-you-lose-it: a self-initiated action breaks the shield;
	# the combat bridge will call break_shield() in S11.
	g1.break_shield()
	_check("self-initiated action breaks shield", not g1.is_shielded())
	var second_try: int = room2.report_death("tdm_blue", "tdm_red")
	_check("broken shield no longer protects", second_try == -1 and not g1.alive)
	_sync_revive(room2, "tdm_blue")
	g1.apply_spawn_shield(4.0)

	# Expire shields, then trade kills to the target: red reaches 20.
	await _settle(0.5)
	# Sync-revive between kills: the real respawn path is the zone's
	# 5 s timer, which headless time will not wait out 20 times. The
	# probe tests the controller's accounting, not the timer, so each
	# iteration force-revives the victim and clears the shield first.
	# Red already has 1 (the shield-break demo kill): 18 more lands
	# one short of the target.
	for i in range(18):
		_sync_revive(room2, "tdm_blue")
		room2.report_death("tdm_blue", "tdm_red")
		await process_frame
	_check("red one short of target (19)", room2.score_for(1) == 19)
	_check("bout NOT over below target", not room2.is_over())
	# 20th kill: blue falls again, red hits the kill target.
	_sync_revive(room2, "tdm_blue")
	room2.report_death("tdm_blue", "tdm_red")
	await process_frame
	_check("red hits kill target 20", room2.score_for(1) == 20)
	_check("TDM bout resolves at kill target", room2.is_over())

	room2.queue_free()
	await process_frame

	# ---- D. Round trip + AFK kick (S11 owner decisions) --------------
	var room4 = ArenaScene.new()
	room4.zone_data = arena
	root.add_child(room4)
	var a1 = room4.spawn_fighter("rt_blue", 0)
	var a2 = room4.spawn_fighter("rt_red", 1)
	room4.origin_stones = {
		"rt_blue": Vector3(5, 1, 5),
		"rt_red": Vector3(-5, 1, -5),
	}
	room4.start_bout()

	var kicked: Array = []
	room4.fighter_afk_kicked.connect(func(fid, pos): kicked.append([fid, pos]))
	var returns: Array = []
	room4.bout_return_requested.connect(func(rmap): returns.append(rmap))

	# AFK kick: idle fighter ejected to their stone; the departure is
	# booked, so elimination resolves last-team-standing.
	room4.kick_fighter("rt_blue")
	_check("AFK kick ejects to origin stone", \
		kicked.size() == 1 and str(kicked[0][0]) == "rt_blue" \
		and (kicked[0][1] as Vector3).distance_to(Vector3(5, 1, 5)) < 0.01)
	_check("bout resolves after AFK departure", room4.is_over())
	_check("bout return map sends everyone to their stone", \
		returns.size() == 1 \
		and (returns[0].get("rt_blue", Vector3.ZERO) as Vector3).distance_to(Vector3(5, 1, 5)) < 0.01 \
		and (returns[0].get("rt_red", Vector3.ZERO) as Vector3).distance_to(Vector3(-5, 1, -5)) < 0.01)
	_check("AFK-kicked fighter is down", not a1.alive and a2.alive)
	room4.queue_free()
	await process_frame

	if _fails == 0:
		print("ARENA INSTANCE PROBE PASSED")
		quit(0)
	else:
		push_error("ARENA INSTANCE PROBE FAILED")
		quit(1)

## Count cover rocks in a room (probe helper).
func _room_rock_count(room) -> int:
	var n := 0
	for c in room.get_children():
		if String(c.name).begins_with("CoverRock_"):
			n += 1
	return n

## Size of the first cover rock (probe helper: pillar vs slab check).
func _room_rock_size(room) -> Vector3:
	for c in room.get_children():
		if String(c.name).begins_with("CoverRock_"):
			for sub in c.get_children():
				if sub is CollisionShape3D and sub.shape is BoxShape3D:
					return (sub.shape as BoxShape3D).size
	return Vector3.ZERO

## Floor plane's albedo (probe helper: the mode env palette check).
func _room_env_floor(room) -> Color:
	if room == null or not ("_floor" in room) or room._floor == null:
		return Color.BLACK
	for c in room._floor.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override is StandardMaterial3D:
			return ((c as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	return Color.BLACK

## Count perimeter walls that show a visual mesh face (probe helper).
func _room_wall_faces(room) -> int:
	if room == null:
		return 0
	var n := 0
	for c in room.get_children():
		if not (c is StaticBody3D):
			continue
		var cn := String(c.name)
		if cn == "ArenaFloor" or cn.begins_with("CoverRock_"):
			continue
		for sub in c.get_children():
			if sub is MeshInstance3D:
				n += 1
				break
	return n

## True when the floor plane carries a noise tint beyond the flat color.
func _room_floor_tinted(room) -> bool:
	if room == null or not ("_floor" in room) or room._floor == null:
		return false
	for c in room._floor.get_children():
		if c is MeshInstance3D:
			var m = (c as MeshInstance3D).material_override
			return m != null and (m as StandardMaterial3D).albedo_texture != null
	return false

## True when any rock sits inside the central duel circle (r = 0.25
## of the room half) -- the elimination ring must keep it open.
func _room_center_blocked(room) -> bool:
	var half: float = float(room.zone_data.zone_radius) * 0.5
	var r: float = half * 0.25
	for c in room.get_children():
		if String(c.name).begins_with("CoverRock_"):
			var flat := Vector2(c.position.x, c.position.z)
			if flat.length() < r:
				return true
	return false

## Force a fighter back to life synchronously (probe-only: simulates
## the respawn without waiting the zone timer out).
func _sync_revive(room, id: String) -> void:
	var f = room._fighters.get(id)
	if f != null:
		f.alive = true
		f.collision_layer = 1
		f.collision_mask = 1
		f.shielded_until = 0.0

func _settle(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await physics_frame
		t += 1.0 / 60.0

func _check(label: String, cond: bool) -> void:
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
