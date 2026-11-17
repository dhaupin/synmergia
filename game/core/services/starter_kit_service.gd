## StarterKitService - Gives new characters their starting equipment
## Hooks into player spawn via GameManager.player_entered_world
extends Node

static var instance: StarterKitService

const ItemScript = preload("res://core/schemas/item.gd")
const DATA_ID := "starter_kits"
const STARTER_TABLET_ID := "acc_tablet_wayfarer"
var _kit_cache: StarterKitData = null

## Resolve the role-keyed grant tables from DataService. The service owns
## the fresh-confirm gate and the grant; the record owns the content.
func _kit_data() -> StarterKitData:
	if _kit_cache != null and _kit_cache.is_valid():
		return _kit_cache
	if DataService == null or not DataService.has_method("get_starter_kits"):
		return null
	_kit_cache = DataService.get_starter_kits()
	if _kit_cache == null or not _kit_cache.is_valid():
		GameLog.warn("StarterKitService: balance record %s is missing or invalid" % DATA_ID)
		return null
	return _kit_cache

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
	if _should_grant_kit(player_id):
		grant_starter_kit(player_id, character_data)
	else:
		GameLog.info("StarterKitService: %s has saved progress -- kit not re-issued" % player_id)
	# The interaction-layer backstop runs for returning characters too: a
	# tabletless bag earns the soulbound Wayfarer tablet, never a soft lock.
	ensure_tablet(player_id)

## Guarantee one tablet. Fresh kits already carry the guaranteed record;
## returning characters who somehow have no tablet receive it here. A tablet
## already in the bag is auto-equipped when the tablet socket is empty.
func ensure_tablet(player_id: String) -> void:
	if InventoryService == null or not InventoryService.has_inventory(player_id):
		var tree := get_tree()
		if tree != null:
			await tree.create_timer(0.5).timeout
			ensure_tablet(player_id)
		return
	var inv: Node = InventoryService.get_inventory(player_id)
	if inv == null:
		return
	if inv.has_method("has_tablet") and inv.has_tablet():
		if inv.has_method("get_equipped_tablet") and inv.get_equipped_tablet() == null:
			var bag_slot: int = inv.find_tablet_slot()
			if bag_slot >= 0:
				inv.equip_item(bag_slot, ItemScript.EquipSlot.TABLET)
		return
	if not _give_starter_item(player_id, STARTER_TABLET_ID):
		GameLog.warn("StarterKitService: could not grant the guaranteed tablet to %s" % player_id)

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

	var kit := _kit_data()
	if kit == null:
		GameLog.warn("StarterKitService: kit data unavailable for %s" % player_id)
		return

	_granted_for[player_id] = true

	var role: int = 0
	if "class_data" in character_data and character_data.class_data:
		role = character_data.class_data.get("role")

	var item_ids: Array = kit.items_for(role)
	for guaranteed_id in kit.guaranteed_for_all():
		if not item_ids.has(guaranteed_id):
			item_ids.append(guaranteed_id)
	var gold: int = kit.gold_for(role)

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
	# Load the item resource from every starter-bearing directory.
	var item_path := ""
	for directory in ["items", "weapons", "armors", "accessories", "consumables"]:
		var candidate := "res://data/%s/%s.tres" % [directory, item_id]
		if ResourceLoader.exists(candidate):
			item_path = candidate
			break
	if item_path.is_empty():
		push_warning("StarterKitService: Item not found: %s" % item_id)
		return false

	var item_res := load(item_path)
	if item_res == null:
		push_warning("StarterKitService: Failed to load item: %s" % item_path)
		return false

	# Create a new instance through the schema's one serializer. The old
	# hand-copied field list silently dropped every field added after it was
	# written (handedness, shield family, resists, crit, block); from_dict
	# means a starter item cannot drift from the catalog record.
	var ItemClass: Script = load("res://core/schemas/item.gd")
	var new_item: Resource = ItemClass.from_dict(item_res.to_dict())

	# Add to inventory. The tablet is equipped directly: it is the interaction
	# tool, soulbound, and must not fail when the bag is full.
	if InventoryService:
		var inv: Node = InventoryService.get_inventory(player_id)
		if inv and inv.has_method("add_item"):
			if new_item.is_tablet():
				if inv.has_method("has_tablet") and inv.has_tablet():
					return true
				if inv.has_method("equip_direct") and inv.get_equipped_tablet() == null:
					if inv.equip_direct(new_item, ItemScript.EquipSlot.TABLET):
						return true
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
