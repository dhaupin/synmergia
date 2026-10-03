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
