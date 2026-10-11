## CraftingService - the crafting GATE (S16.9, prd-crafting.md).
## Crafting is not a minigame; it is a gate: a recipe is data truth,
## the crafter brings the bill, the service checks the ONE purse
## chain, the output is an Item .tres id (the service invents
## nothing). Every craft writes a world delta with the FULL BILL as
## provenance, so "where did this sword come from" is always
## answerable.
##
##   craft/<recipe_id>/<nonce>  set on craft {inputs, output, ok}
##
## Provenance law (the agent-citizen law stands): actor = the crafter
## (human or synthetic -- no special-casing), epoch = the S16.2 sky
## clock. The gate chain, one shape:
##   1. recipe exists (data is the law)
##   2. purse has ALL inputs (no partial consumes)
##   3. QoS rate limit (a craft bot is a detector class)
##   4. failure roll (failure_rate): byproducts drop, inputs are GONE
##   5. success: inputs consumed, output + byproducts granted
##   6. world delta with provenance
## Timed forges are v2 (craft_time_sec > 0 read but not yet timed --
## the field is honored as instant for now, flagged in the answer).
extends Node



## The islands-suite law: every autoload goes through root lookup
## (bare GameLog/DataService reads fail --script-mode compilation).
func _log(level: String, msg: String) -> void:
	var log4 = get_node_or_null("/root/GameLog")
	if log4 == null:
		return
	var call_it: Callable = Callable(log4, level)
	if call_it.is_valid():
		call_it.call(msg)

func _data_service():
	return get_node_or_null("/root/DataService")

## The purse helpers: the REAL InventoryComponent API (slots, not
## id-keyed). _grant passes the DataService INSTANCE down (the bag
## duplicates per slot; the shared-instance law lives there).
func _count_of(inv) -> Dictionary:
	var out := {}
	for it in inv.get_all_items():
		if it != null:
			var iid := str(it.id)
			out[iid] = int(out.get(iid, 0)) + maxi(1, int(it.current_stack))
	return out

func _rm_id(inv, item_id: String, qty: int) -> void:
	var left := qty
	while left > 0:
		var slot: int = inv.find_item(item_id)
		if slot < 0:
			return
		var stack: int = 1
		for it in inv.get_all_items():
			if it != null and str(it.id) == item_id:
				stack = maxi(1, int(it.current_stack))
				break
		var take: int = mini(left, stack)
		inv.remove_item(slot, take)
		left -= take

func _grant(inv, item_id: String, qty: int) -> bool:
	var ds_here = _data_service()
	if ds_here == null:
		return false
	var item = ds_here.get_item(item_id)
	if item != null:
		return bool(inv.add_item(item, qty))
	# Mount-type outputs (gliders, water mounts): the grant rides the
	# RideService OWNERSHIP ledger, not the bag -- a wing is not a
	# thing you carry, it is a thing you own.
	var mount = ds_here.get_mount(item_id)
	if mount != null:
		var ride = get_node_or_null("/root/RideService")
		var owner: String = str(inv.get_owner_id()) if inv.has_method("get_owner_id") else ""
		if ride != null and ride.has_method("grant_mount") and not owner.is_empty():
			return bool(ride.grant_mount(owner, item_id))
	return false

signal craft_completed(player_id: String, recipe_id: String, item_id: String, quantity: int)

const DEFAULT_RATE_LIMIT := "craft"

var _recipes: Dictionary = {}
var _loaded: bool = false


func _ready() -> void:
	pass  # autoload; loaded on demand like the harvest thread


const ResourceScan = preload("res://core/frame/srv/resource_scan.gd")

## Load every data/recipes/*.tres (the catalog law). Idempotent.
func ensure_loaded() -> void:
	if _loaded:
		return
	_recipes.clear()
	for p in ResourceScan.list_resources("res://data/recipes"):
		var r = load(p)
		if r != null and str(r.id) != "":
			_recipes[str(r.id)] = r
	_loaded = true


func get_recipe(id: String):
	ensure_loaded()
	return _recipes.get(str(id))


func all_recipe_ids() -> Array:
	ensure_loaded()
	return _recipes.keys()


