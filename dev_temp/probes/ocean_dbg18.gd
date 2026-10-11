extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var crater = svc.get_volume("ocean_lunar_crater")
	var shelf = svc.get_volume("ocean_haven_shelf")
	var p := Vector3(0, -12, 0)
	# crater local claim: y -12 in [-30, -6+2=-4]? yes. horiz = dist((0,-6),(0,-12)) XZ = 0 <= 68. claims.
	# shelf local claim: y -12 in [-60, 2]? yes. horiz = 0 <= 140. claims.
	# crater horiz 0 < shelf horiz 0 -> tie: best stays first (crater if crater first in dict).
	# but b(0,-12) is NULL -> BOTH refused?
	print("crater surface=", crater.surface_height, " floor_y=", crater.floor_y, " floor_is_radial=", crater.floor_is_radial, " max_depth=", crater.max_depth)
	# shelf: floor_is_radial now false? printed before...
	print("shelf radial=", shelf.floor_is_radial, " floor_y=", shelf.floor_y, " surface=", shelf.surface_height)
	quit(0)
