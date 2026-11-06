## Probe: THE GROUND-LAW AUDIT (the floating-world round, final pass).
## Headless: godot --headless --path game --script res://tests/probe_ground_law_audit.gd
## The owner's live report (web play-test, the skin-spike pack): "I spawn under
## the grass; walking a bit I clip out and levitate; houses/mobs levitate;
## further out I climb an invisible hill the grass doesn't follow."
## Two earlier audit passes taught the reader its own lessons:
##   - the containing tri must come from SURFACE 0 ONLY (main land) --
##     get_faces() returns the MIXED soup (main + skirt + water), and a
##     skirt/water tri stealing containment reads the wrong layer;
##   - the containing tri must be NEAR-FIELD only -- the tangent-plane
##     projection folds the patch's FAR hemisphere onto the sample
##     (far corners cross the plane at |r| ~ 40 km), so a far tri wins
##     the scan and its chord-polluted read poisons every delta.
## This pass reads: walk law (the radial snap), the analytic field, and
## the level-0 tile's barycentric world radial height -- per leg, and the
## draw-vs-law delta rides the plaza anchor (planet chord cancels).
## TWO PASSES force the patch build at level 7 (the mesh-resolution cap's
## near-horizon level) and level 6 (the web draw the HUD counts).
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"

var _okay := true
var _detached_skips: int = 0

func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS: " + label)
	else:
		_okay = false
		print("FAIL: " + label)

func _quit() -> void:
	print("probe_ground_law_audit: %s" % ("ALL PASS" if _okay else "FAILS"))
	print("DETACHED-SKIPS: %d (out-of-tree patch reads skipped; these were the old corruption reads)" % _detached_skips)
	quit(0 if _okay else 1)

func _bary(p, d: Vector3) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.append(-2.0); out.append(-2.0); out.append(-2.0)
	var q: Array = []
	for i in range(3):
		var vi: Vector3 = p[i]
		q.append(vi - (vi.dot(d)) * d)
	var n: Vector3 = (q[1] - q[0]).cross(q[2] - q[0])
	var denom: float = n.dot(n)
	if absf(denom) < 1e-9:
		return out
	out[0] = n.dot(q[1].cross(q[2])) / denom
	out[1] = n.dot(q[2].cross(q[0])) / denom
	out[2] = n.dot(q[0].cross(q[1])) / denom
	return out

