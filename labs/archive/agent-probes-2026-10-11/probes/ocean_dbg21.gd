extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var crater = svc.get_volume("ocean_lunar_crater")
	var shelf = svc.get_volume("ocean_haven_shelf")
	var p := Vector3(0, -12, 0)
	# Call the exact branch logic manually in service order:
	var vals := [crater, shelf]
	for v in vals:
		var radial: bool = bool(v.floor_is_radial)
		print(v.id, " radial=", radial)
		if radial:
			print("  -> radial branch")
		else:
			var surf: float = float(v.surface_height)
			var y_ok: bool = p.y <= surf + 2.0 and p.y >= float(v.floor_y)
			var horiz: float = Vector2(p.x - v.floor_center.x, p.z - v.floor_center.z).length()
			var reach: float = float(v.max_depth) * 2.0 + 20.0
			print("  -> local: y_ok=", y_ok, " horiz=", horiz, " reach=", reach, " claimed=", y_ok and horiz <= reach)
	# And now the REAL volume_at:
	var got = svc.volume_at(p)
	print("volume_at=", got.id if got != null else "null")
	quit(0)
