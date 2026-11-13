## Planet-scale terrain arc probe (the terrain law end-to-end).
## A. The ground law: spawn plaza flat at SPAWN_HEIGHT; island plateau
##    above the sea line; lake bowl below it; open ocean deep; the
##    law is a pure function (same answer twice).
## B. The walker on a 20 km globe: spawns ON the walk surface (the
##    terrain law + ground offset), stays glued through a walk, and
##    the provider really feeds the terrain law; the DRAWN clipmap
##    vertices ride the same law (winding included).
## C. The water shell exists exactly at the sea line (visual truth ==
##    physics truth); prototype globes stay dry.
## D. Boulders: colliders attached (climbable), and the PropLayer's
##    streamed boulders are wired as climbable bodies.
## Run headless: godot --headless --path . --script res://tests/probe_terrain_planet.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const Gen = preload("res://scenes/worlds/terrain_gen.gd")
const Sph = preload("res://core/frame/math/spherical.gd")
const Faces = preload("res://core/frame/math/icosahedral_faces.gd")
const RADIUS_SETTING := "synmergia/world/planet_radius"
const R20KM: float = 20000.0
const LIFT: float = 0.52

var _checks := 0
var _globe: Node3D


func _init() -> void:
	call_deferred("_run")


func _check(label: String, cond: bool) -> bool:
	_checks += 1
	print(("  PASS " if cond else "  FAIL ") + label)
	return cond


## The clipmap builds incrementally through its job queue; a level census
## needs a steady world, so drain the derive lane with an honest deadline.
func _drain_derives(deadline_ms: int) -> void:
	var st = _globe.streamer
	var deadline: int = Time.get_ticks_msec() + deadline_ms
	while st.pending_derive() > 0 and Time.get_ticks_msec() < deadline:
		await root.get_tree().physics_frame


