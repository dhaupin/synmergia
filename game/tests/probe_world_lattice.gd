# probe_world_lattice.gd - S16.1: the multiworld lattice.
#
# Covers:
#   A. Declarations: three worlds load with world_ prefix ids, the
#      universe has exactly one root (main), parenting resolves.
#   B. Derived seeds: same constant + path = same bytes across two
#      fresh registries (the "clock you wind once" proof); different
#      worlds never share a seed (domain separation); underworld
#      nests under main (parent fold changes the bytes).
#   C. Entry law: underworld OFFLINE to players, moon DEV_ONLY, main
#      enterable; the moon has no atmosphere (no gliders -- the wing
#      is a wing).
#   D. Closed-form orbits: the moon's position is a pure function of
#      the epoch (deterministic, periodic, no simulation); positions
#      differ across epochs and repeat after a period.
#   E. Transfer windows: favorability is 0..1, windows are found
#      within the horizon, determinism across calls.
#   F. One clock (S16.2): SignService.sky_epoch_days() is the
#      canonical epoch -- time travel moves the calendar AND the moon.
#
# Script mode: no autoloads needed -- the registry is a frame
# primitive (pure functions + res:// data).
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var WR = load("res://core/frame/srv/world_registry.gd")
	var WD = load("res://core/schemas/world_data.gd")

	# ---- A. Declarations --------------------------------------------------
	var reg = WR.new()
	reg.load_worlds()
	_check("three world declarations load", reg.all_worlds().size() == 3)
	var main = reg.get_world("main")
	var under = reg.get_world("underworld")
	var moon = reg.get_world("moon")
	_check("root world is main (no parent, MAIN kind)", \
		main != null and str(main.parent_world) == "" and int(main.kind) == WD.WorldKind.MAIN)
	_check("underworld nests under main (SUBWORLD)", \
		under != null and str(under.parent_world) == "main" and int(under.kind) == WD.WorldKind.SUBWORLD)
	_check("moon is a CELESTIAL body of main", \
		moon != null and str(moon.parent_world) == "main" and int(moon.kind) == WD.WorldKind.CELESTIAL)
	_check("seed paths nest without collision", \
		main.seed_path() == "world:main" \
		and under.seed_path() == "world:main/subworld:underworld" \
		and moon.seed_path() == "world:main/subworld:moon")

	# ---- B. Derived seeds ---------------------------------------------------
	var s_main: String = reg.world_seed_hex("main")
	var s_under: String = reg.world_seed_hex("underworld")
	var s_moon: String = reg.world_seed_hex("moon")
	_check("seeds are 32-byte hex", s_main.length() == 64 and s_moon.length() == 64)
	_check("worlds never share a seed (domain separation)", \
		s_main != s_under and s_main != s_moon and s_under != s_moon)
	# THE proof: a fresh registry derives the same bytes from the same
	# constant. Wind once, read forever.
	var reg2 = WR.new()
	reg2.load_worlds()
	_check("fresh registry derives identical seeds (determinism)", \
		reg2.world_seed_hex("main") == s_main \
		and reg2.world_seed_hex("underworld") == s_under \
		and reg2.world_seed_hex("moon") == s_moon)
	# A parent fold must actually change the child bytes (underworld is
	# not just "world:underworld" off the universe root).
	var Chain = load("res://core/frame/kv/seed_chain.gd")
	var stack_one: Array[PackedByteArray] = [reg.universe_seed()]
	var flat_under: String = Chain.derive_seed(stack_one, "world:underworld").hex_encode()
	_check("underworld seed folds through the main domain (nesting matters)", \
		flat_under != s_under)
	_check("unknown world derives to empty", \
		reg.world_seed("world_that_is_not").is_empty())

	# ---- C. Entry law --------------------------------------------------------
	_check("main is enterable (production home)", main.is_enterable())
	_check("underworld is OFFLINE to players", not under.is_enterable())
	_check("moon is DEV_ONLY (no player path yet)", \
		int(moon.offline) == WD.OfflineState.DEV_ONLY and not moon.is_enterable())
	_check("the moon has NO atmosphere (gliders stay stowed)", \
		not moon.has_atmosphere and not moon.allows_gliding())
	_check("the moon is light (6 m/s^2) and small (1.2 km)", \
		abs(float(moon.gravity_force) - 6.0) < 0.01 and abs(float(moon.radius_m) - 1200.0) < 0.01)
	_check("main keeps earth physics", \
		abs(float(main.gravity_force) - 20.0) < 0.01 and main.allows_gliding())

	# ---- D. Closed-form orbits ------------------------------------------------
	var p0: Vector3 = WR.orbit_position(moon, 0.0)
	var p1: Vector3 = WR.orbit_position(moon, 1.0)
	var p_again: Vector3 = WR.orbit_position(moon, 0.0)
	_check("orbit position is a pure function (same epoch, same place)", \
		p0 == p_again)
	_check("the moon moves across epochs", p0.distance_to(p1) > 1000.0)
	_check("orbit radius is honored (90 km from main)", \
		abs(p0.length() - 90000.0) < 0.5)
	_check("the moon returns after one period (8 sky days)", \
		WR.orbit_position(moon, 8.0).distance_to(p0) < 0.5)
	_check("non-orbiting worlds sit at ZERO", \
		WR.orbit_position(main, 3.0) == Vector3.ZERO \
		and WR.orbit_position(under, 3.0) == Vector3.ZERO)
	_check("null world is safe (ZERO)", WR.orbit_position(null, 1.0) == Vector3.ZERO)

	# ---- E. Transfer windows ---------------------------------------------------
	var fav: float = WR.window_favorability(main, moon, 0.0)
	_check("favorability is normalized 0..1", fav >= 0.0 and fav <= 1.0)
	var w1: float = WR.next_transfer_window(main, moon, 0.0)
	var w2: float = WR.next_transfer_window(main, moon, 0.0)
	_check("a transfer window opens within one lunar period", \
		w1 > 0.0 and w1 <= float(moon.orbit_period_days) * 2.0)
	_check("windows are deterministic", w1 == w2)
	_check("window epochs actually pass the threshold", \
		WR.window_favorability(main, moon, w1) <= 0.15)
	# On the far side of the orbit no window should report (impossible
	# ask inside a tiny horizon).
	var w_none: float = WR.next_transfer_window(main, moon, w1 + 0.1, 0.0001, 0.25, 0.2)
	_check("no window inside an impossible horizon", w_none < 0.0)

	# ---- F. One clock (S16.2) ----------------------------------------------
	# The Concord clock IS the orbit clock: closed-form orbits evaluate
	# against SignService.sky_epoch_days(), the same override-honoring
	# clock that rolls the sky calendar (sign_service.gd law: services
	# that key off the sky MUST read the override-aware accessors).
	var svc = root.get_node_or_null("SignService")
	_check("SignService available in script mode", svc != null)
	if svc != null:
		svc.ensure_initialized()
		_check("sky_epoch_days seam exists on SignService", svc.has_method("sky_epoch_days"))
		# Far-future day (year 2241): the override rolls the calendar in
		# ISOLATION -- never mutate the live dev calendar from a probe.
		var day_future := 99001
		var e_hi := float(day_future) + 0.25
		svc.set_clock_override(e_hi * 86400.0)
		var e_over: float = svc.sky_epoch_days()
		_check("override moves the epoch AND the day index together", \
			absf(e_over - e_hi) < 0.000001 and svc.current_day_index() == day_future)
		var m_lo: Vector3 = WR.orbit_position(moon, svc.sky_epoch_days())
		var m_hi: Vector3 = WR.orbit_position(moon, e_over + 0.5)
		_check("moon position is a function of the Concord clock", \
			m_lo != Vector3.ZERO and not m_lo.is_equal_approx(m_hi))
		var e_final := float(day_future + 3) + 0.5
		svc.set_clock_override(e_final * 86400.0)
		_check("epoch and day index agree at the far-future day", \
			absf(svc.sky_epoch_days() - e_final) < 0.000001 and svc.current_day_index() == day_future + 3)
		_check("moon orbit periodic across one period under the sky clock", \
			WR.orbit_position(moon, e_final).is_equal_approx( \
				WR.orbit_position(moon, e_final + float(moon.orbit_period_days))))
		svc.set_clock_override(-1.0)
		_check("override reset returns to the live sky clock", \
			absf(svc.sky_epoch_days() - float(Time.get_unix_time_from_system()) / 86400.0) < 0.001)

	if _fails == 0:
		print("WORLD LATTICE PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("WORLD LATTICE PROBE FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
