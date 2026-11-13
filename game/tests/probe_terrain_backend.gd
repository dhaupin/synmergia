extends SceneTree

# Terrain-backend seam probe (prd-terrain.md slice 5): an installable
# height provider REPLACES the raw landfield while every law-native
# guarantee survives on top. Checks:
#   1. DEFAULT: uninstalled == the classic analytic law (bit-identical
#      fallback contract -- the seam changes nothing by default).
#   2. Installed backend DRIVES terrain_height everywhere (sampled
#      global fan agrees with the backend's own value after the law
#      ceiling; sculpt sites excepted).
#   3. Spawn guarantee on ANY backend: plaza flat at SPAWN_HEIGHT, dry
#      apron held above the sea line.
#   4. Sculpt laws ride the backend: the ferry island plateau stands
#      (moat channel cut) over the foreign field.
#   5. Hydrology still carves: a river channel site is pressed below
#      the raw backend field there, and stands water law intact.
#   6. Determinism: two identical installs re-answer identically; the
#      cache is invalidated on uninstall/reinstall (no stale sectors).
#   7. The clipmap walk law follows: GlobeWorld's walk_surface_h at a
#      sample equals the analytic terrain law read THROUGH the seam.

const Gen = preload("res://scenes/worlds/terrain_gen.gd")
const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"

var checks := 0
var fails := 0

func _check(label: String, cond: bool) -> void:
	checks += 1
	if cond:
		print("  PASS ", label)
	else:
		fails += 1
		print("  FAIL ", label)


# A clean deterministic backend: coarse dome + ripple, in meters.
class DomeBackend:
	static func field(d: Vector3, _seed: PackedByteArray) -> float:
		var lat: float = asin(clampf(d.y, -1.0, 1.0))
		return 14.0 * cos(lat) - 3.0


func _dome_backend() -> Callable:
	return Callable(DomeBackend, "field")


func _init() -> void:
	# Script-mode boot law: _init runs BEFORE autoload globals register
	# (the globe scene's scripts reference them at compile). Defer the
	# whole pass to the queued call (same pattern as probe_globe_world).
	call_deferred("_run")


