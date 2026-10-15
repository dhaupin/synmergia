extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var TGen = load("res://scenes/worlds/terrain_gen.gd")
	var seed_b: PackedByteArray = TGen.world_seed_bytes()
	var sea: float = TGen.sea_level(seed_b)
	var spawn: Vector3 = TGen.SPAWN_CENTER
	var east: Vector3 = Vector3(0,1,0).cross(spawn).normalized()
	var capitol: Vector3 = TGen.capitol_dir()
	print("capitol raw noroad: %.1f  carved: %.1f  road_state: %s" % [
		TGen.terrain_height_carved(capitol, seed_b, "_noroad"),
		TGen.terrain_height(capitol, seed_b),
		TGen.road_state_at(capitol, seed_b)])
	for km in [0.30, 0.60, 0.85, 0.98, 1.10, 1.30]:
		var ang: float = km * 1000.0 / 20000.0
		var d: Vector3 = spawn.rotated(east, ang).normalized()
		var raw: float = TGen.terrain_height_carved(d, seed_b, "_noroad")
		var carv: float = TGen.terrain_height(d, seed_b)
		var st: Vector3 = TGen.road_state_at(d, seed_b)
		var win: float = TGen._cove_window(d)
		print("cove %.2fkm raw_%.1f carved_%.1f road_%.2f/bed_%.1f cove_w_%.2f" % [km, raw, carv, st.x, st.z, win])
	quit(0)
