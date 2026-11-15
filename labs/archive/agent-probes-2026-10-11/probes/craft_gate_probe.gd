extends SceneTree
func _initialize() -> void:
	await process_frame
	await process_frame
	var cs = root.get_node_or_null("CraftingService")
	var inv_svc = root.get_node_or_null("InventoryService")
	var InvComp = load("res://core/components/inventory_component.gd")
	var bag = InvComp.new(); bag.set_owner_id("dbg_gate")
	inv_svc.register_inventory("dbg_gate", bag)
	var broke: Variant = cs.craft("dbg_gate", "recipe_iron_ingot")
	print("BROKE:", broke)
	quit(0)
