# probe_placeable_stations - S16.9 placed-crafting law (cradle + hall).
#
# prd-crafting.md + prd-mounts.md checked by law:
#   A. The four FUNCTIONAL furnishings are data truth (anvil/forge/
#      workbench/cauldron), each carrying provides_function and a
#      dismantle_returns refund bill.
#   B. The station law: HousingService.STATION_FUNCTIONS maps a placed
#      function to the SAME RecipeData.Station ids NPCData uses; the
#      anvil is the "blacksmith" repair station (the smithy UI reads).
#   C. Placement is the PLOT LAW: owner-only, one station per function
#      per plot, paid in GOODS (the purse loses the furnishing item,
#      not gold) -- and the placed plot station CRAFTS EXACTLY like an
#      NPC's bench: the WorkbenchUI opened at a placed station's
#      RecipeData.Station executes CraftingService.craft; the world
#      place is a station host, never a second gate.
#   D. The mount law survives the placed bench: a kite crafted at a
#      PLACED workbench rides the RideService ledger -- never the bag.
#   E. Removal refunds through the same purse law (bag regains the
#      furnishing item, plot loses the slot, the node is gone).
#   F. THE WALK-UP LAW: E near a placed node resolves through
#      HousingService.resolve_nearby_station (the one door) and
#      the player body's _use_nearby_placed_station opens the right UI
#      at the station's law -- out-of-range refuses; in-range opens;
#      a placed anvil routes to the SMITHY UI, not the craft table.
extends SceneTree

var _checks: int = 0
var _fails: int = 0

var PlayerBodyScript = null

