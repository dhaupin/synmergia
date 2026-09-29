# probe_calibration.gd - the alignment substrate (prd-industry-labs.md).
#
# The owner law: "the universe should align time, space, state irl"
# and "Linux epoch is/and should be aligned -- that's the first thing
# I'd do in a physics engine." These checks hold the ladder to it:
#
#   A. Five tiers load as data (local/world/system/galaxy/universe).
#   B. THE EPOCH LAW: every tier declares the unix epoch, and the live
#      Concord clock really is unix/86400 (the alignment, measured).
#   C. Mode law: fast tiers TICK (hz > 0), slow tiers EVALUATE (no
#      integration, no drift).
#   D. Drift budgets are monotone within each mode.
#   E. period_s() serves schedulers honestly.
#   F. Space anchors name the spine (barycenter / NSC-9 facility).
#   G. State law: derive where physics is pure, fold where players chose.
#
# Script mode: autoloads at runtime (DataService + SignService).
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ds = root.get_node_or_null("DataService")
	var svc = root.get_node_or_null("SignService")
	_check("DataService + SignService present", ds != null and svc != null)
	if ds == null or svc == null:
		quit(1)
		return
	if not ds._loaded:
		ds.load_all_data()
	svc.ensure_initialized()

	# ---- A. Five tiers as data ---------------------------------------------
	var tiers: Dictionary = ds.get_calibration_tiers()
	_check("five calibration tiers load", tiers.size() == 5)
	var local_t = ds.get_calibration_tier("calibration_local")
	var world_t = ds.get_calibration_tier("calibration_world")
	var system_t = ds.get_calibration_tier("calibration_system")
	var galaxy_t = ds.get_calibration_tier("calibration_galaxy")
	var universe_t = ds.get_calibration_tier("calibration_universe")
	_check("all five tier ids resolve", \
		local_t != null and world_t != null and system_t != null \
		and galaxy_t != null and universe_t != null)

	# ---- B. The epoch law (the alignment, measured live) --------------------
	_check("every tier declares the unix epoch", \
		str(local_t.epoch_source) == "unix" and str(world_t.epoch_source) == "unix" \
		and str(system_t.epoch_source) == "unix" and str(galaxy_t.epoch_source) == "unix" \
		and str(universe_t.epoch_source) == "unix")
	# THE check: the Concord clock IS unix/86400. Linux epoch is aligned.
	var unix: float = float(Time.get_unix_time_from_system())
	var concord: float = svc.sky_epoch_days()
	_check("Concord epoch IS the Linux epoch (unix/86400)", \
		absf(concord - unix / 86400.0) < 0.000001)
	var day_index: int = svc.current_day_index()
	_check("the sky calendar is floor(unix/86400)", day_index == int(floor(unix / 86400.0)))

	# ---- C. Mode law ---------------------------------------------------------
	_check("fast tiers TICK (local 60 Hz, world 2 Hz)", \
		int(local_t.advance_mode) == 0 and int(world_t.advance_mode) == 0 \
		and local_t.tick_hz == 60.0 and world_t.tick_hz == 2.0)
	_check("slow tiers EVALUATE (no integration)", \
		int(system_t.advance_mode) == 1 and int(galaxy_t.advance_mode) == 1 \
		and int(universe_t.advance_mode) == 1 \
		and system_t.tick_hz == 0.0 and galaxy_t.tick_hz == 0.0)

	# ---- D. Drift budgets are monotone within each mode ----------------------
	_check("tick drift grows with scale (local < world)", \
		local_t.max_drift_s < world_t.max_drift_s)
	_check("evaluate drift grows with scale (system <= galaxy <= universe)", \
		system_t.max_drift_s <= galaxy_t.max_drift_s \
		and galaxy_t.max_drift_s <= universe_t.max_drift_s)

	# ---- E. Scheduler honesty ------------------------------------------------
	_check("period_s: local is 1/60 s", absf(local_t.period_s() - 1.0 / 60.0) < 0.000001)
	_check("period_s: universe folds daily", universe_t.period_s() == 86400.0)

	# ---- F. Space anchors name the spine -------------------------------------
	_check("system tier anchors the main barycenter", \
		str(system_t.anchor) == "barycenter:main")
	var reg_script: GDScript = load("res://core/frame/srv/world_registry.gd")
	var reg = reg_script.new()
	reg.load_worlds()
	_check("the barycenter named by the anchor exists in the lattice", \
		reg.get_world("main") != null)
	# NSC-9 facility domain: 10 facility bits -> 0..1023.
	var anchor_fac: int = int(str(galaxy_t.anchor).trim_prefix("nsc9:").to_int())
	_check("galaxy anchor names a valid NSC-9 facility", \
		str(galaxy_t.anchor).begins_with("nsc9:") and anchor_fac < 1024)

	# ---- G. The state law ------------------------------------------------------
	_check("pure physics derives; the universe folds the ledger", \
		bool(system_t.derives_state) and bool(galaxy_t.derives_state) \
		and not bool(local_t.derives_state) and not bool(universe_t.derives_state))

	if _fails == 0:
		print("CALIBRATION PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("CALIBRATION PROBE FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
