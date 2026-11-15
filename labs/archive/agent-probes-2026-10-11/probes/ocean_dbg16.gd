extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var OVS = load("res://core/schemas/ocean_volume.gd")
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var crater = svc.get_volume("ocean_lunar_crater")
	print("b(0,-29):", svc.sample_depth(Vector3(0,-29,0), crater), " band:", svc.band_at(Vector3(0,-29,0)))
	print("b(0,-12):", svc.volume_at(Vector3(0,-12,0)))
	var shelf = svc.get_volume("ocean_haven_shelf")
	var c = svc.current_at(Vector3(0,-5,0))
	print("shelf cur=", c, " cur_vec=", shelf.current_vector(), " vol=", svc.volume_at(Vector3(0,-5,0)).id)
	var l = OVS.new(); l.max_depth=60.0
	print("b52 g8=", l.band_for(52.0, 8.0), " vs 60-10-8=42: 52>=42 -> SQ(3). b45 g8=", l.band_for(45.0,8.0))
	quit(0)
