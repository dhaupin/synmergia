# probe_crafting.gd - S16.9: the crafting gate, the third economy leg.
# prd-crafting.md checked by law:
#   A. Recipes are data truth (the scan reads recipe_*.tres).
#   B. The gate chain: unknown recipe refused; unknown input ITEM in a
#      recipe is a DATA defect (refused, logged); missing purse inputs
#      refused with NO partial consumes; QoS cadence; on failure the
#      inputs are GONE and byproducts drop; on success output+byproducts.
#   C. World delta: craft/<recipe>/<nonce> set with provenance
#      (actor = crafter, epoch = sky clock, the full bill in payload).
#   D. The citizen law: a synthetic crafts the SAME recipe through the
#      SAME chain -- identical answer shape.
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
	var cs = root.get_node_or_null("CraftingService")
	if cs == null:
		push_error("FAIL: CraftingService autoload missing")
		quit(1)
		return
	var inv_svc = root.get_node_or_null("InventoryService")
	var InvComp = load("res://core/components/inventory_component.gd")

	# ---- A. Recipes are data truth --------------------------------
	var ok_recipe = cs.get_recipe("recipe_iron_ingot")
	_check("the iron smelt is catalog data (2 ore -> 1 ingot, 10% failure)", \
		ok_recipe != null and ok_recipe.inputs.size() == 1 \
		and str(ok_recipe.inputs[0]["item_id"]) == "res_iron_ore" \
		and int(ok_recipe.inputs[0]["qty"]) == 2 \
		and absf(float(ok_recipe.failure_rate) - 0.1) < 1e-9)
	_check("unknown recipes refuse at the gate (no invention)", \
		cs.get_recipe("recipe_nope") == null \
		and not str(cs.all_recipe_ids()).is_empty())

	# ---- B. The gate chain -----------------------------------------
	var bag = InvComp.new()
	bag.set_owner_id("craft_citizen")
	inv_svc.register_inventory("craft_citizen", bag)
	var ds = root.get_node_or_null("DataService")

	# No purse inputs -> refused, nothing consumed.
	var broke: Dictionary = cs.craft("craft_citizen", "recipe_iron_ingot")
	_check("missing inputs refuse (no partial consumes, forge stays cold)", \
		not bool(broke["ok"]) and str(broke["results"][0]["reason"]) == "missing_inputs" \
		and _count_id(bag, "res_iron_ore") == 0 and _count_id(bag, "res_iron_ingot") == 0)

	# Load the purse, craft until one failure or two successes (prob).
	bag.add_item(ds.get_item("res_iron_ore"), 10)
	var first: Dictionary = cs.craft("craft_citizen", "recipe_iron_ingot")
	var ate_ok: bool = bool(first["ok"]) or (first["results"].size() > 0 and str(first["results"][0].get("reason", "")) == "forge_ate_it")
	var delta_shape: bool = bool(first["ok"]) or str(first["attempts"][0]["reason"]) == "forge_ate_it"
	_check("an honest purse crafts (or the forge eats, per the roll)", \
		ate_ok and int(first["attempts"]) == 1)

	# The bill is honest: 2 ores went in per attempt.
	var ores_after: int = _count_id(bag, "res_iron_ore")
	var got_ingot: int = _count_id(bag, "res_iron_ingot")
	var got_slag: int = _count_id(bag, "res_slag")
	var ores_delta: int = 10 - ores_after
	_check("the bill takes EXACTLY 2 ores per attempt (no partial eats)", \
		ores_delta == 2)
	var fine: bool = (got_ingot == 1 and got_slag >= 1) or (got_ingot == 0 and got_slag >= 1)
	_check("outcome carries the posture law (ingot on success, slag always)", fine)

	# Unknown item inside a recipe is a DATA defect (refused, loud).
	var bad_recipe = load("res://core/schemas/recipe_data.gd").new()
	bad_recipe.id = "recipe_bad_probe"
	bad_recipe.inputs = Array([{"item_id": "res_does_not_exist", "qty": 1}], 27, "", "")
	bad_recipe.output = {"item_id": "res_iron_ingot", "qty": 1}
	cs._recipes["recipe_bad_probe"] = bad_recipe
	var defect: Dictionary = cs.craft("craft_citizen", "recipe_bad_probe")
	_check("a data-defect recipe refuses (the service invents nothing)", \
		not bool(defect["ok"]) and str(defect["reason"]) == "recipe_data_defect")
	cs._recipes.erase("recipe_bad_probe")

	# ---- C. The world delta (provenance law) ------------------------
	var ws = root.get_node_or_null("WorldStateProjection").world_state()
	var found := false
	for k in ws.world_state_keys("main"):
		if str(k).begins_with("craft/recipe_iron_ingot/"):
			var payload: Dictionary = ws.get_world_state("main", str(k)).get("payload", {})
			var actor_ok: bool = str(payload.get("actor", "")) == "craft_citizen"
			var inputs_ok: bool = payload.get("inputs", []).size() == 1 \
				and str(payload["inputs"][0]["item_id"]) == "res_iron_ore"
			if actor_ok and inputs_ok:
				found = true
				break
	_check("the craft delta carries actor + full bill as provenance", found)

	# ---- D. The citizen law (agent/purse symmetry) -------------------
	var synth_bag = InvComp.new()
	synth_bag.set_owner_id("craft_synth")
	inv_svc.register_inventory("craft_synth", synth_bag)
	synth_bag.add_item(ds.get_item("res_iron_ore"), 4)
	var synth: Dictionary = cs.craft("craft_synth", "recipe_iron_ingot")
	var synth_ok: bool = bool(synth["ok"]) and _count_id(synth_bag, "res_iron_ingot") == 1
	# The smelt roll fails 10% of the time, so the SAME chain may retry:
	# each attempt consumes exactly 2 ore and one success yields the
	# ingot. The roll-agnostic laws (not 'attempts == 1', which flaked
	# when the die came up the bad way):
	#   * attempts >= 1 (the forge tried at least once)
	#   * ore consumed == 2 * attempts (the bill never lies)
	#   * attempts <= 4 (four ore -> at most two failures then success;
	#     a full-failure run of 2 attempts is the only legal wipe-out,
	#     and ok=true bounds attempts anyway since a third attempt
	#     would need 8 ore and the bag only held 4)
	var attempts: int = int(synth["attempts"])
	var ore_eaten: int = 4 - _count_id(synth_bag, "res_iron_ore")
	_check("a synthetic crafts the SAME recipe through the SAME chain", \
		synth_ok and attempts >= 1 and ore_eaten == 2 * attempts and attempts <= 4)

	# ---- E. The equippable crafts (breather + glider) ---------------
	# 1. The reed breather: an ITEM output -> rides the purse like any
	# other craft. Hand station (0), dawn reed = one timber billet.
	var reed_bag = InvComp.new()
	reed_bag.set_owner_id("craft_reed")
	inv_svc.register_inventory("craft_reed", reed_bag)
	reed_bag.add_item(ds.get_item("res_timber"), 1)
	var reed: Dictionary = cs.craft("craft_reed", "recipe_reed_breather")
	_check("the reed breather crafts as an ITEM through the purse", \
		bool(reed["ok"]) and _count_id(reed_bag, "acc_breather_reed") == 1 \
		and _count_id(reed_bag, "res_timber") == 0)

	# 2. The weaver's kite: a MOUNT output -> rides the RideService
	# ownership ledger (a wing is not carried, it is owned).
	var kite_bag = InvComp.new()
	kite_bag.set_owner_id("craft_kite")
	inv_svc.register_inventory("craft_kite", kite_bag)
	kite_bag.add_item(ds.get_item("res_timber"), 6)
	kite_bag.add_item(ds.get_item("res_stone"), 1)
	var kite: Dictionary = cs.craft("craft_kite", "recipe_weaver_kite")
	var ride = root.get_node_or_null("RideService")
	var owns: bool = ride != null and ride.has_method("owns_mount") \
		and ride.owns_mount("craft_kite", "glider_weaver_kite")
	_check("the weaver's kite crafts a MOUNT into the ownership ledger", \
		bool(kite["ok"]) and owns)
	_check("the kite bill consumed timber + stone exactly", \
		_count_id(kite_bag, "res_timber") == 0 and _count_id(kite_bag, "res_stone") == 0 \
		and _count_id(kite_bag, "glider_weaver_kite") == 0)  # a mount NEVER lands in the bag

	# 3. Short purse: the kite gate refuses BEFORE anything eats.
	kite_bag.add_item(ds.get_item("res_timber"), 5)
	var broke_kite: Dictionary = cs.craft("craft_kite", "recipe_weaver_kite")
	_check("a short kite purse refuses whole (no partial eats)", \
		not bool(broke_kite["ok"]) and str(broke_kite["results"][0]["reason"]) == "missing_inputs" \
		and _count_id(kite_bag, "res_timber") == 5)

	if _fails == 0:
		print("CRAFTING PROBE PASSED (%d checks)" % _checks)
	else:
		push_error("CRAFTING PROBE FAILED (%d/%d)" % [_fails, _checks])
