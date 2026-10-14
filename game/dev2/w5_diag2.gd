extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var G = load("res://scenes/worlds/terrain_gen.gd")
	var seed_b: PackedByteArray = G.world_seed_bytes()
	var sea: float = G.sea_level(seed_b)
	var isl: Vector3 = G.ISLAND_CENTER
	var base: float = G._terrain_height_base_nowrap(isl, seed_b)
	var pub: float = G.terrain_height(isl, seed_b)
	print("CORE sea=", sea, " base=", base, " public=", pub, " delta=", pub - base)
	var raw: float = G._natural_raw(isl.normalized(), seed_b)
	print("CORE raw=", raw, " isl_shape=", G._island_shape(isl.normalized()))
	quit(0)
