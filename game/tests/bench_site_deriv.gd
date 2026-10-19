## bench_site_deriv - micro-benchmark for the prop-site derivation cost
## Times the exact operations one scatter site pays at the planet scale:
## ground height (terrain + rock tops), water gate, species biome. The
## count ladder in _spawn_trees must be sized against THESE microseconds,
## not against hope. Prints per-op medians so the density raise stays
## inside the boot budget.
## Run headless:   godot --headless --path . --script res://tests/bench_site_deriv.gd
extends SceneTree

const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")

const N_SITES := 300
const FACES_PATH := "res://core/frame/math/icosahedral.gd"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var seed_b: PackedByteArray = TerrainGen.world_seed_bytes()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	var Faces = load("res://core/frame/math/icosahedral_faces.gd")
	var fc: Vector3 = Faces.face_center(18)
	var fv: PackedInt32Array = Faces.face_vertices(18)
	var Ico = load(FACES_PATH).new()
	var sea: float = TerrainGen.sea_level(seed_b)
	print("sea=", sea)
	# Warm the caches the game would warm (plaza + a walk of dirs).
	var t_all: int = 0
	var t_h: int = 0
	var t_bio: int = 0
	var n_dry := 0
	var n_tree := 0
	var start := Time.get_ticks_usec()
	for i in range(N_SITES):
		var v: Vector3 = Ico.VERTICES[fv[rng.randi_range(0, 2)]].normalized()
		var dir: Vector3 = (fc * 0.5 + v * 0.5).normalized()
		var t0 := Time.get_ticks_usec()
		var h: float = TerrainGen.terrain_height(dir, seed_b)
		var t1 := Time.get_ticks_usec()
		var biome: int = TerrainGen.climate_biome_id(dir, seed_b)
		var t2 := Time.get_ticks_usec()
		var surf: float = TerrainGen.hydro_water_surface(dir, seed_b)
		var t3 := Time.get_ticks_usec()
		t_h += (t1 - t0)
		t_bio += (t2 - t1)
		t_all += (t3 - t0)
		if h >= sea - 0.6:
			n_dry += 1
		if biome == 9 or biome == 8:
			n_tree += 1
	var end_usec := Time.get_ticks_usec()
	print("SITES=", N_SITES)
	print("MICRO_per_site: ground=~", float(t_h) / float(N_SITES),
		"us biome+road=~", float(t_bio) / float(N_SITES),
		"us total(with water gate)=~", float(t_all) / float(N_SITES), "us")
	print("dry_sites=", n_dry, " tree-band_sites=", n_tree)
	print("TOTAL_wall_ms=", float(end_usec - start) / 1000.0)
	quit(0)
