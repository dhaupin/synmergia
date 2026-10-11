extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var shelf = svc.get_volume("ocean_haven_shelf")
	var direct = load("res://data/oceans/ocean_haven_shelf.tres")
	print("SAME=", shelf == direct, " shelf_type=", typeof(shelf), " direct_surf=", direct.surface_height, " shelf_surf=", shelf.surface_height if shelf != null else "null")
	var v = svc.volume_at(Vector3(0,-5,0))
	print("vol_at surf=", v.surface_height if v != null else "null", " same_as_shelf=", v == shelf)
	# Manual sample
	var depth: float = float(direct.surface_height) - (-5.0)
	print("manual depth=", depth)
	print("svc sample=", svc.sample_depth(Vector3(0,-5,0), direct))
	quit(0)
