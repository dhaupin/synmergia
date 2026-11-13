## AdminCatalog - In-game catalog for spawning/managing entities
## Provides UI for browsing and spawning entities by ID
extends Control
class_name AdminCatalog

signal entity_spawned(entity_id: String, success: bool)
signal item_spawned(item_id: String, success: bool)

## Catalog categories
enum Category {
	ALL,
	ENEMIES,
	NPCS,
	ITEMS,
	ZONES,
	QUESTS,
	SKILLS,
}

## UI elements
var _category_tabs: HBoxContainer
var _search_input: LineEdit
var _item_list: ItemList
var _details_panel: PanelContainer
var _spawn_button: Button
var _quantity_spin: SpinBox

## Current state
var _current_category: Category = Category.ALL
var _search_filter: String = ""
var _catalog_entries: Array[Dictionary] = []

func _ready() -> void:
	_initialize_catalog()
	_setup_ui()

func _initialize_catalog() -> void:
	# Pre-populate catalog with known template IDs
	# In production, this would load from data files
	_catalog_entries = [
		# Enemies (eny_*)
		{"id": "eny_goblin", "name": "Goblin", "type": "ENEMY", "level": 1},
		{"id": "eny_goblin_warrior", "name": "Goblin Warrior", "type": "ENEMY", "level": 3},
		{"id": "eny_goblin_shaman", "name": "Goblin Shaman", "type": "ENEMY", "level": 5},
		{"id": "eny_orc", "name": "Orc", "type": "ENEMY", "level": 8},
		{"id": "eny_orc_warlord", "name": "Orc Warlord", "type": "ENEMY", "level": 15},
		{"id": "eny_dragon_whelp", "name": "Dragon Whelp", "type": "ENEMY", "level": 20},
		{"id": "eny_dragon", "name": "Dragon", "type": "ENEMY", "level": 30},
		{"id": "eny_dragon_lord", "name": "Dragon Lord", "type": "ENEMY", "level": 50},

		# NPCs (npc_*)
		{"id": "npc_merchant_generic", "name": "Merchant", "type": "NPC", "level": 1},
		{"id": "npc_guardsman", "name": "Guard", "type": "NPC", "level": 5},
		{"id": "npc_quest_giver_generic", "name": "Quest Giver", "type": "NPC", "level": 1},
		{"id": "npc_tavern_keeper", "name": "Tavern Keeper", "type": "NPC", "level": 1},
		{"id": "npc_weaponsmith", "name": "Weaponsmith", "type": "NPC", "level": 1},
		{"id": "npc_armorsmith", "name": "Armorsmith", "type": "NPC", "level": 1},
		{"id": "npc_trainer_combat", "name": "Combat Trainer", "type": "NPC", "level": 10},
		{"id": "npc_bank_guard", "name": "Bank Guard", "type": "NPC", "level": 15},

		# Items (itm_*)
		{"id": "itm_gold_100", "name": "100 Gold", "type": "ITEM", "level": 1},
		{"id": "itm_gold_1000", "name": "1000 Gold", "type": "ITEM", "level": 1},
		{"id": "itm_health_potion_small", "name": "Minor Health Potion", "type": "ITEM", "level": 1},
		{"id": "itm_health_potion_medium", "name": "Health Potion", "type": "ITEM", "level": 5},
		{"id": "itm_health_potion_large", "name": "Greater Health Potion", "type": "ITEM", "level": 15},
		{"id": "itm_mana_potion_small", "name": "Minor Mana Potion", "type": "ITEM", "level": 1},
		{"id": "itm_sword_iron", "name": "Iron Sword", "type": "ITEM", "level": 3},
		{"id": "itm_sword_steel", "name": "Steel Sword", "type": "ITEM", "level": 10},
		{"id": "itm_sword_mithril", "name": "Mithril Sword", "type": "ITEM", "level": 25},
		{"id": "itm_armor_leather", "name": "Leather Armor", "type": "ITEM", "level": 3},
		{"id": "itm_armor_chain", "name": "Chainmail", "type": "ITEM", "level": 10},
		{"id": "itm_armor_plate", "name": "Plate Armor", "type": "ITEM", "level": 20},

		# Zones (zn_*)
		{"id": "zn_tutorial", "name": "Tutorial Zone", "type": "ZONE", "level": 1},
		{"id": "zn_forest_start", "name": "Starting Forest", "type": "ZONE", "level": 1},
		{"id": "zn_cave_dark", "name": "Dark Cave", "type": "ZONE", "level": 10},
		{"id": "zn_dungeon_easy", "name": "Easy Dungeon", "type": "ZONE", "level": 15},
		{"id": "zn_dungeon_hard", "name": "Hard Dungeon", "type": "ZONE", "level": 25},
		{"id": "zn_arena", "name": "Arena", "type": "ZONE", "level": 20},

		# Quests (qst_*)
		{"id": "qst_tutorial_01", "name": "Tutorial: First Steps", "type": "QUEST", "level": 1},
		{"id": "qst_goblin_slayer", "name": "Goblin Slayer", "type": "QUEST", "level": 3},
		{"id": "qst_delivery_01", "name": "Simple Delivery", "type": "QUEST", "level": 2},
		{"id": "qst_escort_01", "name": "Escort Mission", "type": "QUEST", "level": 5},
		{"id": "qst_dungeon_clear", "name": "Clear the Dungeon", "type": "QUEST", "level": 15},

		# Skills (skl_*)
		{"id": "skl_fireball", "name": "Fireball", "type": "SKILL", "level": 5},
		{"id": "skl_heal", "name": "Heal", "type": "SKILL", "level": 3},
		{"id": "skl_shield", "name": "Shield", "type": "SKILL", "level": 5},
		{"id": "skl_teleport", "name": "Teleport", "type": "SKILL", "level": 20},
	]

