extends SceneTree
func _initialize() -> void:
	await process_frame
	var proj = root.get_node_or_null("WorldStateProjection")
	if proj == null:
		push_error("NO PROJ"); quit(1); return
	var ws = proj.world_state()
	var written: Variant = ws.set_world_state("main", "probe_debug_x", {"actor": "dbg"}, "dbg", 0.0)
	var keys: PackedStringArray = ws.world_state_keys("main")
	var got: Dictionary = ws.get_world_state("main", "probe_debug_x")
	print("SET:", written)
	print("KEYS_COUNT:", keys.size(), " HAS_DEBUG:", keys.has("probe_debug_x"))
	print("GOT:", got)
	var ds = root.get_node_or_null("DataService")
	var bs = root.get_node_or_null("BlacksmithService")
	var inv_svc = root.get_node_or_null("InventoryService")
	var InvComp = load("res://core/components/inventory_component.gd")
	var b = InvComp.new(); b.set_owner_id("wsdbg")
	inv_svc.register_inventory("wsdbg", b)
	var wep = ds.get_item("wep_iron_sword").duplicate()
	var sac = wep.duplicate(); sac.weapon_damage_max = int(sac.weapon_damage_max)+1
	b.add_item(wep,1); b.add_item(sac,1); b.add_item(ds.get_item("res_iron_ore"),2)
	var res: Variant = bs.attempt_upgrade("wsdbg", b, wep, sac, ds.get_item("res_iron_ore"))
	print("RES:", res)
	for k in ws.world_state_keys("main"):
		if str(k).begins_with("forge/"):
			print("FORGEKEY:", k, " -> ", ws.get_world_state("main", str(k)))
	quit(0)
