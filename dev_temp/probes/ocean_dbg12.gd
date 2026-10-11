extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var crater = svc.get_volume("ocean_lunar_crater")
	var shelf = svc.get_volume("ocean_haven_shelf")
	# The HONEST local model: the crater pool is a bowl whose floor
	# center is the moon center (0,0,0) with floor_radius 1194 --
	# i.e. the rock under the pool is the SPHERE of radius 1194
	# (the dish carved 6 m deep into the 1200 sphere). Water fills
	# from the rock up to the surface plane y=-6.
	# Body at (0,-12,0): dist to center = 12; radial rock at 1194 is
	# NOT under this body (the body's radial from center exits at
	# (0,-12,0)*1194/12 = (0,-1194,0) which is DEEP inside the moon).
	# Radial-from-center is the wrong tool for a local dish!
	# The honest floor for a LOCAL pool: the floor is the plane/
	# dish declared by floor_radius MEASURED FROM floor_center --
	# and floor_center for the crater pool must be a LOCAL point
	# above the pool, not the moon center.
	# Model: floor_center = (0, 0, 0) is WRONG for the crater.
	# Use floor_center = pool center at surface level (0,-6,0) and
	# floor_radius = depth of the pool (24): floor = sphere of 24 m
	# radius around... no, floor should be BELOW: center (0,-6,0),
	# floor at 24 m below => floor_radius measured downward.
	# Cleanest: floor_center = (0,-30,0) (24+6 below the line),
	# floor_radius = 0 ... clamps everything to 0.
	# -> The schema needs an honest LOCAL floor: keep floor_center +
	# floor_radius but set them LOCAL to the pool:
	# floor_center = (0,-6,0) (the surface center), floor_radius=24
	# means rock 24 m below the surface center along -Y.
	# sample: column = (surface - pos.y) clamped by (pos.y - (floor_center.y - floor_radius))?? 
	# SIMPLEST HONEST: floor is a PLANE at floor_y = -30 (surface -6 minus max_depth 24).
	# The radial fields are for WORLD-shell oceans (the shelf). For
	# the crater, plane math is exactly right:
	print("crater body at -12: plane depth=", -6.0 - (-12.0), " floor_y=", -6.0 - 24.0)
	print("clamp needed: min(6, -12 - (-30)) = ", minf(6.0, -12.0 - (-30.0)))
	quit(0)
