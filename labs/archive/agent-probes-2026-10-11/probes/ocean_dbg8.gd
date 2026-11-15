extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var OVS = load("res://core/schemas/ocean_volume.gd")
	var ladder = OVS.new()
	ladder.max_depth = 60.0
	print("b52 grace0=", ladder.band_for(52.0, 0.0), " b52 grace8=", ladder.band_for(52.0, 8.0), " b60 grace8=", ladder.band_for(60.0, 8.0))
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var crater = svc.get_volume("ocean_lunar_crater")
	var shelf = svc.get_volume("ocean_haven_shelf")
	var p := Vector3(0, 1191.0, 0)
	print("rock: depth_plane=", float(crater.surface_height) - p.y, " dist=", p.distance_to(Vector3.ZERO), " column=", float(crater.floor_radius) - p.distance_to(Vector3.ZERO))
	print("rock sample=", svc.sample_depth(p, crater))
	var u := Vector3(0, 1190.0, 0)
	print("under: column=", float(crater.floor_radius) - u.distance_to(Vector3.ZERO), " sample=", svc.sample_depth(u, crater))
	var at1180 := Vector3(0, 1180.0, 0)
	var got = svc.volume_at(at1180)
	print("vol1180 is crater=", got == crater, " is shelf=", got == shelf, " id=", got.id if got != null else "null")
	print("shelf claim=", float(shelf.floor_radius) + float(shelf.max_depth) + 50.0, " dist1180=", at1180.distance_to(Vector3.ZERO))
	print("crater current vec=", crater.current_vector(), " strength=", crater.current_strength)
	quit(0)