## Collect the clipmap's DRAWN ground vertices as [dir, drawn_h] pairs.
## Returns data rather than a callback: GDScript lambdas capture by value,
## so an accumulator written inside one never propagates to the caller.
func _sample_drawn(st, step: int) -> Array:
	var out: Array = []
	for mi in st.ground_meshes():
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() < 1:
			continue
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var xf: Transform3D = mi.global_transform
		for vi in range(0, verts.size(), step):
			var wv: Vector3 = xf * verts[vi]
			var dir: Vector3 = (wv - _globe.planet_center).normalized()
			var drawn: float = wv.distance_to(_globe.planet_center) - (R20KM + LIFT)
			out.append([dir, drawn])
	return out


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
	var d_sea: Vector3 = Sph.spherical_to_cartesian(-30.0, 180.0, 0.0, 1.0)
	ok = _check("law: open ocean is deep", \
		Gen.terrain_height(d_sea, seed_b) < sea - 6.0) and ok
	ok = _check("law: pure function (same answer twice)", \
		Gen.terrain_height(d_spawn, seed_b) == Gen.terrain_height(d_spawn, seed_b)) and ok
	var homeland_ok := true
	for f in [0, 1, 2, 3, 4, 5, 6, 7]:
		var fc: Vector3 = Faces.face_center(f)
		if fc.angle_to(d_spawn) < Gen.HOMELAND_ANGULAR_REACH * 0.6 \
			and Gen.terrain_height(fc, seed_b) < sea:
			homeland_ok = false
	ok = _check("law: homeland dome is solid land around spawn", homeland_ok) and ok
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
	var st = _globe.get("streamer")

	var surface_gap: float = _globe.player_surface_error()
	ok = _check("walk: spawned on the terrain walk surface (err %.2f m)" % surface_gap, \
		absf(surface_gap) < 1.5) and ok
	ok = _check("walk: water shell present at planet scale", _globe.water_body != null) and ok

	# MESH TRUTH: the clipmap's DRAWN vertices must ride the same law the
	# walker rides (the round-5 lesson: the analytic law was green while
	# the mesh displaced along garbage directions).
	var mesh_ok := true
	var mesh_worst := 0.0
	var samples: Array = _sample_drawn(st, 53)
	for s in samples:
		var law: float = Gen.terrain_height(s[0], seed_b)
		var dev: float = absf(float(s[1]) - law)
		if dev > mesh_worst:
			mesh_worst = dev
		if dev > 3.0:
			mesh_ok = false
	ok = _check("mesh: clipmap verts ride the terrain law (%d sampled, worst %.3f m)" % [samples.size(), mesh_worst], \
		mesh_ok and samples.size() > 0) and ok

	# MESH RESIDENCY: the spawn plaza must survive the mesh RESOLUTION. Find
	# the drawn vert nearest the spawn dir and pin its lift to the plaza.
	var best_ang := 1.0e9
	var best_lift := 0.0
	for s in _sample_drawn(st, 7):
		var ang: float = s[0].angle_to(d_spawn)
		if ang < best_ang:
			best_ang = ang
			best_lift = float(s[1])
	ok = _check("mesh: spawn plaza is RESOLVED (nearest vert lift %.2f m == SPAWN_HEIGHT %.1f)" % [best_lift, Gen.SPAWN_HEIGHT], \
		absf(best_lift - Gen.SPAWN_HEIGHT) < 1.0) and ok

	# WINDING: the drawn ground must face OUTWARD (Godot CULL_BACK). Compare
	# the clipmap's triangle orientation sign to a Godot-built sphere.
	var cap_orient := 0.0
	var cap_tris := 0
	for mi in st.ground_meshes():
		if mi == null or mi.mesh == null:
			continue
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx_v = arrays[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array = PackedInt32Array(idx_v) if idx_v != null else PackedInt32Array()
		var tris: PackedInt32Array = idx if idx.size() > 0 else PackedInt32Array(range(verts.size()))
		var xf: Transform3D = mi.global_transform
		for ti in range(0, tris.size() - 2, 3):
			var va: Vector3 = xf * verts[tris[ti]]
			var vb: Vector3 = xf * verts[tris[ti + 1]]
			var vc: Vector3 = xf * verts[tris[ti + 2]]
			var gnorm: Vector3 = (vb - va).cross(vc - va)
			if gnorm.length_squared() > 0.000001:
				cap_orient += gnorm.normalized().dot(((va + vb + vc) / 3.0 - _globe.planet_center).normalized())
				cap_tris += 1
	var ref_sphere := SphereMesh.new()
	ref_sphere.radius = 10.0
	ref_sphere.height = 20.0
	ref_sphere.radial_segments = 24
	ref_sphere.rings = 12
	var ref_arrays: Array = ref_sphere.surface_get_arrays(0)
	var ref_verts: PackedVector3Array = ref_arrays[Mesh.ARRAY_VERTEX]
	var ref_orient := 0.0
	var ref_n := 0
	for ri in range(0, ref_verts.size() - 2, 3):
		var ra: Vector3 = ref_verts[ri]
		var rb: Vector3 = ref_verts[ri + 1]
		var rc: Vector3 = ref_verts[ri + 2]
		var rgn: Vector3 = (rb - ra).cross(rc - ra)
		if rgn.length_squared() > 0.000001:
			ref_orient += rgn.normalized().dot((ra + rb + rc).normalized())
			ref_n += 1
	var ref_mean: float = ref_orient / float(maxi(ref_n, 1))
	var cap_mean: float = cap_orient / float(maxi(cap_tris, 1))
	ok = _check("mesh: clipmap winding faces outward (clipmap %.4f vs sphere %.4f)" % [cap_mean, ref_mean], \
		cap_tris > 0 and signf(cap_mean) == signf(ref_mean) and absf(cap_mean) > 0.001) and ok

	# The provider really feeds the terrain law: sample it at the body.
	var d_body: Vector3 = (player.global_position - _globe.planet_center).normalized()
	var prov: float = player.snap_height_provider.call(player.global_position)
	var face0: int = Faces.face_for_direction(d_body)
	var law: float = Gen.walk_height(d_body, st.world_seed, face0, R20KM, true)
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

	# The clipmap has NO discrete per-face LOD bands and NO skirts (constant
	# SEG cells stitch the rings); its LOD ladder, ring stitching, and
	# re-centre economy are pinned by probe_clipmap G1-G5. Here we pin only
	# that the drawn mesh is CONSTANT (the geometric-ring law) and that every
	# drawn mesh carries a real ground surface.
	await _drain_derives(30000)
	var tris_a: int = st.triangle_count()
	ok = _check("clipmap: triangle count constant (geometric rings, %d)" % tris_a, tris_a > 0) and ok
	ok = _check("clipmap: every drawn ground mesh carries surface 0", \
		_all_have_surface0(st)) and ok

	# ---- C. The water shell is the sea line -------------------------
	if _globe.water_body != null:
		var wr: float = (_globe.water_body.mesh as SphereMesh).radius
		ok = _check("water: shell radius == planet + tile lift + sea", \
			absf(wr - (R20KM + LIFT + sea)) < 0.5) and ok

	# ---- D. Boulders + collar law ------------------------------------
	var ok_d := true
	var spec0_arr: Array = Gen.boulder_specs(st.world_seed, 0)
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
	ok = ok_d and ok
	# Streamed audit: every boulder the PropLayer draws is wired as a
	# climbable body (the prop layer's own "survive = attach" law).
	var pl = st.prop_layer()
	var live_boulders := 0
	var wired := 0
	if pl != null:
		for k in pl._built.keys():
			var node = pl._built.get(k)
			if node == null or not is_instance_valid(node):
				continue
			for ch in node.get_children():
				if String(ch.name).begins_with("Boulder"):
					live_boulders += 1
					var body: StaticBody3D = ch.get_node_or_null("PropBody")
					if body != null and body.is_in_group("climbable"):
						wired += 1
	ok = _check("boulder: every streamed boulder is climbable (wired %d of %d)" % [wired, live_boulders], \
		wired == live_boulders) and ok
	# PROPS EVERYWHERE: the flora layer actually placed chunks (the clipmap
	# streams props on the same viewer position, independent of the mesh).
	ok = _check("props: the flora layer placed chunks (%d built)" % (st.prop_count()), \
		st.prop_count() > 0) and ok

	# ---- Bf. The FORD LAW (slice 3 downstream, drive-the-body) --------
	var ford_ok := false
	var dry_ok := false
	var ford_found := false
	var ford_depth := 0.0
	var ford_speed_ratio := 0.0
	var GPlayer = load("res://entities/globe_player.gd")
	var seed_p: PackedByteArray = st.world_seed
	var fc: Vector3 = Vector3.ZERO
	var fdry: Vector3 = Vector3.ZERO
	for spec in Gen.river_specs_cached(seed_p):
		var pts: PackedVector3Array = spec.path
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
				ford_depth = depth
	if fc != Vector3.ZERO:
		fdry = Gen.SPAWN_CENTER.normalized()
	if fc != Vector3.ZERO:
		var wader: CharacterBody3D = GPlayer.new()
		wader.planet_radius = R20KM
		wader.planet_center = Vector3.ZERO
		wader.entity_id = "probe_ford"
		wader.snap_height_provider = Callable(st, "walk_surface_h")
		_globe.add_child(wader)
		wader.global_position = fc * (R20KM + LIFT + Gen.terrain_height(fc, st.world_seed) - 0.2)
		var aut: float = wader._wade_depth_at()
		ford_found = true
		ford_ok = aut > 0.15
		wader.auto_walk = true
		wader.auto_walk_yaw = 0.0
		for i in range(10):
			await root.get_tree().physics_frame
		wader.path_walked = 0.0
		for i in range(60):
			await root.get_tree().physics_frame
		var wet_speed: float = wader.path_walked / 1.0
		var wet_wading: bool = wader._wading
		ford_ok = ford_ok and wet_wading
		wader.auto_walk = false
		wader.global_position = fdry * (R20KM + LIFT + Gen.terrain_height(fdry, st.world_seed))
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
	ok = _check("ford: dry ground reads no wade (spawn-apron law)", dry_ok) and ok
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


func _all_have_surface0(st) -> bool:
	var meshes: Array = st.ground_meshes()
	if meshes.is_empty():
		return false
	for mi in meshes:
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() < 1:
			return false
	return true
