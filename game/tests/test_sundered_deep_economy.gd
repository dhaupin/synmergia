# test_sundered_deep_economy.gd - S14.7.1: the Sundered Sea seed pass
# (labs/prd-ocean-depths.md sec 8-10). The deep-shelf economy lands as
# DATA + SERVICES first (no fake visuals):
#
#   A. THE RADIAL WATERLINE: a world-sea volume whose waterline is the
#      planet's own sea sphere -- the seed's sea truth, resolved ONCE
#      (OceanService.sea_surface_radius == shell + TerrainGen sea level).
#   B. THE CURRENT IS THE FERRY LANE: the volume's declared vector is
#      backend_sundered's RUN tangent at 0.5 m/s, and a current-immune
#      body reads a ZERO stamp (the S14.6 immunity law, sea edition).
#   C. THE BANDS ARE HONEST AT ANY LATITUDE: depth measured down the
#      radial from the sea sphere; squeeze at 50, crush past 60.
#   D. THE DEPTH HARVEST GATES: reef kelp (30-45 m) + trench pearl
#      (50-58 m) nodes refuse BY NAME -- not_in_water / too_shallow /
#      too_deep (fail closed, no body no harvest) and pay THROUGH the
#      honest purse when the body samples inside the band.
#   E. THE ABYSSAL BREATHER LOOP: pearl x1 + kelp x8 crafts
#      acc_breather_abyss_pearl (x8 air, +20 m grace, current_immune),
#      equips into the necklace slot, and breather_for speaks it.
#
# Script mode law: autoloads at runtime (OceanService, DataService,
# HarvestService, PlayerManager, InventoryService, CraftingService);
# schema/worl/terrain scripts load() in the body, never preloaded.
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)