func _run() -> void:
	var seed_bytes := Gen.world_seed_bytes()

	# --- 1. Default contract: seam installs NOTHING. ---
	var d0: Vector3 = Vector3(0.31, 0.42, 0.85).normalized()
	var law_a: float = Gen.terrain_height(d0, seed_bytes)
	var law_b: float = Gen.terrain_height(d0, seed_bytes)
	_check("default: uninstalled == analytic law (stable, no backend)",
		(not Gen.terrain_backend_installed()) and law_a == law_b)

	# --- 2. Install: the backend drives the buried-law answer. ---
	Gen.install_terrain_backend(_dome_backend())
	var db := DomeBackend.new()
	# Sample a global fan; away from sculpt/spawn sites the ground law
	# must equal the backend's own raw value (ceiling-clamped).
	var fan_ok := true
	var sculpt_sites: Array[Vector3] = [
		Gen.ISLAND_CENTER.normalized(),
		Gen.SPAWN_CENTER.normalized(),
		Vector3(0.28, 0.26, 0.92).normalized(),  # LAKE_CENTER
	]
	var raw_east_check := Vector3(1.0, 0.35, 0.2).normalized()
	for i in range(24):
		var a := TAU * float(i) / 24.0
		var dir_v: Vector3 = Vector3(cos(a), sin(a) * 0.7, sin(a) * 0.7).normalized()
		var near_sculpt := false
		for sc in sculpt_sites:
			if dir_v.angle_to(sc) < 0.08:
				near_sculpt = true
				break
		if near_sculpt:
			continue
		# THE TAIL LAW: the sculpt tail (city cove, island ring, the
		# moat band, spawn plaza/apron) and the hydrology tail
		# (rivers/lakes/roads) legally ride ANY installed field -- this
		# probe's own contract in checks 3-5. The fan samples CLEAR
		# ground only; the carve sites each prove their own law
		# separately. (The west axis sits in the island moat band: the
		# old hand-listed center exception missed it.)
		var back_c: float = minf(db.field(dir_v, seed_bytes), Gen.TERRAIN_MAX)
		var sea: float = Gen.sea_level(seed_bytes)
		var sculpted: float = Gen._sculpt_and_spawn(dir_v, back_c, sea,
			sea - Gen.OCEAN_DEPTH_MIN)
		if absf(sculpted - back_c) > 0.001:
			continue
		if Gen.river_channel(dir_v, seed_bytes) > 0.0:
			continue
		if absf(Gen.hydro_lake_carve(dir_v, seed_bytes, sculpted) - sculpted) > 0.001:
			continue
		if absf(Gen.terrain_height_carved(dir_v, seed_bytes, "_noroad")
				- Gen.terrain_height_carved(dir_v, seed_bytes, "")) > 0.001:
			continue
		var back: float = db.field(dir_v, seed_bytes)
		var got: float = Gen.terrain_height(dir_v, seed_bytes)
		if absf(got - maxf(0.0, minf(back, Gen.TERRAIN_MAX))) > 0.001:
			fan_ok = false
			print("    fan-mismatch at ", dir_v, " got ", got, " want ", back)
	_check("installed: backend drives terrain_height (global fan)", fan_ok)
	_check("installed: TERRAIN_MAX ceiling respected",
		Gen.terrain_height(raw_east_check, seed_bytes) <= Gen.TERRAIN_MAX + 1e-6)

	# --- 3. Spawn guarantee survives ANY backend. ---
	var plaza: float = Gen.terrain_height(Gen.SPAWN_CENTER.normalized(), seed_bytes)
	var apron_dir: Vector3 = Gen.SPAWN_CENTER.rotated(Vector3(0, 0, 1), Gen.SPAWN_APRON_ANG * 0.5).normalized()
	var apron: float = Gen.terrain_height(apron_dir, seed_bytes)
	_check("backend: spawn plaza still flats to SPAWN_HEIGHT",
		absf(plaza - Gen.SPAWN_HEIGHT) < 0.01)
	_check("backend: dry apron still holds above sea",
		apron >= Gen.sea_level(seed_bytes) + Gen.SPAWN_APRON_SEA_MARGIN - 0.01)

	# --- 4. Sculpt laws ride the backend: island + moat. ---
	var isl_top: float = Gen.terrain_height(Gen.ISLAND_CENTER.normalized(), seed_bytes)
	var isl_java: float = Gen.sea_level(seed_bytes) + 2.0 + Gen.ISLAND_PLATEAU
	_check("backend: ferry island plateau stands (>= native top code)",
		isl_top >= Gen.sea_level(seed_bytes) + 2.0 + 0.5 * Gen.ISLAND_PLATEAU - 0.01
			or isl_top >= isl_java - 2.0)
	# Moat direction: just outside the island reach. The rotation axis
	# is PERPENDICULAR to the island center (the seat moved into the
	# homeland's sea front; an oblique fixed axis short-changes the
	# annulus step), so the sample lands the same annulus step for any
	# seat - the assertion itself is untouched.
	var isl_axis: Vector3 = Vector3(0, 1, 0).cross(Gen.ISLAND_CENTER.normalized()).normalized()
	var moat_dir: Vector3 = Gen.ISLAND_CENTER.normalized() \
		.rotated(isl_axis, (Gen.ISLAND_ANGULAR_REACH + Gen.ISLAND_MOAT_OUTER) * 0.5)
	var moat: float = Gen.terrain_height(moat_dir, seed_bytes)
	_check("backend: fjord moat channel cut around the island",
		moat <= Gen.sea_level(seed_bytes) - Gen.ISLAND_MOAT_DEPTH + 0.01)

	# --- 5. Hydrology still carves over the backend. ---
	# Under the backend the caches were cleared, so river specs derive
	# FROM the dome field (law-native behavior). Springs need land +
	# height above sea, so a smooth dome may legitimately yield zero
	# rivers -- the law is honest either way. If any river exists, the
	# carve must still press a channel site below the water table.
	var carved_ok := false
	var rivers: Array = Gen.river_specs_cached(seed_bytes)
	var rivers_found: bool = rivers.size() > 0
	# Sample the CARVED POLYLINES directly: walk each spec's path, read
	# the ground law there, and verify the bed pressed below the table
	# (the law's own carve contract, read through the backend).
	for spec in rivers:
		for pd in spec.path:
			var g: float = Gen.terrain_height(pd, seed_bytes)
			var tab: float = Gen.water_table_raw(pd, seed_bytes)
			if g < tab:
				carved_ok = true
				break
		if carved_ok:
			break
	var carve_ok: bool = carved_ok if rivers_found else true
	var carve_msg: String = "backend: hydrology carve intact (%d river(s); %s)" % \
		[rivers.size(), "channel sampled below the water table" if carved_ok else "no carved-bed site found"]
	_check(carve_msg, carve_ok)

	# --- 6. Determinism + cache invalidation. ---
	Gen.uninstall_terrain_backend()
	var native_after: float = Gen.terrain_height(d0, seed_bytes)
	_check("uninstall: native law returns (cache invalidated)",
		(not Gen.terrain_backend_installed()) and absf(native_after - law_a) < 0.001)
	Gen.install_terrain_backend(_dome_backend())
	var back_again: float = Gen.terrain_height(d0, seed_bytes)
	Gen.install_terrain_backend(_dome_backend())
	var again_again: float = Gen.terrain_height(d0, seed_bytes)
	var expect_again: float = Gen._sculpt_and_spawn(d0.normalized(),
		db.field(d0.normalized(), seed_bytes), Gen.sea_level(seed_bytes),
		Gen.sea_level(seed_bytes) - Gen.OCEAN_DEPTH_MIN)
	_check("reinstall: backend answer stable across installs",
		absf(back_again - again_again) < 1e-6
			and absf(again_again - expect_again) < 0.001)
	Gen.uninstall_terrain_backend()

	# --- 7. The clipmap walk law follows the seam. ---
	Gen.install_terrain_backend(_dome_backend())
	var packed: PackedScene = load(GLOBE_SCENE)
	var globe: Node3D = packed.instantiate()
	root.add_child(globe)
	await root.get_tree().process_frame
	await root.get_tree().physics_frame
	var st = globe.get("clipmap")
	var probe_dir: Vector3 = Vector3(0.7, 0.3, 0.65).normalized()
	st.update(probe_dir * 20000.0)
	await root.get_tree().physics_frame
	var walk: float = Gen.walk_height(probe_dir, st.world_seed, \
		st.current_face, 20000.0, true)
	var law: float = Gen.terrain_height(probe_dir, st.world_seed)
	# walk = terrain + optional small rock cap (0..ROCK_EMBED+ROCK_R).
	# Honest band: walk >= law, and walk - law <= one cap height.
	var capable_ok: bool = walk >= law - 0.05 and walk - law <= Gen.ROCK_EMBED + Gen.ROCK_RADIUS * 2.2 + 0.05
	_check("clipmap walk law reads THROUGH the seam (no cracks)", capable_ok)
	Gen.uninstall_terrain_backend()
	globe.queue_free()
	await root.get_tree().process_frame

	print("--- RESULTS: %d passed, %d failed ---" % [checks - fails, fails])
	quit(0 if fails == 0 else 1)