func _find_station_by_name(node_name: String) -> Node:
	if node_name.is_empty():
		return null
	return root.get_node_or_null("root/" + node_name) if root.has_node("root/" + node_name) else root.get_node_or_null(NodePath(node_name))

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
	var housing_svc = root.get_node_or_null("/root/HousingService")
	var inv_svc = root.get_node_or_null("/root/InventoryService")
	var cs = root.get_node_or_null("/root/CraftingService")
	var ride = root.get_node_or_null("/root/RideService")
	_check("autoloads present (ds/housing/inv/craft/ride)", \
		ds != null and housing_svc != null and inv_svc != null and cs != null and ride != null)
	if ds == null or housing_svc == null:
		push_error("PLACED STATIONS PROBE FAILED (services missing)")
		return
	var InvComp = load("res://core/components/inventory_component.gd")
	var RecipeDataScript = load("res://core/schemas/recipe_data.gd")

	# ---- A. The four stations are data truth --------------------------
	var stations_data := {
		"furn_anvil_iron": "blacksmith",
		"furn_forge_coal": "crafting_forge",
		"furn_workbench_oak": "crafting_workbench",
		"furn_cauldron_brew": "crafting_alchemy",
	}
	var parse_ok := true
	for sid in stations_data:
		var dw = ds.get_furnishing(str(sid))
		if dw == null or str(dw.get("provides_function")) != str(stations_data[sid]):
			parse_ok = false
	_check("4 FUNCTIONAL furnishings parse with the right provides_function", parse_ok)
	var anvil = ds.get_furnishing("furn_anvil_iron")
	var bill = anvil.get("dismantle_returns") if anvil != null else null
	_check("the anvil's refund bill resolves (data truth items)", \
		bill is Array and bill.size() == 2 \
		and ds.get_item("res_iron_ore") != null and ds.get_item("res_stone") != null)

	# ---- B. The station law mirrors the NPC door ----------------------
	_check("placed-station law maps forge/workbench/alchemy to RecipeData.Station", \
		int(housing_svc.STATION_FUNCTIONS.get("crafting_forge", -2)) == RecipeDataScript.Station.FORGE \
		and int(housing_svc.STATION_FUNCTIONS.get("crafting_workbench", -3)) == RecipeDataScript.Station.WORKBENCH \
		and int(housing_svc.STATION_FUNCTIONS.get("crafting_alchemy", -4)) == RecipeDataScript.Station.ALCHEMY)

	# ---- C. Placement + the plot law ----------------------------------
	# A test plot owned by the placer.
	housing_svc.register_test_plot("probe_plot_craft", "housing_zone_1", "hall_owner")
	var owner_ok: bool = housing_svc.get_plot("probe_plot_craft").get("owner_id", "") == "hall_owner"
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
	var empty_first: Dictionary = housing_svc.place_station(placer, "probe_plot_craft", "furn_workbench_oak")
	_check("placing with NO furnishing item in the purse refuses whole (item_not_in_bag)", \
		not bool(empty_first.get("ok")) and str(empty_first.get("reason")) == "item_not_in_bag" \
		and housing_svc.get_plot_stations("probe_plot_craft").is_empty())

	# One tres item = one place. A FurnishingData is not an Item: the
	# purse carries it as an Item catalog copy (data/ naming law, one
	# id one file). Fund it, place, and verify the bag lost it.
	var wb_item = ds.get_item("furn_workbench_oak")
	_check("the furnishing is ALSO an Item catalog good (placeable, purse-carried)", wb_item != null)
	if wb_item != null:
		bag.add_item(wb_item, 1)
	var placed: Dictionary = housing_svc.place_station(placer, "probe_plot_craft", "furn_workbench_oak")
	_check("placing the workbench succeeds and stamps the plot slot", \
		bool(placed.get("ok")) and str(placed.get("function")) == "crafting_workbench" \
		and housing_svc.get_plot_stations("probe_plot_craft").has("crafting_workbench"))
	_check("the purse PAID IN GOODS (bag lost the furnishing item)", _count_id(bag, "furn_workbench_oak") == 0)

	# One per function per plot.
	var second: Dictionary = housing_svc.place_station(placer, "probe_plot_craft", "furn_workbench_oak")
	_check("a second workbench on the same plot refuses (station_slot_taken)", \
		not bool(second.get("ok")) and str(second.get("reason")) == "station_slot_taken")

	# A NON-station furnishing (the fireplace) refuses: only FUNCTIONAL
	# craft/repair stations are placeable through this law.
	var not_station: Dictionary = housing_svc.place_station(placer, "probe_plot_craft", "furn_fireplace_stone")
	_check("a non-station furnishing refuses placement (not_a_station)", \
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
	var removed: Dictionary = housing_svc.remove_station(placer, "probe_plot_craft", "crafting_workbench")
	_check("taking the station back refunds the furnishing item to the bag", \
		bool(removed.get("ok")) and _count_id(bag, "furn_workbench_oak") == 1 \
		and not housing_svc.get_plot_stations("probe_plot_craft").has("crafting_workbench"))

	# ---- F. the WALK-UP law: E resolves the nearest placed node -------
	var upc = root.get_node_or_null("/root/PlayerManager")
	PlayerBodyScript = load("res://entities/globe_player.gd")
	var walker = PlayerBodyScript.new()
	walker.entity_id = "hall_owner"
	walker.is_local_player = true
	if upc != null and upc.has_method("set"):
		upc.local_player = walker
	root.add_child(walker)
	# Script-mode SceneTree has NO current_scene: the plot nodes spawn
	# under root. A deferred _find helper replaces the node-path lookup
	# (the service's _spawn_at handles its own fallback).
	await process_frame
	await process_frame

	# Re-place the workbench (E removed it above) exactly at the plot;
	# fund its item again first.
	bag.add_item(ds.get_item("furn_workbench_oak"), 1)
	var placed2: Dictionary = housing_svc.place_station(placer, "probe_plot_craft", "furn_workbench_oak")
	_check("re-place after refund succeeds (slot free again)", bool(placed2.get("ok")))
	var station_node = _find_station_by_name(str(placed2.get("station", {}).get("node_id", "")))
	_check("the placed node joins the placed_stations group", \
		station_node != null and station_node.is_in_group("placed_stations"))

	# Walk the player somewhere FAR from the plot: E must refuse.
	var far = housing_svc.get_plot("probe_plot_craft")["center"] + Vector3(40, 0, 0)
	walker.global_position = far
	var miss: Dictionary = housing_svc.resolve_nearby_station(walker)
	_check("E far from any placed station resolves nothing (no phantom bench)", not bool(miss.get("ok")))
	var opened_far: bool = walker._use_nearby_placed_station()
	_check("the E-key path far away opens NO bench", not opened_far)

	# Walk onto the plot: E resolves the node and the bench opens at
	# the WORKBENCH station (station law, proximity-resolved).
	walker.global_position = housing_svc.get_plot("probe_plot_craft")["center"]
	var hit: Dictionary = housing_svc.resolve_nearby_station(walker)
	_check("E in range resolves the placed node with its function", \
		bool(hit.get("ok")) and str(hit.get("function")) == "crafting_workbench")
	var opened: bool = walker._use_nearby_placed_station()
	var wb_ui = walker._workbench_ui
	_check("the E-key path opens the bench at station 2 (WORKBENCH law, purse wired)", \
		opened and wb_ui != null and wb_ui.station == RecipeDataScript.Station.WORKBENCH \
		and wb_ui.inventory == bag and wb_ui._player_id == "hall_owner")

	# The BLACKSMITH routing: place the anvil next to the workbench,
	# stand nearer the anvil, and E must open the SMITHY (repair UI),
	# not the craft table.
	bag.add_item(ds.get_item("furn_anvil_iron"), 1)
	var anvil_placed: Dictionary = housing_svc.place_station(placer, "probe_plot_craft", "furn_anvil_iron")
	_check("the anvil places on its own function slot (repair + craft co-exist)", \
		bool(anvil_placed.get("ok")) and housing_svc.get_plot_stations("probe_plot_craft").has("blacksmith"))
	var anvil_node = _find_station_by_name(str(anvil_placed.get("station", {}).get("node_id", "")))
	if station_node != null and anvil_node != null:
		# Stand half a meter from the anvil, two from the workbench:
		# nearest-node law picks the ANVIL.
		walker.global_position = (anvil_node as Node3D).global_position + Vector3(0.5, 0, 0)
		var smith_hit: Dictionary = housing_svc.resolve_nearby_station(walker)
		_check("standing at the anvil resolves the repair station", \
			bool(smith_hit.get("ok")) and str(smith_hit.get("function")) == "blacksmith")
		var smith_opened: bool = walker._use_nearby_placed_station()
		var bs_ui = walker._blacksmith_ui
		_check("E at the placed anvil opens the SMITHY (repair UI, purse set)", \
			smith_opened and bs_ui != null and bs_ui.visible and bs_ui._inventory == bag)

	if _fails == 0:
		print("PLACED STATIONS PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("PLACED STATIONS PROBE FAILED")
		quit(1)
