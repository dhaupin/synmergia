## Tests for SwimState -- the S14.2 water state machine (frame
## primitive, co-located per labs conventions).
##
## Covers: the band ladder (WADING -> SURFACE_SWIM -> SUBMERGED ->
## SQUEEZE -> CRUSH), the two clocks (breath drains under, refills
## at the surface; pressure accrues in SQUEEZE, eases off at the
## surface), drowning accrual, the rock sentinel (inside stone =
## DRY, no breath spent), the breather law (grace deepens squeeze,
## CRUSH never moves), speed honesty (squeeze slows you), and the
## glider gate (water is not air).
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var SS = load("res://core/frame/srv/swim_state.gd")

	# ---- A. The band ladder ----------------------------------------------------
	var s = SS.new()
	var dt: float = 1.0 / 60.0
	_check("above the line is DRY", s.tick(dt, -2.0, 50.0, 60.0) == SS.State.DRY)
	_check("ankles are WADING", s.tick(dt, 0.8, 50.0, 60.0) == SS.State.WADING)
	_check("head-up top meter is SURFACE_SWIM", s.tick(dt, 2.0, 50.0, 60.0) == SS.State.SURFACE_SWIM)
	_check("full swim is SUBMERGED", s.tick(dt, 10.0, 50.0, 60.0) == SS.State.SUBMERGED)
	_check("past the squeeze line is SQUEEZE", s.tick(dt, 52.0, 50.0, 60.0) == SS.State.SQUEEZE)
	_check("past max_depth is CRUSH", s.tick(dt, 61.0, 50.0, 60.0) == SS.State.CRUSH)
	_check("the rock sentinel (-1) reads DRY (stone is not water)", \
		s.tick(dt, -1.0, 50.0, 60.0) == SS.State.DRY)

	# ---- B. The breath clock ------------------------------------------------------
	var b = SS.new()
	for i in range(600):
		b.tick(dt, 20.0, 50.0, 60.0)
	_check("breath drains while submerged (10 s under: 35 s left)", \
		absf(b.breath - (SS.BREATH_SECONDS - 10.0)) < 0.1)
	_check("not drowning yet", not b.is_drowning())
	for i in range(2110):
		b.tick(dt, 20.0, 50.0, 60.0)
	_check("breath gone after 45 s under", b.breath <= 0.0 and b.is_drowning())
	_check("drowning accrues only past zero (the overtime is honest)", \
		b.drowning_s > 0.0 and b.drowning_s < 1.0)
	# Surfacing refills: back to the top meter.
	for i in range(6):
		b.tick(dt, 1.5, 50.0, 60.0)
	_check("surfacing refills the breath clock", b.breath == SS.BREATH_SECONDS)
	_check("surfacing stops the drowning accrual", b.drowning_s == 0.0 and not b.is_drowning())

	# ---- C. Pressure accrues and eases ---------------------------------------------
	var p = SS.new()
	for i in range(300):
		p.tick(dt, 55.0, 50.0, 60.0, 0.1, 0.0)
	_check("SQUEEZE accrues pressure scaled by depth past the line", p.pressure > 0.0)
	var peaked: float = p.pressure
	for i in range(600):
		p.tick(dt, -2.0, 50.0, 60.0, 0.1, 0.0)
	_check("surfacing eases pressure (decompression, gradual)", \
		p.pressure < peaked and not p.is_drowning())
	# The tame pool: pressure_per_meter 0 AND the pool's squeeze line
	# is at max_depth (14 vs 24): the squeeze band is EMPTY, so the
	# tame pool's squeeze band simply does not exist -- and CRUSH at
	# 24 m never carries a per-meter tax. Base pressure is part of
	# the VOLUME's rate (the driver multiplies per_meter into depth-
	# past-line; a 0-tax volume accrues nothing).
	var tame = SS.new()
	for i in range(600):
		tame.tick(dt, 23.0, 24.0, 24.0, 0.0, 0.0)
	_check("the Builder's Pool accrues no pressure (tame by design)", tame.pressure == 0.0)

	# ---- D. CRUSH: the ocean says no -------------------------------------------------
	var c = SS.new()
	var breath_before: float = c.breath
	c.tick(dt, 61.0, 50.0, 60.0, 0.1, 0.0)
	_check("CRUSH drains breath 4x", \
		absf((breath_before - c.breath) - dt * SS.CRUSH_DRAIN_MULTIPLIER) < 0.001)

	# ---- E. The breather law ------------------------------------------------------------
	# The service passes the RAW squeeze line; the primitive applies
	# the grace itself (one law -- no caller double-applies it).
	var g = SS.new()
	g.tick(dt, 52.0, 50.0, 60.0, 0.1, 8.0)
	_check("grace 8 deepens the squeeze line (52 m is now free swim)", \
		g.state == SS.State.SUBMERGED)
	g.tick(dt, 59.0, 50.0, 60.0, 0.1, 8.0)
	_check("but CRUSH never moves (59 m is still SQUEEZE, 60+ is CRUSH)", \
		g.state == SS.State.SQUEEZE)
	g.tick(dt, 61.0, 50.0, 60.0, 0.1, 8.0)
	_check("the stone's patience is gear-proof (61 m is CRUSH)", \
		g.state == SS.State.CRUSH)
	# Breath capacity multiplies the clock (gear owns air).
	var cap = SS.new()
	cap.set_breath_capacity(4.0)
	_check("a x4 breather quadruples the clock", \
		absf(cap.breath - SS.BREATH_SECONDS * 4.0) < 0.001)

	# ---- F. Speed honesty + the glider gate ---------------------------------------------
	_check("WADING is a slow walk", SS.new().swim_speed_scale() != 0.0)
	var slow = SS.new()
	slow.tick(dt, 55.0, 50.0, 60.0)
	_check("SQUEEZE slows you (drag the pressure makes honest)", \
		slow.swim_speed_scale() < 1.0)
	var swimmer = SS.new()
	swimmer.tick(dt, 10.0, 50.0, 60.0)
	_check("a submerged body may not deploy the glider", not swimmer.allows_glider())
	swimmer.tick(dt, -3.0, 50.0, 60.0)
	_check("a dry body may deploy the glider", swimmer.allows_glider())

	if _fails == 0:
		print("SWIM STATE TEST PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("SWIM STATE TEST FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
