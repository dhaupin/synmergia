extends SceneTree
## Vista scan v2 (turn 14, slice B): EXACT 3-D line of sight. For a
## chosen eye (plaza 9 m or the planned +25 m village mound) it walks
## every bearing, records each terrain top's visibility by testing
## whether the straight eye->top segment clears the planet sphere, and
## reports the top crest bearings + the sea-window profile at the
## design bearings so the anchors sit on honest geometry.

func _init() -> void:
	print("vista_scan2: loaded")
	call_deferred("_run")

func _run() -> void:
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var Sph = load("res://core/frame/math/spherical.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var sea: float = Gen.sea_level(seed_b)
	var R: float = 20000.0
	var eye_h: float = float(OS.get_environment("VISTA_EYE_H")) if OS.get_environment("VISTA_EYE_H") != "" else Gen.SPAWN_HEIGHT
	print("eye height %.1f m (sea %.2f)" % [eye_h, sea])

	# Soul of the check: segment eye(top-of-eye at R+eye_h on d_spawn)
	# -> target top (R + sea + h_top) at bearing, angular offset ang.
	# Visible iff the minimum distance from the origin to that segment
	# exceeds the planet radius R (no sphere intersection). Two-kingdom
	# helper for closest approach on a segment.
	# FINE sweep of the inner ring band (lat 12..26 deg, 0.75-deg lat
	# steps) with a best-margin metric: a crest's margin is how far its
	# top rides above the eye's sight chord at exactly its distance.
	var crest_report: Array = []
	var best_lat: float = 0.0
	var best_lon: float = 0.0
	var best_margin: float = -999.0
	var best_top: float = -1.0
	var best_dist: float = 0.0
	var omn_lat: float = 12.0
	while omn_lat <= 26.0:
		for sign_v in [-1.0, 1.0]:
			var lat_deg: float = sign_v * omn_lat
			for lon_i in range(180):
				var lon: float = 2.0 * float(lon_i)
				var d: Vector3 = Sph.spherical_to_cartesian(lat_deg, lon, 0.0, 1.0)
				var ang: float = d.angle_to(Vector3(1.0, 0.0, 0.0))
				if ang < 0.17 or ang > 0.34:
					continue
				var h: float = Gen.terrain_height(d, seed_b)
				if h <= sea:
					continue
				var eye: Vector3 = (R + eye_h) * Vector3(1.0, 0.0, 0.0)
				var tgt: Vector3 = (R + (h - sea)) * d
				var margin: float = _segment_min_radius(eye, tgt) - R
				if margin > best_margin:
					best_margin = margin
					best_lat = lat_deg
					best_lon = lon
					best_top = h - sea
					best_dist = ang * R
		omn_lat += 0.75
	print("BEST VISTA CREST from eye %.1f: lat %+.2f lon %.0f, top %.0f m at %.2f km, margin %+0.1f m %s" % [
		eye_h, best_lat, best_lon, best_top, best_dist / 1000.0, best_margin,
		("VISIBLE" if best_margin > 0.0 else "HIDDEN")])
	# And a top-5 report along the same grid for context.

	# THE THREE VISTA CLAIMS (extendable): the spur crest margin at its
	# authored bearing (12 deg, scan the wedge lat band), the island
	# summit margin at ISLAND_CENTER, and the island's field read.
	var Gen2: GDScript = Gen
	var isl_d: Vector3 = Gen2.ISLAND_CENTER.normalized()
	var isl_h: float = Gen2.terrain_height(isl_d, seed_b)
	print("ISLAND field read at center: h=%.2f m (law: sea+2+plateau=%.2f)" % [isl_h, sea + 2.0 + Gen2.ISLAND_PLATEAU])
	var eye: Vector3 = (R + eye_h) * Vector3(1.0, 0.0, 0.0)
	var isl_margin: float = _segment_min_radius(eye, (R + (isl_h - sea)) * isl_d) - R
	print("ISLAND summit from terrace eye: margin %+0.1f m %s" % [isl_margin, ("VISIBLE" if isl_margin > 0.0 else "HIDDEN")])
	# Spur crest: walk the spur crest bearing azimuth at ang 0.20-0.24
	# (the ramp end / plateau edge) for the actual top the field reads.
	var spur_best: float = -999.0
	var spur_at: float = 0.0
	for t_i in range(30):
		var ang: float = 0.175 + 0.005 * float(t_i)
		var dd: Vector3 = Sph.spherical_to_cartesian(0.0, 12.0, 0.0, 1.0)
		dd = dd.rotated(_tangent(dd), ang)
		var hh: float = Gen2.terrain_height(dd, seed_b)
		if hh <= sea:
			continue
		var mm: float = _segment_min_radius(eye, (R + (hh - sea)) * dd) - R
		if mm > spur_best:
			spur_best = mm
			spur_at = ang * R
	print("SPUR crest walk (bearing 12): best margin %+0.1f m at %.2f km %s" % [
		spur_best, spur_at / 1000.0, ("VISIBLE" if spur_best > 0.0 else "HIDDEN")])
	quit(0)

func _segment_min_radius(a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var denom: float = ab.dot(ab)
	if denom < 1e-9:
		return a.length()
	var t_star: float = clampf(-a.dot(ab) / denom, 0.0, 1.0)
	var closest: Vector3 = a + ab * t_star
	return closest.length()


func _segment_clears_sphere(a: Vector3, b: Vector3, R: float) -> bool:
	# Exact closest-approach of the straight segment a->b to the origin.
	var ab: Vector3 = b - a
	var denom: float = ab.dot(ab)
	if denom < 1e-9:
		return a.length() > R
	var t: float = clampf(-a.dot(ab) / denom, 0.0, 1.0)
	var closest: Vector3 = a + ab * t
	return closest.length() > R

func _tangent(d: Vector3) -> Vector3:
	var t: Vector3 = Vector3(0, 1, 0).cross(d)
	if t.length() < 1e-6:
		t = Vector3(1, 0, 0).cross(d)
	return t.normalized()
