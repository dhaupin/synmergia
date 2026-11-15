extends SceneTree
const WorldData = preload("res://core/schemas/world_data.gd")
func _init() -> void:
	var wd = load("res://data/worlds/world_main.tres")
	print("tres_loaded=", wd != null)
	print("backend_id=", str(wd.terrain_backend_id))
	print("lore_ok=", str(wd.lore).length() > 0)
	print("radius=", wd.radius_m)
	quit(0 if (wd != null and str(wd.terrain_backend_id) == "sundered") else 1)
