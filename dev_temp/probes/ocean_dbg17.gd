extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var crater = svc.get_volume("ocean_lunar_crater")
	var shelf = svc.get_volume("ocean_haven_shelf")
	# volume_at(0,-12,0) returns SHELF? The shelf is radial=false now,
	# claims box: pos.y in [floor_y=-60, surface 0+2=2], horiz <=
	# max_depth*2+20 = 140 of (0,0). (0,-12,0): inside! And crater
	# claims too. best selection in LOCAL branch: `if best == null`
	# -- shelf iterates FIRST (dict order) and claims, crater's local
	# branch requires best == null to claim! BUG: local claim ignores
	# distance comparison. Fix: local branch should compare too.
	print("order test: crater=", crater, " shelf=", shelf)
	quit(0)
