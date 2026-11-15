extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var crater = svc.get_volume("ocean_lunar_crater")
	var shelf = svc.get_volume("ocean_haven_shelf")
	print("SURF crater=", crater.surface_height, " shelf=", shelf.surface_height)
	# The crater's surface plane is at y=-6. Its water column: rock at
	# 1194 radial, surface plane at y=-6 -> where the plane meets the
	# sphere: radial distance of the plane point (0,-6,0) = 6. So the
	# crater's water fills radials 6..1194? NO -- the crater is a
	# BOWL near the top of the moon sphere (radius 1200). Rock at
	# radial 1194 under the bowl; water surface at y=-6 near the top
	# pole. The column at (0,-12,0): dist=12, floor 1194 -> column =
	# 1182?? That is nonsense for a bowl at the pole.
	# HONEST MODEL: the crater is a DISHED region; the rock under the
	# pool at the pole is at radial ~1194; the water surface at y=-6.
	# A body at (0,-12): 6 m below the surface, 1182 m above the
	# center, but the ROCK under it is at radial 1194 along ITS
	# radial direction -- (0,-12,0) normalized * 1194 = (0,-1194,0),
	# NOT under the bowl at all! The bowl is a LOCAL dish; radial
	# geometry from the CENTER is wrong for a local crater.
	# CORRECT: floor_center should be the crater's local center.
	print("pole rock would be at y=", 1200.0 - 6.0)
	quit(0)
