extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var shelf = svc.get_volume("ocean_haven_shelf")
	var crater = svc.get_volume("ocean_lunar_crater")
	# At (0,-5,0): crater claims first (its box: -31..-4 with 2 m slack? surface -6 +2 = -4; -5 < -4 so inside).
	# Shelf's radial band: dist 5 < floor_r 20000 -> INSIDE THE ROCK -> shelf refuses!
	# The shelf's water is at the TOP of the world sphere near y=0 with rock below at radial 20000 --
	# but (0,-5,0) has dist 5 from center: that IS inside the planet!
	# HONEST WORLD-SHELL WATER: the surface plane at y=0 near the POLE means the water
	# occupies y in [-60, 0] around x,z where the shell is at ~y=-20000?? NO --
	# the main world's PLAYABLE surface: the globe shell radius 20000 centered ZERO.
	# The playable world y=0 plane is the SURFACE (the scene's world_root positions the
	# planet center far below). So the shelf's floor_center is NOT ZERO in scene space.
	# In the playable scene, the planet center sits at -20000-ish Y (or the shell is local).
	# HONEST DECLARATION: floor_center must be where the scene's planet center actually is:
	# for the main playable world, the scene places the shell around origin with y=0 surface.
	# So the world-shell model in SCENE space: floor_center=(0,-60,0) with... no.
	# CLEANEST: the shelf is ALSO a local column: floor plane at y=-60 (max_depth).
	# The radial model only earns its keep when the scene has a true world sphere center.
	# The playable world's water: plane surface at 0, floor at -60. LOCAL model.
	print("shelf as local: floor_y=-60: sample(0,-5,0)=", minf(5.0, maxf(-5.0 - (-60.0), 0.0)))
	quit(0)
