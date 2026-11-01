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

## Idempotency: player_entered_world can fire more than once for the
## same character (early emission during scene bootstrap plus the
## world's authoritative call), and each firing used to run a full
## grant -- the first one often burned the attempt while the bag was
## still under its fallback id, so the player spawned empty-handed.
var _granted_for: Dictionary = {}

## The character_confirmed relay (cheap-pair loop): the fresh-confirm
## set, keyed by character_id. Both Enter-World legs are creation
## paths, so a confirmed character earns the kit THIS session; a
## returning character (saved progress, no fresh mark) does not -- the
## old unconditional grant re-issued the kit on every boot.
var _fresh_confirmed: Dictionary = {}

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	GameLog.info("StarterKitService: Ready")

	# The character_confirmed relay. CharacterSelect DEFINES the signal
	# but sat with zero emitters and zero listeners; the selection scene
	# is created and torn down freely, so the consumer connects through
	# the tree instead of a boot-lifetime hook: every fresh node
	# carrying that script gets its signal connected. Runtime path
	# compare (not parse-time preload) keeps the script-mode law
	# intact.
	var tree := get_tree()
	if tree != null and not tree.node_added.is_connected(_on_tree_node_added):
		tree.node_added.connect(_on_tree_node_added)

	# Connect to player spawn
	if GameManager and GameManager.has_signal("player_entered_world"):
		if not GameManager.player_entered_world.is_connected(_on_player_entered_world):
			GameManager.player_entered_world.connect(_on_player_entered_world)

## Called when player enters the world: gate on the fresh-confirm law
## before the grant (see _should_grant_kit).
func _on_player_entered_world(player_id: String, character_data) -> void:
	if not _should_grant_kit(player_id):
		GameLog.info("StarterKitService: %s has saved progress -- kit not re-issued" % player_id)
		return
	grant_starter_kit(player_id, character_data)

## The tree relay: every node that carries the selection script gets
## its character_confirmed connected to the fresh-confirm handler.
func _on_tree_node_added(node: Node) -> void:
	var script: Script = node.get_script()
	if script == null or script.resource_path != "res://ui/menus/character_select.gd":
		return
	if node.has_signal("character_confirmed") and not node.character_confirmed.is_connected(_on_character_confirmed):
		node.character_confirmed.connect(_on_character_confirmed)

## The selection screen announced a finalized (brand-new) character.
func _on_character_confirmed(data) -> void:
	if data == null or not ("character_id" in data):
		return
	var char_id := str(data.character_id)
	if char_id.is_empty():
		return
	_fresh_confirmed[char_id] = true
	GameLog.info("StarterKitService: fresh confirm marked for %s" % char_id)

## Grant decision law: the character was confirmed fresh this session
## (both Enter-World legs count) OR it never completed a session with
## us (no saved progress). Returning characters with a saved bag keep
## their bag -- they do not collect a second kit.
func _should_grant_kit(player_id: String) -> bool:
	if _fresh_confirmed.get(player_id, false):
		return true
	var progress := get_node_or_null("/root/PlayerProgress")
	if progress != null and progress.has_method("has_progress") and progress.has_progress(player_id):
		return false
	return true

## Grant starter kit to a new character
func grant_starter_kit(player_id: String, character_data) -> void:
	if not character_data:
		GameLog.warn("StarterKitService: No character data for %s" % player_id)
		return

	if _granted_for.has(player_id):
		GameLog.debug("StarterKitService: kit already granted to %s" % player_id)
		return

	# The bag registers during scene bootstrap, often AFTER the first
	# player_entered_world emission. If it is not up yet, defer instead
	# of failing -- a failed grant here is how players spawned empty.
	if InventoryService == null or not InventoryService.has_inventory(player_id):
		GameLog.info("StarterKitService: bag not ready for %s -- deferring grant" % player_id)
		var tree := get_tree()
		if tree != null:
			await tree.create_timer(0.5).timeout
			grant_starter_kit(player_id, character_data)
		return

	_granted_for[player_id] = true

	var role: int = 0
	if "class_data" in character_data and character_data.class_data:
		role = character_data.class_data.get("role")

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
		new_item.id = item_res.get("id")
	if "display_name" in item_res:
		new_item.display_name = item_res.get("display_name")
	if "description" in item_res:
		new_item.description = item_res.get("description")
	if "icon_path" in item_res:
		new_item.icon_path = item_res.get("icon_path")
	if "item_category" in item_res:
		new_item.item_category = item_res.get("item_category")
	if "rarity" in item_res:
		new_item.rarity = item_res.get("rarity")
	if "equip_slot" in item_res:
		new_item.equip_slot = item_res.get("equip_slot")
	if "weapon_type" in item_res:
		new_item.weapon_type = item_res.get("weapon_type")
	if "stack_size" in item_res:
		new_item.stack_size = item_res.get("stack_size")
	if "sell_price" in item_res:
		new_item.sell_price = item_res.get("sell_price")
	if "buy_price" in item_res:
		new_item.buy_price = item_res.get("buy_price")
	if "required_level" in item_res:
		new_item.required_level = item_res.get("required_level")
	if "stats" in item_res:
		new_item.stats = item_res.get("stats")
	if "weapon_damage_min" in item_res:
		new_item.weapon_damage_min = item_res.get("weapon_damage_min")
	if "weapon_damage_max" in item_res:
		new_item.weapon_damage_max = item_res.get("weapon_damage_max")
	if "attack_speed" in item_res:
		new_item.attack_speed = item_res.get("attack_speed")

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