## The containing tile read on SURFACE 0 (main land) only. The tri is
## picked BY NEAREST CENTROID (angular), then a ray along d through the
## origin hits the tri's own plane frame-exactly; the hit point must be
## barycentric-inside in the plane's own 2D basis. NAN = no land tile
## near the sample (the audit flags the hole instead of reading it).
## (Audit pass-2 lesson: get_faces() mixes main+skirt+water, and the
## tangent-plane projection folds the patch's far hemisphere onto the
## sample -- reads must isolate surface 0 and never trust that soup.)
func _mesh_at(st, F, tile_r: float, d: Vector3, edge_m: float, Gen, seed_b: PackedByteArray) -> float:
	# THE VERTEX LAW (MISSDEBUG receipt): the spawn direction maps by
	# direction to face 16, by position to 18, and the tiles that actually
	# cover a near-vertex sample live in WHICHEVER face's patch contains
	# that ground -- so the read scans EVERY BUILT PATCH and takes the
	# global nearest-centroid tri.
	# THE FRAME LAW (probe_walk_mesh_gap receipt): surface-0 verts are in
	# the MeshInstance's LOCAL space; world space rides xf * vert (the
	# earlier hand-law 'vert + face_center * tile_r' was the wrong frame
	# and is why every pass missed).
	var best_ang: float = INF
	var best_p: Array = []
	var miss_note: String = ""
	# THE PLANET-CENTER LAW (the rebase probes' receipt): the globe's
	# scene-shift keeps the player bounded by MOVING the planet -- the
	# mesh verts ride the mesh instance's transform into world space but
	# every direction, the centroid band and the ray/plane read are
	# RELATIVE TO THE PLANET CENTER, never the world origin.
	var pc: Vector3 = Vector3.ZERO
	# THE STREAMER IS A RefCounted (its .parent MEMBER names the mesh
	# holder node, which carries no script) -- so the planet_center read
	# hops UP the tree from st.parent until the globe-script node answers.
	var hop = st.parent
	while hop != null:
		if hop.get("planet_center") != null:
			pc = hop.get("planet_center")
			break
		hop = hop.get_parent()
	for face in (st._patches as Dictionary).keys():
		var mi: MeshInstance3D = (st._patches as Dictionary).get(face)
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() < 1:
			continue
		# THE DETACHED-NODE LAW (the corruption round's receipt): a patch
		# node between erect and add_child (or a stale node the walk
		# already freed) is OUTSIDE the tree; global_transform on it
		# returns IDENTITY and the read feeds LOCAL verts into world
		# space -- the old -4.5 km "face-16 crumple" numbers came exactly
		# from this frame break. Skip and count; only in-tree patches
		# compete for the containing tri.
		if not mi.is_inside_tree():
			_detached_skips += 1
			continue
		# SURFACE ROLE LAW: the global-best-over-surfaces scan reintroduces
		# the pass-1 soup lesson (a WATER tri at sea level h=0 contamination
		# won every near-plaza band -- the anchors all read flush 0.00 while
		# the law stood 28 m up). So each surface is SCORED against the
		# analytic law at its own sampled verts (|v-pc| - tile_r vs
		# terrain_height(dir_v)), the LOWEST-mean-delta surface is the land
		# layer for this patch, and only that surface's tris compete.
		var surf_note: String = ""
		var xf_shown := false
		var surf_data: Array = []  # {verts, idx, stride, n, band, score}
		for s in range(mi.mesh.get_surface_count()):
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var vr: Variant = arrays[Mesh.ARRAY_VERTEX]
			if vr == null:
				continue
			var verts: PackedVector3Array = vr
			var ir: Variant = arrays[Mesh.ARRAY_INDEX]
			var idx: PackedInt32Array = ir if ir != null else PackedInt32Array()
			var xf: Transform3D = mi.global_transform
			var stride: int = 1 if idx.size() > 0 else 0
			var n: int = (idx.size() / 3) if idx.size() > 0 else (verts.size() / 3)
			var band: float = edge_m / tile_r * 1.9   # centroid angular band
			var score_sum: float = 0.0
			var score_n: int = 0
			var min_vert_ang: float = INF
			var step_v: int = maxi(1, verts.size() / 128)
			for vi in range(0, verts.size(), step_v):
				var wv: Vector3 = xf * verts[vi]
				var dir_v: Vector3 = (wv - pc).normalized()
				min_vert_ang = minf(min_vert_ang, dir_v.angle_to(d))
				score_sum += absf(wv.distance_to(pc) - tile_r \
					- Gen.terrain_height(dir_v, seed_b))
				score_n += 1
			var score: float = (score_sum / float(maxi(1, score_n)))
			surf_data.append({"verts": verts, "idx": idx, "stride": stride, "n": n,
				"band": band, "score": score, "min_ang": min_vert_ang})
			if not xf_shown:
				xf_shown = true
				print("    XF f%d local-origin(%.1f,%.1f,%.1f) basis=(%.2f,%.2f,%.2f | %.2f,%.2f,%.2f | %.2f,%.2f,%.2f)"
					% [int(face), xf.origin.x, xf.origin.y, xf.origin.z,
						xf.basis.x.x, xf.basis.x.y, xf.basis.x.z,
						xf.basis.y.x, xf.basis.y.y, xf.basis.y.z,
						xf.basis.z.x, xf.basis.z.y, xf.basis.z.z])
				if not xf_shown:
					xf_shown = true
					print("    XF f%d local-origin(%.1f,%.1f,%.1f) basis=(%.2f,%.2f,%.2f | %.2f,%.2f,%.2f | %.2f,%.2f,%.2f)"
						% [int(face), xf.origin.x, xf.origin.y, xf.origin.z,
							xf.basis.x.x, xf.basis.x.y, xf.basis.x.z,
							xf.basis.y.x, xf.basis.y.y, xf.basis.y.z,
							xf.basis.z.x, xf.basis.z.y, xf.basis.z.z])
			surf_note += " s%d(v%d law-delta %.2f min-vert-ang %.4f)" \
				% [s, verts.size(), score, min_vert_ang]
			if score > 10.0:
				# THE CORRUPTION SLICE: the off-law surface prints its own
				# verts (done vs the analytic law at the same dirs) so the
				# drawn-vs-law divergence has a NAME, not just a mean.
				var worst_i: Array = []
				var kk := 0
				for vi in range(0, verts.size(), maxi(1, verts.size() / 4)):
					var wv2: Vector3 = xf * verts[vi]
					var d2: Vector3 = (wv2 - pc).normalized()
					var h2: float = wv2.distance_to(pc) - tile_r
					var law2: float = Gen.terrain_height(d2, seed_b)
					print("    offs-law f%d s%d v%d: dir(%.2f,%.2f,%.2f) drawn_h %.1f law %.1f delta %+.1f"
						% [int(face), s, vi, d2.x, d2.y, d2.z, h2, law2, h2 - law2])
					kk += 1
					if kk >= 4:
						break
		if surf_data.is_empty():
			continue
		# The LAND surface: lowest mean law-delta. A tie is broken by the
		# order (main is authored first -- array order is stable).
		var best_score: float = INF
		var land_s: int = -1
		for si in range(surf_data.size()):
			if float(surf_data[si]["score"]) < best_score:
				best_score = float(surf_data[si]["score"])
				land_s = si
		var sd: Dictionary = surf_data[land_s]
		var xf: Transform3D = mi.global_transform
		var verts2: PackedVector3Array = sd["verts"]
		var idx2: PackedInt32Array = sd["idx"]
		var stride2: int = int(sd["stride"])
		var n2: int = int(sd["n"])
		var band2: float = float(sd["band"])
		var face_count: int = 0
		for t in range(n2):
			var i0: int = idx2[t * 3] if stride2 == 1 else t * 3
			var i1: int = idx2[t * 3 + 1] if stride2 == 1 else t * 3 + 1
			var i2: int = idx2[t * 3 + 2] if stride2 == 1 else t * 3 + 2
			var p0: Vector3 = xf * verts2[i0]
			var p1: Vector3 = xf * verts2[i1]
			var p2: Vector3 = xf * verts2[i2]
			var ang: float = ((p0 + p1 + p2) / 3.0 - pc).normalized().angle_to(d)
			if ang <= band2 and ang < best_ang:
				best_ang = ang
				best_p = [p0, p1, p2]
				face_count += 1
		if face_count == 0:
			miss_note += surf_note
		print("  SURFROLE f%d:%s land=s%d" % [int(face), surf_note, land_s])
	if best_p.is_empty():
		print("  MISSDEBUG all:%s -- no tri inside %.6f rad" % [miss_note, edge_m / tile_r * 1.9])
		return NAN
	# RAY-PLANE: x = t*d from the PLANET CENTER, t ~ tile_r scale
	var a0: Vector3 = best_p[0]
	var pn: Vector3 = (best_p[1] - a0).cross(best_p[2] - a0)
	var denom: float = pn.dot(d)
	if absf(denom) < 1e-9:
		return NAN
	var t_hit: float = pn.dot(a0 - pc) / denom
	if t_hit <= 0.0:
		return NAN
	var x_hit: Vector3 = pc + d * t_hit
	# 2D bary of the hit point in the plane's own orthonormal basis
	var e1: Vector3 = (best_p[1] - a0).normalized()
	var e2: Vector3 = pn.cross(e1).normalized()
	var rel: Vector2 = Vector2((x_hit - a0).dot(e1), (x_hit - a0).dot(e2))
	var ab: Vector2 = Vector2((best_p[1] - a0).dot(e1), (best_p[1] - a0).dot(e2))
	var ac: Vector2 = Vector2((best_p[2] - a0).dot(e1), (best_p[2] - a0).dot(e2))
	var det: float = ab.x * ac.y - ab.y * ac.x
	if absf(det) < 1e-12:
		return NAN
	var w1: float = (rel.x * ac.y - rel.y * ac.x) / det
	var w2: float = (ab.x * rel.y - ab.y * rel.x) / det
	var w0: float = 1.0 - w1 - w2
	if w0 < -0.02 or w1 < -0.02 or w2 < -0.02:
		return NAN
	print("  TRIREAD corners h=%.2f/%.2f/%.2f from-planet-center (verts %.0f,%.0f,%.0f | %.0f,%.0f,%.0f | %.0f,%.0f,%.0f)"
		% [float((best_p[0] - pc).length() - tile_r), float((best_p[1] - pc).length() - tile_r), float((best_p[2] - pc).length() - tile_r),
			best_p[0].x, best_p[0].y, best_p[0].z, best_p[1].x, best_p[1].y, best_p[1].z, best_p[2].x, best_p[2].y, best_p[2].z])
	return t_hit - tile_r

