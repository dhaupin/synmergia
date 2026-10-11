extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var ResourceScan = load("res://core/frame/srv/resource_scan.gd")
	var paths = ResourceScan.list_resources("res://data/gliders")
	var r = load(paths[0])
	var s = r.get_script()
	print("HIGH: global_name=", (s as Script).get_global_name())
	print("HIGH: instance_has?=", (s as Script).instance_has(r))
	var m = load("res://data/mounts/mount_gullwing.tres")
	print("HIGH: mount global_name=", (m.get_script() as Script).get_global_name())
	quit(0)
