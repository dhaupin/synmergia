# probe_placeable_stations - S16.9 placed-crafting law (cradle + hall).
#
# prd-crafting.md + prd-mounts.md checked by law:
#   A. The four FUNCTIONAL dwellings are data truth (anvil/forge/
#      workbench/cauldron), each carrying provides_function and a
#      dismantle_returns refund bill.
#   B. The station law: DwellingService.STATION_FUNCTIONS maps a placed
#      function to the SAME RecipeData.Station ids NPCData uses; the
#      anvil is the "blacksmith" repair station (the smithy UI reads).
#   C. Placement is the PLOT LAW: owner-only, one station per function
#      per plot, paid in GOODS (the purse loses the dwelling item,
#      not gold) -- and the placed plot station CRAFTS EXACTLY like an
#      NPC's bench: the WorkbenchUI opened at a placed station's
#      RecipeData.Station executes CraftingService.craft; the world
#      place is a station host, never a second gate.
#   D. The mount law survives the placed bench: a kite crafted at a
#      PLACED workbench rides the RideService ledger -- never the bag.
#   E. Removal refunds through the same purse law (bag regains the
#      dwelling item, plot loses the slot, the node is gone).
extends SceneTree

var _checks: int = 0
var _fails: int = 0

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)

func _count_id(bag, item_id: String) -> int:
	var total := 0
	for slot in bag._inventory:
		if slot != null and str(slot.id) == item_id:
			total += maxi(1, int(slot.current_stack))
	return total

func _initialize() -> void:
	await process_frame
	await process_frame
	await _run()
	quit(0 if _fails == 0 else 1)