func _ensure_patch(st, face: int, lvl: int) -> bool:
	## Reload the covering patch until it is IN-TREE at the target
	## level. Returns false when the composition never settles (the
	## audit then prints its own honest environment verdict).
	for attempt in range(4):
		var patched: bool = int(st._patch_lvl.get(face, -1)) == lvl
		var mi_p: MeshInstance3D = st._patches.get(face)
		if patched and mi_p != null and mi_p.is_inside_tree():
			return true
		st._load_patch(face, lvl)
		await process_frame
	var mi_f: MeshInstance3D = st._patches.get(face)
	print("ENSURE face=%d lvl=%d settled=%s" % [face, lvl, str(mi_f != null and mi_f.is_inside_tree() and int(st._patch_lvl.get(face, -1)) == lvl)])
	return mi_f != null and mi_f.is_inside_tree() and int(st._patch_lvl.get(face, -1)) == lvl

func _initialize() -> void:
	await process_frame
	var packed: PackedScene = load(GLOBE_SCENE)
	var globe = packed.instantiate()
	root.add_child(globe)
	for i in range(6):
		await process_frame
	var st = globe.get("streamer")
	if st == null:
		print("FAIL: no streamer on the boot")
		quit(1)
		return
	var R: float = float(globe.get("planet_radius"))
	var F = load("res://core/frame/math/icosahedral_faces.gd")
	var Gen = preload("res://scenes/worlds/terrain_gen.gd")
	var Sph = load("res://core/frame/math/spherical.gd")
	var scr = load("res://scenes/worlds/globe_world.gd")
	# THE COMPOSITION LAW (the race round's receipt): the probe FORCES
	# patch levels (lvl 7 cap / lvl 6 web) while the live streamer's own
	# LOD tick re-demands its own levels every frame and swaps/stashes a
	# patch BETWEEN _load_patch and the read -- the anchor then reads a
	# live set that no longer holds the covering face. The streamer's
	# _process ALSO drives the async appliers, so it must NOT be frozen
	# (the freeze hung the audit at the first big build: trace4). The
	# fix is per-read instead: _ensure_patch re-checks the covering
	# face's level AND tree attachment right before every read and
	# reloads on a race; a patch the audit never gets in-place is an
	# honest environment verdict, printed as such (still a FAIL).
	var seed_b: PackedByteArray = st.world_seed
	var tile_r: float = R + 0.52
	print("radius=%.0f seed_ok=%s" % [R, str(seed_b.size() > 0)])

	# The boot's own path; the HUD prints lat/lon in degrees, so the
	# owner's shots decode to: shot 3 lon -0.18 deg = 63 m (wolf float),
	# shot 4 lon -1.76 deg = 615 m (the apron ramp, ground 45.0).
	var legs: Array = [
		{"lat": 0.0, "lon": 0.0, "tag": "plaza-0m"},
		{"lat": 0.0, "lon": -0.0032, "tag": "hud3---63m"},
		{"lat": 0.0, "lon": -0.03, "tag": "hud4---600m"},
		{"lat": 0.0, "lon": -0.05, "tag": "apron-1km"},
		{"lat": 0.0, "lon": -0.1, "tag": "apron-out-2km"},
	]
	var frames := 0
	var plaza_face: int = F.face_for_direction(Sph.spherical_to_cartesian(0.0, 0.0, 0.0, 1.0))

	# THE OLD-TERRAIN ENUMERATION: the flat green base shell must not
	# dress the whole planet at terrain-arc scale.
	var shell := (root as Node).find_child("GlobeShell", true, false)
	if shell == null:
		print("ENUM: no GlobeShell node")
	else:
		for c in shell.get_children():
			if c is MeshInstance3D and c.mesh is SphereMesh:
				var sm: SphereMesh = c.mesh
				print("ENUM: base shell SphereMesh radius=%.2f segs=%d/%d visible=%s"
					% [sm.radius, sm.radial_segments, sm.rings, str(c.visible)])
				var sv = shell.find_child("ShellVisual", true, false)
				print("ENUM: ShellVisual visible=%s (the SHELL-VISUAL LAW: hidden at planet scale)" % (str(sv.visible) if sv != null else "ABSENT"))

	for lvl_pass in [[7, "lvl7-cap"], [6, "lvl6-web"]]:
		var lvl: int = int(lvl_pass[0])
		var pass_tag: String = str(lvl_pass[1])
		var edge_m: float = 1.0515 * R / pow(2.0, lvl)
		# THE SPAWN IS ON A FIVE-FACE ICOSAHEDRAL VERTEX (SPAWN_CENTER=(1,0,0)
		# is a canonical icosa vertex -- the MISSDEBUG receipt): no single
		# tile contains the EXACT vertex direction, and the continue-on-fail
		# anchor skip must never eat the legs. So the anchor stands ~100 m
		# off the vertex and the face comes from the STREAMER'S OWN mapper
		# (st.current_face after update) -- the walk law's own map.
		var zero: Vector3 = Sph.spherical_to_cartesian(
			float(scr.SPAWN_LAT_DEG), float(scr.SPAWN_LON_DEG) + 0.286, 0.0, 1.0)
		st.update(zero * R)
		await process_frame
		plaza_face = st.current_face
		if not await _ensure_patch(st, plaza_face, lvl):
			print("FAIL: ANCHOR %s: the covering face %d never settled in-tree at its level (composition)" % [pass_tag, plaza_face])
			_okay = false
			continue
		var walk0: float = st.walk_surface_h(zero)
		var mesh0: float = _mesh_at(st, F, tile_r, zero, edge_m, Gen, seed_b)
		if is_nan(mesh0):
			if await _ensure_patch(st, plaza_face, lvl):
				mesh0 = _mesh_at(st, F, tile_r, zero, edge_m, Gen, seed_b)
		if is_nan(mesh0):
			print("FAIL: ANCHOR %s: no land tile contained the near-vertex anchor" % pass_tag)
			_okay = false
			continue
		print("ANCHOR %s (edge %.1f m, face %d): walk %.2f mesh-read %.2f mesh-law %+.2f"
			% [pass_tag, edge_m, plaza_face, walk0, mesh0, mesh0 - walk0])
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
					_quit()
					return
			var face: int = st.current_face
			await _ensure_patch(st, face, lvl)
			var lvl_seen: int = int(st._patch_lvl.get(face, lvl))
			var walk: float = st.walk_surface_h(d)
			var terrain: float = Gen.terrain_height(d, seed_b)
			var mesh_h: float = _mesh_at(st, F, tile_r, d, edge_m, Gen, seed_b)
			var in_tile: bool = not is_nan(mesh_h)
			var delta: float = (((mesh_h - mesh0) - (walk - walk0)) if in_tile else NAN)
			print("LEG %s [%s]: face=%d lvl=%d | walk %.2f | law(terrain) %.2f | caps %.2f | draw-delta %+.2f %s"
				% [str(leg.tag), pass_tag, face, lvl_seen, walk, terrain, walk - terrain,
					delta, ("IN-TILE" if in_tile else "NO-LAND-TILE")])
			if in_tile:
				var law0: float = Gen.terrain_height(zero, seed_b)
				var law_delta: float = (terrain - law0) - (walk - walk0)
				if absf(law_delta) > 0.5:
					print("  (skirt note: walk-law differs from the raw field by %+.2f here)" % (walk - terrain))
				_check("LEG %s [%s]: draw-vs-law within the 6 m walk bound (delta %+.1f)"
					% [str(leg.tag), pass_tag, absf(delta)], absf(delta) < 6.0)

	_check("live set capped (<= 6 patches after the audit walk: %d)" % (st._patches as Dictionary).size(),
		(st._patches as Dictionary).size() <= 6)
	_quit()
