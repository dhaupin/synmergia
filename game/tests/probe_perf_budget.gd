## Probe: the PER/BUDGET slice -- performance budgets as pinned checks
## (the ledger's parked "the per/budget slice"). Headless:
##   godot --headless --path game --script res://tests/probe_perf_budget.gd
##
## The clipmap is the SOLE renderer now: it draws a FIXED ring ladder
## (a centre cap + N_LEVELS rings), so the streaming contract is the
## ladder staying inside budget, not a per-face patch build:
##   B1. The cold build (build_all) stays inside the BUILD time budget.
##   B2. The drawn ground stays inside the TRI budget (cap + rings).
##   B3. A spread player sweep (update at 8 bearings) stays inside the
##       SWEEP budget and the mesh count stays at the fixed ladder size.
##   B4. The sweep leaves no stale machinery (mesh count == ladder size).
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
## Budgets (s, honest headless-machine values -- pinned loose enough to
## cross machines, tight enough to catch a real stall; the probe PRINTS
## the measured numbers so recalibration is a reading, not a guess).
const BUILD_TIME_S: float = 30.0      # one cold build_all at 20 km
const SWEEP_TIME_S: float = 60.0      # 8-bearing re-centre sweep
const GROUND_TRI_BUDGET: int = 60000  # the whole ladder (cap + rings)

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
	var pl: float = float(globe.get("planet_radius"))
	var ladder: int = st.ground_meshes().size()

	# B1: the cold build (a fresh build_all) stays inside the budget.
	var t0: int = Time.get_ticks_usec()
	st.build_all()
	var build_s: float = float(Time.get_ticks_usec() - t0) / 1000000.0
	_check("cold build %.2f s < %.1f s" % [build_s, BUILD_TIME_S], build_s < BUILD_TIME_S)

	# B2: the drawn ground's triangle budget.
	var total_tris: int = 0
	for mi in st.ground_meshes():
		if mi == null or mi.mesh == null:
			continue
		var faces: PackedVector3Array = mi.mesh.get_faces()
		total_tris += faces.size() / 3
	_check("drawn ground %d tris < %d combined budget" % [total_tris, GROUND_TRI_BUDGET],
		total_tris > 0 and total_tris < GROUND_TRI_BUDGET)

	# B3 + B4: the spread player sweep, same live instance.
	var F = load("res://core/frame/math/icosahedral_faces.gd")
	var t1: int = Time.get_ticks_usec()
	var steady_ok := true
	for f in range(20):
		if f % 2 != 0:
			continue
		var tf0: int = Time.get_ticks_usec()
		st.update(F.face_center(int(f)) * pl)
		print("SWEEP face=%d took %.2f s (running %.2f s) meshes=%d" % [
			int(f), float(Time.get_ticks_usec() - tf0) / 1000000.0,
			float(Time.get_ticks_usec() - t1) / 1000000.0, st.ground_meshes().size()])
		if st.ground_meshes().size() != ladder:
			steady_ok = false
	var sweep_s: float = float(Time.get_ticks_usec() - t1) / 1000000.0
	_check("planet sweep %.1f s < %.0f s (%d bearings)" % [sweep_s, SWEEP_TIME_S, 10],
		sweep_s < SWEEP_TIME_S)
	_check("mesh count stays at the fixed ladder size (%d) through the sweep" % ladder, steady_ok)
	_check("sweep leaves the ladder at steady state", st.ground_meshes().size() == ladder)
	print("probe_perf_budget: %s (cold build %.2f s, %d tris, sweep %.1f s, ladder %d)"
		% ["ALL PASS" if _fails == 0 else "%d FAIL" % _fails, build_s, total_tris, sweep_s, ladder])
	quit(0 if _fails == 0 else 1)
