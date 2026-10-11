extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var crater = svc.get_volume("ocean_lunar_crater")
	var shelf = svc.get_volume("ocean_haven_shelf")
	print("crater floor_is_radial=", crater.floor_is_radial, " floor_y=", crater.floor_y)
	print("shelf floor_is_radial=", shelf.floor_is_radial)
	# The probe's rock point (0,1191,0) is from the OLD radial model
	# -- with a LOCAL pool at y=-6..-30 the probe points must move
	# into the pool's actual space: surface -6, floor -30.
	print("rock sample(0,-29,0)=", svc.sample_depth(Vector3(0,-29,0), crater))
	print("under sample(0,-31,0)=", svc.sample_depth(Vector3(0,-31,0), crater))
	print("vol_at(0,-12,0)=", svc.volume_at(Vector3(0,-12,0)).id if svc.volume_at(Vector3(0,-12,0)) != null else "null")
	print("vol_at(0,-5,0)=", svc.volume_at(Vector3(0,-5,0)).id if svc.volume_at(Vector3(0,-5,0)) != null else "null")
	quit(0)