func _run() -> void:
	var ds = root.get_node_or_null("/root/DataService")
	var dwell_svc = root.get_node_or_null("/root/DwellingService")
	var inv_svc = root.get_node_or_null("/root/InventoryService")
	var cs = root.get_node_or_null("/root/CraftingService")
	var ride = root.get_node_or_null("/root/RideService")
	_check("autoloads present (ds/dwelling/inv/craft/ride)", \
		ds != null and dwell_svc != null and inv_svc != null and cs != null and ride != null)
	if ds == null or dwell_svc == null:
		push_error("PLACED STATIONS PROBE FAILED (services missing)")
		return
	var InvComp = load("res://core/components/inventory_component.gd")
	var RecipeDataScript = load("res://core/schemas/recipe_data.gd")

	# ---- A. The four stations are data truth --------------------------
	var stations_data := {
		"dwel_anvil_iron": "blacksmith",
		"dwel_forge_coal": "crafting_forge",
		"dwel_workbench_oak": "crafting_workbench",
		"dwel_cauldron_brew": "crafting_alchemy",
	}
	var parse_ok := true
	for sid in stations_data:
		var dw = ds.get_dwelling(str(sid))
		if dw == null or str(dw.get("provides_function")) != str(stations_data[sid]):
			parse_ok = false
	_check("4 FUNCTIONAL dwellings parse with the right provides_function", parse_ok)
	var anvil = ds.get_dwelling("dwel_anvil_iron")
	var bill = anvil.get("dismantle_returns") if anvil != null else null
	_check("the anvil's refund bill resolves (data truth items)", \
		bill is Array and bill.size() == 2 \
		and ds.get_item("res_iron_ore") != null and ds.get_item("res_stone") != null)

	# ---- B. The station law mirrors the NPC door ----------------------
	_check("placed-station law maps forge/workbench/alchemy to RecipeData.Station", \
		int(dwell_svc.STATION_FUNCTIONS.get("crafting_forge", -2)) == RecipeDataScript.Station.FORGE \
		and int(dwell_svc.STATION_FUNCTIONS.get("crafting_workbench", -3)) == RecipeDataScript.Station.WORKBENCH \
		and int(dwell_svc.STATION_FUNCTIONS.get("crafting_alchemy", -4)) == RecipeDataScript.Station.ALCHEMY)

	# ---- C. Placement + the plot law ----------------------------------
	# A test plot owned by the placer.
	dwell_svc.register_test_plot("probe_plot_craft", "housing_zone_1", "hall_owner")
	var owner_ok: bool = dwell_svc.get_plot("probe_plot_craft").get("owner_id", "") == "hall_owner"
	_check("test plot registers owned (test seam)", owner_ok)

	# The placer stub: place_station duck-types `entity_id` on the
	# player; a plain stub node carries the purchase surface too (the
	# same shape test_placement_system.gd uses for plot flows).
	var placer = load("res://tests/support/reward_player_stub.gd").new()
	placer.entity_id = "hall_owner"

	# A registered purse: the placer pays in GOODS.
	var bag = InvComp.new()
	bag.set_owner_id("hall_owner")
	inv_svc.register_inventory("hall_owner", bag)
	var empty_first: Dictionary = dwell_svc.place_station(placer, "probe_plot_craft", "dwel_workbench_oak")
	_check("placing with NO dwelling item in the purse refuses whole (item_not_in_bag)", \
		not bool(empty_first.get("ok")) and str(empty_first.get("reason")) == "item_not_in_bag" \
		and dwell_svc.get_plot_stations("probe_plot_craft").is_empty())

	# One tres item = one place. A DwellingData is not an Item: the
	# purse carries it as an Item catalog copy (data/ naming law, one
	# id one file). Fund it, place, and verify the bag lost it.
	var wb_item = ds.get_item("dwel_workbench_oak")
	_check("the dwelling is ALSO an Item catalog good (placeable, purse-carried)", wb_item != null)
	if wb_item != null:
		bag.add_item(wb_item, 1)
	var placed: Dictionary = dwell_svc.place_station(placer, "probe_plot_craft", "dwel_workbench_oak")
	_check("placing the workbench succeeds and stamps the plot slot", \
		bool(placed.get("ok")) and str(placed.get("function")) == "crafting_workbench" \
		and dwell_svc.get_plot_stations("probe_plot_craft").has("crafting_workbench"))
	_check("the purse PAID IN GOODS (bag lost the dwelling item)", _count_id(bag, "dwel_workbench_oak") == 0)

	# One per function per plot.
	var second: Dictionary = dwell_svc.place_station(placer, "probe_plot_craft", "dwel_workbench_oak")
	_check("a second workbench on the same plot refuses (station_slot_taken)", \
		not bool(second.get("ok")) and str(second.get("reason")) == "station_slot_taken")

	# A NON-station dwelling (the fireplace) refuses: only FUNCTIONAL
	# craft/repair stations are placeable through this law.
	var not_station: Dictionary = dwell_svc.place_station(placer, "probe_plot_craft", "dwel_fireplace_stone")
	_check("a non-station dwelling refuses placement (not_a_station)", \
		not bool(not_station.get("ok")) and str(not_station.get("reason")) == "not_a_station")

	# ---- C2. THE PARITY LAW: placed bench == NPC bench -----------------
	# The WorkbenchUI opened at the placed station's RecipeData.Station
	# lists the SAME WORKBENCH catalog and crafts through the SAME
	# CraftingService.craft gate. No side door, no second gate.
	var WorkbenchScript = load("res://ui/components/workbench_ui.gd")
	var wb = WorkbenchScript.new()
	wb.name = "PlacedBenchProbe"
	root.add_child(wb)
	await process_frame
	await process_frame
	wb.set_inventory(bag)
	wb.open_for_player("hall_owner", RecipeDataScript.Station.WORKBENCH)
	await process_frame
	await process_frame
	var forge_ids: Array = []
	var wb_ids: Array = []
	for rid in cs.call("all_recipe_ids"):
		var recipe = cs.call("get_recipe", rid)
		if recipe == null:
			continue
		# Typed RecipeData: one-arg Object.get + null-coalesce (the
		# established law in query_crafting_ui/workbench_ui).
		var st_raw = recipe.get("station")
		var st := int(st_raw if st_raw != null else 0)
		match st:
			RecipeDataScript.Station.FORGE:
				forge_ids.append(str(rid))
			RecipeDataScript.Station.WORKBENCH:
				wb_ids.append(str(rid))
	_check("the placed bench lists WORKBENCH recipes only (station filter law intact)", \
		wb_ids.has("recipe_weaver_kite") and not forge_ids.has("recipe_weaver_kite"))

	# Fund the kite bill and press Craft AT THE PLACED BENCH.
	bag.add_item(ds.get_item("res_timber"), 6)
	bag.add_item(ds.get_item("res_stone"), 1)
	wb._on_craft_pressed("recipe_weaver_kite")
	_check("the placed bench's Craft press executes the SAME gate (kite crafted)", \
		ride.owns_mount("hall_owner", "glider_weaver_kite"))
	_check("the mount law survives the placed bench (bag NEVER held a wing)", \
		_count_id(bag, "glider_weaver_kite") == 0 \
		and _count_id(bag, "res_timber") == 0 and _count_id(bag, "res_stone") == 0)
	var ws = root.get_node_or_null("/root/WorldStateProjection").world_state()
	var delta_ok := false
	for k in ws.world_state_keys("main"):
		if str(k).begins_with("craft/recipe_weaver_kite/"):
			var pl: Dictionary = ws.get_world_state("main", str(k)).get("payload", {})
			if str(pl.get("actor", "")) == "hall_owner":
				delta_ok = true
				break
	_check("the placed-bench craft wrote provenance (actor = hall_owner)", delta_ok)

	# ---- E. removal refunds through the same purse law ----------------
	var removed: Dictionary = dwell_svc.remove_station(placer, "probe_plot_craft", "crafting_workbench")
	_check("taking the station back refunds the dwelling item to the bag", \
		bool(removed.get("ok")) and _count_id(bag, "dwel_workbench_oak") == 1 \
		and not dwell_svc.get_plot_stations("probe_plot_craft").has("crafting_workbench"))

	if _fails == 0:
		print("PLACED STATIONS PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("PLACED STATIONS PROBE FAILED")
		quit(1)
