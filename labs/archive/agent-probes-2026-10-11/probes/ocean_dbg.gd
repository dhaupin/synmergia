extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var shelf = svc.get_volume("ocean_haven_shelf")
	var crater = svc.get_volume("ocean_lunar_crater")
	print("BANDS shelf below=", svc.sample_depth(Vector3(0,-5,0), shelf))
	print("CRATER rock=", svc.sample_depth(Vector3(0, 1191.0, 0), crater))
	print("CRATER under=", svc.sample_depth(Vector3(0, 1190.0, 0), crater))
	print("CRATER -10=", svc.sample_depth(Vector3(0, -10.0, 0), crater))
	print("BAND 10.0=", load("res://core/schemas/ocean_volume.gd").band_for(10.0, 0.0))
	print("BAND -0.5=", load("res://core/schemas/ocean_volume.gd").band_for(-0.5, 0.0))
	print("VOL_AT crater 1180=", svc.volume_at(Vector3(0, 1180.0, 0)))
	print("CRATER current=", svc.current_at(Vector3(0, -8, 0)))
	quit(0)
