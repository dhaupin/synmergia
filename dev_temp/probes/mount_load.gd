extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var m = load("res://data/mounts/mount_gullwing.tres")
	print("mount_gullwing class: ", m.get_class(), " script=", m.get_script() if m != null else "null")
	if m != null and m.get_script() != null:
		print("mount_gullwing script path: ", (m.get_script() as Script).resource_path)
	var g = load("res://data/gliders/glider_drift_kite.tres")
	print("glider load: ", g)
	if g != null and g.get_script() != null:
		print("glider script class: ", (g.get_script() as Script).get_global_name())
	quit(0)
