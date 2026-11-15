extends SceneTree
func _initialize() -> void:
	await process_frame
	await process_frame
	var ds = root.get_node_or_null("DataService")
	var inv_svc = root.get_node_or_null("InventoryService")
	var bs = root.get_node_or_null("BlacksmithService")
	var InvComp = load("res://core/components/inventory_component.gd")
	var bag = InvComp.new()
	bag.set_owner_id("dbg3")
	inv_svc.register_inventory("dbg3", bag)
	var base = ds.get_item("wep_iron_sword")
	var t = base.duplicate()
	t.id = "probe_target"
	var s = base.duplicate()
	s.id = "probe_sac"
	s.weapon_damage_max = int(s.weapon_damage_max) + 1
	var myth = ds.get_item("res_ore_mythril")
	bag.add_item(t, 1)
	bag.add_item(s, 1)
	bag.add_item(myth, 2)
	print("target_min=", t.weapon_damage_min, " target_max=", t.weapon_damage_max)
	var r = bs.attempt_upgrade("dbg3", bag, t, s, myth)
	print("RESULT=", r)
	print("t_max_after=", t.weapon_damage_max, " level=", t.upgrade_level)
	quit(0)
