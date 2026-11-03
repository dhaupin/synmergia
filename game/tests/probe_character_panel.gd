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
## E. LIVE-TRUTH STATS (issue #21): the stats tab must read the
##    character AS THEY ARE -- level-aware totals at the LIVE level
##    (restored progress can outrun the creation-time CharacterData)
##    plus the gear delta the live bag applies -- the same book
##    InventoryComponent pushes onto the player. Real gear goes
##    through a real bag; the derived stats route the same merged
##    book (one formula source, no forked math).
##
## NOTE: probe scripts compile BEFORE autoloads register -- bare
## autoload identifiers are a compile error here. Resolve services via
## root.get_node_or_null (the documented --script pattern).
##
## Run: godot --headless --path game --script res://tests/probe_character_panel.gd
extends SceneTree

var _checks := 0


func _check(label: String, cond: bool, detail: String = "") -> bool:
	_checks += 1
	var line := "  %s %s" % ["PASS" if cond else "FAIL", label]
	if not cond and not detail.is_empty():
		line += " <" + detail + ">"
	print(line)
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

	# --- E. LIVE-TRUTH STATS (issue #21) --------------------------------
	# The stats cards must read the character AS THEY ARE: level-aware
	# totals at the LIVE level (the creation-time CharacterData stays
	# behind on purpose) plus the gear delta the live bag applies.
	var CharacterDataScript = load("res://core/schemas/character_data.gd")
	var cd = CharacterDataScript.new()
	cd.character_id = "probe_cp_live"
	cd.level = 1  # the stale creation-time book, deliberately
	var l1_total: int = cd.get_stat_total("strength", 1)
	ok = _check("E1 load_class totals resolve", l1_total > 0) and ok
	var l7: int = cd.get_stat_total("strength", 7)
	ok = _check("E2 totals ride the level law", l7 > l1_total) and ok

	# Real gear through the REAL bag: the sword boots +5 strength and
	# the ring +2 vitality into get_equipment_stats -- the same book
	# InventoryComponent pushes onto the player.
	var sword = load("res://data/weapons/wep_iron_sword.tres")
	var ring = load("res://data/accessories/acc_ring_first_light.tres")
	ok = _check("E3 real gear loads as items", sword != null and ring != null) and ok
	var added_sw: bool = bag.add_item(sword)
	var added_rg: bool = bag.add_item(ring)
	ok = _check("E4 gear enters the bag", added_sw and added_rg) and ok
	# The Apple from leg B owns slot 0 -- equip each piece from its own
	# actual bag slot, never an assumed index.
	var sw_slot := -1
	var rg_slot := -1
	for slot in range(bag._inventory.size()):
		var held = bag._inventory[slot]
		if held != null and held.id == sword.id:
			sw_slot = slot
		elif held != null and held.id == ring.id:
			rg_slot = slot
	var eq_sw: bool = inv_svc.get_inventory("probe_cp_1").equip_item(sw_slot)
	var eq_rg: bool = inv_svc.get_inventory("probe_cp_1").equip_item(rg_slot)
	ok = _check("E5 bag equips both pieces", eq_sw and eq_rg) and ok
	var gear_now: Dictionary = inv_svc.get_inventory("probe_cp_1").get_equipment_stats()
	ok = _check("E6 equipment stats read +5 str / +2 vit",
		int(gear_now.get("strength", 0)) == 5
		and int(gear_now.get("vitality", 0)) == 2) and ok

	# A live player whose progress level outran the book: entity_id
	# stays probe_cp_1 so the bag wiring above still resolves.
	var live_src := GDScript.new()
	live_src.source_code = "extends Node\nvar entity_id: String = \"probe_cp_1\"\nvar level: int = 7\n"
	live_src.reload()
	var live_player = live_src.new()
	live_player.name = "ProbeLivePlayer"
	root.add_child(live_player)
	pm.set_local_player(live_player)

	panel.set_character_data(cd)
	panel._show_tab(panel.Tab.STATS)
	await process_frame

	var str_card = panel.find_child("Stat_str", true, false)
	var str_val = str_card.get_node_or_null("HBox/VBox/Value") if str_card != null else null
	var str_expect: int = cd.get_stat_total("strength", 7) + 5
	ok = _check("E7 strength card shows live level + gear",
		str_val != null and str_val.text == "%d (+5 gear)" % str_expect,
		"card=%s value=%s text=%s" % [str_card != null, str_val != null,
		str_val.text if str_val != null else ""]) and ok
	var vit_card = panel.find_child("Stat_vit", true, false)
	var vit_val = vit_card.get_node_or_null("HBox/VBox/Value") if vit_card != null else null
	var vit_expect: int = cd.get_stat_total("vitality", 7) + 2
	ok = _check("E8 vitality card shows gear",
		vit_val != null and vit_val.text == "%d (+2 gear)" % vit_expect,
		"card=%s value=%s text=%s" % [vit_card != null, vit_val != null,
		vit_val.text if vit_val != null else ""]) and ok

	var name_lbl2 = panel.find_child("CharName", true, false)
	ok = _check("E9 header rides the LIVE level (7, not the book's 1)",
		name_lbl2 != null and str(name_lbl2.text).ends_with("- Level 7"),
		"text=%s" % (str(name_lbl2.text) if name_lbl2 != null else "")) and ok

	# Derived stats route the SAME merged book in (max_health is the
	# expected answer, not a forked formula).
	var merged_expect: Dictionary = {
		"strength": cd.get_stat_total("strength", 7) + 5,
		"intelligence": cd.get_stat_total("intelligence", 7),
		"wisdom": cd.get_stat_total("wisdom", 7),
		"agility": cd.get_stat_total("agility", 7),
		"vitality": cd.get_stat_total("vitality", 7) + 2,
		"endurance": cd.get_stat_total("endurance", 7)
	}
	var mh_expect: int = int(cd.get_derived_stats(merged_expect).get("max_health", 0))
	var mh_row = panel.find_child("Derived_max_health", true, false)
	var mh_val = mh_row.get_node_or_null("Value") if mh_row != null else null
	ok = _check("E10 derived max health uses the merged live book",
		mh_val != null and mh_val.text == str(mh_expect) and mh_expect > 100,
		"text=%s expect=%d" % [mh_val.text if mh_val != null else "", mh_expect]) and ok

	print("probe_character_panel: %d checks, %s" % [_checks, "PASS" if ok else "FAIL"])
	quit(0 if ok else 1)
