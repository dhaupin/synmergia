extends SceneTree

## bench_terrain.gd — the GDScript side of the Facet 1 timing.
##
## Generates the IDENTICAL Fibonacci-sphere direction batch that
## srv/julia-bridge/terrain_batch.jl evaluates, then times the frame's
## own derivation of the raw analytic heightfield over it. Run:
##   godot --headless --path . --script res://tests/bench_terrain.gd
##
## The totals cross-check against the Julia batch (a parity signal);
## the two timings are the Facet 1 speedup number.
##
## Measures TWO frame costs:
##   - the RAW law (_natural_raw) -- the direct Julia comparison;
##   - the PUBLIC law (terrain_height, raw + hydro carve + road) -- what
##     the clipmap actually calls per vertex.

const N := 20000
const SEED_HEX := "73616c7463726f776e2d69736c652d34"

func _fib_sphere(n: int) -> Array:
	var pts: Array = []
	var ga: float = PI * (3.0 - sqrt(5.0))
	for i in range(n):
		var z: float = 1.0 - (2.0 * float(i) + 1.0) / float(n)
		var r: float = sqrt(maxf(0.0, 1.0 - z * z))
		var th: float = ga * float(i)
		pts.append(Vector3(cos(th) * r, z, sin(th) * r))
	return pts

func _init() -> void:
	var G = load("res://scenes/worlds/terrain_gen.gd")
	var seed: PackedByteArray = G.world_seed_bytes()
	print("SEED_HEX=", seed.hex_encode(), " (expect ", SEED_HEX, ")")
	var dirs: Array = _fib_sphere(N)

	# Warm up both paths (compile / memoize the seed-salt + sea).
	var acc: float = 0.0
	for i in range(500):
		acc += G._natural_raw(dirs[i].normalized(), seed)
	acc = 0.0

	# --- RAW law timing (direct Julia comparison) ---
	var t0: int = Time.get_ticks_usec()
	for d in dirs:
		acc += G._natural_raw(d.normalized(), seed)
	var t1: int = Time.get_ticks_usec()
	print("GDSCRIPT_RAW_USEC ", t1 - t0, " n=", N, " total=", "%.9f" % acc)

	# --- PUBLIC law timing (what the clipmap calls) ---
	acc = 0.0
	for i in range(500):
		acc += G.terrain_height(dirs[i].normalized(), seed)
	acc = 0.0
	var t2: int = Time.get_ticks_usec()
	for d in dirs:
		acc += G.terrain_height(d.normalized(), seed)
	var t3: int = Time.get_ticks_usec()
	print("GDSCRIPT_PUBLIC_USEC ", t3 - t2, " n=", N, " total=", "%.9f" % acc)

	quit(0)
