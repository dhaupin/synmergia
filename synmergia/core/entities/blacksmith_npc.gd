## BlacksmithNPC - Equipment repair vendor
## Interactable NPC that repairs player equipment
class_name BlacksmithNPC
extends Entity

@export var npc_name: String = "Blacksmith"
@export var shop_title: String = "The Smithy"
@export var dialogue_greeting: String = "What can I fix for ye?"
@export var dialogue_repair_all: String = "Let me take a look at yer gear..."
@export var dialogue_not_enough_gold: String = "Ye don't have enough gold, friend."
@export var dialogue_nothing_to_repair: String = "Yer gear's in fine shape already!"
@export var dialogue_repaired: String = "Good as new! Come back if ye break it again."
@export var dialogue_farewell: String = "Stay safe out there."

# Repair settings (can be customized per blacksmith)
@export var base_repair_cost_multiplier: float = 1.0  # Local modifier (famous smiths cost more)
@export var offers_bulk_discount: bool = true
@export var bulk_discount_percent: float = 10.0

# Location type (affects repair costs)
enum LocationType {
	TOWN,      # Standard pricing
	OUTPOST,   # Slightly more expensive
	VILLAGE,   # Cheaper (rural)
	DUNGEON,   # Emergency repairs (expensive)
	CAPITAL    # Premium pricing
}
@export var location_type: LocationType = LocationType.TOWN

# Visual configuration
@export var npc_skin_id: String = "blacksmith_male_01"
@export var has_apron: bool = true
@export var has_hammer: bool = true
@export var ambient_sfx: String = ""  # Forge sounds

signal interacted(player: Entity)
signal repair_initiated(player: Entity, items: int, cost: int)
signal repair_completed(player: Entity, items: int, cost: int)
signal repair_cancelled(player: Entity)

func _ready() -> void:
	super._ready()
	entity_type = EntityType.NPC
	controller_type = ControllerType.NPC
	display_name = npc_name
	
	# Set default stats for a blacksmith (non-combatant)
	stats.strength = 20  # Strong from forging
	stats.vitality = 15
	stats.agility = 8
	stats.intelligence = 10
	
	max_health = 100 + (stats.vitality * 10)
	current_health = max_health

## Get the blacksmith's base repair cost multiplier based on location
func get_location_cost_multiplier() -> float:
	match location_type:
		LocationType.TOWN:
			return 1.0
		LocationType.OUTPOST:
			return 1.25
		LocationType.VILLAGE:
			return 0.9
		LocationType.DUNGEON:
			return 2.0  # Emergency pricing
		LocationType.CAPITAL:
			return 1.5
	return 1.0

## Get total cost modifier for this blacksmith
func get_total_cost_modifier() -> float:
	return base_repair_cost_multiplier * get_location_cost_multiplier()

## Handle player interaction
func interact(player: Entity) -> Dictionary:
	interacted.emit(player)
	
	if not player.inventory_component:
		return {"success": false, "reason": "Player has no inventory"}
	
	var inventory: InventoryComponent = player.inventory_component
	var blacksmith: BlacksmithService = BlacksmithService.get_instance()
	
	if not blacksmith:
		return {"success": false, "reason": "Blacksmith service unavailable"}
	
	# Get repair preview
	var preview := blacksmith.get_repair_preview(inventory, offers_bulk_discount)
	
	if preview.item_count == 0:
		return {
			"success": true,
			"action": "nothing_to_repair",
			"dialogue": dialogue_nothing_to_repair
		}
	
	# Calculate adjusted costs
	var adjusted_cost := int(preview.total_cost * get_total_cost_modifier())
	var player_gold := inventory.get_gold()
	
	if player_gold < adjusted_cost:
		return {
			"success": true,
			"action": "cannot_afford",
			"dialogue": dialogue_not_enough_gold,
			"cost": adjusted_cost,
			"has": player_gold
		}
	
	return {
		"success": true,
		"action": "can_repair",
		"dialogue": dialogue_repair_all,
		"items": preview.items,
		"item_count": preview.item_count,
		"cost": adjusted_cost,
		"has": player_gold
	}

## Execute repair for a player
func repair_all(player: Entity) -> Dictionary:
	repair_initiated.emit(player, 0, 0)  # Emit before to show animation
	
	if not player.inventory_component:
		return {"success": false, "reason": "Player has no inventory"}
	
	var inventory: InventoryComponent = player.inventory_component
	var blacksmith: BlacksmithService = BlacksmithService.get_instance()
	
	if not blacksmith:
		return {"success": false, "reason": "Blacksmith service unavailable"}
	
	# Get repair preview and calculate cost
	var preview := blacksmith.get_repair_preview(inventory, offers_bulk_discount)
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
	
	# Perform repair
	var result := blacksmith.repair_all_equipped(player.entity_id, inventory, offers_bulk_discount)
	
	if result.success:
		# Apply location modifier to cost
		inventory.remove_gold(adjusted_cost)
		repair_completed.emit(player, result.items_repaired, adjusted_cost)
		return {
			"success": true,
			"action": "repaired",
			"dialogue": dialogue_repaired,
			"items_repaired": result.items_repaired,
			"cost": adjusted_cost
		}
	else:
		repair_cancelled.emit(player)
		return result

## Get interaction data for UI
func get_interaction_data() -> Dictionary:
	return {
		"type": "blacksmith",
		"name": npc_name,
		"title": shop_title,
		"greeting": dialogue_greeting,
		"location_type": LocationType.keys()[location_type],
		"cost_modifier": get_total_cost_modifier(),
		"offers_discount": offers_bulk_discount,
		"discount_percent": bulk_discount_percent if offers_bulk_discount else 0
	}

## Get location type display name
func get_location_display_name() -> String:
	match location_type:
		LocationType.TOWN:
			return "Town Blacksmith"
		LocationType.OUTPOST:
			return "Outpost Forge"
		LocationType.VILLAGE:
			return "Village Smithy"
		LocationType.DUNGEON:
			return "Dungeon Forge"
		LocationType.CAPITAL:
			return "Royal Smithy"
	return "Blacksmith"
