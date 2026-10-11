# probe_harvest.gd - S16.5.3: the harvest service, the live-delta thread.
#
# Covers:
#   A. Registration law: a node is data truth (unknown item refused,
#      world resolved from ZoneData, empty ids refused).
#   B. The gate chain: harvest grants through the InventoryService
#      purse (real InvComp.add_item), depletes, writes the world
#      delta with provenance (actor = harvester, epoch = sky clock).
#   C. The second lock: a depleted node refuses; respawn restores it
#      and leaves the auditable cleared record.
#   D. The agent-citizen law: a synthetic harvests the SAME node
#      through the SAME chain -- identical answer shape, identical
#      delta provenance shape.
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

## The bag has no count API: slots are an Array of Item (null = empty).
## Stacks carry current_stack; singles count 1.
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
	var hs = root.get_node_or_null("HarvestService")
	if hs == null:
		push_error("FAIL: HarvestService autoload missing")
		quit(1)
		return
	var ws = root.get_node_or_null("WorldStateProjection").world_state()
	var inv_svc = root.get_node_or_null("InventoryService")

	# Two citizens, one node type: a human purse and a synthetic purse.
	var InvComp = load("res://core/components/inventory_component.gd")
	var human_bag = InvComp.new()
	human_bag.set_owner_id("hs_human")
	inv_svc.register_inventory("hs_human", human_bag)
	var synth_bag = InvComp.new()
	synth_bag.set_owner_id("hs_synth_1")
	inv_svc.register_inventory("hs_synth_1", synth_bag)

	# -- A. Registration law -----------------------------------------
	_check("an unknown item refuses registration (data is the law)",
		hs.register_node("hs_bad", "zone_forest_meadow", "res_does_not_exist", Vector3.ZERO) == "")
	_check("empty ids refuse registration",
		hs.register_node("", "zone_forest_meadow", "res_iron_ore", Vector3.ZERO) == "")
	var nid: String = hs.register_node("hs_iron_1", "zone_forest_meadow", "res_iron_ore", Vector3(2, 0, 3), 1, 9999.0)
	_check("a lawful node registers against data truth (res_iron_ore)",
		nid == "hs_iron_1" and hs.node_ids().has("hs_iron_1") and not hs.is_depleted(nid))

	# -- B. The gate chain -------------------------------------------
	var broke: Dictionary = hs.harvest("hs_nobody", nid)
	_check("a citizen with no purse cannot harvest (the world drops nothing into the void)",
		str(broke.get("reason", "")) == "no_inventory")

	var r1: Dictionary = hs.harvest("hs_human", nid)
	_check("a lawful harvest answers {ok, item_id, quantity}",
		bool(r1.get("ok", false)) and str(r1.get("item_id", "")) == "res_iron_ore" and int(r1.get("quantity", 0)) == 1)
	var inv = inv_svc.get_inventory("hs_human")
	_check("the grant rode the purse chain (the bag holds the ore)",
		inv != null and _count_id(inv, "res_iron_ore") >= 1)
	_check("the node depleted",
		hs.is_depleted(nid) and hs.respawn_in(nid) > 0.0)

	var delta: Dictionary = ws.get_world_state("main", "harvest/%s" % nid)
	var dpl: Dictionary = delta.get("payload", {}) if delta.get("payload", {}) is Dictionary else {}
	_check("the depletion is a world delta: actor = harvester, epoch = sky clock, item truth",
		bool(dpl.get("depleted", false)) and str(dpl.get("item_id", "")) == "res_iron_ore" \
		and str(delta.get("actor", "")) == "hs_human" and float(delta.get("epoch", 0.0)) > 0.0)

	# -- C. The second lock + respawn --------------------------------
	var r2: Dictionary = hs.harvest("hs_human", nid)
	_check("a depleted node refuses (the second lock)",
		str(r2.get("reason", "")) == "depleted")

	hs.force_ready(nid)
	_check("force_ready makes the node harvestable again (test clock hand)",
		not hs.is_depleted(nid))

	# -- D. The agent-citizen law ------------------------------------
	var r3: Dictionary = hs.harvest("hs_synth_1", nid)
	_check("a SYNTHETIC harvests through the SAME chain: same answer shape",
		bool(r3.get("ok", false)) and str(r3.get("item_id", "")) == "res_iron_ore")
	var synth_inv = inv_svc.get_inventory("hs_synth_1")
	_check("the synthetic's purse holds the ore (equal citizens, equal grants)",
		synth_inv != null and _count_id(synth_inv, "res_iron_ore") >= 1)
	var delta2: Dictionary = ws.get_world_state("main", "harvest/%s" % nid)
	_check("the synthetic's delta carries the same provenance shape as the human's",
		str(delta2.get("actor", "")) == "hs_synth_1" and float(delta2.get("epoch", 0.0)) > 0.0)

	# -- E. Respawn erasure (auditable cleared record) ----------------
	var respawned: Dictionary = {"fired": false}
	hs.node_respawned.connect(func(n): respawned["fired"] = true)
	var nid2: String = hs.register_node("hs_herb_1", "zone_forest_meadow", "res_iron_ore", Vector3(4, 0, 6), 1, 0.2)
	hs.harvest("hs_human", nid2)
	_check("the timed node depleted and wrote its delta",
		hs.is_depleted(nid2) and not ws.get_world_state("main", "harvest/hs_herb_1").is_empty())
	await create_timer(0.5).timeout
	_check("respawn restored the node and fired the signal",
		not hs.is_depleted(nid2) and bool(respawned["fired"]))
	# The respawn's ERASE leaves the auditable cleared record at the
	# key: who the last harvester was, and that the world took it back.
	var back: Dictionary = ws.get_world_state("main", "harvest/hs_herb_1")
	_check("respawn leaves the auditable cleared record (actor = world)",
		bool(back.get("payload", {}).get("cleared", false)) and str(back.get("actor", "")) == "world")

	# -- F. Timber + stone (the Gloomwood chop + the quarry) ----------
	# Registering a lumber node: DataService truth only -- the service
	# refuses unknown items, so these checks double as data-law proof
	# that res_timber / res_stone actually EXIST in the registry.
	var tree_nid: String = hs.register_node("hs_gloomwood_pine_1", "zone_forest_meadow", "res_timber", Vector3(6, 0, 2), 2, 30.0)
	_check("a tree registers as a timber node (chop the Gloomwood)",
		tree_nid == "hs_gloomwood_pine_1")
	var rock_nid: String = hs.register_node("hs_quarry_boulder_1", "zone_forest_meadow", "res_stone", Vector3(7, 0, 4), 1, 30.0)
	_check("a boulder registers as a stone node (the quarry gives)",
		rock_nid == "hs_quarry_boulder_1")
	var chop: Dictionary = hs.harvest("hs_human", tree_nid)
	_check("chopping the tree grants timber through the SAME purse chain",
		bool(chop.get("ok", false)) and str(chop.get("item_id", "")) == "res_timber" \
		and int(chop.get("quantity", 0)) == 2)
	_check("the purse holds the timber (2 per chop)",
		_count_id(inv, "res_timber") == 2)
	var mine: Dictionary = hs.harvest("hs_synth_1", rock_nid)
	_check("a synthetic mines the boulder: stone rides the same law",
		bool(mine.get("ok", false)) and str(mine.get("item_id", "")) == "res_stone" \
		and _count_id(synth_inv, "res_stone") == 1)
	_check("both nodes depleted on their harvest (the world remembers the take)",
		hs.is_depleted(tree_nid) and hs.is_depleted(rock_nid))
	var chop_delta: Dictionary = ws.get_world_state("main", "harvest/%s" % tree_nid)
	_check("the chop delta carries actor + timber provenance",
		str(chop_delta.get("actor", "")) == "hs_human" \
		and str(chop_delta.get("payload", {}).get("item_id", "")) == "res_timber")

	print("probe_harvest: %d checks, %d failures" % [_checks, _fails])
