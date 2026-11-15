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
	bag.set_owner_id("dbg2")
	inv_svc.register_inventory("dbg2", bag)
	var base = ds.get_item("wep_iron_sword")
	print("base=", base)
	var t = base.duplicate()
	var s = base.duplicate()
	s.weapon_damage_max = int(s.weapon_damage_max) + 1
	var myth = ds.get_item("res_ore_mythril")
	bag.add_item(t, 1)
	bag.add_item(s, 1)
	bag.add_item(myth, 2)
	print("in-bag check: have_t=", _count_id(bag, "wep_iron_sword"))
	var r = bs.attempt_upgrade("dbg2", bag, t, s, myth)
	print("RESULT=", r)
	quit(0)
