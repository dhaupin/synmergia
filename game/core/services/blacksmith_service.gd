## BlacksmithService - Equipment repair system
## Handles NPC interactions for repairing durability on equipment
extends Node

# Singleton reference
static var instance: BlacksmithService

# Repair pricing
@export var base_repair_cost_per_durability: float = 1.0  # Gold per durability point
@export var weapon_multiplier: float = 1.5  # Weapons cost more to repair
@export var armor_multiplier: float = 1.0  # Base armor cost
@export var accessory_multiplier: float = 0.5  # Accessories cost less

# Bulk repair discount
@export var bulk_discount_threshold: int = 5  # Items to qualify
@export var bulk_discount: float = 0.10  # 10% off for bulk repairs

signal repair_completed(player_id: String, items_repaired: int, total_cost: int)
signal repair_failed(player_id: String, reason: String)
signal item_too_broken(player_id: String, item_id: String)
signal forge_completed(player_id: String, target_item_id: String, new_level: int, ok: bool)

## ---- THE FORGE (prd-blacksmith: the RYL2-blooded upgrade law) ------
## Upgrade an item: the sacrifice GAMBLES the target. Gate law:
##   1. target is an upgradable EQUIP (weapons + armor + shields;
##      RINGS/NECKLACES/accessories are a different law -- refused)
##   2. the sacrifice is a real item of the SAME tier with a STRICTLY
##      SUPERIOR primary stat (inferior or equal refused; red/white
##      vs green) -- the transfer law
##   3. the ore must be the target's TIER or higher; below-tier ore
##      is legal but reades the negative delta (the forge is honest)
##   4. the chance table is BalanceData (data truth; tunable)
##   5. failure: the sacrifice is DESTROYED, the target LOSES
##      1-10 max endurance and (soft cap law) may drop one level;
##      the target survives (the PRD: not the reset-loop death)
##   6. success: the sacrifice is consumed (the transfer law --
##      "consumed whether the transfer succeeds or not"), +1 level
##   7. the hard cap is ABSOLUTE: beyond upgrade_hard_cap the
##      attempt REFUSES (the wackiness guard -- a wall, not odds)
##   8. every attempt is a world delta with provenance (actor,
##      epoch, target, sacrifice, ores, result) -- the ledger can
##      answer "how did this weapon get here" and a duplicated
##      stat trail is detectable
## "MYTHIC-cap ~90%" — the clamp law.

func _ready() -> void:
	instance = self
	GameLog.info("BlacksmithService: Ready")

## Get singleton instance
static func singleton() -> BlacksmithService:
	return instance

## Calculate repair cost for a single item
func calculate_repair_cost(item) -> int:
	if item == null or item.max_durability <= 0:
		return 0

	if not item.can_repair:
		return 0

	var missing_durability: int = int(item.max_durability) - int(item.current_durability)
	if missing_durability <= 0:
		return 0

	var cost: int = int(missing_durability) * int(base_repair_cost_per_durability)

	# Apply multiplier based on item type
	match item.item_category:
		"weapon":
			cost = int(cost * weapon_multiplier)
		"armor":
			cost = int(cost * armor_multiplier)
		"accessory":
			cost = int(cost * accessory_multiplier)

	# Apply rarity penalty (higher rarity = more expensive).
	# item.rarity is an Item.Rarity enum int -- the previous String match
	# never fired, so every rarity paid the same. Index the enum.
	match int(item.rarity):
		0: pass                       # common
		1: cost = int(cost * 1.25)    # rare
		2: cost = int(cost * 1.5)     # epic
		3: cost = int(cost * 2.0)     # legendary
		4: cost = int(cost * 3.0)     # mythic

	return maxi(1, cost)  # Minimum cost of 1 gold

## Calculate total repair cost for multiple items
func calculate_bulk_repair_cost(items: Array, apply_discount: bool = true) -> int:
	var total := 0
	for item in items:
		total += calculate_repair_cost(item)

	# Apply bulk discount if qualified
	if apply_discount and items.size() >= bulk_discount_threshold:
		total = int(total * (1.0 - bulk_discount))

	return total

