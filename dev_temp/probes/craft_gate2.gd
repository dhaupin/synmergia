extends SceneTree
func _initialize() -> void:
	await process_frame
	await process_frame
	var cs = root.get_node_or_null("CraftingService")
	var inv_svc = root.get_node_or_null("InventoryService")
	var InvComp = load("res://core/components/inventory_component.gd")
	var bag = InvComp.new(); bag.set_owner_id("dbg_gate2")
	inv_svc.register_inventory("dbg_gate2", bag)
	var broke: Dictionary = cs.craft("dbg_gate2", "recipe_iron_ingot")
	print("ATT:", broke["attempts"], " TYPE:", typeof(broke["attempts"]), " RES:", broke["results"])
	quit(0)
