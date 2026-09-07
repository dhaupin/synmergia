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
	
	# Apply rarity penalty (higher rarity = more expensive)
	match item.rarity:
		"common":
			pass  # No penalty
		"uncommon":
			cost = int(cost * 1.1)
		"rare":
			cost = int(cost * 1.25)
		"epic":
			cost = int(cost * 1.5)
		"legendary":
			cost = int(cost * 2.0)
	
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
		return {"success": false, "reason": "No item in that slot"}
	
	if item.max_durability <= 0:
		return {"success": false, "reason": "Item cannot be repaired"}
	
	if not item.can_repair:
		return {"success": false, "reason": "Item cannot be repaired"}
	
	if not item.is_broken() and item.current_durability >= item.max_durability:
		return {"success": false, "reason": "Item is already fully repaired"}
	
	var cost := calculate_repair_cost(item)
	
	# Check if player has enough gold
	var player_gold: int = int(inventory.get_gold())
	if player_gold < cost:
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
		if item and item.max_durability > 0 and item.can_repair:
			if item.is_broken() or item.current_durability < item.max_durability:
				items_needing_repair.append(item)
	
	if items_needing_repair.size() == 0:
		return {"success": false, "reason": "No items need repair"}
	
	var cost := calculate_bulk_repair_cost(items_needing_repair, apply_discount)
	
	# Check if player has enough gold
	var player_gold: int = int(inventory.get_gold())
	if player_gold < cost:
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