## Repair a single item (removes gold from player)
func repair_item(player_id: String, inventory, equip_slot: int) -> Dictionary:
	var item = inventory.get_equipped_item(equip_slot)

	if item == null:
		## repair_failed had listeners (blacksmith_ui + hud_services)
		## but zero emitters -- every failure was a silent dict. Fire
		## each honest failure so the HUD toast path lives.
		repair_failed.emit(player_id, "No item in that slot")
		return {"success": false, "reason": "No item in that slot"}

	if item.max_durability <= 0:
		item_too_broken.emit(player_id, str(item.id))
		return {"success": false, "reason": "Item cannot be repaired"}

	if not item.can_repair:
		item_too_broken.emit(player_id, str(item.id))
		return {"success": false, "reason": "Item cannot be repaired"}

	if not item.is_broken() and item.current_durability >= item.max_durability:
		repair_failed.emit(player_id, "Item is already fully repaired")
		return {"success": false, "reason": "Item is already fully repaired"}

	var cost := calculate_repair_cost(item)

	# Check if player has enough gold
	var player_gold: int = int(inventory.get_gold())
	if player_gold < cost:
		repair_failed.emit(player_id, "Not enough gold")
		return {"success": false, "reason": "Not enough gold", "cost": cost, "has": player_gold}

	# Deduct gold and repair
	inventory.remove_gold(cost)
	item.repair()

	repair_completed.emit(player_id, 1, cost)

	return {
		"success": true,
		"item_name": item.display_name,
		"cost": cost,
		"new_durability": item.current_durability
	}

## Repair all equipped items
func repair_all_equipped(player_id: String, inventory, apply_discount: bool = true) -> Dictionary:
	var items: Array = inventory.get_all_equipped_items()

	# Filter to only items that need repair
	var items_needing_repair: Array = []
	for item in items:
		if item and item.max_durability > 0:
			if not item.can_repair:
				## The old filter required can_repair, so nothing
				## broken-but-unrepairable ever surfaced here; now it
				## announces itself and is skipped like before.
				if item.is_broken():
					item_too_broken.emit(player_id, str(item.id))
				continue
			if item.is_broken() or item.current_durability < item.max_durability:
				items_needing_repair.append(item)

	if items_needing_repair.size() == 0:
		repair_failed.emit(player_id, "No items need repair")
		return {"success": false, "reason": "No items need repair"}

	var cost := calculate_bulk_repair_cost(items_needing_repair, apply_discount)

	# Check if player has enough gold
	var player_gold: int = int(inventory.get_gold())
	if player_gold < cost:
		repair_failed.emit(player_id, "Not enough gold")
		return {"success": false, "reason": "Not enough gold", "cost": cost, "has": player_gold}

	# Deduct gold and repair all
	inventory.remove_gold(cost)
	var repaired_count := 0
	for item in items_needing_repair:
		item.repair()
		repaired_count += 1

	repair_completed.emit(player_id, repaired_count, cost)

	var discount_applied := apply_discount and items_needing_repair.size() >= bulk_discount_threshold

	return {
		"success": true,
		"items_repaired": repaired_count,
		"total_cost": cost,
		"discount_applied": discount_applied,
		"discount_percent": bulk_discount if discount_applied else 0
	}

## Get repair preview (what would be repaired and cost)
func get_repair_preview(inventory, apply_discount: bool = true) -> Dictionary:
	var items: Array = inventory.get_all_equipped_items()

	var items_needing_repair: Array[Dictionary] = []
	var total_cost: int = 0

	for item in items:
		if item and item.max_durability > 0 and item.can_repair:
			if item.is_broken() or item.current_durability < item.max_durability:
				var cost := calculate_repair_cost(item)
				items_needing_repair.append({
					"item_name": item.display_name,
					"current_durability": item.current_durability,
					"max_durability": item.max_durability,
					"cost": cost,
					"is_broken": item.is_broken()
				})
				total_cost += cost

	# Apply discount
	var discount_applied := apply_discount and items_needing_repair.size() >= bulk_discount_threshold
	if discount_applied:
		total_cost = int(total_cost * (1.0 - bulk_discount))

	return {
		"items": items_needing_repair,
		"item_count": items_needing_repair.size(),
		"subtotal": total_cost if not discount_applied else int(total_cost / (1.0 - bulk_discount)),
		"total_cost": total_cost,
		"discount_applied": discount_applied,
		"discount_percent": bulk_discount if discount_applied else 0
	}

## Check if player can afford repair
func can_afford_repair(inventory, apply_discount: bool = true) -> bool:
	var preview := get_repair_preview(inventory, apply_discount)
	return inventory.get_gold() >= preview.get("total_cost", 0)


## ---- THE FORGE (the RYL2-blooded upgrade law, build order 2) ------

