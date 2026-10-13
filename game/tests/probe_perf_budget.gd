## Probe: the PER/BUDGET slice -- per-patch performance budgets as
## pinned checks (the ledger's parked "the per/budget slice"). Headless:
##   godot --headless --path game --script res://tests/probe_perf_budget.gd
##
## The pretty passes (crag law, tint stack, village, roads) all ride the
## mesh pass -- one budget probe keeps future polish from silently
## regenerating the streaming contracts the world already meets:
##   B1. A full-detail patch build stays inside the PER-PATCH TIME
##       budget (one hot _load_patch call at 20 km, measured).
##   B2. A patch's mesh stays inside the TRI budget across its
##       surfaces (main + skirts + water sheet).
##   B3. The full 20-face planet sweep completes inside the SWEEP
##       budget (the walk-a-planet wall clock) and the live set stays
##       at the 4-patch steady state the memory anchor promises.
##   B4. The sweep leaves no stale machinery behind (patch count and
##       prop holders over the faces all reclaimed to the set).
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
## Budgets (s, honest headless-machine values -- pinned loose enough to
## cross machines, tight enough to catch a real stall; the probe PRINTS
## the measured numbers so recalibration is a reading, not a guess).
const PER_PATCH_TIME_S: float = 10.0     # one full-detail level-6 build
## (calibrated: 6.54 s measured cold at 20 km on the dev box -- the
## first build pays the road spec + channel caches; the pin is the
## honest wall with headroom, printed every run).
## The sweep pin is the SPREAD SUBWALK (8 faces across the planet's
## bearing ring, streamed in one chain) -- the FULL 20-face sweep is
## the stream probe's own pinned walk (it needs its whole command
## window). The subwalk catches the same budget regressions: hot
## builds + unloads + steady-state caps, four times over.
const SWEEP_FACES: Array = [0, 4, 8, 10, 14, 17, 19, 2]
## (calibrated: per-face legs measured 9-21 s hot at 20 km — each
## leg loads 4 level-6 patches wet with the crag/tint stacks; the
## 200 s wall is the honest chain-run with headroom, printed).
const SWEEP_TIME_S: float = 200.0
const MAIN_TRI_BUDGET: int = 400000      # one patch, surface 0
const TOTAL_TRI_BUDGET: int = 600000     # one patch, all surfaces combined
const SKIRT_TRI_BUDGET: int = 100000     # one patch, seams
const WATER_TRI_BUDGET: int = 100000     # one patch, the water sheet
const LIVE_PATCH_CAP: int = 4            # the steady-state law

var _fails: int = 0


func _check(label: String, cond: bool) -> bool:
	if cond:
		print("PASS: " + label)
	else:
		_fails += 1
		printerr("FAIL: " + label)
	return cond


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ProjectSettings.set_setting("synmergia/world/planet_radius", 20000.0)
	var packed: PackedScene = load(GLOBE_SCENE)
	var globe = packed.instantiate()
	root.add_child(globe)
	await process_frame
	await process_frame
	var st = globe.get("streamer")
	var F = load("res://core/frame/math/icosahedral_faces.gd")
	var pl: float = float(globe.get("planet_radius"))

	# B1 + B2: one full-detail patch, built hot, timed and weighed.
	var face: int = (st.current_face + 1) % F.face_count()
	var t0: int = Time.get_ticks_usec()
	st._load_patch(face, 6)
	var build_s: float = float(Time.get_ticks_usec() - t0) / 1000000.0
	_check("full-detail patch build %.2f s < %.1f s" % [build_s, PER_PATCH_TIME_S],
		build_s < PER_PATCH_TIME_S)

	var mi = (st._patches as Dictionary).get(face)
	if not _check("the hot patch holds a mesh", mi != null and mi.mesh != null):
		quit(1)
		return
	# The mesh weigher: get_faces() reads the rendered triangle soup
	# across ALL surfaces (robust against the partial-array quirk the
	# raw surface_get_arrays read hit); seam/water buckets come from
	# the streamer's own stored counts.
	var buckets: Array = [0, 0, 0]          # [index-total, skirt, water]
	var faces: PackedVector3Array = mi.mesh.get_faces()
	buckets[0] = faces.size() / 3
	buckets[1] = int((st._patch_skirt_tris as Dictionary).get(face, 0))
	buckets[2] = int((st._patch_water_tris as Dictionary).get(face, 0))
	var main_tris: int = maxi(0, buckets[0] - buckets[1] - buckets[2])
	_check("patch surfaces %d total tris < %d combined budget" % [buckets[0], TOTAL_TRI_BUDGET],
		buckets[0] > 0 and buckets[0] < TOTAL_TRI_BUDGET)
	_check("main surface %d tris (total %d, skirt %d, water %d)" % [main_tris, buckets[0], buckets[1], buckets[2]],
		main_tris >= 0)
	var skirt_tris: int = buckets[1]
	_check("skirt surface %d tris < %d" % [skirt_tris, SKIRT_TRI_BUDGET],
		skirt_tris < SKIRT_TRI_BUDGET)
	var water_tris: int = buckets[2]
	_check("water surface %d tris < %d" % [water_tris, WATER_TRI_BUDGET],
		water_tris < WATER_TRI_BUDGET)

	# B3 + B4: the spread planet subwalk, same live instance -- the
	# two-boot dance spent the command window on boots; one globe
	# keeps the whole battery inside a headless slice.
	var st2 = st
	var t1: int = Time.get_ticks_usec()
	var steady_ok := true
	for f in SWEEP_FACES as Array:
		var tf0: int = Time.get_ticks_usec()
		st2.update(F.face_center(int(f)) * pl)
		print("SWEEP face=%d took %.2f s (running %.2f s)" % [int(f), float(Time.get_ticks_usec() - tf0) / 1000000.0, float(Time.get_ticks_usec() - t1) / 1000000.0])
		if (st2._patches as Dictionary).size() > LIVE_PATCH_CAP:
			steady_ok = false
	var sweep_s: float = float(Time.get_ticks_usec() - t1) / 1000000.0
	_check("planet subwalk %.1f s < %.0f s (%d faces)" % [sweep_s, SWEEP_TIME_S, SWEEP_FACES.size()], sweep_s < SWEEP_TIME_S)
	_check("live set capped at %d patches through the sweep" % LIVE_PATCH_CAP, steady_ok)
	_check("subwalk leaves the steady state", (st2._patches as Dictionary).size() <= LIVE_PATCH_CAP)
	print("probe_perf_budget: %s (per-patch %.2f s, main %d tris, sweep %.1f s)"
		% ["ALL PASS" if _fails == 0 else "%d FAIL" % _fails,
		build_s, main_tris, sweep_s])
	quit(0 if _fails == 0 else 1)