## THE CRAFT: one gate chain, same answer shape as every other
## service: {ok, reason | recipe, output, failed}. `times` repeats the
## whole gate per craft (each iteration consumes and rolls -- no
## batching around the gates).
func craft(player_id: String, recipe_id: String, times: int = 1) -> Dictionary:
	ensure_loaded()
	var pid := str(player_id).strip_edges()
	var rid := str(recipe_id).strip_edges()
	var recipe = _recipes.get(rid)
	if pid.is_empty() or recipe == null:
		return {"ok": false, "reason": "unknown_recipe" if recipe == null else "no_crafter"}

	# The purse (one InventoryService chain -- no side doors).
	var inv_svc = get_node_or_null("/root/InventoryService")
	var inv = inv_svc.get_inventory(pid) if inv_svc != null else null
	if inv == null or not inv.has_method("add_item") or not inv.has_method("remove_item"):
		return {"ok": false, "reason": "no_inventory"}

	# Inputs data truth: every item must exist BEFORE the purse check
	# (a bad id in a recipe is a DATA defect, not a gate miss).
	var ds = _data_service()
	var bill: Array = []
	for input_dict in recipe.inputs:
		var iid := str(input_dict.get("item_id", ""))
		var qty := maxi(1, int(input_dict.get("qty", 1)))
		if iid.is_empty() or ds == null or not ds.has_method("get_item") or ds.get_item(iid) == null:
			_log("warn", "CraftingService: recipe '%s' has an unknown input '%s' (data defect)" % [rid, iid])
			return {"ok": false, "reason": "recipe_data_defect", "item_id": iid}
		bill.append({"item_id": iid, "qty": qty})

	var out_id := str(recipe.output.get("item_id", ""))
	var out_qty := maxi(1, int(recipe.output.get("qty", 1)))
	if out_id.is_empty() or (ds.get_item(out_id) == null and ds.get_mount(out_id) == null):
		_log("warn", "CraftingService: recipe '%s' has an unknown output '%s' (data defect)" % [rid, out_id])
		return {"ok": false, "reason": "recipe_data_defect", "item_id": out_id}

	var results: Array = []
	var done := 0
	for _i in range(maxi(1, times)):
		# Gate 2: purse has ALL inputs. Count first, consume second
		# (no partial consumes: the forge does not eat what you lack).
		var have_of := _count_of(inv)
		var purse_ok := true
		for entry in bill:
			if int(have_of.get(str(entry["item_id"]), 0)) < int(entry["qty"]):
				purse_ok = false
				break
		if not purse_ok:
			results.append({"ok": false, "reason": "missing_inputs"})
			break

		# Gate 3: the rate limit (the detector class reads cadence).
		var qos = get_node_or_null("/root/QoSService")
		if qos != null and qos.has_method("rate_limit") and not qos.rate_limit(pid, DEFAULT_RATE_LIMIT):
			results.append({"ok": false, "reason": "rate_limited"})
			break

		# Consume ALL inputs (the forge takes its due): per-id slot
		# walks through the REAL purse API (remove_item is slot-keyed).
		for entry in bill:
			_rm_id(inv, str(entry["item_id"]), int(entry["qty"]))

		# Gate 4: the failure roll (data truth posture).
		var failed: bool = randf() < clampf(float(recipe.failure_rate), 0.0, 1.0)

		if failed:
			# Byproducts drop, the inputs are GONE (the forge eats).
			for by_dict in recipe.byproducts:
				var bid := str(by_dict.get("item_id", ""))
				var bqty := maxi(1, int(by_dict.get("qty", 1)))
				if not bid.is_empty():
					_grant(inv, bid, bqty)
			results.append({"ok": false, "reason": "forge_ate_it", "byproducts": recipe.byproducts.size()})
		else:
			_grant(inv, out_id, out_qty)
			# Byproducts granted on SUCCESS too (slag sells).
			for by_dict in recipe.byproducts:
				var bid2 := str(by_dict.get("item_id", ""))
				var bqty2 := maxi(1, int(by_dict.get("qty", 1)))
				if not bid2.is_empty():
					_grant(inv, bid2, bqty2)
			results.append({"ok": true, "item_id": out_id, "qty": out_qty})
			craft_completed.emit(pid, rid, out_id, out_qty)
			done += 1

	# Gate 6: ONE world delta per craft call (the bill IS the
	# provenance; the answer's per-craft outcomes ride in the payload).
	var succeeded := done > 0
	_write_craft_delta(pid, rid, recipe, bill, {"item_id": out_id, "qty": out_qty}, succeeded, results)
	return {"ok": succeeded, "recipe": rid, "attempts": results.size(),
		"crafted": done, "results": results, "timed": float(recipe.craft_time_sec) > 0.0}


## The one-book write: same chain as the harvest thread. A no-registry
## (deep script) craft still crafts; the ledger skips.
func _write_craft_delta(pid: String, rid: String, recipe, bill: Array, output: Dictionary, succeeded: bool, results: Array) -> void:
	var proj = get_node_or_null("/root/WorldStateProjection")
	if proj == null or not proj.has_method("world_state"):
		return
	var ws = proj.world_state()
	var epoch: float = -1.0
	var sign_svc = get_node_or_null("/root/SignService")
	if sign_svc != null and sign_svc.has_method("sky_epoch_days"):
		epoch = sign_svc.sky_epoch_days()
	var nonce: int = randi() % 100000
	var key := "craft/%s/%d" % [rid, nonce]
	ws.set_world_state("main", key, {
		"actor": pid,
		"recipe": rid,
		"inputs": bill,
		"output": output,
		"ok": succeeded,
		"outcomes": results,
		"station": int(recipe.station),
	}, pid, epoch)
