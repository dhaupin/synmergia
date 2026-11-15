extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var ResourceScan = load("res://core/frame/srv/resource_scan.gd")
	var paths = ResourceScan.list_resources("res://data/gliders")
	for p in paths: print("HIGH: path=", p)
	var r = load(paths[0]) if paths.size() > 0 else null
	if r != null:
		print("HIGH: loaded id=", r.get("id"), " class=", r.get_class())
	quit(0)
