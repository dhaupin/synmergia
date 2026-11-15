extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var crater = svc.get_volume("ocean_lunar_crater")
	var shelf = svc.get_volume("ocean_haven_shelf")
	var p := Vector3(0, -12, 0)
	# manual claim tests
	var cv_surf: float = float(crater.surface_height)
	var cv_ok_y: bool = p.y <= cv_surf + 2.0 and p.y >= float(crater.floor_y)
	var cv_horiz: float = Vector2(p.x - crater.floor_center.x, p.z - crater.floor_center.z).length()
	var cv_reach: float = float(crater.max_depth) * 2.0 + 20.0
	print("crater y_ok=", cv_ok_y, " horiz=", cv_horiz, " reach=", cv_reach, " floor_is_radial=", bool(crater.floor_is_radial))
	print("types: floor_is_radial type=", typeof(crater.floor_is_radial))
	quit(0)
