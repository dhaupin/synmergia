extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var shelf = svc.get_volume("ocean_haven_shelf")
	# Shelf at (0,-5,0): radial model. dist=5, floor_r=20000 ->
	# column = 20000-5 = 19995, depth=5 -> sample 5. But vol_at now?
	print("shelf vol_at(0,-5,0)=", svc.volume_at(Vector3(0,-5,0)).id if svc.volume_at(Vector3(0,-5,0)) != null else "null")
	print("shelf sample=", svc.sample_depth(Vector3(0,-5,0), shelf))
	print("current=", svc.current_at(Vector3(0,-5,0)))
	quit(0)
