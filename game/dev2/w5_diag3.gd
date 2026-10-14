extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var G = load("res://scenes/worlds/terrain_gen.gd")
	var seed_b: PackedByteArray = G.world_seed_bytes()
	var isl: Vector3 = G.ISLAND_CENTER
	var h0: float = G._terrain_height_base(isl, seed_b)
	var st: Vector3 = G.road_state_at(isl, seed_b)
	var after_road: float = G.road_height_override(isl, seed_b, h0)
	var carved_no_road: float = G.terrain_height_carved(isl, seed_b, "_noroad")
	print("RES h0=", h0, " road_state=", st, " after_road=", after_road, " carved_noroad=", carved_no_road, " public=", G.terrain_height(isl, seed_b))
	quit(0)