func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	var ds = root.get_node_or_null("DataService")
	var hs = root.get_node_or_null("HarvestService")
	var cs = root.get_node_or_null("CraftingService")
	var pm = root.get_node_or_null("PlayerManager")
	var inv_svc = root.get_node_or_null("InventoryService")
	_check("services present", svc != null and ds != null and hs != null \
		and cs != null and pm != null and inv_svc != null)
	if svc == null or ds == null or hs == null or cs == null or pm == null or inv_svc == null:
		quit(1)
		return
	if not ds._loaded:
		ds.load_all_data()
	svc.ensure_loaded()
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var BS = load("res://scenes/worlds/backend_sundered.gd")
	var OV = load("res://core/schemas/ocean_volume.gd")
	var Itm = load("res://core/schemas/item.gd")
	var InvComp = load("res://core/components/inventory_component.gd")

	var vol = svc.get_volume("ocean_sundered_sea")
	var dir: Vector3 = BS.STRAIT_CENTER.normalized()
	var sea_r: float = svc.sea_surface_radius()
	var _pos := func(depth: float) -> Vector3:
		return dir * (sea_r - depth)
	var dt: float = 1.0 / 60.0

	# ---- A. The radial waterline ------------------------------------------
	_check("the Sundered Sea loads as a volume", vol != null)
	_check("the sea is a RADIAL waterline on radial rock (the pairing law)", \
		vol != null and bool(vol.waterline_is_radial) and bool(vol.floor_is_radial))
	var want: float = 20000.0 + Gen.sea_level(Gen.world_seed_bytes())
	_check("the waterline radius is the SEED's sea truth (shell + sea level)", \
		absf(sea_r - want) < 0.001)
	var inside = svc.volume_at(_pos.call(35.0))
	_check("the 35 m strait column belongs to the Sundered Sea", \
		inside != null and str(inside.id) == "ocean_sundered_sea")
	_check("depth samples read down the radial (35 m in)", \
		absf(svc.sample_depth(_pos.call(35.0)) - 35.0) < 0.001)
	_check("the waterline sample reads NEGATIVE above the line", \
		svc.sample_depth(_pos.call(-1.0)) < 0.0)
	_check("inside the rock the sampler says STONE (-1)", \
		svc.sample_depth(dir * 19300.0) == -1.0)
	_check("the sea claims through the wading reach (+2 m) and no further", \
		svc.volume_at(_pos.call(-1.0)) != null \
		and svc.volume_at(_pos.call(-3.0)) == null)

	# ---- B. The current is the ferry lane ----------------------------------
	var lane: Vector3 = BS.RUN_DIR.normalized() * 0.5
	var here: Vector3 = svc.current_at(_pos.call(25.0))
	_check("the declared current is the RUN tangent at 0.5 m/s", \
		here.distance_to(lane) < 0.001)
	var t: Dictionary = svc.tick_swimmer("ferry_laner", _pos.call(25.0), dt)
	_check("the swimmer tick carries the lane push", \
		(t["current"] as Variant).distance_to(lane) < 0.001)
	var ti: Dictionary = svc.tick_swimmer("ferry_laner", _pos.call(25.0), dt, 0.0, 0.0, 0.0, true)
	_check("a current-immune tick stamps ZERO (the sea cannot carry it)", \
		(ti["current"] as Variant) == Vector3.ZERO)

	# ---- C. Bands are honest down the radial --------------------------------
	_check("20 m reads SUBMERGED at the strait", \
		svc.band_at(_pos.call(20.0)) == OV.DepthBand.SUBMERGED)
	_check("49 m is still the swim band (squeeze line = 60 - 10)", \
		svc.band_at(_pos.call(49.0)) == OV.DepthBand.SUBMERGED)
	_check("55 m reads SQUEEZE (the pressure tax is real)", \
		svc.band_at(_pos.call(55.0)) == OV.DepthBand.SQUEEZE)
	_check("61 m reads CRUSH (past the volume's max depth)", \
		svc.band_at(_pos.call(61.0)) == OV.DepthBand.CRUSH)

	# ---- D. The depth harvest gates -----------------------------------------
	_check("kelp + pearl items are data truth", \
		ds.get_item("res_kelp_fiber") != null and ds.get_item("res_abyss_pearl") != null)
	var kelp_id: String = hs.register_node("node_kelp_garden", "zone_sundered_strait", \
		"res_kelp_fiber", _pos.call(35.0), 3, 999999.0, 30.0, 45.0)
	var pearl_id: String = hs.register_node("node_trench_pearl", "zone_sundered_strait", \
		"res_abyss_pearl", _pos.call(55.0), 2, 999999.0, 50.0, 58.0)
	_check("both deep nodes register", kelp_id != "" and pearl_id != "")

	# The receipt body: a duck Node3D the body truth reads (entity_id +
	# global_position, the same shape the globe body presents).
	var body_script := GDScript.new()
	body_script.source_code = "extends Node3D\nvar entity_id: String = \"dd_diver\"\n"
	body_script.reload()
	var body: Node3D = body_script.new()
	root.add_child(body)
	pm.set_local_player(body)

	var diver_bag = InvComp.new()
	diver_bag.set_owner_id("dd_diver")
	inv_svc.register_inventory("dd_diver", diver_bag)

	# D1 fail closed: the body's sample is STONE -> not_in_water.
	body.position = Vector3.ZERO
	_check("harvest from dry ground refuses not_in_water", \
		hs.harvest("dd_diver", kelp_id)["reason"] == "not_in_water")
	# D2 the shallow water refuses the reef band (12 m < 30).
	body.position = _pos.call(12.0)
	var shallow: Dictionary = hs.harvest("dd_diver", kelp_id)
	_check("12 m refuses the reef garden too_shallow", \
		shallow["reason"] == "too_shallow" and float(shallow["depth_m"]) == 12.0)
	# D3 the below-floor water refuses (52 m > 45).
	body.position = _pos.call(52.0)
	_check("52 m refuses the reef garden too_deep", \
		hs.harvest("dd_diver", kelp_id)["reason"] == "too_deep")
	# D4 in-band: the body swims the garden, harvest PAYS through the purse.
	body.position = _pos.call(35.0)
	var got: Dictionary = hs.harvest("dd_diver", kelp_id)
	_check("35 m harvests the reef garden", bool(got["ok"]))
	_check("the purse holds 3 kelp fiber after the grant", _count_id(diver_bag, "res_kelp_fiber") == 3)
	_check("the node depletes and owns its provenance", hs.is_depleted(kelp_id) \
		and str(diver_bag._inventory[0].id).length() > 0)
	# D5 the trench band lets only the deep through.
	var trench_bag = InvComp.new()
	trench_bag.set_owner_id("dd_trench")
	inv_svc.register_inventory("dd_trench", trench_bag)
	body.set("entity_id", "dd_trench")
	body.position = _pos.call(59.0)
	_check("59 m refuses the trench node too_deep (58 is the ceiling)", \
		hs.harvest("dd_trench", pearl_id)["reason"] == "too_deep")
	body.position = _pos.call(55.0)
	var pearl: Dictionary = hs.harvest("dd_trench", pearl_id)
	_check("55 m harvests the trench pearl", bool(pearl["ok"]))
	_check("the trench purse holds 2 abyss pearls", _count_id(trench_bag, "res_abyss_pearl") == 2)
	# D6 no body at all: the gate fails closed blind.
	pm.set_local_player(null)
	_check("a bodyless actor cannot take the deep garden", \
		hs.harvest("dd_trench", pearl_id)["reason"] == "not_in_water")

	# ---- E. The abyssal breather loop ---------------------------------------
	var recipe = cs.get_recipe("recipe_abyssal_breather")
	_check("the breather recipe is catalog truth (1 pearl + 8 kelp, hand station)", \
		recipe != null and recipe.inputs.size() == 2 \
		and str(recipe.inputs[0]["item_id"]) == "res_abyss_pearl" \
		and int(recipe.inputs[0]["qty"]) == 1 \
		and str(recipe.inputs[1]["item_id"]) == "res_kelp_fiber" \
		and int(recipe.inputs[1]["qty"]) == 8 \
		and int(recipe.station) == 0)
	var kelp_only_bag = InvComp.new()
	kelp_only_bag.set_owner_id("dd_kelp")
	kelp_only_bag.add_item(ds.get_item("res_kelp_fiber"), 8)
	inv_svc.register_inventory("dd_kelp", kelp_only_bag)
	_check("the pearl is the scarce word: 8 kelp alone crafts nothing", \
		not bool(cs.craft("dd_kelp", "recipe_abyssal_breather")["ok"]))
	var stringer_bag = InvComp.new()
	stringer_bag.set_owner_id("dd_stringer")
	stringer_bag.add_item(ds.get_item("res_abyss_pearl"), 1)
	stringer_bag.add_item(ds.get_item("res_kelp_fiber"), 8)
	inv_svc.register_inventory("dd_stringer", stringer_bag)
	var crafted: Dictionary = cs.craft("dd_stringer", "recipe_abyssal_breather")
	_check("1 pearl + 8 kelp crafts the abyssal breather", bool(crafted["ok"]))
	_check("the bill leaves the bag empty of reagents", \
		_count_id(stringer_bag, "res_abyss_pearl") == 0 \
		and _count_id(stringer_bag, "res_kelp_fiber") == 0)
	var slot: int = stringer_bag.find_item("acc_breather_abyss_pearl")
	_check("the breather equips into the necklace slot", \
		slot >= 0 and bool(stringer_bag.equip_item(slot)) \
		and str(stringer_bag.get_equipped(Itm.EquipSlot.NECKLACE).id) == "acc_breather_abyss_pearl")
	var defa: Dictionary = svc.breather_for("dd_diver")
	_check("a bare bag reads the default breather law", \
		absf(float(defa["mult"]) - 1.0) < 1e-9 and absf(float(defa["grace_m"])) < 1e-9 \
		and bool(defa["current_immune"]) == false)
	var br: Dictionary = svc.breather_for("dd_stringer")
	_check("the pearl breather speaks x8 air, +20 m grace, current immunity", \
		absf(float(br["mult"]) - 8.0) < 1e-9 and absf(float(br["grace_m"]) - 20.0) < 1e-9 \
		and bool(br["current_immune"]))
	_check("an un-equip resets the breather law (equipment truth, not history)", \
		(bool(stringer_bag.unequip_item(int(Itm.EquipSlot.NECKLACE))) \
		and bool(svc.breather_for("dd_stringer")["current_immune"]) == false))

	# ---- The book rests clean ------------------------------------------------
	svc.forget_swimmer("ferry_laner")
	inv_svc.unregister_inventory("dd_diver")
	inv_svc.unregister_inventory("dd_trench")
	inv_svc.unregister_inventory("dd_kelp")
	inv_svc.unregister_inventory("dd_stringer")

	if _fails == 0:
		print("SUNDERED DEEP RECEIPT PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("SUNDERED DEEP RECEIPT FAILED")
		quit(1)

func _count_id(bag, item_id: String) -> int:
	var total := 0
	for slot in bag._inventory:
		if slot != null and str(slot.id) == item_id:
			total += maxi(1, int(slot.current_stack))
	return total
