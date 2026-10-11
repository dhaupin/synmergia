extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var crater = svc.get_volume("ocean_lunar_crater")
	var shelf = svc.get_volume("ocean_haven_shelf")
	var ur := Vector3(0, -31, 0)
	print("inside sample=", svc.sample_depth(ur), " band=", svc.band_at(ur))
	print("shelf below sample=", svc.sample_depth(Vector3(0,-5,0), shelf), " vol=", svc.volume_at(Vector3(0,-5,0)).id if svc.volume_at(Vector3(0,-5,0)) != null else "null")
	var OVS = load("res://core/schemas/ocean_volume.gd")
	print("band B.DRY=", OVS.DepthBand.DRY, " band_at(inside)=", svc.band_at(ur), " eq=", svc.band_at(ur) == OVS.DepthBand.DRY)
	quit(0)
