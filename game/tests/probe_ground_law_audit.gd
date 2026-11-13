## Probe: THE GROUND-LAW AUDIT (the floating-world round, final pass).
## Headless: godot --headless --path game --script res://tests/probe_ground_law_audit.gd
## The owner's live report (web play-test, the skin-spike pack): "I spawn under
## the grass; walking a bit I clip out and levitate; houses/mobs levitate;
## further out I climb an invisible hill the grass doesn't follow."
##
## The clipmap is the SOLE renderer now. The old reader scanned the clipmap's
## per-face icosa patches; the clipmap draws a player-centred ring ladder, so
## the audit reads THE CLIPMAP'S DRAWN GROUND MESHES (cap + rings): the walk
## law (the radial snap the body rides) and the drawn mesh's own radial height
## must agree along a set of legs out from spawn. The containing-tri scan
## isolates the mesh by nearest triangle centroid and reads its radial height
## (draw-vs-law delta rides the plaza anchor so the planet chord cancels).
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"

var _okay := true
var _globe: Node = null


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS: " + label)
	else:
		_okay = false
		print("FAIL: " + label)


func _quit() -> void:
	# DRAIN BEFORE QUIT (the shutdown-fence law): a worker thread still
	# deriving when the process quits tears down mid-derive and can corrupt
	# the exit code. Wait for the lane to empty (bounded).
	var st = _globe.get("clipmap") if _globe != null else null
	if st != null:
		var deadline: int = Time.get_ticks_msec() + 30000
		while st.pending_derive() > 0 and Time.get_ticks_msec() < deadline:
			await process_frame
	print("probe_ground_law_audit: %s" % ("ALL PASS" if _okay else "FAILS"))
	quit(0 if _okay else 1)


