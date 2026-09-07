## StarterKitService - Gives new characters their starting equipment
## Hooks into player spawn via GameManager.player_entered_world
extends Node

static var instance: StarterKitService

## Starter kit definitions by class role
## Format: role -> [item_id, item_id, ...]
const STARTER_KITS: Dictionary = {
	# Warrior/Tank roles get sword + shield
	0: ["wep_iron_sword"],  # Role 0 = GM (fallback)
	1: ["wep_iron_sword"],   # Tank
	2: ["wep_iron_sword"],   # Melee DPS
	3: ["wep_wooden_bow"],  # Ranged DPS
	4: [],                   # Healer (no weapon in data yet)
	5: [],                   # Support
	6: [],                   # Control
}

## Starting gold by role
const STARTING_GOLD: Dictionary = {
	0: 500,
	1: 200,
	2: 150,
	3: 150,
	4: 100,
	5: 100,
	6: 100,
}

signal starter_kit_granted(player_id: String, items: Array)

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	GameLog.info("StarterKitService: Ready")

	# Connect to player spawn
	if GameManager and GameManager.has_signal("player_entered_world"):
		if not GameManager.player_entered_world.is_connected(_on_player_entered_world):
			GameManager.player_entered_world.connect(_on_player_entered_world)

## Called when player enters the world
func _on_player_entered_world(player_id: String, character_data) -> void:
	grant_starter_kit(player_id, character_data)

## Grant starter kit to a new character
func grant_starter_kit(player_id: String, character_data) -> void:
	if not character_data:
		GameLog.warn("StarterKitService: No character data for %s" % player_id)
		return

	var role: int = 0
	if "class_data" in character_data and character_data.class_data:
		role = character_data.class_data.get("role", 0)

	var item_ids: Array = STARTER_KITS.get(role, STARTER_KITS.get(0, []))
	var gold: int = STARTING_GOLD.get(role, STARTING_GOLD.get(0, 100))

	var granted_items: Array = []
	var failed_items: Array = []

	# Give each starter item
	for item_id in item_ids:
		if _give_starter_item(player_id, item_id):
			granted_items.append(item_id)
		else:
			failed_items.append(item_id)

	# Give starting gold
	if gold > 0:
		_grant_gold(player_id, gold)

	if not granted_items.is_empty():
		GameLog.info("StarterKitService: Granted %s items to %s (role=%d)" % [granted_items.size(), player_id, role])
		starter_kit_granted.emit(player_id, granted_items)
	else:
		GameLog.debug("StarterKitService: No items to grant to %s" % player_id)

	if not failed_items.is_empty():
		GameLog.warn("StarterKitService: Failed to grant items: %s" % failed_items)

## Give a single starter item to player
func _give_starter_item(player_id: String, item_id: String) -> bool:
	# Load the item resource
	var item_path := "res://data/items/%s.tres" % item_id
	if not ResourceLoader.exists(item_path):
		# Try other paths
		item_path = "res://data/weapons/%s.tres" % item_id
		if not ResourceLoader.exists(item_path):
			item_path = "res://data/armors/%s.tres" % item_id
			if not ResourceLoader.exists(item_path):
				item_path = "res://data/consumables/%s.tres" % item_id
				if not ResourceLoader.exists(item_path):
					push_warning("StarterKitService: Item not found: %s" % item_id)
					return false

	var item_res := load(item_path)
	if item_res == null:
		push_warning("StarterKitService: Failed to load item: %s" % item_path)
		return false

	# Create a new instance of the item
	var ItemClass: Script = load("res://core/schemas/item.gd")
	var new_item: Resource = ItemClass.new()
	if "id" in item_res:
		new_item.id = item_res.get("id", item_id)
	if "display_name" in item_res:
		new_item.display_name = item_res.get("display_name", item_id)
	if "description" in item_res:
		new_item.description = item_res.get("description", "")
	if "icon_path" in item_res:
		new_item.icon_path = item_res.get("icon_path", "")
	if "item_category" in item_res:
		new_item.item_category = item_res.get("item_category", 0)
	if "rarity" in item_res:
		new_item.rarity = item_res.get("rarity", 0)
	if "equip_slot" in item_res:
		new_item.equip_slot = item_res.get("equip_slot", -1)
	if "weapon_type" in item_res:
		new_item.weapon_type = item_res.get("weapon_type", 0)
	if "stack_size" in item_res:
		new_item.stack_size = item_res.get("stack_size", 1)
	if "sell_price" in item_res:
		new_item.sell_price = item_res.get("sell_price", 0)
	if "buy_price" in item_res:
		new_item.buy_price = item_res.get("buy_price", 0)
	if "required_level" in item_res:
		new_item.required_level = item_res.get("required_level", 1)
	if "stats" in item_res:
		new_item.stats = item_res.get("stats", {})
	if "weapon_damage_min" in item_res:
		new_item.weapon_damage_min = item_res.get("weapon_damage_min", 0)
	if "weapon_damage_max" in item_res:
		new_item.weapon_damage_max = item_res.get("weapon_damage_max", 0)
	if "attack_speed" in item_res:
		new_item.attack_speed = item_res.get("attack_speed", 1.0)

	# Add to inventory
	if InventoryService:
		var inv: Node = InventoryService.get_inventory(player_id)
		if inv and inv.has_method("add_item"):
			return inv.add_item(new_item)
		else:
			push_warning("StarterKitService: Player inventory not found: %s" % player_id)
			return false
	else:
		push_warning("StarterKitService: InventoryService not available")
		return false

## Grant starting gold
func _grant_gold(player_id: String, amount: int) -> void:
	if InventoryService:
		var inv: Node = InventoryService.get_inventory(player_id)
		if inv and inv.has_method("set_gold"):
			inv.set_gold(amount)
			GameLog.debug("StarterKitService: Gave %d gold to %s" % [amount, player_id])