func _setup_ui() -> void:
	# Main container
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Admin Catalog"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	# Search bar
	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Search by ID or name..."
	_search_input.text_submitted.connect(_on_search_changed)
	vbox.add_child(_search_input)

	# Category tabs
	_category_tabs = HBoxContainer.new()
	var categories := ["All", "Enemies", "NPCs", "Items", "Zones", "Quests", "Skills"]
	for i in range(categories.size()):
		var btn := Button.new()
		btn.text = categories[i]
		btn.pressed.connect(_on_category_selected.bind(i))
		_category_tabs.add_child(btn)
	vbox.add_child(_category_tabs)

	# Item list (left panel)
	_item_list = ItemList.new()
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_list.item_selected.connect(_on_item_selected)
	vbox.add_child(_item_list)

	# Bottom panel with spawn controls
	var bottom_hbox := HBoxContainer.new()

	_quantity_spin = SpinBox.new()
	_quantity_spin.min_value = 1
	_quantity_spin.max_value = 100
	_quantity_spin.value = 1
	_quantity_spin.prefix = "Qty: "
	bottom_hbox.add_child(_quantity_spin)

	_spawn_button = Button.new()
	_spawn_button.text = "Spawn"
	_spawn_button.pressed.connect(_on_spawn_pressed)
	bottom_hbox.add_child(_spawn_button)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(_refresh_list)
	bottom_hbox.add_child(refresh_btn)

	vbox.add_child(bottom_hbox)

	# Initial population
	_refresh_list()

func _refresh_list() -> void:
	_item_list.clear()

	for entry in _catalog_entries:
		# Apply category filter
		if _current_category != Category.ALL:
			var type_filter := _get_category_type(_current_category)
			if entry.type != type_filter:
				continue

		# Apply search filter
		if _search_filter != "":
			var search := _search_filter.to_lower()
			var matches_name := entry.name.to_lower().contains(search)
			var matches_id := entry.id.to_lower().contains(search)
			if not matches_name and not matches_id:
				continue

		var display := "%s [%s]" % [entry.name, entry.id]
		_item_list.add_item(display)

