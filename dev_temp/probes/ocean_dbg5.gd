extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var script = load("res://core/services/ocean_service.gd")
	var inst = script.new()
	inst.ensure_loaded()
	var shelf = inst.get_volume("ocean_haven_shelf")
	var pos := Vector3(0, -5, 0)
	var depth: float = float(shelf.surface_height) - pos.y
	var center: Vector3 = shelf.floor_center if shelf.floor_center != Vector3.ZERO else Vector3.ZERO
	var floor_r: float = float(shelf.floor_radius) if float(shelf.floor_radius) > 0.0 else inst.DEFAULT_FLOOR_RADIUS
	var floor_y_at_body: float = center.y + floor_r
	var max_honest: float = maxf(pos.y - floor_y_at_body, 0.0)
	print("depth=", depth, " floor_y_at_body=", floor_y_at_body, " max_honest=", max_honest, " result=", minf(depth, max_honest))
	quit(0)