const FORGE_BALANCE_PATH := "res://data/balance/forge_balance.tres"
static var _forge_balance = null

static func _balance():
	if _forge_balance == null:
		_forge_balance = load(FORGE_BALANCE_PATH)
	return _forge_balance

## The tier of an item: rarity for the forge's scale (COMMON..MYTHIC
## indices 0..4; the ladder is 5 grades so tiers clamp to 0..4).
static func _tier_of(item) -> int:
	if item == null or "rarity" not in item:
		return 0
	return clampi(int(item.rarity), 0, 4)

## Upgradable classes: WEAPON + ARMOR (jewelry is a different law;
## resources/consumables/events are not gear). The Item category
## enum lives in item.gd: WEAPON=0 ARMOR=1 ACCESSORY=2.
static func _is_upgradable(item) -> bool:
	if item == null or "item_category" not in item:
		return false
	var cat: int = int(item.item_category)
	return cat == 0 or cat == 1

## The forge's primary-stat read: weapons carry damage_max, armor
## carries armor_value. The transfer law compares THESE.
static func _primary_stat(item) -> int:
	if item == null:
		return 0
	var cat: int = int(item.item_category) if "item_category" in item else 3
	if cat == 0:
		return int(item.weapon_damage_max)
	if cat == 1:
		return int(item.armor_value)
	return 0

## THE ATTEMPT. inventory = the caller's bag; target/sacrifice/ore
## are real Item resources the UI (or probe) picked. Answer shape:
## {ok, reason | new_level, endurance, stats}; the world delta rides
## after the answer (the ledger never blocks the forge).
func attempt_upgrade(player_id: String, inventory, target, sacrifice, ore) -> Dictionary:
	var pid := str(player_id).strip_edges()
	var bal = _balance()
	if bal == null:
		return {"ok": false, "reason": "forge_unbalanced"}
	if target == null or sacrifice == null or ore == null:
		return {"ok": false, "reason": "no_materials"}

	# GATE 1: the target is gear and under the hard cap (THE WALL).
	if not _is_upgradable(target):
		return {"ok": false, "reason": "not_upgradable"}
	if int(target.upgrade_level) >= int(bal.upgrade_hard_cap):
		return {"ok": false, "reason": "hard_cap", "level": int(target.upgrade_level)}

	# GATE 2 (the transfer law): same-tier sacrifice, STRICTLY superior
	# primary stat (equal is white, not green: refused).
	var t_cat: int = int(target.item_category)
	if _tier_of(sacrifice) != _tier_of(target):
		return {"ok": false, "reason": "tier_mismatch", "target_tier": _tier_of(target), "sacrifice_tier": _tier_of(sacrifice)}
	if _primary_stat(sacrifice) <= _primary_stat(target):
		return {"ok": false, "reason": "sacrifice_not_superior", "sacrifice_stat": _primary_stat(sacrifice), "target_stat": _primary_stat(target)}

	# GATE 3: the ore's grade vs the target tier (parity or above);
	# below-tier ore is LEGAL (the forge is honest about the odds).
	var ore_tier: int = _tier_of(ore)
	var target_tier: int = _tier_of(target)

	# GATE 4 (the purse): the ORE itself must be IN the bag (and the
	# sacrifice must be IN the bag too -- you cannot forge a weapon
	# with a memory of a sword).
	if inventory == null or not inventory.has_method("get_all_items"):
		return {"ok": false, "reason": "no_purse"}
	var _count_of := func(id: String) -> int:
		var n := 0
		for it in inventory.get_all_items():
			if it != null and str(it.id) == id:
				n += maxi(1, int(it.current_stack))
		return n
	var ore_have: int = _count_of.call(str(ore.id))
	if ore_have < 1:
		return {"ok": false, "reason": "ore_not_in_bag"}
	# The bag DUPLICATES what it holds (per-slot dupes; no shared
	# instances), so the in-bag law reads BY IDENTITY SHAPE: the
	# sacrifice id is in the bag, AND one of its bag copies carries a
	# primary stat >= the sacrifice's (the one we will burn).
	var sac_id: String = str(sacrifice.id)
	var sac_have := false
	for it in inventory.get_all_items():
		if it != null and str(it.id) == sac_id and _primary_stat(it) >= _primary_stat(sacrifice):
			sac_have = true
			sacrifice = it  # burn the BAG's copy (the one that leaves)
			break
	if not sac_have:
		return {"ok": false, "reason": "sacrifice_not_in_bag"}

	# GATE 4b: the chance table (data truth). Below-tier ore reads
	# its negative delta; above-tier grades stack with the SOFT CAP
	# halving (each grade past soft_cap_grade halves its own delta).
	var delta: float = float(bal.ore_bonus_delta[clampi(ore_tier, 0, 4)])
	if ore_tier > target_tier:
		var steps := mini(ore_tier - target_tier, int(bal.soft_cap_grade))
		var halved := delta
		var applied: float = 0.0
		for _s in range(maxi(1, steps)):
			applied += halved
			halved *= 0.5
		delta = applied
	var chance: float = clampf(float(bal.base_chance[clampi(target_tier, 0, 4)]) + delta, 0.0, float(bal.my_thic_cap))

	# Consume: one ore + the sacrifice (ALWAYS -- the transfer law:
	# "consumed whether the transfer succeeds or not").
	_consume_id(inventory, str(ore.id), 1)
	_consume_instance(inventory, sacrifice)

	# GATE 5: the roll and the failure posture.
	var success: bool = randf() < chance
	var endurance_dmg := 0
	var old_level: int = int(target.upgrade_level)
	if success:
		target.upgrade_level = old_level + 1
		# The successful transfer DOES apply (the sacrifice bought it):
		# primary stat grafts at the new level's edge (v1: flat +1 tier
		# step, the deep stat-transfer law lands with socket balance).
		var step: int = 1
		var cat: int = int(target.item_category)
		if cat == 0:
			target.weapon_damage_max = int(target.weapon_damage_max) + step
			target.weapon_damage_min = mini(int(target.weapon_damage_min) + step, int(target.weapon_damage_max))  # min can never exceed max
		elif cat == 1:
			target.armor_value = int(target.armor_value) + step
		var result := {"ok": true, "new_level": int(target.upgrade_level), "endurance_dmg": 0, "chance": chance}
		forge_completed.emit(pid, str(target.id), int(target.upgrade_level), true)
		_write_forge_delta(pid, target, sacrifice, ore, result, true)
		return result

	# FAILURE: the sacrifice is DESTROYED (it already left the bag
	# above), the target SCARS: 1-10 max endurance stripped, and one
	# upgrade level drops (the RYL2 lesson, the target SURVIVES).
	endurance_dmg = randi_range(int(bal.endurance_damage_min), int(bal.endurance_damage_max))
	target.max_endurance = maxi(1, int(target.max_endurance) - endurance_dmg)
	target.current_endurance = mini(int(target.current_endurance), int(target.max_endurance))
	if bool(bal.downgrade_on_failure) and old_level > 0:
		target.upgrade_level = old_level - 1
	var result := {"ok": false, "reason": "forge_ate_it", "endurance_dmg": endurance_dmg, "level": int(target.upgrade_level), "chance": chance}
	forge_completed.emit(pid, str(target.id), int(target.upgrade_level), false)
	_write_forge_delta(pid, target, sacrifice, ore, result, false)
	return result

