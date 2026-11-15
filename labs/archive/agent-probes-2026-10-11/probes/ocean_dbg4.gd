extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	# Load OceanService's SCRIPT fresh and call sample_depth on an
	# instance directly (bypassing the autoload instance) -- is the
	# autoload running STALE code?
	var script = load("res://core/services/ocean_service.gd")
	var inst = script.new()
	inst.ensure_loaded()
	var shelf = inst.get_volume("ocean_haven_shelf")
	print("fresh sample=", inst.sample_depth(Vector3(0,-5,0), shelf))
	var svc = root.get_node_or_null("OceanService")
	print("autoload script path=", svc.get_script().resource_path)
	quit(0)