func _get_category_type(category: Category) -> String:
	match category:
		Category.ENEMIES: return "ENEMY"
		Category.NPCS: return "NPC"
		Category.ITEMS: return "ITEM"
		Category.ZONES: return "ZONE"
		Category.QUESTS: return "QUEST"
		Category.SKILLS: return "SKILL"
	return ""

func _on_category_selected(category: int) -> void:
	_current_category = category as Category
	_refresh_list()

func _on_search_changed(text: String) -> void:
	_search_filter = text
	_refresh_list()

func _on_item_selected(index: int) -> void:
	# Show details or enable spawn
	pass

func _on_spawn_pressed() -> void:
	var selected := _item_list.get_selected_items()
	if selected.is_empty():
		GameLog.warn("AdminCatalog: No item selected")
		return

	var item_text := _item_list.get_item_text(selected[0])
	# Extract ID from "[name] [id]"
	var id_match := RegEx.new()
	id_match.compile("\\[([^\\]]+)\\]")
	var result := id_match.search(item_text)
	if result:
		var template_id: String = result.get_string(1)
		var quantity: int = int(_quantity_spin.value)

		# Determine spawn type and call appropriate service
		var success: bool = _spawn_by_id(template_id, quantity)

		if success:
			GameLog.info("AdminCatalog: Spawned %d x %s" % [quantity, template_id])
		else:
			GameLog.error("AdminCatalog: Failed to spawn %s" % template_id)

func _spawn_by_id(template_id: String, quantity: int = 1) -> bool:
	# Validate ID format
	if not IDRegistry.is_valid_id(template_id):
		GameLog.error("AdminCatalog: Invalid ID format: %s" % template_id)
		return false

	var id_type := IDRegistry.get_type(template_id)

	match id_type:
		"ENEMY", "ENTITY":
			return _spawn_enemy(template_id, quantity)
		"NPC":
			return _spawn_npc(template_id)
		"ITEM":
			return _spawn_item(template_id, quantity)
		"ZONE":
			return _teleport_to_zone(template_id)
		"QUEST":
			return _give_quest(template_id)
		"SKILL":
			return _teach_skill(template_id)
		_:
			GameLog.error("AdminCatalog: Unknown type '%s' for ID %s" % [id_type, template_id])
			return false

	return true

func _spawn_enemy(template_id: String, quantity: int) -> bool:
	if SpawnService:
		for i in range(quantity):
			var spawn_pos := Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
			# SpawnService would have a method like spawn_enemy(template_id, position)
			# For now, emit event
			EventHub.entity.spawned.emit(template_id, "zn_debug", spawn_pos)
		return true
	return false

func _spawn_npc(template_id: String) -> bool:
	if SpawnService:
		EventHub.entity.spawned.emit(template_id, "zn_debug", Vector3.ZERO)
		return true
	return false

func _spawn_item(template_id: String, quantity: int) -> bool:
	# Would add to player's inventory via InventoryService
	if InventoryService:
		EventHub.inventory.item_picked_up.emit("plr_admin", template_id, -1)
		return true
	return false

func _teleport_to_zone(zone_id: String) -> bool:
	if ZoneManager:
		EventHub.system.alert_sent.emit("system", "Teleporting to %s" % zone_id, 0, [])
		return true
	return false

func _give_quest(quest_id: String) -> bool:
	GameLog.info("AdminCatalog: Would give quest %s" % quest_id)
	return true

func _teach_skill(skill_id: String) -> bool:
	GameLog.info("AdminCatalog: Would teach skill %s" % skill_id)
	return true

## Get catalog entry by ID
func get_entry_by_id(id: String) -> Dictionary:
	for entry in _catalog_entries:
		if entry.id == id:
			return entry
	return {}

## Get all entries filtered by type
func get_entries_by_type(type_filter: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for entry in _catalog_entries:
		if entry.type == type_filter:
			results.append(entry)
	return results

## Add a new entry to the catalog (for runtime registration)
func register_entry(id: String, name: String, type_str: String, level: int = 1) -> void:
	_catalog_entries.append({
		"id": id,
		"name": name,
		"type": type_str.to_upper(),
		"level": level
	})
	_refresh_list()
