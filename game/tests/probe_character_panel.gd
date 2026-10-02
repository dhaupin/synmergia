## Probe: CharacterPanel tab visibility + inventory hydration.
## Play-test round 11 (post-crash screenshot: panel body blank, tabs painted).
##
## A. _show_tab must VISIBLY swap tab bodies. The old loop iterated the
##    Tab enum Dictionary (String names) against _tab_contents keyed by
##    Tab.values() (ints) -- every lookup missed and NO body was ever
##    shown. Tabs painted; body stayed blank.
## B. The Inventory grid must hydrate from the LIVE bag even when no
##    character data was ever pushed (globe single-player never sets
##    GameManager.selected_character_data). Register a bag, bind a
##    minimal local player, refresh, and read the item name off a slot.
## C. GlobeWorldPlayer binds itself to PlayerManager and exposes its bag
##    as `inventory_component` (the panel's duck-typed resolve path).
##    Without both, the globe body's bag was unreachable from the panel.
##
## NOTE: probe scripts compile BEFORE autoloads register -- bare
## autoload identifiers are a compile error here. Resolve services via
## root.get_node_or_null (the documented --script pattern).
##
## Run: godot --headless --path game --script res://tests/probe_character_panel.gd
extends SceneTree

var _checks := 0


func _check(label: String, cond: bool) -> bool:
	_checks += 1
	print("  %s %s" % ["PASS" if cond else "FAIL", label])
	return cond


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	var inv_svc = root.get_node_or_null("InventoryService")
	var pm = root.get_node_or_null("PlayerManager")
	var gm = root.get_node_or_null("GameManager")
	if inv_svc == null or pm == null or gm == null:
		print("FAIL: autoloads missing (InventoryService/PlayerManager/GameManager)")
		quit(1)
		return

	# --- A. Tab bodies actually swap ------------------------------------
	var PanelScript = load("res://ui/components/character_panel.gd")
	var panel = PanelScript.new()
	root.add_child(panel)
	await process_frame
	panel.open("")
	await process_frame

	var bodies: Array = []
	for i in range(5):
		bodies.append(panel.find_child("TabContent_%d" % i, true, false))
	var all_found := true
	for b in bodies:
		if b == null:
			all_found = false
	ok = _check("A1 all 5 tab bodies built", all_found) and ok
	if not all_found:
		print("FAIL: tab bodies missing; checks=%d" % _checks)
		quit(1)
		return
	ok = _check("A2 INVENTORY body visible on open", bodies[0].visible) and ok
	var others_hidden := true
	for i in range(1, 5):
		if bodies[i].visible:
			others_hidden = false
	ok = _check("A3 other bodies hidden on open", others_hidden) and ok
	panel._show_tab(panel.Tab.EQUIP)
	await process_frame
	ok = _check("A4 switch to EQUIP flips visibility",
		bodies[1].visible and not bodies[0].visible) and ok

	# --- B. Inventory hydrates without character data -------------------
	# Globe single-player context: no selected_character_data, one bag
	# registered under the local player's id.
	var InvComp = load("res://core/components/inventory_component.gd")
	var ItemScript = load("res://core/schemas/item.gd")
	var bag = InvComp.new()
	bag.name = "ProbeBag"
	root.add_child(bag)
	var item = ItemScript.new()
	item.display_name = "Probe Apple"
	bag.set_owner_id("probe_cp_1")
	var added: bool = bag.add_item(item)
	ok = _check("B1 probe bag accepts an item", added) and ok
	inv_svc.register_inventory("probe_cp_1", bag)

	# Minimal local player: entity_id is all PlayerManager.get_local_player_id
	# duck-types (same shape the globe body presents).
	var fake_script := GDScript.new()
	fake_script.source_code = "extends Node\nvar entity_id: String = \"probe_cp_1\"\n"
	fake_script.reload()
	var fake = fake_script.new()
	fake.name = "ProbeLocalPlayer"
	root.add_child(fake)
	pm.set_local_player(fake)

	var no_char_data: bool = gm.selected_character_data == null
	ok = _check("B2 probe runs without character data (globe shape)", no_char_data) and ok

	panel.refresh_inventory()
	await process_frame
	var grid = panel.find_child("InventoryGrid", true, false)
	ok = _check("B3 inventory grid exists", grid != null) and ok
	if grid != null and grid.get_child_count() > 0:
		var slot0 = grid.get_child(0)
		var lbl = slot0.get_node_or_null("ItemLabel")
		ok = _check("B4 slot 0 shows the live item name",
			lbl != null and lbl.text == "Probe Apple") and ok
	else:
		ok = _check("B4 slot 0 shows the live item name", false) and ok
	ok = _check("B5 no empty-hint when a bag is live",
		panel.find_child("EmptyHint", true, false) == null) and ok

	# --- C. Globe body binds PlayerManager + exposes the bag ------------
	var GlobePlayer = load("res://entities/globe_player.gd")
	var gp = GlobePlayer.new()
	root.add_child(gp)
	# The world scene stamps entity_id right after add_child.
	gp.entity_id = "probe_globe_1"
	# _register_bag is deferred 0.1 s (id must be final).
	await create_timer(0.25).timeout
	ok = _check("C1 globe body bound as local player",
		pm.get_local_player() == gp) and ok
	ok = _check("C2 local player id resolves from the body",
		pm.get_local_player_id() == "probe_globe_1") and ok
	ok = _check("C3 bag exposed as inventory_component",
		gp.inventory_component != null and gp.inventory_component.get_script() == InvComp) and ok
	ok = _check("C4 bag registered with InventoryService",
		inv_svc.get_inventory("probe_globe_1") == gp.inventory_component) and ok

	# D. The panel resolves the globe body's bag through that wiring.
	panel.refresh_inventory()
	await process_frame
	ok = _check("D1 globe bag reachable from the panel",
		panel._resolve_inventory() == gp.inventory_component) and ok

	print("probe_character_panel: %d checks, %s" % [_checks, "PASS" if ok else "FAIL"])
	quit(0 if ok else 1)
