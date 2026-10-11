extends SceneTree
func _initialize() -> void:
	await process_frame
	await process_frame
	var cs = root.get_node_or_null("CraftingService")
	var inv_svc = root.get_node_or_null("InventoryService")
	var ride = root.get_node_or_null("RideService")
	var ds = root.get_node_or_null("DataService")
	print("DS-MOUNT:", ds.get_mount("glider_weaver_kite") != null)
	print("RIDE:", ride, " HAS-GRANT:", ride != null and ride.has_method("grant_mount"))
	var InvComp = load("res://core/components/inventory_component.gd")
	var b = InvComp.new(); b.set_owner_id("dbg_kite")
	inv_svc.register_inventory("dbg_kite", b)
	b.add_item(ds.get_item("res_timber"), 6); b.add_item(ds.get_item("res_stone"), 1)
	var r: Variant = cs.craft("dbg_kite", "recipe_weaver_kite")
	print("CRAFT:", r)
	print("OWNS:", ride.owns_mount("dbg_kite", "glider_weaver_kite"))
	quit(0)
