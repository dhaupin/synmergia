## BlacksmithNPC - Equipment repair vendor
## Interactable NPC that repairs player equipment using NPCData
class_name BlacksmithNPC
extends Entity

# NPC template data
var npc_data: NPCData = null

# Faction stance (Faction.FRIENDLY/NEUTRAL/HOSTILE)
var faction: int = 1  # Faction.NEUTRAL

# Cached values from NPCData
var _shop_title: String = "The Smithy"
var _greeting: String = "What can I fix for ye?"
var _farewell: String = "Stay safe out there."

signal interacted(player: Entity)
signal repair_initiated(player: Entity, items: int, cost: int)
signal repair_completed(player: Entity, items: int, cost: int)
signal repair_cancelled(player: Entity)

func _ready() -> void:
	super._ready()
	entity_type = EntityType.NPC
	controller_type = ControllerType.NPC
	
	# Apply NPCData if available
	if npc_data:
		_apply_npc_data()

## Apply NPCData template
func apply_data(data: NPCData) -> void:
	npc_data = data
	_apply_npc_data()

func _apply_npc_data() -> void:
	if not npc_data:
		return

	display_name = npc_data.display_name
	_shop_title = npc_data.shop_title if npc_data.shop_title != "" else "The Smithy"
	_greeting = npc_data.greeting
	_farewell = npc_data.farewell

	# Set faction
	if npc_data.faction == "friendly":
		faction = Faction.FRIENDLY
	elif npc_data.faction == "hostile":
		faction = Faction.HOSTILE
	else:
		faction = Faction.NEUTRAL

	# Set stats from NPCData
	stats.strength = npc_data.strength if npc_data.strength > 0 else 10
	stats.vitality = npc_data.vitality if npc_data.vitality > 0 else 10
	stats.agility = npc_data.agility if npc_data.agility > 0 else 10
	stats.intelligence = npc_data.intelligence if npc_data.intelligence > 0 else 10

	max_health = 100 + (stats.vitality * 10)
	current_health = max_health

## Get total cost modifier for this blacksmith
func get_total_cost_modifier() -> float:
	if npc_data:
		return npc_data.get_total_cost_modifier()
	return 1.0

## Handle player interaction
func interact(player: Entity) -> Dictionary:
	interacted.emit(player)

	if not player.inventory_component:
		return {"success": false, "reason": "Player has no inventory"}

	var inventory: InventoryComponent = player.inventory_component
	var blacksmith: BlacksmithService = BlacksmithService.get_instance()

	if not blacksmith:
		return {"success": false, "reason": "Blacksmith service unavailable"}
	
	var offers_discount := npc_data.offers_bulk_discount if npc_data else true

	# Get repair preview
	var preview := blacksmith.get_repair_preview(inventory, offers_discount)

	if preview.item_count == 0:
		return {
			"success": true,
			"action": "nothing_to_repair",
			"dialogue": "Yer gear's in fine shape already!"
		}

	# Calculate adjusted costs
	var adjusted_cost := int(preview.total_cost * get_total_cost_modifier())
	var player_gold := inventory.get_gold()

	if player_gold < adjusted_cost:
		return {
			"success": true,
			"action": "cannot_afford",
			"dialogue": "Ye don't have enough gold, friend.",
			"cost": adjusted_cost,
			"has": player_gold
		}

	return {
		"success": true,
		"action": "can_repair",
		"dialogue": "Let me take a look at yer gear...",
		"items": preview.items,
		"item_count": preview.item_count,
		"cost": adjusted_cost,
		"has": player_gold
	}

## Execute repair for a player
func repair_all(player: Entity) -> Dictionary:
	repair_initiated.emit(player, 0, 0)

	if not player.inventory_component:
		return {"success": false, "reason": "Player has no inventory"}

	var inventory: InventoryComponent = player.inventory_component
	var blacksmith: BlacksmithService = BlacksmithService.get_instance()

	if not blacksmith:
		return {"success": false, "reason": "Blacksmith service unavailable"}
	
	var offers_discount := npc_data.offers_bulk_discount if npc_data else true

	var preview := blacksmith.get_repair_preview(inventory, offers_discount)
	var adjusted_cost := int(preview.total_cost * get_total_cost_modifier())

	var player_gold := inventory.get_gold()
	if player_gold < adjusted_cost:
		repair_cancelled.emit(player)
		return {
			"success": false,
			"reason": "Not enough gold",
			"cost": adjusted_cost,
			"has": player_gold
		}

	var result := blacksmith.repair_all_equipped(player.entity_id, inventory, offers_discount)

	if result.success:
		inventory.remove_gold(adjusted_cost)
		repair_completed.emit(player, result.items_repaired, adjusted_cost)
		return {
			"success": true,
			"action": "repaired",
			"dialogue": "Good as new! Come back if ye break it again.",
			"items_repaired": result.items_repaired,
			"cost": adjusted_cost
		}
	else:
		repair_cancelled.emit(player)
		return result

## Get interaction data for UI
func get_interaction_data() -> Dictionary:
	var location_name := "Town"
	var discount_percent := 10.0
	var offers_discount := true
	
	if npc_data:
		location_name = NPCData.LocationType.keys()[npc_data.location_type]
		discount_percent = npc_data.bulk_discount_percent
		offers_discount = npc_data.offers_bulk_discount

	return {
		"type": "blacksmith",
		"name": display_name,
		"title": _shop_title,
		"greeting": _greeting,
		"location_type": location_name,
		"cost_modifier": get_total_cost_modifier(),
		"offers_discount": offers_discount,
		"discount_percent": discount_percent if offers_discount else 0
	}
