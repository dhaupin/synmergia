extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var crater = svc.get_volume("ocean_lunar_crater")
	# (0,-29) with explicit volume: why 1.0?
	var pos := Vector3(0, -29, 0)
	var depth: float = float(crater.surface_height) - pos.y
	var col: float = pos.y - float(crater.floor_y)
	print("depth=", depth, " column_local=", col, " min=", minf(depth, col))
	# Without explicit volume:
	print("via volume_at: vol=", svc.volume_at(pos).id if svc.volume_at(pos) != null else "null")
	print("sample no-vol=", svc.sample_depth(pos))
	quit(0)
