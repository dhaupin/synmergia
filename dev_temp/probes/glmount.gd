extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var ResourceScan = load("res://core/frame/srv/resource_scan.gd")
	var paths = ResourceScan.list_resources("res://data/gliders")
	var r = load(paths[0])
	var s = r.get_script()
	print("HIGH: script is=", s, " null?=", s == null)
	print("HIGH: is MountData?=", r is Resource)
	print("HIGH: r.get('id')=", r.get("id"))
	print("HIGH: typeof id=", typeof(r.get("id")))
	if s != null:
		print("HIGH: script_path=", (s as Script).resource_path, " valid=", (s as Script).can_instantiate())
	quit(0)
