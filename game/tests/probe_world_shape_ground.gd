## Probe: the WORLD SHAPE pins (the 2026-10-13 "all four" pass:
## budget-sized continent, oceanify, real mountains, honest ceiling).
## Headless script mode:
##   godot --headless --path game --script res://tests/probe_world_shape_ground.gd
##
## The PRD (labs/prd-world.md) carries two land masses for v1: the
## starter continent (150 km2 BUDGET, "not a promise") plus the
## offshore ferry island; everything else is ocean -- and the terrain
## law must read as real terrain (inland mountains, snowline bands).
## Pins:
##   W1. The world's land is continent-scale: total land area inside
##       a generous budget band (not planet-wide, not a green sheet).
##   W2. The homeland plateau is SOLID land out to the plateau band
##       (the boot's streamed neighborhood never opens on the sea).
##   W3. Mountains EXIST inland: enough peaks over sea+50 m to matter,
##       and no sample breaches the TERRAIN_MAX ceiling.
##   W4. The spawn plaza is exactly SPAWN_HEIGHT; the shore apron
##       outside it stays dry (the boot never lands wet).
##   W5. The island rides the PRD shape: volcanic top at sea+22 m,
##       the moat channel below the sea line (the ferry's crossing).
##   W6. Determinism: the same seed produces the same law answers.
extends SceneTree

var _fails: int = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		_fails += 1
		printerr("FAIL: " + label)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var sea: float = Gen.sea_level(seed_b)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261013
	var spawn: Vector3 = Gen.SPAWN_CENTER
	var N := 20000
	var plateau_ang: float = Gen.HOMELAND_ANGULAR_REACH * 0.6
	var land := 0
	var peaks50 := 0
	var mirages := 0  # samples above the ceiling (must never exist)
	var plateau_cap_dirs := 0
	var plateau_land_dirs := 0
	# W4's apron sweep: eight fixed dirs walking the shore band between
	# the plaza edge and the apron's outer reach (0.05..0.085 rad).
	var apron_dry := true
	var ray_hint: Vector3 = Vector3(0, 1, 0).cross(spawn).normalized()
	for k in range(8):
		var ang_apron: float = 0.05 + 0.005 * float(k)
		var apron_dir: Vector3 = spawn.rotated(ray_hint, ang_apron)
		if Gen.terrain_height(apron_dir, seed_b) < sea:
			apron_dry = false
	for i in range(N):
		var d: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var h: float = Gen.terrain_height(d, seed_b)
		if h > Gen.TERRAIN_MAX + 1.0:
			mirages += 1
		var ang_spawn: float = d.angle_to(spawn)
		if h > sea + 0.05:
			land += 1
			if h - sea > 50.0:
				peaks50 += 1
		if ang_spawn < plateau_ang:
			plateau_cap_dirs += 1
			if h > sea:
				plateau_land_dirs += 1
			elif d.angle_to(Gen.ISLAND_CENTER.normalized()) > Gen.ISLAND_ANGULAR_REACH \
					and d.angle_to(Gen.ISLAND_CENTER.normalized()) < Gen.ISLAND_MOAT_OUTER:
				# THE AUTHORED STRAIT (turn 14, the owner's starter-vista
				# proto): the ferry island moved INTO the homeland's sea
				# front, so the moat law deliberately cuts the crossing
				# between the village harbor and the island INSIDE the
				# plateau cap. The exemption reads the moat constants
				# exactly — only the authored annulus is allowed to read
				# sea; any other open water inside the plateau is still
				# a W2 break (the law's intent, unchanged).
				plateau_land_dirs += 1


	# W1: continent-scale land inside a generous budget band. The PRD's
	# 150 km2 is a budget, not a promise; the band catches both the
	# under-culled green sheet AND the planet-wide land spill.
	var area_km2: float = float(land) / float(N) * 4.0 * PI * 400.0
	_check(area_km2 > 100.0 and area_km2 < 380.0,
		"world land is continent-scale (%.0f km2 inside 100..380 band; W1)" % area_km2)
	# W2: the homeland plateau never opens on the sea.
	_check(plateau_land_dirs == plateau_cap_dirs,
		"homeland plateau is solid land (%d/%d dirs; W2)" % [plateau_land_dirs, plateau_cap_dirs])
	# W3: mountains exist (inland, above the hill band) and respect
	# the ceiling.
	_check(peaks50 >= 8, "inland mountains exist (%d peaks > sea+50 m; W3)" % peaks50)
	_check(mirages == 0, "no sample breaches the terrain ceiling (W3)")
	# W4: the plaza is exactly the boot height and the shore apron
	# just outside the plaza is dry.
	_check(absf(Gen.terrain_height(spawn, seed_b) - Gen.SPAWN_HEIGHT) < 0.01,
		"spawn plaza height exact (W4)")
	_check(apron_dry, "shore apron outside the plaza is dry (W4)")
	# W5: the ferry island = sea+22 top, and the moat channel is below
	# the sea line (sample INSIDE the moat band 0.012..0.03 rad).
	var isl_c: Vector3 = Gen.ISLAND_CENTER
	var isl_top: float = Gen.terrain_height(isl_c, seed_b)
	_check(absf(isl_top - (sea + 2.0 + Gen.ISLAND_PLATEAU)) < 1.0,
		"island top rides the volcanic plateau law (sea+%.1f m; W5)" % (isl_top - sea))
	var moat_dir: Vector3 = isl_c.rotated(
		Vector3(0, 1, 0).cross(isl_c).normalized(), Gen.ISLAND_ANGULAR_REACH + 0.008)
	var moat_h: float = Gen.terrain_height(moat_dir, seed_b)
	_check(moat_h < sea - 2.0, "moat channel cuts below the sea line (ferry owns the crossing; W5)")
	# W6: determinism -- 300 shared dirs answer the same value twice.
	var det_ok := true
	for i in range(300):
		var d2: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		if absf(Gen.terrain_height(d2, seed_b) - Gen.terrain_height(d2, seed_b)) > 0.0:
			det_ok = false
			break
	_check(det_ok, "the law is deterministic on a shared seed (W6)")

	print("WORLD SHAPE probe: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
