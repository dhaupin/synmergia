extends SceneTree

## Julia parity receipt (tests/test_julia_parity.gd):
## the GDScript frame's own derived values vs the Julia pre-solve tier
## (srv/julia-bridge/worldmath.jl + presolve.jl) for the same inputs.
##
## The Julia side is the float64 oracle; GDScript's frame math runs in
## float32 (Vector3), so seeds must match EXACTLY (integer/byte math)
## while orbit/favorability match to float32 precision. The oracle
## values below are what `julia --project=. presolve.jl --epochs 3`
## prints; they are the contract this receipt pins. Run:
##   godot --headless --path . --script res://tests/test_julia_parity.gd

const WorldRegistryScript = preload("res://core/frame/srv/world_registry.gd")

const SEED_MAIN := "5d8e24a05d428934c6adf4badb6cc6aa9afbaacbf4ed44c801d6a615a814603b"
const SEED_MOON := "01bcff183981449b1dbaa44bd1aee3eb3bf81e3e10dc0c44ff0aa1e7a71931dd"
const SEED_UNDERWORLD := "a2d86dfda69638f0168c6711b638e2f0c9e19ec7b02aeed589b0b26290015d53"
const UNIVERSE_HEX := "73796e6d65726769610000000000000000000000000000000000000000000000"

# Julia oracle: moon orbit at sky days 0/1/2 (worldmath.jl, float64).
const JULIA_ORBIT := [
	Vector3(68835.79685560397, -6940.864918240803, 57562.63949334462),
	Vector3(7676.496176429477, -10734.835603501087, 89027.15715453947),
	Vector3(-57979.5918513922, -8240.485182076005, 68340.77357412603),
]
# Julia oracle: moon-main window favorability at sky days 0/1/2.
const JULIA_FAV := [0.22281692032865347, 0.47281692032865347, 0.7228169203286535]

const ORBIT_REL_TOL := 1e-5
const FAV_ABS_TOL := 1e-12

var _failures: int = 0

func _ok(msg: String) -> void:
	print("[OK] ", msg)

func _fail(msg: String) -> void:
	_failures += 1
	printerr("[FAIL] ", msg)

func _initialize() -> void:
	var reg = WorldRegistryScript.new()
	reg.load_worlds()

	if reg.universe_seed().hex_encode() != UNIVERSE_HEX:
		_fail("universe seed drifted")
	else:
		_ok("universe seed matches")

	for pair in [["main", SEED_MAIN], ["moon", SEED_MOON], ["underworld", SEED_UNDERWORLD]]:
		var got: String = reg.world_seed_hex(pair[0])
		if got != pair[1]:
			_fail("seed(%s) drifted: %s" % [pair[0], got])
		else:
			_ok("seed(%s) matches the Julia oracle" % pair[0])

	var moon = reg.get_world("moon")
	var main = reg.get_world("main")
	for i in 3:
		var sky := float(i)
		var p: Vector3 = WorldRegistryScript.orbit_position(moon, sky)
		var oracle: Vector3 = JULIA_ORBIT[i]
		var denom := maxf(oracle.length(), 1.0)
		if p.distance_to(oracle) / denom > ORBIT_REL_TOL:
			_fail("orbit(moon, %d) off: %s vs %s" % [i, str(p), str(oracle)])
		else:
			_ok("orbit(moon, %d) matches to float32 precision" % i)

		var f: float = WorldRegistryScript.window_favorability(moon, main, sky)
		if absf(f - JULIA_FAV[i]) > FAV_ABS_TOL:
			_fail("fav(moon-main, %d) off: %.17f vs %.17f" % [i, f, JULIA_FAV[i]])
		else:
			_ok("fav(moon-main, %d) matches the Julia oracle" % i)

	reg = null
	if _failures == 0:
		print("JULIA PARITY RECEIPT PASS")
		quit(0)
	else:
		printerr("JULIA PARITY RECEIPT FAIL (%d)" % _failures)
		quit(1)
