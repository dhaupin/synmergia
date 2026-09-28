## Tests for the spherical math primitive (prd-spherical-mvp.md S1)
## Loads spherical.gd by PATH, not class_name: fresh class_names are
## invisible to script mode until an editor import pass (GuardData lesson).
extends SceneTree

func _init() -> void:
	var ok := true
	if not _test_haversine_known_answers():
		push_error("FAIL: haversine_known_answers")
		ok = false
	if not _test_haversine_symmetry_and_zero():
		push_error("FAIL: haversine_symmetry_and_zero")
		ok = false
	if not _test_haversine_antipode():
		push_error("FAIL: haversine_antipode")
		ok = false
	if not _test_bearing():
		push_error("FAIL: bearing")
		ok = false
	if not _test_great_circle_intermediate():
		push_error("FAIL: great_circle_intermediate")
		ok = false
	if not _test_coordinate_roundtrip():
		push_error("FAIL: coordinate_roundtrip")
		ok = false
	if not _test_icosahedral_convention_match():
		push_error("FAIL: icosahedral_convention_match")
		ok = false
	quit(0 if ok else 1)

func _sph() -> GDScript:
	return load("res://core/frame/math/spherical.gd")

func _test_haversine_known_answers() -> bool:
	var Sph = _sph()
	# One degree of arc on Earth's mean radius sphere: 2*pi*R/360.
	var one_deg_earth: float = 2.0 * PI * Sph.EARTH_RADIUS_METERS / 360.0
	var got: float = Sph.haversine(0.0, 0.0, 0.0, 1.0, Sph.EARTH_RADIUS_METERS)
	assert(abs(got - one_deg_earth) < 100.0)
	# One degree on the 20 km v1 planet: ~349.07 m.
	var one_deg_planet: float = 2.0 * PI * Sph.PLANET_RADIUS_METERS / 360.0
	var got_planet: float = Sph.haversine(0.0, 0.0, 0.0, 1.0)
	assert(abs(got_planet - one_deg_planet) < 0.1)
	return true

func _test_haversine_symmetry_and_zero() -> bool:
	var Sph = _sph()
	var ab: float = Sph.haversine(10.0, 20.0, 30.0, 40.0)
	var ba: float = Sph.haversine(30.0, 40.0, 10.0, 20.0)
	assert(abs(ab - ba) < 0.0001)
	assert(Sph.haversine(5.0, 5.0, 5.0, 5.0) < 0.0001)
	return true

func _test_haversine_antipode() -> bool:
	var Sph = _sph()
	# Antipodal half-circumference on the v1 planet.
	var half: float = PI * Sph.PLANET_RADIUS_METERS
	var d1: float = Sph.haversine(0.0, 0.0, 0.0, 180.0)
	assert(abs(d1 - half) < 1.0)
	var d2: float = Sph.haversine(89.0, 0.0, -89.0, 180.0)
	assert(abs(d2 - half) < 1.0)
	return true

func _test_bearing() -> bool:
	var Sph = _sph()
	# Due north and due east along meridian/equator.
	assert(abs(Sph.geodesic_bearing(0.0, 0.0, 89.0, 0.0)) < 0.001)
	assert(abs(Sph.geodesic_bearing(0.0, 0.0, 0.0, 90.0) - 90.0) < 0.001)
	# Westward bearing normalizes into [0, 360): 270, not -90.
	assert(abs(Sph.geodesic_bearing(0.0, 0.0, 0.0, -90.0) - 270.0) < 0.001)
	# Eastward across the dateline stays 90.
	assert(abs(Sph.geodesic_bearing(0.0, 179.0, 0.0, -179.0) - 90.0) < 0.001)
	# Southward is 180.
	assert(abs(Sph.geodesic_bearing(10.0, 0.0, -10.0, 0.0) - 180.0) < 0.001)
	return true

func _test_great_circle_intermediate() -> bool:
	var Sph = _sph()
	# Midpoint of the equator arc (0,0)->(0,90) is (0,45).
	var m1: Vector2 = Sph.great_circle_intermediate(0.0, 0.0, 0.0, 90.0, 0.5)
	assert(abs(m1.x) < 0.001 and abs(m1.y - 45.0) < 0.001)
	# Midpoint of the meridian arc (0,0)->(90,0) is (45,0).
	var m2: Vector2 = Sph.great_circle_intermediate(0.0, 0.0, 90.0, 0.0, 0.5)
	assert(abs(m2.x - 45.0) < 0.001 and abs(m2.y) < 0.001)
	# Endpoints reproduce.
	var e0: Vector2 = Sph.great_circle_intermediate(10.0, 20.0, 30.0, 40.0, 0.0)
	assert(abs(e0.x - 10.0) < 0.001 and abs(e0.y - 20.0) < 0.001)
	var e1: Vector2 = Sph.great_circle_intermediate(10.0, 20.0, 30.0, 40.0, 1.0)
	assert(abs(e1.x - 30.0) < 0.001 and abs(e1.y - 40.0) < 0.001)
	# Coincident points do not divide by zero.
	var same: Vector2 = Sph.great_circle_intermediate(12.0, 34.0, 12.0, 34.0, 0.5)
	assert(abs(same.x - 12.0) < 0.001 and abs(same.y - 34.0) < 0.001)
	return true

func _test_coordinate_roundtrip() -> bool:
	var Sph = _sph()
	var probes := [
		Vector2(0.0, 0.0), Vector2(45.0, 90.0), Vector2(-60.0, 120.0),
		Vector2(90.0, 0.0), Vector2(-90.0, 0.0), Vector2(10.0, -179.5),
		Vector2(10.0, 180.0),
	]
	for p in probes:
		var cart: Vector3 = Sph.spherical_to_cartesian(p.x, p.y)
		# On-surface magnitude equals the radius.
		assert(abs(cart.length() - Sph.PLANET_RADIUS_METERS) < 0.001)
		var back: Vector2 = Sph.cartesian_to_spherical(cart)
		assert(abs(back.x - p.x) < 0.001)
		# Lon wraps: 180 == -180.
		var dlon: float = abs(back.y - p.y)
		if dlon > 180.0:
			dlon = 360.0 - dlon
		assert(dlon < 0.001)
	return true

func _test_icosahedral_convention_match() -> bool:
	# Spherical cartesian must agree with Icosahedral.project's
	# lat/lon convention, or S3's position->cell mapping breaks.
	var Sph = _sph()
	var Ico = load("res://core/frame/math/icosahedral.gd").new()
	var probes := [Vector2(0.0, 0.0), Vector2(30.0, 60.0), Vector2(-45.0, -120.0)]
	for p in probes:
		var cart: Vector3 = Sph.spherical_to_cartesian(p.x, p.y)
		var ico_latlon: Vector2 = Ico.project(cart)
		assert(abs(ico_latlon.x - p.x) < 0.01)
		var dlon: float = abs(ico_latlon.y - p.y)
		if dlon > 180.0:
			dlon = 360.0 - dlon
		assert(dlon < 0.01)
	return true
