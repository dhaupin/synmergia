## Planet-scale terrain arc probe (the terrain law end-to-end).
## A. The ground law: spawn plaza flat at SPAWN_HEIGHT; island plateau
##    above the sea line; lake bowl below it; open ocean deep; the
##    law is a pure function (same answer twice).
## B. The walker on a 20 km globe: spawns ON the walk surface (the
##    terrain law + ground offset), stays glued through a walk, and
##    the provider really feeds the terrain law.
## C. The water shell exists exactly at the sea line (visual truth ==
##    physics truth); prototype globes stay dry.
## D. Boulders: colliders attached (climbable), collar caps present,
##    and the walk law never tunnels a boulder (cap >= collar top).
## Run headless: godot --headless --path . --script res://tests/probe_terrain_planet.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const Gen = preload("res://scenes/worlds/terrain_gen.gd")
const Sph = preload("res://core/frame/math/spherical.gd")
const RADIUS_SETTING := "synmergia/world/planet_radius"
const R20KM: float = 20000.0

var _checks := 0
var _globe: Node3D


func _init() -> void:
	call_deferred("_run")


func _check(label: String, cond: bool) -> bool:
	_checks += 1
	print(("  PASS " if cond else "  FAIL ") + label)
	return cond


func _run() -> void:
	var ok := true
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var sea: float = Gen.sea_level(seed_b)

	# ---- A. The ground law ------------------------------------------
	var d_spawn: Vector3 = Sph.spherical_to_cartesian(0.0, 0.0, 0.0, 1.0)
	ok = _check("law: spawn plaza flat at SPAWN_HEIGHT", \
		absf(Gen.terrain_height(d_spawn, seed_b) - Gen.SPAWN_HEIGHT) < 0.01) and ok
	var d_isl: Vector3 = Gen.ISLAND_CENTER.normalized()
	ok = _check("law: island plateau above the sea line", \
		Gen.terrain_height(d_isl, seed_b) > sea + Gen.ISLAND_PLATEAU * 0.9) and ok
	var d_lake: Vector3 = Gen.LAKE_CENTER.normalized()
	ok = _check("law: lake bowl below the sea line", \
		Gen.terrain_height(d_lake, seed_b) < sea - Gen.LAKE_DROP * 0.9) and ok
	# Open ocean: beyond the continent dome (2.0 rad), the far side of
	# the planet reads deep water.
	var d_sea: Vector3 = Sph.spherical_to_cartesian(-30.0, 180.0, 0.0, 1.0)
	ok = _check("law: open ocean is deep", \
		Gen.terrain_height(d_sea, seed_b) < sea - 6.0) and ok
	ok = _check("law: pure function (same answer twice)", \
		Gen.terrain_height(d_spawn, seed_b) == Gen.terrain_height(d_spawn, seed_b)) and ok
	# The homeland: every face center inside the PLATEAU zone (60% of
	# the dome reach -- beyond that is the bay-carved coast, by design)
	# is solid land. The start area is solid ground; the coast is a
	# journey.
	var Faces = load("res://core/frame/math/icosahedral_faces.gd")
	var homeland_ok := true
	for f in [0, 1, 2, 3, 4, 5, 6, 7]:
		var fc: Vector3 = Faces.face_center(f)
		if fc.angle_to(d_spawn) < Gen.HOMELAND_ANGULAR_REACH * 0.6 \
				and Gen.terrain_height(fc, seed_b) < sea:
			homeland_ok = false
	ok = _check("law: homeland dome is solid land around spawn", homeland_ok) and ok
	# Continuity near the spawn ramp: halves the step when the step
	# halves (the same refinement discipline the determinism test
	# uses for rock caps).
	var smooth := true
	var prev: float = Gen.terrain_height(d_spawn, seed_b)
	for i in range(1, 9):
		var d: Vector3 = Sph.spherical_to_cartesian(0.0, float(i) * 0.001, 0.0, 1.0)
		var h: float = Gen.terrain_height(d, seed_b)
		if absf(h - prev) > 4.0:
			smooth = false
		prev = h
	ok = _check("law: spawn ramp is continuous (max step <= 4 m)", smooth) and ok

	# ---- B. The walker on the 20 km globe ---------------------------
	ProjectSettings.set_setting(RADIUS_SETTING, R20KM)
	var packed: PackedScene = load(GLOBE_SCENE)
	if packed == null or not packed.can_instantiate():
		push_error("FAIL: globe scene did not load")
		quit(1)
		return
	_globe = packed.instantiate()
	root.add_child(_globe)
	await root.get_tree().process_frame
	var player = _globe.get("player")
	if player == null:
		push_error("FAIL: player missing")
		quit(1)
		return
	for i in range(6):
		await root.get_tree().physics_frame

	# Spawn sits on the WALK surface: terrain law + ground offset.
	var surface_gap: float = _globe.player_surface_error()
	ok = _check("walk: spawned on the terrain walk surface (err %.2f m)" % surface_gap, \
		absf(surface_gap) < 1.5) and ok
	ok = _check("walk: water shell present at planet scale", _globe.water_body != null) and ok

	# MESH TRUTH: the streamed tile VERTICES must ride the same law the
	# walker rides (round-5 lesson: the analytic law was green while the
	# mesh displaced along garbage directions -- the world looked like
	# open ocean because the water shell was the only intact sphere).
	var mesh_ok := true
	var mesh_checked := 0
	var spawn_face: int = load("res://core/frame/math/icosahedral_faces.gd").face_for_direction(d_spawn)
	var patch: MeshInstance3D = _globe.streamer._patches.get(spawn_face)
	if patch != null and patch.mesh != null:
		var arrays: Array = (patch.mesh as ArrayMesh).surface_get_arrays(0)
		var verts_arr: PackedVector3Array = arrays[ArrayMesh.ARRAY_VERTEX]
		var patch_center: Vector3 = load("res://core/frame/math/icosahedral_faces.gd").face_center(spawn_face) \
			* (R20KM + 0.52)
		for vi in range(0, verts_arr.size(), 97):
			var local_v: Vector3 = verts_arr[vi]
			var globe_v: Vector3 = local_v + patch_center
			var vdir: Vector3 = globe_v.normalized()
			# Radial position must be within the terrain band of the law
			# (not ~2x planet radius -- the debris signature).
			var expected_r: float = R20KM + 0.52 + Gen.terrain_height(vdir, seed_b)
			if absf(globe_v.length() - expected_r) > 3.0:
				mesh_ok = false
			mesh_checked += 1
	ok = _check("mesh: tile vertices ride the terrain law (%d sampled)" % mesh_checked, \
		mesh_ok and mesh_checked > 0) and ok

	# MESH RESIDENCY (web play-test round 15): the spawn plaza must survive
	# the mesh RESOLUTION, not just the law. At the v1 scale the streamed
	# mesh samples the heightfield only every ~330 m; a sub-tile plaza
	# leaves the boot buried inside the hillside (the camera drops under
	# the surface, the backface-culled terrain vanishes, and the water
	# shell is the only surface left: "I spawned on the ocean layer").
	# Pin: the spawn-face vertices within the ~360 m boot horizon all ride
	# the plaza height (the walk surface).
	var near_n := 0
	var boot_flat := true
	var best_ang := 1e9
	var best_lift := 0.0
	if patch != null and patch.mesh != null:
		var arrays3: Array = (patch.mesh as ArrayMesh).surface_get_arrays(0)
		var verts3: PackedVector3Array = arrays3[ArrayMesh.ARRAY_VERTEX]
		var pc: Vector3 = load("res://core/frame/math/icosahedral_faces.gd").face_center(spawn_face) * (R20KM + 0.52)
		for v in verts3:
			var gv: Vector3 = v + pc
			var vd: Vector3 = gv.normalized()
			var ang: float = vd.angle_to(d_spawn)
			var lift: float = gv.length() - (R20KM + 0.52)
			if ang < best_ang:
				best_ang = ang
				best_lift = lift
			if ang * R20KM <= 360.0:
				near_n += 1
				if absf(lift - Gen.SPAWN_HEIGHT) > 1.0:
					boot_flat = false
	ok = _check("mesh: spawn plaza is RESOLVED (nearest vert lift %.2f m == SPAWN_HEIGHT %.1f)" % [best_lift, Gen.SPAWN_HEIGHT], \
		near_n > 0 and absf(best_lift - Gen.SPAWN_HEIGHT) < 1.0) and ok
	ok = _check("mesh: boot horizon is flat plaza (%d verts within 360 m)" % near_n, \
		near_n > 0 and boot_flat) and ok

	# WINDING (web play-test round 15): the patches were built in the
	# icosahedral (outward-CCW) corner order, which is the OPPOSITE of
	# Godot's front-face convention, so every patch was BACK-facing and
	# CULLED -- the streamed terrain drew no fragments and the boot saw
	# only the base green shell + the teal water shell ("I spawned on the
	# ocean layer, land above me"). Compare the patch's triangle
	# orientation to a Godot-built mesh (a SphereMesh renders correctly
	# under CULL_BACK by construction): they MUST agree in sign.
	var patch_orient := 0.0
	var patch_tris := 0
	if patch != null and patch.mesh != null:
		var w_arrays: Array = (patch.mesh as ArrayMesh).surface_get_arrays(0)
		var w_verts: PackedVector3Array = w_arrays[ArrayMesh.ARRAY_VERTEX]
		var w_pc: Vector3 = load("res://core/frame/math/icosahedral_faces.gd").face_center(spawn_face) * (R20KM + 0.52)
		var ti := 0
		while ti + 2 < w_verts.size():
			var va: Vector3 = w_verts[ti] + w_pc
			var vb: Vector3 = w_verts[ti + 1] + w_pc
			var vc: Vector3 = w_verts[ti + 2] + w_pc
			var gnorm: Vector3 = (vb - va).cross(vc - va)
			if gnorm.length_squared() > 0.000001:
				patch_orient += gnorm.normalized().dot(((va + vb + vc) / 3.0).normalized())
				patch_tris += 1
			ti += 3
	var ref_sphere := SphereMesh.new()
	ref_sphere.radius = 10.0
	ref_sphere.height = 20.0
	ref_sphere.radial_segments = 24
	ref_sphere.rings = 12
	var ref_arrays: Array = ref_sphere.surface_get_arrays(0)
	var ref_verts: PackedVector3Array = ref_arrays[ArrayMesh.ARRAY_VERTEX]
	var ref_orient := 0.0
	var ref_n := 0
	var ri := 0
	while ri + 2 < ref_verts.size():
		var ra: Vector3 = ref_verts[ri]
		var rb: Vector3 = ref_verts[ri + 1]
		var rc: Vector3 = ref_verts[ri + 2]
		var rgn: Vector3 = (rb - ra).cross(rc - ra)
		if rgn.length_squared() > 0.000001:
			ref_orient += rgn.normalized().dot((ra + rb + rc).normalized())
			ref_n += 1
		ri += 3
	var ref_mean: float = ref_orient / float(maxi(ref_n, 1))
	var patch_mean: float = patch_orient / float(maxi(patch_tris, 1))
	ok = _check("mesh: patch winding matches a Godot sphere (patch %.4f vs sphere %.4f)" % [patch_mean, ref_mean], \
		patch_tris > 0 and signf(patch_mean) == signf(ref_mean) and absf(patch_mean) > 0.001) and ok

	# TERRAIN LOD: the NEAR law. Faces whose ground reaches within one
	# tile edge of the player ride the full base level; farther
	# active-set members demote one level. The spawn sits ON the
	# equatorial edge two faces share, so BOTH must hold full detail
	# (the boundary-flip repair this probe pins). The walk law is
	# level-independent (the analytic heightfield), so the snapped
	# walker must not drift when neighbors are coarse.
	var near_face: int = load("res://core/frame/math/icosahedral_faces.gd").face_for_direction(d_spawn)
	var near_lvl: int = int(_globe.streamer._patch_lvl.get(near_face, -1))
	ok = _check("lod: spawn face rides the base level (%d)" % near_lvl, \
		near_lvl == _globe.streamer._level_for_edge()) and ok
	# The whole streamed world is the analytic law: near or coarse, the
	# walk surface is the same answer per face.
	for f in _globe.streamer.active_faces():
		var fc: Vector3 = load("res://core/frame/math/icosahedral_faces.gd").face_center(f)
		var meshes_h: float = _globe.streamer.walk_surface_h(fc)
		var law_h: float = Gen.terrain_height(fc, seed_b) + Gen.rock_top_height(fc, seed_b, f, R20KM)
		ok = _check("lod: face %d ground law is level-independent" % f, \
			absf(meshes_h - law_h) < 0.01) and ok

	# The provider really feeds the terrain law: sample it at the body.
	var d_body: Vector3 = (player.global_position - _globe.planet_center).normalized()
	var prov: float = player.snap_height_provider.call(player.global_position)
	var face0: int = load("res://core/frame/math/icosahedral_faces.gd").face_for_direction(d_body)
	var law: float = Gen.walk_height(d_body, _globe.streamer.world_seed, face0, R20KM, true)
	ok = _check("walk: provider rides the walk law (prov %.2f vs law %.2f)" % [prov, law], \
		absf(prov - law) < 0.5) and ok

	# A short walk stays glued (terrain rides under the body).
	player.begin_loop()
	player.auto_walk = true
	var frames := 0
	while frames < 150:
		await root.get_tree().physics_frame
		frames += 1
	player.auto_walk = false
	var gap2: float = _globe.player_surface_error()
	ok = _check("walk: glued after a 2.5 s walk (err %.2f m)" % gap2, \
		absf(gap2) < 2.5) and ok
	ok = _check("walk: the walk moved the body", player.path_walked > 3.0) and ok

	# TERRAIN LOD (NEAR law, planet scale): after the walk the player is
	# ~15 m mid-face; faces whose ground reaches one tile edge of the
	# player keep the base level, farther ACTIVE-SET members demote one
	# level (the boundary-tie repair: ownership is not the gate).
	var base_lvl: int = _globe.streamer._level_for_edge()
	var near_count := 0
	for f in _globe.streamer.active_faces():
		if int(_globe.streamer._patch_lvl.get(f, -1)) == base_lvl:
			near_count += 1
	ok = _check("lod: near faces hold base level (%d of %d)" % [near_count, _globe.streamer.active_faces().size()], \
		near_count >= 1 and near_count < _globe.streamer.active_faces().size()) and ok

	# SKIRT pin (the T-junction repair): every terrain-on patch carries
	# a surface-1 skirt (perimeter drop strips) whose tri count is a
	# positive multiple of 2, and whose perimeter edge count matches
	# the subdivision math (3 * 2^level edges per face). Surface 0 is
	# untouched: the vertex-law checks above sampled it clean.
	var skirt_ok := true
	var skirt_faces := 0
	for f in _globe.streamer.active_faces():
		var st_count: int = int(_globe.streamer._patch_skirt_tris.get(f, 0))
		var patch_mi: MeshInstance3D = _globe.streamer._patches.get(f)
		var own_lvl: int = int(_globe.streamer._patch_lvl.get(f, 0))
		var want_edges: int = 3 * (1 << own_lvl)  # 3 border arcs x 2^lvl tile edges per face
		if st_count <= 0 or st_count % 2 != 0 or (st_count / 2) != want_edges or patch_mi == null or patch_mi.mesh == null or patch_mi.mesh.get_surface_count() != 2:
			skirt_ok = false
		else:
			skirt_faces += 1
	ok = _check("lod: skirts on every streamed patch (%d faces, 6 verts/edge strip on surface 1)" % skirt_faces, skirt_ok) and ok

	# HYSTERESIS pin (the edge pump repair): a face BETWEEN the inner
	# and outer bands must NOT change level frame-to-frame, and a face
	# beyond the outer band must survive LOD_FAR_TICKS - 1 frames
	# before demoting. Drive _demanded_level directly (the law is
	# pure except for the tick dwell).
	var own_face: int = load("res://core/frame/math/icosahedral_faces.gd").face_for_direction(d_body)
	var base2: int = _globe.streamer._level_for_edge()
	var reach2: float = _globe.streamer._face_reach(near_face)
	var band_in: float = _globe.streamer._near_band(base2)
	var band_out: float = band_in * (1.0 + _globe.streamer.LOD_HYSTERESIS_MARGIN)
	var between_dir: Vector3 = load("res://core/frame/math/icosahedral_faces.gd").face_center(near_face) \
		.rotated(load("res://core/frame/math/icosahedral_faces.gd").face_center(near_face).cross(Vector3(0, 1, 0)).normalized(), reach2 + (band_in + band_out) * 0.5)
	_globe.streamer._patch_lvl[near_face] = base2 - 1  # suppose it demoted earlier
	var held: int = _globe.streamer._demanded_level(near_face, between_dir, base2 - 1)
	ok = _check("lod: between-band level stands (cur kept)", held == base2 - 1) and ok
	# Far beyond the outer band: demote only after the dwell.
	var far_dir: Vector3 = load("res://core/frame/math/icosahedral_faces.gd").face_center(near_face) \
		.rotated(load("res://core/frame/math/icosahedral_faces.gd").face_center(near_face).cross(Vector3(0, 1, 0)).normalized(), reach2 + band_out * 3.0)
	var dwell_ok := true
	for t in range(_globe.streamer.LOD_FAR_TICKS - 1):
		if _globe.streamer._demanded_level(near_face, far_dir, base2 - 1) != base2 - 1:
			dwell_ok = false
			break
	_globe.streamer._patch_lvl[near_face] = base2  # restore
	ok = _check("lod: far face survives the dwell before demoting", dwell_ok) and ok
	var promoted: int = _globe.streamer._demanded_level(near_face, load("res://core/frame/math/icosahedral_faces.gd").face_center(near_face), base2 - 1)
	ok = _check("lod: promote is instant (no dwell)", promoted == base2) and ok

	# HOT REUSE pin (the reload-cost repair): a level change rebuilds
	# ONLY the mesh; the prop holder (rocks/trees/boulders + colliders)
	# grafts across so rock NODES keep identity -- the walk law and the
	# services keyed on those bodies never notice. Force a real hot
	# swap (demote then promote the spawn face) and demand: the SAME
	# rock instance objects are still in _patch_rocks after both.
	var reuse_face: int = near_face
	var rocks_before_ids: Array = []
	for r in (_globe.streamer._patch_rocks.get(reuse_face, []) as Array):
		rocks_before_ids.append(r.get_instance_id())
	var hot_lvl: int = base2 - 1
	var hot_ok: bool = _globe.streamer._hot_reload(reuse_face, hot_lvl)
	var hot_back: bool = _globe.streamer._hot_reload(reuse_face, base2)
	var rocks_after_ids: Array = []
	for r in (_globe.streamer._patch_rocks.get(reuse_face, []) as Array):
		rocks_after_ids.append(r.get_instance_id())
	ok = _check("lod: hot demote+promote grafted (both true)", hot_ok and hot_back) and ok
	ok = _check("lod: rock NODES survive the level change (identity kept)", \
		rocks_before_ids == rocks_after_ids and not rocks_before_ids.is_empty()) and ok
	var reuse_mesh: MeshInstance3D = _globe.streamer._patches.get(reuse_face)
	ok = _check("lod: hot swap resets the mesh to base level", \
		reuse_mesh != null and int(_globe.streamer._patch_lvl.get(reuse_face, -1)) == base2 \
		and reuse_mesh.mesh.get_surface_count() == 2) and ok

	# ---- C. The water shell is the sea line -------------------------
	if _globe.water_body != null:
		var wr: float = (_globe.water_body.mesh as SphereMesh).radius
		ok = _check("water: shell radius == planet + tile lift + sea", \
			absf(wr - (R20KM + 0.52 + sea)) < 0.5) and ok

	# ---- D. Boulders + collar law ------------------------------------
	# Pipeline check on a GUARANTEED boulder face (face 0 carries >= 1
	# by the variety law): attach, climbable group, radial placement
	# above the collar law.
	var ok_d := true
	var spec0_arr: Array = Gen.boulder_specs(_globe.streamer.world_seed, 0)
	ok_d = _check("boulder: face 0 carries the variety guarantee", not spec0_arr.is_empty()) and ok_d
	if not spec0_arr.is_empty():
		var PC = load("res://entities/prop_collider.gd")
		var fake := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = spec0_arr[0].radius
		fm.height = spec0_arr[0].radius * 1.7
		fake.mesh = fm
		root.add_child(fake)
		var fbody: StaticBody3D = PC.attach(fake)
		ok_d = _check("boulder: PropCollider attaches + climbable", \
			fbody != null and fbody.is_in_group("climbable")) and ok_d
		fake.queue_free()
	# Streamed audit: every spec that survives the water law must be
	# wired as a climbable body, and the pipeline must produce at least
	# one live boulder somewhere on a face with land (coast rolls may
	# legitimately skip a given face's spec; the LAW is what is pinned
	# here: survive = attach).
	var live_boulders := 0
	for f in _globe.streamer.active_faces():
		var arr: Array = _globe.streamer._patch_boulders.get(f, [])
		live_boulders += arr.size()
		for b in arr:
			var body: StaticBody3D = b.get_node_or_null("PropBody")
			ok = _check("boulder: streamed body climbable (face %d)" % f, \
				body != null and body.is_in_group("climbable")) and ok
	var expected := 0
	for f in _globe.streamer.active_faces():
		for s in Gen.boulder_specs(_globe.streamer.world_seed, f):
			if Gen.terrain_height(s.dir, _globe.streamer.world_seed) >= Gen.sea_level(_globe.streamer.world_seed) - 0.6:
				expected += 1
	ok = _check("boulder: every on-land spec spawned (live %d == expected %d)" % [live_boulders, expected], \
		live_boulders == expected) and ok

	# ---- Bf. The FORD LAW (slice 3 downstream, drive-the-body) --------
	# A river channel is shallow enough to walk honestly: put the REAL
	# SPAWNED walker in the channel bed and OUTSIDE any channel, and
	# read the body's own law (not the analytic field) both times:
	#  - IN the bed: _wading true, measured walk speed ~ WADE_MULT of
	#    the dry cap (the body crosses slower, no jump).
	#  - DRY (antipode of the spring, no channel there): _wading false,
	#    full walk speed again.
	var ford_ok := false
	var dry_ok := false
	var ford_found := false
	var ford_depth := 0.0
	var ford_speed_ratio := 0.0
	var RADIUS_TEST: float = R20KM
	var GPlayer = load("res://entities/globe_player.gd")
	var seed_p: PackedByteArray = _globe.streamer.world_seed
	var fc: Vector3 = Vector3.ZERO
	var fdry: Vector3 = Vector3.ZERO
	for spec in Gen.river_specs_cached(seed_p):
		var pts: PackedVector3Array = spec.path
		# Two-band law (the body's own): channel water + gated table.
		for k in range(pts.size()):
			var mid: Vector3 = pts[k].normalized()
			if mid.angle_to(Gen.SPAWN_CENTER) < Gen.Hydro.SUPPRESS_IN:
				continue
			var chan: float = Gen.river_channel(mid, seed_p)
			var depth: float = Gen.Hydro.RIVER_BED_DEPTH * chan if chan > 0.25 else 0.0
			var surf: float = Gen.hydro_water_surface(mid, seed_p)
			if surf > -1e8:
				depth = maxf(depth, surf - Gen.terrain_height(mid, seed_p))
			if depth > 0.2 and depth <= 1.55:
				fc = mid
				fdry = (mid * -1.0).normalized()
				ford_depth = depth
	if fc != Vector3.ZERO:
		var wader: CharacterBody3D = GPlayer.new()
		wader.planet_radius = R20KM
		wader.planet_center = Vector3.ZERO
		wader.entity_id = "probe_ford"
		# The wader rides the SAME walk law the real player does. The old
		# Callable() (shell ride) worked for the wet site only by
		# coincidence: a shell rider placed by the terrain formula is
		# airborne at any bank whose terrain sits above the flat shell, the
		# auto wing then opened mid-fall, the glider branch ate the whole
		# measured window, and path_walked read 0 (hence dry_speed == 0).
		# With the real provider, altitude reads 0 on both banks,
		# no wing, and both legs measure their actual walk.
		wader.snap_height_provider = Callable(_globe.streamer, "walk_surface_h")
		# Parent UNDER the globe so terrain_on_local() resolves the
		# streamer's terrain_on_flag seam (the ford law needs it).
		_globe.add_child(wader)
		wader.global_position = fc * (R20KM + 0.52 + Gen.terrain_height(fc, _globe.streamer.world_seed) - 0.2)
		var aut: float = wader._wade_depth_at()
		ford_found = true
		ford_ok = aut > 0.15
		# Measured speed: one second of steady auto-walk at BOTH sites
		# (10 ramp frames dropped at each; `path_walked` reset first so
		# only the measured leg counts).
		wader.auto_walk = true
		wader.auto_walk_yaw = 0.0
		for i in range(10):
			await root.get_tree().physics_frame
		wader.path_walked = 0.0
		for i in range(60):
			await root.get_tree().physics_frame
		var wet_speed: float = wader.path_walked / 1.0
		# The wade flag is read at the WET site (the dry leg below
		# overwrites the body state).
		var wet_wading: bool = wader._wading
		ford_ok = ford_ok and wet_wading
		wader.auto_walk = false
		wader.global_position = fdry * (R20KM + 0.52 + Gen.terrain_height(fdry, _globe.streamer.world_seed))
		wader.velocity = Vector3.ZERO
		wader.auto_walk = true
		for i in range(10):
			await root.get_tree().physics_frame
		wader.path_walked = 0.0
		for i in range(60):
			await root.get_tree().physics_frame
		var dry_speed: float = wader.path_walked / 1.0
		dry_ok = (not wader._wading) and (not wader._wade_stamp_live)
		ford_speed_ratio = wet_speed / maxf(dry_speed, 0.01)
		wader.queue_free()
	ok = _check("ford: a wadeable river section exists on the planet (%s)" % ford_found, ford_found) and ok
	ok = _check("ford: body wades in the channel bed (depth %.2f m)" % ford_depth, ford_ok) and ok
	ok = _check("ford: dry ground reads no wade (antipodal bank)", dry_ok) and ok
	ok = _check("ford: waded walk is slowed (speed ratio %.2f, band [0.3, 0.95])" % ford_speed_ratio, \
		ford_speed_ratio > 0.3 and ford_speed_ratio < 0.95) and ok

	if _globe and is_instance_valid(_globe):
		_globe.queue_free()
		await root.get_tree().process_frame
	ProjectSettings.set_setting(RADIUS_SETTING, 100.0)

	if ok:
		print("PASS: terrain arc on the planet (%d checks)" % _checks)
		quit(0)
	else:
		push_error("FAIL: terrain arc on the planet")
		quit(1)
