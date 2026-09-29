# probe_swim.gd - S14.2: the first swimmer (labs/prd-ocean-depths.md
# sec 3-4). The Builder's Pool on the Watched Stone is where the
# ocean learns to swim: the swim profile is data, the state machine
# is a frame primitive, and the service drives both from the sampler.
#
# Covers:
#   A. movement_swim.tres loads as AQUATIC data (no hard-coded swim).
#   B. The service driver: one tick returns everything a reader needs
#      (state, depth, band, current, breath, pressure, drowning).
#   C. The Builder's Pool: a full dive drives WADING -> SURFACE_SWIM
#      -> SUBMERGED; breath drains; surfacing refills; the tame pool
#      never accrues pressure.
#   D. The Haven Shelf: the squeeze tax is REAL (pressure accrues
#      past 50 m), CRUSH drains 4x, and the current is the ferry lane.
#   E. Drowning: the overtime pool accrues honestly and stops dry.
#   F. The book: swimmers are tracked per body and forgotten cleanly.
#
# Script mode: autoloads at runtime (OceanService, DataService).
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	var ds = root.get_node_or_null("DataService")
	_check("OceanService + DataService present", svc != null and ds != null)
	if svc == null or ds == null:
		quit(1)
		return
	if not ds._loaded:
		ds.load_all_data()
	svc.ensure_loaded()
	var SS = load("res://core/frame/srv/swim_state.gd")

	# ---- A. The swim profile is DATA ---------------------------------------
	var prof = ds.get_movement_profile("movement_swim")
	_check("movement_swim.tres loads through DataService", prof != null)
	_check("the profile is AQUATIC (the class the state machine hooks)", \
		prof != null and int(prof.locomotion_class) == 3)
	_check("swim speed lives on the profile (3.4 m/s, no jump)", \
		prof != null and absf(float(prof.swim_speed) - 3.4) < 0.001 \
		and float(prof.jump_force) == 0.0)

	# ---- B. The service driver ------------------------------------------------
	var crater = svc.get_volume("ocean_lunar_crater")
	var r: Dictionary = svc.tick_swimmer("pool_swimmer", Vector3(0, -12, 0), 1.0 / 60.0)
	_check("one tick returns the whole water truth", \
		r.has("state") and r.has("depth") and r.has("band") and r.has("current") \
		and r.has("breath") and r.has("pressure") and r.has("drowning_s"))
	_check("the pool swimmer at 6 m is SUBMERGED", int(r["state"]) == SS.State.SUBMERGED)

	# ---- C. The first swim: a full dive in the Builder's Pool ------------------
	svc.forget_swimmer("dive_1")
	var dt: float = 1.0 / 60.0
	# Walk in: ankles at y=-6.5 (0.5 m deep).
	var w: Dictionary = svc.tick_swimmer("dive_1", Vector3(0, -6.5, 0), dt)
	_check("entering the pool reads WADING", int(w["state"]) == SS.State.WADING)
	# Head-up: 1.5 m deep (top meter of the swim band).
	var h: Dictionary = svc.tick_swimmer("dive_1", Vector3(0, -7.5, 0), dt)
	_check("the top meter reads SURFACE_SWIM (breath refills)", int(h["state"]) == SS.State.SURFACE_SWIM)
	# Dive to the floor-1 (23 m deep, 1 m above the rock).
	for i in range(600):
		svc.tick_swimmer("dive_1", Vector3(0, -29.0, 0), dt)
	var deep = svc.swim_state("dive_1")
	_check("10 s at the pool floor: breath drained to 35 s", \
		absf(float(deep.breath) - (SS.BREATH_SECONDS - 10.0)) < 0.1)
	_check("the tame pool accrues NO pressure (the workshop is kind)", \
		float(deep.pressure) == 0.0)
	# Surface: breath refills.
	for i in range(6):
		svc.tick_swimmer("dive_1", Vector3(0, -7.5, 0), dt)
	var up = svc.swim_state("dive_1")
	_check("surfacing refills the breath clock", float(up.breath) == SS.BREATH_SECONDS)

	# ---- D. The Haven Shelf: the real ocean has teeth ----------------------------
	svc.forget_swimmer("deep_diver")
	var dt2: float = 1.0 / 60.0
	# A body at 55 m on the shelf (5 m past the squeeze line, 0.1/m tax).
	for i in range(300):
		svc.tick_swimmer("deep_diver", Vector3(3000, -55.0, 0), dt2)
	var squeezed = svc.swim_state("deep_diver")
	_check("5 s past the squeeze line accrues pressure", float(squeezed.pressure) > 0.0)
	_check("the shelf's squeeze state is honest", \
		svc.tick_swimmer("deep_diver", Vector3(3000, -55.0, 0), dt2)["state"] == SS.State.SQUEEZE)
	# The current: the ferry lane pushes.
	var cur: Vector3 = svc.tick_swimmer("deep_diver", Vector3(3000, -55.0, 0), dt2)["current"]
	_check("the shelf current pushes (the ferry lane is real)", cur.length() > 0.0)
	# CRUSH: 61 m down.
	svc.forget_swimmer("crushed")
	var breath_before: float = SS.BREATH_SECONDS
	svc.tick_swimmer("crushed", Vector3(3000, -61.0, 0), dt2)
	var crushed = svc.swim_state("crushed")
	_check("CRUSH reads as CRUSH", int(crushed.state) == SS.State.CRUSH)
	_check("CRUSH drains breath fast (4x)", \
		absf((breath_before - float(crushed.breath)) - dt2 * SS.CRUSH_DRAIN_MULTIPLIER) < 0.001)

	# ---- E. Drowning ------------------------------------------------------------
	svc.forget_swimmer("drowner")
	for i in range(3000):
		svc.tick_swimmer("drowner", Vector3(0, -20.0, 0), dt2)
	var d = svc.swim_state("drowner")
	_check("45 s under = drowning (the clock ran out)", d.is_drowning())
	_check("the overtime pool accrues honestly", float(d.drowning_s) > 0.0 and float(d.drowning_s) < 10.0)
	# Dry land stops everything.
	svc.tick_swimmer("drowner", Vector3(0, 5.0, 0), dt2)
	var d2 = svc.swim_state("drowner")
	_check("dry land resets breath and drowning", \
		float(d2.breath) == SS.BREATH_SECONDS and float(d2.drowning_s) == 0.0)

	# ---- F. The book is clean -----------------------------------------------------
	svc.forget_swimmer("dive_1")
	svc.forget_swimmer("deep_diver")
	svc.forget_swimmer("crushed")
	svc.forget_swimmer("drowner")
	_check("forgotten swimmers leave no book residue", svc.swim_state("dive_1") == null)

	if _fails == 0:
		print("SWIM PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("SWIM PROBE FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
