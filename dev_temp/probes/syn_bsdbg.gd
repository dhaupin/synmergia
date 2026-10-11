extends SceneTree
func _count_id(bag, item_id: String) -> int:
	var total := 0
	for slot in bag._inventory:
		if slot != null and str(slot.id) == item_id:
			total += maxi(1, int(slot.current_stack))
	return total
func _initialize() -> void:
	await process_frame
	await process_frame
	var ds = root.get_node_or_null("DataService")
	var inv_svc = root.get_node_or_null("InventoryService")
	var bs = root.get_node_or_null("BlacksmithService")
	var InvComp = load("res://core/components/inventory_component.gd")
	var bag = InvComp.new()
	bag.set_owner_id("dbg_forge")
	inv_svc.register_inventory("dbg_forge", bag)
	var target = ds.get_item("wep_rusted_sword")
	var sac = ds.get_item("wep_rusted_sword")
	print("target=", target, " sac=", sac)
	var ore = ds.get_item("res_iron_ore")
	var myth = ds.get_item("res_ore_mythril")
	print("ore=", ore, " mythril=", myth)
	bag.add_item(target, 1)
	bag.add_item(sac, 1)
	bag.add_item(ore, 6)
	bag.add_item(myth, 1)
	var r = bs.attempt_upgrade("dbg_forge", bag, target, sac, myth)
	print("RESULT=", r)
	print("ore_left=", _count_id(bag, "res_iron_ore"), " myth_left=", _count_id(bag, "res_ore_mythril"))
	quit(0)