func _consume_id(inventory, item_id: String, qty: int) -> void:
	var left := qty
	while left > 0:
		var slot: int = inventory.find_item(item_id)
		if slot < 0:
			return
		var it = inventory.get_all_items()[0]
		var stack := 1
		for cand in inventory.get_all_items():
			if cand != null and str(cand.id) == item_id:
				stack = maxi(1, int(cand.current_stack))
				break
		var take := mini(left, stack)
		inventory.remove_item(slot, take)
		left -= take

func _consume_instance(inventory, instance) -> void:
	var items: Array = inventory.get_all_items()
	for i in range(items.size()):
		if items[i] == instance:
			inventory.remove_item(i, -1)
			return

func _write_forge_delta(pid: String, target, sacrifice, ore, result: Dictionary, success: bool) -> void:
	var proj = get_node_or_null("/root/WorldStateProjection")
	if proj == null or not proj.has_method("world_state"):
		return
	var ws = proj.world_state()
	var epoch: float = -1.0
	var sign_svc = get_node_or_null("/root/SignService")
	if sign_svc != null and sign_svc.has_method("sky_epoch_days"):
		epoch = sign_svc.sky_epoch_days()
	var key := "forge/%s/%d" % [str(target.id), int(target.upgrade_level)]
	ws.set_world_state("main", key, {
		"actor": pid,
		"target": str(target.id),
		"sacrifice": str(sacrifice.id),
		"ore": str(ore.id),
		"success": success,
		"result": result,
	}, pid, epoch)
