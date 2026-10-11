extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	await process_frame
	var ds = root.get_node_or_null("/root/DataService")
	var ids := []
	for k in ds.get_all_mounts().keys():
		ids.append(str(k))
	ids.sort()
	print("HIGH: mounts=", ids)
	print("HIGH: gullwing id=", ds.get_mount("mount_gullwing") != null)
	print("HIGH: drift_kite id=", ds.get_mount("glider_drift_kite") != null)
	quit(0)
