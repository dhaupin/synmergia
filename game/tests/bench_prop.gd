extends SceneTree

## bench_prop.gd — the GDScript side of the Facet 3 timing.
##
## Derives the IDENTICAL per-face rock + boulder spec set that
## srv/julia-bridge/prop_batch.jl derives, then times the frame's own
## derivation. Run:
##   godot --headless --path . --script res://tests/bench_prop.gd
##
## The checksums cross-check against the Julia batch (a parity signal);
## the two timings are the Facet 3 speedup number. This is the per-face
## cost the prop layer pays (PropLayer buckets a face's specs once per
## face via provider.rock_specs / provider.boulder_specs).

const SEED_HEX := "73616c7463726f776e2d69736c652d34"

func _init() -> void:
	var G = load("res://scenes/worlds/terrain_gen.gd")
	var seed: PackedByteArray = G.world_seed_bytes()
	print("SEED_HEX=", seed.hex_encode(), " (expect ", SEED_HEX, ")")

	# Warm up (compile the spec path + memoize sea).
	G.rock_specs(seed, 0)
	G.boulder_specs(seed, 0)

	var t0: int = Time.get_ticks_usec()
	var rocks: int = 0
	var boulders: int = 0
	var checksum: float = 0.0
	for f in range(20):
		for s in G.rock_specs(seed, f):
			rocks += 1
			checksum += s.dir.x + s.dir.y + s.dir.z + s.scale + s.yaw
		for b in G.boulder_specs(seed, f):
			boulders += 1
			checksum += b.dir.x + b.dir.y + b.dir.z + b.radius + b.yaw
	var t1: int = Time.get_ticks_usec()
	print("GDSCRIPT_PROP_USEC ", t1 - t0, " rocks=", rocks, " boulders=", boulders,
			" checksum=", "%.10f" % checksum)
	quit(0)
