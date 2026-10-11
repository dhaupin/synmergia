extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	await process_frame
	var cs = root.get_node_or_null("/root/CraftingService")
	var inv_svc = root.get_node_or_null("/root/InventoryService")
	var ride = root.get_node_or_null("/root/RideService")
	var ds = root.get_node_or_null("/root/DataService")
	print("cs=", cs, " inv=", inv_svc, " ride=", ride, " ds=", ds)
	var m = root.get_node_or_null("/root/DataService")
	await process_frame
	var mount = ds.get_mount("glider_weaver_kite") if ds != null else null
	print("mount lookup: ", mount)
	if mount != null:
		print("mount id=", mount.id)
	var inv = inv_svc.get_inventory("dbg_kite")
	print("inv=", inv)
	var r = cs.craft("dbg_kite", "recipe_weaver_kite")
	print("craft=", r)
	print("mount after: ", ds.get_mount("glider_weaver_kite"))
	print("owns after craft: ", ride.owns_mount("dbg_kite", "glider_weaver_kite"))
	quit(0)
