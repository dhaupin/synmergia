## Probe: THE MESH-SURFACE ENUMERATOR (the floating-world round, pass 2).
## godot --headless --path game --script res://tests/probe_mesh_surface_enum.gd
## pass 1 (probe_ground_law_audit) receipted the draw-vs-law deltas:
##   lvl6 (the web's draw): -45.9 m @600 m, -62.7 m @1 km
##   lvl7 (the cap's draw): -23.0 m @600 m
## but its containing-tile read pulled triangles from get_faces()'s MIXED
## soup (main + skirt + water in one array), so the pass-2 enumerator
## splits the surfaces apart and, for each deployed radius sample,
## prints per-surface: tri span, the containing tri, its three corners'
## LAW read (terrain_height at the corner dir) vs the corner's actual
## radial length. The split answers ONE question: does the BUILDER put
## the law into the land verts (=> my pass-1 read sampled skirt/water),
## or does the LAND surface itself carry heights that disagree with the
## law (=> a real builder-vs-walk divergence, the once-and-for-all bug)?
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"

func _bary(p, d: Vector3) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.append(-2.0); out.append(-2.0); out.append(-2.0)
	var q: Array = []
	for i in range(3):
		var vi: Vector3 = p[i]
		q.append(vi - (vi.dot(d)) * d)
	var r0: Vector3 = q[0]
	var r1: Vector3 = q[1]
	var r2: Vector3 = q[2]
	var n: Vector3 = (r1 - r0).cross(r2 - r0)
	var denom: float = n.dot(n)
	if absf(denom) < 1e-9:
		return out
	out[0] = n.dot(r1.cross(r2)) / denom
	out[1] = n.dot(r2.cross(r0)) / denom
	out[2] = n.dot(r0.cross(r1)) / denom
	return out

func _initialize() -> void:
	# This probe reads the icosa STREAMER internals; pin the renderer
	# so the default (clipmap) does not change what it inspects.
	ProjectSettings.set_setting("synmergia/world/terrain_render", "streamer")
	await process_frame
	var packed: PackedScene = load(GLOBE_SCENE)
	var globe = packed.instantiate()
	root.add_child(globe)
	for i in range(6):
		await process_frame
	var st = globe.get("streamer")
	var R: float = float(globe.get("planet_radius"))
	var F = load("res://core/frame/math/icosahedral_faces.gd")
	var Gen = preload("res://scenes/worlds/terrain_gen.gd")
	var Sph = load("res://core/frame/math/spherical.gd")
	var scr = load("res://scenes/worlds/globe_world.gd")
	var seed_b: PackedByteArray = st.world_seed
	var tile_r: float = R + 0.52
	var samples: Array = [
		{"lon": 0.0, "tag": "plaza-0m"},
		{"lon": -0.03, "tag": "hud4---600m"},
		{"lon": -0.05, "tag": "apron-1km"},
	]
	# the boot streams the spawn face on its own law (base level)
	await process_frame
	for svar in samples:
		var d: Vector3 = Sph.spherical_to_cartesian(
			float(scr.SPAWN_LAT_DEG), float(scr.SPAWN_LON_DEG) + rad_to_deg(float(svar.lon)), 0.0, 1.0).normalized()
		st.update(d * R)
		for i in range(4):
			await process_frame
		var face: int = st.current_face
		var mi: MeshInstance3D = (st._patches as Dictionary).get(face)
		if mi == null or mi.mesh == null:
			print("SAMPLE %s: face=%d NOT STREAMED" % [str(svar.tag), face])
			continue
		var center: Vector3 = F.face_center(int(face)) * tile_r
		var walk: float = st.walk_surface_h(d)
		var law: float = Gen.terrain_height(d, seed_b)
		print("SAMPLE %s: face=%d lvl=%d surf=%d | walk %.2f law %.2f"
			% [str(svar.tag), face, int(st._patch_lvl.get(face, -1)), mi.mesh.get_surface_count(), walk, law])
		for s in range(mi.mesh.get_surface_count()):
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var verts_raw: Variant = arrays[Mesh.ARRAY_VERTEX]
			var idx_raw: Variant = arrays[Mesh.ARRAY_INDEX]
			if verts_raw == null:
				continue
			var verts: PackedVector3Array = verts_raw
			var idx: PackedInt32Array = idx_raw if idx_raw != null else PackedInt32Array()
			var hmin: float = INF
			var hmax: float = -INF
			for v in verts:
				var hv: float = (v + center).dot(d) - tile_r
				hmin = minf(hmin, hv)
				hmax = maxf(hmax, hv)
			# the containing tri IN THIS SURFACE (slow scan, patches only)
			var found: bool = false
			var mv: float = NAN
			var t_of: int = 0
			var tri0: Array = []
			# surface-local tri soup: walk the surface's own arrays
			var sv: PackedVector3Array = verts
			var si: PackedInt32Array = idx
			var ntri: int = (si.size() / 3) if si.size() > 0 else (sv.size() / 3)
			for t in range(ntri):
				var p0: Vector3 = sv[si[t * 3] if si.size() > 0 else t * 3] + center
				var p1: Vector3 = sv[si[t * 3 + 1] if si.size() > 0 else t * 3 + 1] + center
				var p2: Vector3 = sv[si[t * 3 + 2] if si.size() > 0 else t * 3 + 2] + center
				var w: PackedFloat32Array = _bary([p0, p1, p2], d)
				if w[0] >= -1e-6 and w[1] >= -1e-6 and w[2] >= -1e-6 \
						and w[0] <= 1.0 + 1e-6 and w[1] <= 1.0 + 1e-6 and w[2] <= 1.0 + 1e-6:
					found = true
					t_of = t
					mv = w[0] * p0.dot(d) + w[1] * p1.dot(d) + w[2] * p2.dot(d) - tile_r
					tri0 = [p0, p1, p2]
					break
			var det: String = ("read %+.2f (tri %d/%d)" % [mv, t_of, ntri]) if found else "no containing tri"
			print("  SURF %d: tris=%d radial %.1f..%.1f | %s" % [s, ntri, hmin, hmax, det])
			if found and s == 0:
				var cd: String = ""
				for i in range(3):
					var ci: Vector3 = tri0[i]
					var dir_c: Vector3 = ci.normalized()
					var law_c: float = Gen.terrain_height(dir_c, seed_b)
					var rad_c: float = ci.length() - tile_r
					cd += " [law %.2f|vert %.2f|d %.2f]" % [law_c, rad_c, rad_c - law_c]
				print("    corners:" + cd)
			if found and s != 0:
				var cd2: String = ""
				for i in range(3):
					var ci2: Vector3 = tri0[i]
					cd2 += " [rad %.2f]" % (ci2.length() - tile_r)
				print("    corners:" + cd2)
	quit(0)
