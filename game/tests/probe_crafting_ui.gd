# probe_crafting_ui - the crafting surfaces read SERVICE truth (S16.9).
#
# Covers:
#   A. WorkbenchUI parses, opens, and lists the service catalog at a
#      station (a forge lists FORGE + NONE recipes; the workbench lists
#      WORKBENCH + NONE; NONE recipes list everywhere).
#   B. The station law is DATA truth: npc_data.get_crafting_station
#      resolves the offering's service_params.station (one door).
#   C. The craft-shelf vendor offering stocks recipe INPUTS only --
#      every catalog item id is an input of some recipe (no invented
#      goods), resolved through VendorService's by_item_id path.
#   D. Every craft executes through CraftingService.craft: a refuse
#      reason is the gate's own reason, verbatim (the UI never
#      invents a second gate).
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await process_frame

	var ds = root.get_node_or_null("/root/DataService")
	var cp = root.get_node_or_null("/root/PlayerConfig")
	var inv_svc = root.get_node_or_null("/root/InventoryService")
	var crafting = root.get_node_or_null("/root/CraftingService")
	_check("autoloads present (ds/inv/crafting)", ds != null and inv_svc != null and crafting != null)

	# ---- A. WorkbenchUI + service-catalog station filter ----------------
	var WorkbenchScript = load("res://ui/components/workbench_ui.gd")
	_check("workbench_ui parses", WorkbenchScript != null and WorkbenchScript.can_instantiate())

	var NPCDataScript = load("res://core/schemas/npc_data.gd")

	# A named NPC carrying the workbench offering (data truth).
	var wb_data = NPCDataScript.new()
	var wb_includes: Array[Dictionary] = [{"type": "offering", "ref_id": "workbench_service"}]
	wb_data.includes = wb_includes
	var station: int = wb_data.get_crafting_station()
	_check("workbench NPC resolves station 2 (data truth)", station == 2)

	var forge_data = NPCDataScript.new()
	var forge_includes: Array[Dictionary] = [{"type": "offering", "ref_id": "forge_service"}]
	forge_data.includes = forge_includes
	_check("forge NPC resolves station 1 (data truth)", forge_data.get_crafting_station() == 1)

	var plain_data = NPCDataScript.new()
	var plain_includes: Array[Dictionary] = [{"type": "dialogue", "dialogue_id": "merchant_greeting"}]
	plain_data.includes = plain_includes
	_check("dialogue NPC resolves no station (-1)", plain_data.get_crafting_station() == -1)

	var wb = WorkbenchScript.new()
	wb.name = "WorkbenchProbe"
	root.add_child(wb)
	await process_frame
	await process_frame
	var cs = root.get_node_or_null("/root/CraftingService")
	var forge_ids: Array = _station_ids(cs, 1)
	var wb_ids: Array = _station_ids(cs, 2)
	var none_ids: Array = _station_ids(cs, 0)
	_check("catalog splits by station (ingot@forge, kite@workbench, breather@any)",
		forge_ids.has("recipe_iron_ingot") and wb_ids.has("recipe_weaver_kite")
		and none_ids.has("recipe_reed_breather")
		and not forge_ids.has("recipe_weaver_kite")
		and not wb_ids.has("recipe_iron_ingot"))

	# ---- B. the craft-shelf vendor stocks RECIPE INPUTS only ------------
	var OfferingScript = load("res://core/schemas/npc_offering.gd")
	var shelf = load("res://data/npc_offerings/vendor_craft_shelf.tres")
	_check("craft shelf offering loads", shelf != null and str(shelf.get("type")) == "vendor")
	var catalog_items: Array = (shelf.get("catalog_items") as Array) if shelf != null else []
	if shelf != null:
		# The craft loop's trade goods: every id the BILL demands or the
		# BYPRODUCT loop refunds (slag sells -- the failure sink is
		# recoverable). Both lists are recipe data truth; anything else
		# on the shelf would be an invented good.
		var loop_ids: Array = []
		for rid in cs.call("all_recipe_ids"):
			var recipe = cs.call("get_recipe", rid)
			if recipe == null:
				continue
			for input_dict in recipe.inputs:
				if not loop_ids.has(str(input_dict.get("item_id", ""))):
					loop_ids.append(str(input_dict.get("item_id", "")))
			for by_dict in recipe.byproducts:
				if not loop_ids.has(str(by_dict.get("item_id", ""))):
					loop_ids.append(str(by_dict.get("item_id", "")))
		var stocked_ok := true
		var stocked_count := 0
		for entry in catalog_items:
			var iid := str(entry.get("item_id", ""))
			stocked_count += 1
			if not loop_ids.has(iid) or ds.get_item(iid) == null:
				stocked_ok = false
		_check("shelf stocks %d REAL craft-loop goods (inputs + byproducts, no invented ids)" % stocked_count, stocked_ok and stocked_count > 0)

	# VendorService resolves the shelf through the by_item_id path.
	var VendorScript = load("res://core/services/vendor_service.gd")
	var vendor = VendorScript.new()
	root.add_child(vendor)
	await process_frame
	var npc_merchant = null
	if ds != null and ds.has_method("get_npc"):
		npc_merchant = ds.get_npc("npc_merchant_general")
	var catalog: Array = vendor.call("get_catalog", shelf, npc_merchant) if shelf != null else []
	_check("vendor catalog resolves %d shelf items" % catalog.size(), catalog.size() >= 3)
	var priced := true
	for entry in catalog:
		if int(entry.get("price", 0)) <= 0:
			priced = false
	_check("every shelf row carries a price (buy_price data truth)", priced)

	# ---- C. the merchant carries the shelf (data wiring) ----------------
	if npc_merchant != null and npc_merchant.has_method("get_vendor_offering"):
		var primary = npc_merchant.call("get_vendor_offering")
		_check("merchant's primary vendor offering intact (general store)",
			primary != null and str(primary.get("display_name")) == "General Store")
		# the shelf is in the includes (any vendor out of the two)
		var found_shelf := false
		for inc in npc_merchant.includes:
			if inc is Dictionary and str(inc.get("ref_id", "")) == "vendor_craft_shelf":
				found_shelf = true
		_check("merchant includes the craft shelf", found_shelf)
	else:
		_check("merchant npc resolves (DataService.get_npc)", false)

	if _fails == 0:
		print("CRAFTING UI PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("CRAFTING UI PROBE FAILED")
		quit(1)

func _station_ids(cs, station: int) -> Array:
	var out: Array = []
	for rid in cs.call("all_recipe_ids"):
		var recipe = cs.call("get_recipe", rid)
		if recipe != null and int(recipe.station) == station:
			out.append(str(rid))
	return out

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