## The containing-tile read on the CLIPMAP's drawn ground. The clipmap's
## ground meshes are triangle soups in the mesh instance's local frame. A
## ray from the PLANET CENTER along d is tested against every tri's plane;
## among the tris whose hit point is barycentric-inside, the OUTERMOST
## (largest t) is the drawn surface the ray exits through. NAN = no drawn
## tri contains the sample (a hole). Returns the radial height above the
## base shell.
func _mesh_at(st, F, tile_r: float, d: Vector3, edge_m: float) -> float:
	var pc: Vector3 = _globe.get("planet_center")
	var best_t: float = -INF
	for mi in st.ground_meshes():
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() < 1:
			continue
		if not mi.is_inside_tree():
			continue
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var vr: Variant = arrays[Mesh.ARRAY_VERTEX]
		if vr == null:
			continue
		var verts: PackedVector3Array = vr
		var ir: Variant = arrays[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array = ir if ir != null else PackedInt32Array()
		var stride: int = 1 if idx.size() > 0 else 0
		var n: int = (idx.size() / 3) if idx.size() > 0 else (verts.size() / 3)
		var xf: Transform3D = mi.global_transform
		for t in range(n):
			var i0: int = idx[t * 3] if stride == 1 else t * 3
			var i1: int = idx[t * 3 + 1] if stride == 1 else t * 3 + 1
			var i2: int = idx[t * 3 + 2] if stride == 1 else t * 3 + 2
			var a0: Vector3 = xf * verts[i0]
			var a1: Vector3 = xf * verts[i1]
			var a2: Vector3 = xf * verts[i2]
			var pn: Vector3 = (a1 - a0).cross(a2 - a0)
			var denom: float = pn.dot(d)
			if absf(denom) < 1e-9:
				continue
			var t_hit: float = pn.dot(a0 - pc) / denom
			if t_hit <= 0.0 or t_hit <= best_t:
				continue
			var x_hit: Vector3 = pc + d * t_hit
			var e1: Vector3 = (a1 - a0).normalized()
			var e2: Vector3 = pn.cross(e1).normalized()
			var rel: Vector2 = Vector2((x_hit - a0).dot(e1), (x_hit - a0).dot(e2))
			var ab: Vector2 = Vector2((a1 - a0).dot(e1), (a1 - a0).dot(e2))
			var ac: Vector2 = Vector2((a2 - a0).dot(e1), (a2 - a0).dot(e2))
			var det: float = ab.x * ac.y - ab.y * ac.x
			if absf(det) < 1e-12:
				continue
			var w1: float = (rel.x * ac.y - rel.y * ac.x) / det
			var w2: float = (ab.x * rel.y - ab.y * rel.x) / det
			var w0: float = 1.0 - w1 - w2
			if w0 < -0.02 or w1 < -0.02 or w2 < -0.02:
				continue
			best_t = t_hit
	if best_t < 0.0:
		return NAN
	return best_t - tile_r


func _initialize() -> void:
	await process_frame
	var packed: PackedScene = load(GLOBE_SCENE)
	var globe = packed.instantiate()
	_globe = globe
	root.add_child(globe)
	for i in range(8):
		await process_frame
	var st = globe.get("clipmap")
	if st == null:
		print("FAIL: no clipmap on the boot")
		quit(1)
		return
	var R: float = float(globe.get("planet_radius"))
	var F = load("res://core/frame/math/icosahedral_faces.gd")
	var Gen = preload("res://scenes/worlds/terrain_gen.gd")
	var Sph = load("res://core/frame/math/spherical.gd")
	var scr = load("res://scenes/worlds/globe_world.gd")
	var seed_b: PackedByteArray = st.world_seed
	var tile_r: float = R + 0.52
	print("radius=%.0f seed_ok=%s" % [R, str(seed_b.size() > 0)])

	# The clipmap's innermost cell at planet scale is ~8 m, so the audit's
	# "edge" for the centroid band is the drawn resolution near the player.
	var edge_m: float = R * 0.0078 * 2.0 * PI / 128.0 * 2.0

	# The boot's own path; the HUD prints lat/lon in degrees, so the
	# owner's shots decode to: shot 3 lon -0.18 deg = 63 m (wolf float),
	# shot 4 lon -1.76 deg = 615 m (the apron ramp).
	var legs: Array = [
		{"lat": 0.0, "lon": 0.0, "tag": "plaza-0m"},
		{"lat": 0.0, "lon": -0.0032, "tag": "hud3---63m"},
		{"lat": 0.0, "lon": -0.03, "tag": "hud4---600m"},
		{"lat": 0.0, "lon": -0.05, "tag": "apron-1km"},
		{"lat": 0.0, "lon": -0.1, "tag": "apron-out-2km"},
	]

	var zero: Vector3 = Sph.spherical_to_cartesian(
		float(scr.SPAWN_LAT_DEG), float(scr.SPAWN_LON_DEG) + 0.286, 0.0, 1.0)
	st.update(zero * R)
	await process_frame
	var walk0: float = st.walk_surface_h(zero)
	var mesh0: float = _mesh_at(st, F, tile_r, zero, edge_m)
	_check("ANCHOR: the drawn clipmap contains the near-vertex anchor", not is_nan(mesh0))
	if is_nan(mesh0):
		await _quit()
		return
	print("ANCHOR (edge %.1f m): walk %.2f mesh-read %.2f mesh-law %+.2f"
		% [edge_m, walk0, mesh0, mesh0 - walk0])

	# THE EXACT-VERTEX ANCHOR: the spawn direction itself must be contained
	# in a drawn tri (the tightest draw-vs-law pin).
	var exact: Vector3 = Sph.spherical_to_cartesian(
		float(scr.SPAWN_LAT_DEG), float(scr.SPAWN_LON_DEG), 0.0, 1.0).normalized()
	st.update(exact * R)
	await process_frame
	var exact_mesh: float = _mesh_at(st, F, tile_r, exact, edge_m)
	var exact_walk: float = st.walk_surface_h(exact)
	_check("EXACT-VERTEX: spawn direction is contained in a drawn tri", not is_nan(exact_mesh))
	if not is_nan(exact_mesh):
		_check("EXACT-VERTEX: draw-vs-walk within the 6 m walk bound (delta %+.1f)"
			% absf(exact_mesh - exact_walk), absf(exact_mesh - exact_walk) < 6.0)
		print("EXACT-VERTEX: walk %.2f mesh-read %.2f mesh-law %+.2f"
			% [exact_walk, exact_mesh, exact_mesh - exact_walk])

	var frames := 0
	for leg in legs:
		var d: Vector3 = Sph.spherical_to_cartesian(
			float(scr.SPAWN_LAT_DEG) + rad_to_deg(float(leg.lat)),
			float(scr.SPAWN_LON_DEG) + rad_to_deg(float(leg.lon)), 0.0, 1.0).normalized()
		st.update(d * R)
		for i in range(4):
			await process_frame
			frames += 1
			if frames > 5000:
				print("FAIL: watchdog frame cap")
				await _quit()
				return
		var walk: float = st.walk_surface_h(d)
		var terrain: float = Gen.terrain_height(d, seed_b)
		var mesh_h: float = _mesh_at(st, F, tile_r, d, edge_m)
		var in_tile: bool = not is_nan(mesh_h)
		var delta: float = (((mesh_h - mesh0) - (walk - walk0)) if in_tile else NAN)
		print("LEG %s: walk %.2f | law(terrain) %.2f | caps %.2f | draw-delta %+.2f %s"
			% [str(leg.tag), walk, terrain, walk - terrain,
				delta, ("IN-TILE" if in_tile else "NO-DRAWN-TILE")])
		if in_tile:
			_check("LEG %s: draw-vs-law within the 6 m walk bound (delta %+.1f)"
				% [str(leg.tag), absf(delta)], absf(delta) < 6.0)
		else:
			_check("LEG %s: the drawn clipmap contains the sample" % str(leg.tag), false)

	_check("clipmap holds the full ring ladder (>= 5 meshes)", st.patch_count() >= 5)
	await _quit()
