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

	# ---- H. Cosmic constants (declared where the ladder will consume them) ----
	_check("cosmic constants undeclared on the fast tiers", \
		local_t.light_speed_m_s == 0.0 and world_t.light_speed_m_s == 0.0 \
		and system_t.light_speed_m_s == 0.0 and galaxy_t.light_speed_m_s == 0.0)
	_check("c is the SI exact value (299792458 m/s)", \
		universe_t.light_speed_m_s == 299792458.0)
	_check("H0 declared (Planck 2018, 67.4 km/s/Mpc)", \
		universe_t.expansion_rate_h0_km_s_mpc == 67.4)
	# Light-lag honesty: the system tier's own scale is sub-light-ms.
	# Orbit radius 90 km / c is ~0.3 ms -- the slow tiers may ignore
	# lag today; the constant is there for the day it matters.
	var moon = reg.get_world("moon")
	var lag_s: float = float(moon.orbit_radius_m) / universe_t.light_speed_m_s
	_check("system-scale light lag is honestly negligible (< 1 ms)", \
		lag_s > 0.0 and lag_s < 0.001)

	# ---- I. The Horizon (the outer limit, derived -- owner: "we have
	# to have an outer limit in synmergia, like irl") -----------------------
	var WR: GDScript = reg_script
	var origin: float = universe_t.origin_unix
	_check("the origin is declared (the first commit)", origin == 1789861412.0)
	var age_now: float = WR.cosmic_age_s(origin, svc.sky_epoch_days())
	var age_direct: float = float(Time.get_unix_time_from_system()) - origin
	_check("cosmic age IS now minus the bang (pure evaluation)", \
		absf(age_now - age_direct) < 1.0)
	# t0 = 1789861412 = 2026-09-19/20 (unix 1767225600 = 2026-01-01,
	# +261.9 days): the universe is DAYS old at this writing. Bounds:
	# older than a day (it has history), younger than ten years (young).
	_check("the universe is young (its code is its fossil record)", \
		age_now > 1.0 * 86400.0 and age_now < 10.0 * 365.25 * 86400.0)
	var r0: float = WR.observable_radius_m(origin, svc.sky_epoch_days(), universe_t.light_speed_m_s)
	var r1: float = WR.observable_radius_m(origin, svc.sky_epoch_days() + 1.0, universe_t.light_speed_m_s)
	# Relative tolerance: at horizon magnitudes (~2e15 m) an absolute
	# 1 m bound is below float64 resolution -- the honest check is the
	# GROWTH RATE, not the meter count.
	_check("the horizon grows at exactly c", \
		r0 > 0.0 and absf((r1 - r0) / (universe_t.light_speed_m_s * 86400.0) - 1.0) < 0.000000001)
	_check("nothing is observable before the bang", \
		WR.cosmic_age_s(origin, float(origin) / 86400.0 - 10.0) == 0.0 \
		and WR.observable_radius_m(origin, float(origin) / 86400.0 - 10.0, universe_t.light_speed_m_s) == 0.0)
	_check("the Rest frame is declared (trilateral facilities)", \
	str(universe_t.rest_frame).begins_with("nsc9:trilateral:"))
	var rest_facets: PackedStringArray = str(universe_t.rest_frame).trim_prefix("nsc9:trilateral:").split("+")
	var rest_ok: bool = rest_facets.size() == 3
	for f in rest_facets:
		rest_ok = rest_ok and int(f) < 1024
	_check("the rest frame names three valid NSC-9 facilities", rest_ok)
	_check("only the universe tier carries the origin", \
		local_t.get("origin_unix") == 0.0 and system_t.get("origin_unix") == 0.0)

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
