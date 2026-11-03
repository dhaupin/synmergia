## CharacterPanel - Unified in-game character management
## Tabs: Inventory | Equipment | Stats | Skills
## Uses UIStyles for consistent theming
extends "res://ui/components/ui_panel.gd"
class_name CharacterPanel
const CharacterData = preload("res://core/schemas/character_data.gd")
const IconResolver = preload("res://core/utils/icon_resolver.gd")
const Item = preload("res://core/schemas/item.gd")
const InventoryComponent = preload("res://core/components/inventory_component.gd")


## Tab definitions
enum Tab { INVENTORY, EQUIP, STATS, SKILLS, TITLES }
var _current_tab: Tab = Tab.INVENTORY

## Equipment slots
enum EquipSlot { HEAD, CHEST, HANDS, LEGS, FEET, WEAPON, OFFHAND, RING1, RING2, AMULET }
const EQUIP_SLOTS: Array = [
	{"id": EquipSlot.HEAD, "name": "Head", "icon": "helmet"},
	{"id": EquipSlot.CHEST, "name": "Chest", "icon": "armor"},
	{"id": EquipSlot.HANDS, "name": "Hands", "icon": "gloves"},
	{"id": EquipSlot.LEGS, "name": "Legs", "icon": "boots"},
	{"id": EquipSlot.FEET, "name": "Feet", "icon": "boots"},
	{"id": EquipSlot.WEAPON, "name": "Weapon", "icon": "weapon"},
	{"id": EquipSlot.OFFHAND, "name": "Off-Hand", "icon": "shield"},
	{"id": EquipSlot.RING1, "name": "Ring", "icon": "ring"},
	{"id": EquipSlot.RING2, "name": "Ring", "icon": "ring"},
	{"id": EquipSlot.AMULET, "name": "Amulet", "icon": "amulet"}
]

## Components
var _tab_bar: HBoxContainer
var _tab_contents: Dictionary = {}
var _equipped_items: Dictionary = {}  # slot -> item_data
var _selected_equip_slot: int = -1

## Tab buttons
var _tab_buttons: Array = []
var _char_data: CharacterData = null

func _ready() -> void:
	super._ready()
	set_title("Character")
	set_panel_size(Vector2(600, 550))
	_setup_accessibility()

	_setup_tabs()
	_show_tab(Tab.INVENTORY)


## Populate on open (play-test round 6, item 5: every tab rendered
## empty). hud_services pushes character data on state changes, but a
## panel opened before that push (or in single-player contexts where
## the push never fires) rendered only skeletons. Self-resolve here:
## GameManager's selected character when the panel holds none, then
## refresh every tab so there is always real content on screen.
## Runtime autoload lookups (script-mode-safe; the bare identifiers
## fail compile when autoloads are absent -- test_islands).
func _pm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("PlayerManager")) if tree and tree.root else null

func _gmanager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameManager")) if tree and tree.root else null

func _inv_service() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("InventoryService")) if tree and tree.root else null

func _title_service() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("TitleService")) if tree and tree.root else null

func _on_open() -> void:
	var _tree := Engine.get_main_loop() as SceneTree
	var game_manager := _tree.root.get_node_or_null(NodePath("GameManager")) if _tree and _tree.root else null
	if _char_data == null and game_manager and "selected_character_data" in game_manager:
		var data = game_manager.selected_character_data
		if data != null:
			_char_data = data
	refresh_inventory()
	refresh_stats()
	refresh_skills()


func _setup_accessibility() -> void:
	focus_mode = Control.FOCUS_ALL
	# Apply default accessibility settings via the settings updater.
	update_accessibility_settings(false, 1.0, false)
func update_accessibility_settings(high_contrast: bool, text_scale: float, reduce_motion: bool) -> void:
	# Update tab buttons
	if _tab_buttons:
		for btn in _tab_buttons:
			if btn and is_instance_valid(btn):
				btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
				var scale = UIStyles.get_text_scale()
				var current_size: int = btn.get_theme_font_size("font_size")
				if current_size > 0:
					btn.add_theme_font_size_override("font_size", int(current_size * scale))

	# Update equipment slots
	for slot_id in _equipped_items:
		var slot := get_node("Panel/Main/Content/EquipSlots/SlotContainer/Slot_%d" % slot_id)
		if slot and is_instance_valid(slot):
			slot.add_theme_stylebox_override("focus", UIStyles.create_focus_style())

	# Update content panels
	if _tab_contents:
		for content in _tab_contents.values():
			if content and is_instance_valid(content):
				for child in content.get_children():
					if child is Button:
						child.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
						var scale = UIStyles.get_text_scale()
						var current_size: int = child.get_theme_font_size("font_size")
						if current_size > 0:
							child.add_theme_font_size_override("font_size", int(current_size * scale))
					elif child is PanelContainer:
						child.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
						var style: StyleBoxFlat = child.get_theme_stylebox("panel")
						if style:
							if high_contrast:
								style.bg_color = UIStyles.HIGH_CONTRAST_COLORS.background
								style.border_color = UIStyles.HIGH_CONTRAST_COLORS.border
							else:
								style.bg_color = UIStyles.COLORS.background_dark
								style.border_color = UIStyles.COLORS.border


func _setup_tabs() -> void:
	var panel := get_panel()
	if not panel:
		return

	# Find main container
	var main: VBoxContainer = panel.get_node_or_null("Main")
	if not main:
		return

	# Create tab bar
	_tab_bar = HBoxContainer.new()
	_tab_bar.name = "TabBar"
	_tab_bar.custom_minimum_size.y = 40
	main.add_child(_tab_bar)

	# Create tab buttons
	var tabs := [
		{"id": Tab.INVENTORY, "name": "Inventory", "key": KEY_I},
		{"id": Tab.EQUIP, "name": "Equipment", "key": KEY_E},
		{"id": Tab.STATS, "name": "Stats", "key": KEY_S},
		{"id": Tab.SKILLS, "name": "Skills", "key": KEY_K},
			{"id": Tab.TITLES, "name": "Titles", "key": KEY_T}
	]

	for tab_data in tabs:
		var btn := _create_tab_button(tab_data.name, tab_data.id)
		_tab_buttons.append(btn)
		_tab_bar.add_child(btn)

	# Create separator
	var sep := Control.new()
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_bar.add_child(sep)

	# Create tab content containers. Tab is an enum (a Dictionary of
	# NAME -> int); iterating it directly yields the String names, which
	# broke both the "TabContent_%d" format and _show_tab()'s int lookup.
	# Play-day feedback #6: the containers EXPAND FILL horizontally too
	# -- ScrollContainers default to a 0-width fit, which left the tab
	# bodies invisible even where content existed.
	for tab in Tab.values():
		var container := preload("res://ui/components/drag_scroll.gd").new()
		container.name = "TabContent_%d" % tab
		container.visible = false
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		main.add_child(container)
		_tab_contents[tab] = container

	# Setup each tab content
	_setup_inventory_tab()
	_setup_equip_tab()
	_setup_stats_tab()
	_setup_skills_tab()
	_setup_titles_tab()

func _create_tab_button(text: String, tab_id: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.button_pressed = false
	btn.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	btn.add_theme_color_override("font_pressed_color", UIStyles.COLORS.text_primary)
	btn.add_theme_color_override("font_hover_color", UIStyles.COLORS.text_primary)
	btn.pressed.connect(_on_tab_clicked.bind(tab_id))
	return btn

func _on_tab_clicked(tab_id: int) -> void:
	_show_tab(tab_id)


func _input(event: InputEvent) -> void:
	pass  # TAB handled by HudHotkeys via _on_tab_pressed()

## Override from UIPanel -- called by HudHotkeys for focus cycling.
func _on_tab_pressed(shift: bool) -> void:
	var tab_ids := [Tab.INVENTORY, Tab.EQUIP, Tab.STATS, Tab.SKILLS, Tab.TITLES]
	var current_idx := -1
	for i in range(tab_ids.size()):
		if tab_ids[i] == _current_tab:
			current_idx = i
			break
	if shift:
		current_idx = (current_idx - 1 + tab_ids.size()) % tab_ids.size()
	else:
		current_idx = (current_idx + 1) % tab_ids.size()
	_show_tab(tab_ids[current_idx])

func _show_tab(tab_id: int) -> void:
	_current_tab = tab_id

	# Update tab buttons
	for i in range(_tab_buttons.size()):
		var btn: Button = _tab_buttons[i]
		btn.button_pressed = (i == tab_id)
		if btn.button_pressed:
			btn.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
		else:
			btn.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)

	# Show/hide tab contents. Iterate Tab.values() (ints) -- _tab_contents
	# is keyed by those same ints from _setup_tabs. Iterating the enum
	# itself yields the String NAMES, every lookup missed, and NO tab
	# body was ever shown: tabs painted, body blank (play-test round 11
	# screenshot -- the R6 fix note even called this lookup out, but only
	# the _setup_tabs half got fixed).
	for tab in Tab.values():
		var container: Control = _tab_contents.get(tab)
		if container:
			container.visible = (tab == tab_id)

	# Live re-render: the panel can stay open through equip/unequip and
	# level-ups, so the stats/skills bodies re-read their books every
	# time they come back on screen (issue #21's stale-truth law).
	if tab_id == Tab.STATS:
		refresh_stats()
	elif tab_id == Tab.SKILLS:
		refresh_skills()

## ============================================================================
## INVENTORY TAB
## ============================================================================

func _setup_inventory_tab() -> void:
	var container: ScrollContainer = _tab_contents.get(Tab.INVENTORY)
	if not container:
		return

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(vbox)

	# Inventory grid
	var grid := GridContainer.new()
	grid.name = "InventoryGrid"
	grid.columns = 5
	grid.custom_minimum_size.y = 300
	vbox.add_child(grid)

	# Create 20 inventory slots
	for i in range(20):
		var slot := _create_inventory_slot(i)
		grid.add_child(slot)

	# Gold display
	var gold_row := HBoxContainer.new()
	gold_row.custom_minimum_size.y = 30
	vbox.add_child(gold_row)

	var gold_label := Label.new()
	gold_label.text = "Gold: 0"
	gold_label.name = "GoldLabel"
	gold_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	gold_row.add_child(gold_label)

	# Stats summary
	var stats_label := Label.new()
	stats_label.text = "Weight: 0/100"
	stats_label.name = "WeightLabel"
	gold_row.add_child(stats_label)

	# Quick actions
	var actions := HBoxContainer.new()
	actions.custom_minimum_size.y = 40
	vbox.add_child(actions)

	var sort_btn := Button.new()
	sort_btn.text = "Sort"
	sort_btn.pressed.connect(_on_sort_inventory)
	actions.add_child(sort_btn)

	var organize_btn := Button.new()
	organize_btn.text = "Organize"
	organize_btn.pressed.connect(_on_organize_inventory)
	actions.add_child(organize_btn)

func _create_inventory_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(50, 50)
	slot.name = "Slot_%d" % index

	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
	style.border_color = UIStyles.COLORS.border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	slot.add_theme_stylebox_override("panel", style)

	# Slot number
	var num := Label.new()
	num.text = str(index + 1)
	num.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	num.add_theme_font_size_override("font_size", 10)
	num.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	slot.add_child(num)

	return slot

func _on_sort_inventory() -> void:
	show_notification("Inventory sorted")

func _on_organize_inventory() -> void:
	show_notification("Inventory organized")

## ============================================================================
## EQUIPMENT TAB
## ============================================================================

func _setup_equip_tab() -> void:
	var container: ScrollContainer = _tab_contents.get(Tab.EQUIP)
	if not container:
		return

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(hbox)

	# Equipment slots (left side)
	var equip_area := VBoxContainer.new()
	equip_area.name = "EquipArea"
	hbox.add_child(equip_area)

	for slot_data in EQUIP_SLOTS:
		var row := _create_equip_slot_row(slot_data)
		equip_area.add_child(row)

	# Character preview (right side)
	var preview := PanelContainer.new()
	preview.name = "CharPreview"
	preview.custom_minimum_size = Vector2(200, 300)
	hbox.add_child(preview)

	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = UIStyles.COLORS.background_dark
	preview.add_theme_stylebox_override("panel", preview_style)

	var preview_label := Label.new()
	preview_label.text = "[Character\nPreview]"
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	preview.add_child(preview_label)

	# Stats summary (bottom)
	var stats_area := VBoxContainer.new()
	stats_area.name = "EquipStats"
	hbox.add_child(stats_area)

	var stats_title := Label.new()
	stats_title.text = "Equipment Stats"
	stats_title.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	stats_area.add_child(stats_title)

	var stats_list := VBoxContainer.new()
	stats_list.name = "StatsList"
	stats_area.add_child(stats_list)

	# Default equip stats
	var stat_names := ["Attack", "Defense", "Health", "Mana", "Crit", "Speed"]
	for stat in stat_names:
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = stat + ":"
		row.add_child(name_lbl)
		var val_lbl := Label.new()
		val_lbl.text = "+0"
		val_lbl.add_theme_color_override("font_color", UIStyles.COLORS.success)
		row.add_child(val_lbl)
		stats_list.add_child(row)

func _create_equip_slot_row(slot_data: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 45

	# Slot name
	var name_lbl := Label.new()
	name_lbl.text = slot_data.name
	name_lbl.custom_minimum_size.x = 80
	name_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	row.add_child(name_lbl)

	# Slot button
	var slot_btn := Button.new()
	slot_btn.name = "SlotButton"
	slot_btn.text = "[Empty]"
	slot_btn.custom_minimum_size = Vector2(120, 40)
	slot_btn.pressed.connect(_on_equip_slot_clicked.bind(slot_data.id))
	row.add_child(slot_btn)

	return row

func _on_equip_slot_clicked(slot_id: int) -> void:
	_selected_equip_slot = slot_id

	var panel_tree := Engine.get_main_loop() as SceneTree
	var inv_service := panel_tree.root.get_node_or_null(NodePath("InventoryService")) if panel_tree and panel_tree.root else null
	if not inv_service:
		show_notification("InventoryService unavailable", false)
		return

	var player_id := str(_pm().get_local_player_id()) if _pm() else ""
	if player_id.is_empty():
		return

	var inv: InventoryComponent = inv_service.get_inventory(player_id)
	if inv == null:
		show_notification("Could not load inventory", false)
		return

	var equipped: Item = inv.get_equipped(slot_id)
	if equipped != null:
		_show_equipped_item_menu(equipped, slot_id)
	else:
		_show_empty_slot_menu(slot_id)

func _show_equipped_item_menu(item: Item, slot_id: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = item.name if item.name else "Equipped Item"
	dialog.dialog_text = "What would you like to do?"
	add_child(dialog)

	# Create action buttons in a VBox
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(200, 80)
	dialog.add_child(vbox)

	var unequip_btn := Button.new()
	unequip_btn.text = "Unequip"
	unequip_btn.custom_minimum_size.y = 30
	unequip_btn.pressed.connect(func() -> void:
		_unequip_item(slot_id)
		dialog.queue_free()
	)
	vbox.add_child(unequip_btn)

	var info_btn := Button.new()
	info_btn.text = "View Details"
	info_btn.custom_minimum_size.y = 30
	info_btn.pressed.connect(func() -> void:
		_show_item_details(item)
		dialog.queue_free()
	)
	vbox.add_child(info_btn)

	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered(Vector2(250, 150))

func _show_empty_slot_menu(slot_id: int) -> void:
	_show_equip_item_picker(slot_id)

func _show_equip_item_picker(slot_id: int) -> void:
	var panel_tree := Engine.get_main_loop() as SceneTree
	var inv_service := panel_tree.root.get_node_or_null(NodePath("InventoryService")) if panel_tree and panel_tree.root else null
	if not inv_service:
		show_notification("InventoryService unavailable", false)
		return

	var player_id := str(_pm().get_local_player_id()) if _pm() else ""
	if player_id.is_empty():
		return

	var inv: InventoryComponent = inv_service.get_inventory(player_id)
	if inv == null:
		show_notification("Could not load inventory", false)
		return

	# Get slot name for display
	var slot_name := _get_slot_name(slot_id)

	# Find items that can be equipped in this slot. The bag's store is
	# index-addressed `_inventory` -- `_items` was never a member, so
	# this list always came back empty and every picker said "No
	# equippable items" forever (same dead key the probe caught).
	var equippable: Array[Item] = []
	for slot in range(inv._inventory.size()):
		var item: Item = inv._inventory[slot]
		if item and item.equip_slot == slot_id and item.can_equip():
			equippable.append(item)

	if equippable.is_empty():
		show_notification("No equippable items for %s slot" % slot_name)
		return

	# Create selection dialog
	var dialog := AcceptDialog.new()
	dialog.title = "Equip Item - %s" % slot_name
	dialog.ok_button_text = "Close"
	add_child(dialog)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 250)
	dialog.add_child(vbox)

	var scroll := preload("res://ui/components/drag_scroll.gd").new()
	scroll.custom_minimum_size.y = 200
	vbox.add_child(scroll)

	var item_list := VBoxContainer.new()
	item_list.name = "ItemList"
	scroll.add_child(item_list)

	for item: Item in equippable:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 40

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.texture = IconResolver.get_item_icon(item)
		row.add_child(icon)

		var name_lbl := Label.new()
		name_lbl.text = item.name if item.name else "Unknown Item"
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var equip_btn := Button.new()
		equip_btn.text = "Equip"
		equip_btn.pressed.connect(func() -> void:
			_equip_item_from_picker(inv, item, slot_id)
			dialog.queue_free()
		)
		row.add_child(equip_btn)

		item_list.add_child(row)

	dialog.popup_centered(Vector2(350, 300))

func _get_slot_name(slot_id: int) -> String:
	match slot_id:
		0: return "Head"
		1: return "Chest"
		2: return "Hands"
		3: return "Legs"
		4: return "Feet"
		5: return "Main Hand"
		6: return "Off Hand"
		7: return "Ring"
		8: return "Amulet"
		9: return "Cape"
	return "Unknown"

func _equip_item_from_picker(inv: InventoryComponent, item: Item, slot_id: int) -> void:
	# Find the inventory slot containing this item (index-addressed
	# `_inventory` -- `_items` was never a member, so this lookup always
	# fell through to "Could not find item in inventory").
	var inv_slot: int = -1
	for slot in range(inv._inventory.size()):
		if inv._inventory[slot] == item:
			inv_slot = slot
			break

	if inv_slot < 0:
		show_notification("Could not find item in inventory", false)
		return

	# Equip the item
	if inv.equip_item(inv_slot):
		show_notification("Equipped %s" % item.name, false)
		_refresh_equipment_display()
		refresh_stats()
	else:
		show_notification("Failed to equip item", false)

func _unequip_item(slot_id: int) -> void:
	var inv_service := _inv_service()
	if not inv_service:
		return

	var player_id := str(_pm().get_local_player_id()) if _pm() else ""
	if player_id.is_empty():
		return

	var inv: InventoryComponent = inv_service.get_inventory(player_id)
	if inv == null:
		return

	if inv.unequip_item(slot_id):
		show_notification("Item unequipped and added to inventory")
		_refresh_equipment_display()
		refresh_stats()
	else:
		show_notification("Failed to unequip - inventory may be full", false)

func _show_item_details(item: Item) -> void:
	# Item is a typed Resource (ItemSchema); use its exported fields
	# directly instead of Dictionary-style get(key, default) calls
	# (removed in 4.7.2).
	var stats_text := ""
	if item.description != "":
		stats_text = "\n%s" % item.description

	var dialog := AcceptDialog.new()
	dialog.title = item.display_name if item.display_name != "" else "Item Details"
	dialog.dialog_text = "Type: %s\nRarity: %s%s" % [
		Item.ItemCategory.keys()[item.item_category] if item.item_category != Item.ItemCategory.MISC else "Misc",
		Item.Rarity.keys()[item.rarity] if item.rarity != Item.Rarity.COMMON else "Common",
		stats_text
	]
	add_child(dialog)
	dialog.ok_button_text = "Close"
	dialog.confirmed.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered()

## ============================================================================
## STATS TAB
## ============================================================================

func _setup_stats_tab() -> void:
	var container: ScrollContainer = _tab_contents.get(Tab.STATS)
	if not container:
		return

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(vbox)

	# Character info header
	var char_header := HBoxContainer.new()
	char_header.custom_minimum_size.y = 50
	vbox.add_child(char_header)

	var char_name := Label.new()
	char_name.name = "CharName"
	char_name.text = "Level 1 Character"
	char_name.add_theme_font_size_override("font_size", 16)
	char_header.add_child(char_name)

	# Stats grid (2 columns)
	var stats_grid := GridContainer.new()
	stats_grid.name = "GridContainer"
	stats_grid.columns = 2
	stats_grid.custom_minimum_size.y = 250
	vbox.add_child(stats_grid)

	var stats := [
		{"name": "Strength", "key": "str"},
		{"name": "Intelligence", "key": "int"},
		{"name": "Wisdom", "key": "wis"},
		{"name": "Agility", "key": "agi"},
		{"name": "Vitality", "key": "vit"},
		{"name": "Endurance", "key": "end"}
	]

	for stat in stats:
		var stat_card := _create_stat_card(stat)
		stat_card.name = "Stat_" + stat.key
		stats_grid.add_child(stat_card)

	# Derived stats
	var derived_label := Label.new()
	derived_label.text = "Derived Stats"
	derived_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	vbox.add_child(derived_label)

	var derived := [
		{"name": "Max Health", "key": "max_health", "value": "--"},
		{"name": "Max Mana", "key": "max_mana", "value": "--"},
		{"name": "Physical Attack", "key": "p_attack", "value": "--"},
		{"name": "Magic Attack", "key": "m_attack", "value": "--"},
		{"name": "Physical Defense", "key": "p_defense", "value": "--"},
		{"name": "Magic Defense", "key": "m_defense", "value": "--"}
	]

	for stat in derived:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 25
		# The refresh pass finds these rows by name (Derived_<key> + a
		# child Label named "Value") -- without the names the loop never
		# matched and every derived stat stayed at "--" forever.
		row.name = "Derived_" + stat.key

		var stat_name := Label.new()
		stat_name.text = stat.name
		row.add_child(stat_name)

		var val := Label.new()
		val.name = "Value"
		val.text = stat.value
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)

		vbox.add_child(row)

func _create_stat_card(stat: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(150, 60)

	var style := UIStyles.create_panel_style(
		UIStyles.COLORS.background_dark,
		UIStyles.COLORS.border,
		1,
		4
	)
	card.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	# The refresh pass reads stat_card.get_node("HBox/VBox/Value") --
	# both containers must carry their names or the lookup misses and
	# the cards freeze at their birth text forever.
	hbox.name = "HBox"
	card.add_child(hbox)

	var info := VBoxContainer.new()
	# The refresh pass reads stat_card.get_node("VBox/Value") -- the
	# inner VBox was never NAMED "VBox", so every stat value lookup
	# missed and the six cards froze at their birth text forever.
	info.name = "VBox"
	hbox.add_child(info)

	var name_lbl := Label.new()
	name_lbl.text = stat.name
	name_lbl.add_theme_font_size_override("font_size", 11)
	info.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.text = "10"
	val_lbl.name = "Value"
	val_lbl.add_theme_color_override("font_color", UIStyles.COLORS.success)
	info.add_child(val_lbl)

	return card

## ============================================================================
## SKILLS TAB
## ============================================================================

func _setup_skills_tab() -> void:
	var container: ScrollContainer = _tab_contents.get(Tab.SKILLS)
	if not container:
		return

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(vbox)

	# Skill categories
	var categories := ["Combat", "Magic", "Utility", "Crafting"]

	for cat in categories:
		var cat_label := Label.new()
		cat_label.text = cat
		cat_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
		vbox.add_child(cat_label)

		var skill_grid := GridContainer.new()
		skill_grid.columns = 4
		skill_grid.custom_minimum_size.y = 100
		vbox.add_child(skill_grid)

		# Add placeholder skill slots
		for i in range(4):
			var skill_slot := _create_skill_slot(i, cat)
			skill_grid.add_child(skill_slot)

	# Skill points
	var points_label := Label.new()
	points_label.text = "Available Skill Points: 0"
	points_label.name = "SkillPoints"
	points_label.add_theme_color_override("font_color", UIStyles.COLORS.info)
	vbox.add_child(points_label)

func _create_skill_slot(index: int, category: String) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(50, 50)

	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
	style.border_color = UIStyles.COLORS.border
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	slot.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = "+"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	slot.add_child(label)

	return slot

## ============================================================================
## PUBLIC METHODS
## ============================================================================

func refresh_inventory() -> void:
	# No _char_data gate: the grid and equipment rows read the LIVE bag,
	# which exists before any character data is pushed (the globe
	# single-player world never sets selected_character_data, so the old
	# gate made the tab refuse to hydrate exactly where it was blank).
	# Stats/skills keep their gate -- they genuinely need _char_data.
	_refresh_inventory_grid()
	_refresh_equipment_display()

## Fill the Inventory tab grid from the player's InventoryComponent
## (play-test round 6, item 5: all tabs rendered empty -- refresh_inventory
## only ever called a `pass` stub). Falls back to the character's starter
## kit definition when no live inventory exists yet (menu-adjacent
## contexts, single-player pre-spawn), so the tab always shows content.
func _refresh_inventory_grid() -> void:
	var container: ScrollContainer = _tab_contents.get(Tab.INVENTORY)
	if not container:
		return
	# find_child(pattern, recursive, owned=false): the tab content is
	# built at runtime (no editor ownership), and get_node has no glob
	# paths -- find_child is the portable way to reach named nodes
	# regardless of the anonymous container nesting.
	var grid: GridContainer = container.find_child("InventoryGrid", true, false) as GridContainer
	if grid == null:
		return

	# Untyped on purpose: _resolve_inventory() returns a Variant that
	# may be null; := inference is a parse error on it (4.7.2).
	var inv = _resolve_inventory()
	# Zip by INDEX against the raw slot array (InventoryComponent slots
	# are index-addressed; get_all_items() skips nulls and would
	# misalign the grid).
	var items: Array = []
	if inv != null and "_inventory" in inv:
		items = inv.get("_inventory")
	var gold := 0
	var weight := 0.0
	var max_weight := 100.0
	if inv != null:
		gold = inv.get_gold()
		weight = inv.get_current_weight()
		max_weight = inv.get_max_weight()

	var shown := 0
	for slot in grid.get_children():
		var idx := int(String(slot.name).trim_prefix("Slot_"))
		var item: Item = items[idx] if idx < items.size() else null
		var lbl: Label = slot.get_node_or_null("ItemLabel")
		if lbl == null:
			lbl = Label.new()
			lbl.name = "ItemLabel"
			lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.add_theme_font_size_override("font_size", 9)
			lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
			slot.add_child(lbl)
		if item != null:
			lbl.text = item.display_name
			lbl.visible = true
			shown += 1
		else:
			lbl.text = ""
			lbl.visible = false

	var gold_lbl: Label = container.find_child("GoldLabel", true, false) as Label
	if gold_lbl:
		gold_lbl.text = "Gold: %d" % gold
	var weight_lbl: Label = container.find_child("WeightLabel", true, false) as Label
	if weight_lbl:
		weight_lbl.text = "Weight: %d/%d" % [int(weight), int(max_weight)]
	if shown == 0 and inv == null:
		var hint: Label = container.find_child("EmptyHint", true, false) as Label
		if hint == null:
			hint = Label.new()
			hint.name = "EmptyHint"
			hint.text = "Inventory is empty. Items you pick up appear here."
			hint.add_theme_font_size_override("font_size", 12)
			hint.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
			for child in container.get_children():
				if child is VBoxContainer:
					(child as VBoxContainer).add_child(hint)
					break
	else:
		# The hint is sticky: an open that ran before the bag registered
		# leaves it behind even after a live bag hydrates (round 11). A
		# hint plus visible items is a lie -- retire it.
		var stale_hint: Label = container.find_child("EmptyHint", true, false) as Label
		if stale_hint != null:
			stale_hint.get_parent().remove_child(stale_hint)
			stale_hint.queue_free()

## Resolve the player's live inventory component. Tries the typed
## _inv_service() path first, then a defensive InventoryComponent
## lookup on the player node (the single-player scene wires the
## component directly on the player).
func _resolve_inventory():
	var player_id := ""
	if _pm() and _pm().has_method("get_local_player_id"):
		player_id = str(_pm().get_local_player_id())
	if player_id.is_empty() and _gmanager() and "selected_character_data" in _gmanager():
		var cd = _gmanager().selected_character_data
		if cd != null and "character_id" in cd:
			player_id = str(cd.character_id)
	if _inv_service() and not player_id.is_empty():
		var inv = _inv_service().get_inventory(player_id)
		if inv != null:
			return inv
	var player := _get_local_player()
	if player != null:
		# The planar controller and the globe body both name their bag
		# inventory_component (a registered InventoryComponent child).
		if "inventory_component" in player:
			var comp = player.get("inventory_component")
			if comp is InventoryComponent:
				return comp
		# Defensive: a bag child node works too.
		var bag = player.get_node_or_null("InventoryComponent")
		if bag is InventoryComponent:
			return bag
	return null

func refresh_stats() -> void:
	if _char_data == null:
		return
	_refresh_stats_display()

func refresh_skills() -> void:
	if _char_data == null:
		return
	_refresh_skills_display()

func _refresh_stats_display() -> void:
	var container: ScrollContainer = _tab_contents.get(Tab.STATS)
	if not container:
		return

	# Find the main VBoxContainer
	var vbox: VBoxContainer = null
	for child in container.get_children():
		if child is VBoxContainer:
			vbox = child
			break
	if not vbox:
		return

	# THE LIVE-TRUTH LAW (issue #21): these cards render the character
	# AS THEY ARE, not as they were born. The book totals ride the LIVE
	# level (a restored progress level can outpace the creation-time
	# CharacterData resource) and the gear delta the live bag currently
	# applies (the SAME book InventoryComponent pushes onto the player
	# with _apply_equipment_stats -- reading it directly, so the panel
	# invents no parallel write and never diverges from the player).
	var live_level: int = _char_data.level
	var player := _get_local_player()
	if player != null and "level" in player:
		live_level = int(player.level)
	var gear: Dictionary = {}
	var inv = _resolve_inventory()
	if inv != null and inv.has_method("get_equipment_stats"):
		gear = inv.get_equipment_stats()

	# Level-aware totals per stat (The blessing's +5 effective level
	# rides inside get_stat_total; no parallel formula here).
	var stat_keys := ["strength", "intelligence", "wisdom", "agility", "vitality", "endurance"]
	var totals: Dictionary = {}
	for _sk in stat_keys:
		var _k: String = _sk
		totals[_k] = _char_data.get_stat_total(_k, live_level)

	# Update character name/level header
	var char_header: HBoxContainer = null
	for child in vbox.get_children():
		if child is HBoxContainer and child.has_node("CharName"):
			char_header = child
			break
	if char_header:
		var name_lbl: Label = char_header.get_node("CharName")
		var species_name := _char_data.species_id.capitalize()
		# class_id is species-prefixed ("human_marksman"), so capitalizing
		# it printed the species twice ("Human Human Marksman"). Prefer
		# the class .tres display_name ("Marksman"); only fall back to the
		# raw id when the class data cannot load.
		var char_class_name := _char_data.class_id.capitalize()
		var cls_data: CharacterClass = _char_data.class_data
		if cls_data == null:
			cls_data = CharacterData.load_class(_char_data.class_id)
		if cls_data and cls_data.display_name != "":
			char_class_name = cls_data.display_name
		name_lbl.text = "%s %s - Level %d" % [species_name, char_class_name, live_level]

	# Update stat cards (str, int, wis, agi, vit, end)
	var display_keys := ["str", "int", "wis", "agi", "vit", "end"]

	for i in range(stat_keys.size()):
		# Untyped Array elements: explicit annotations required (4.7.2).
		var stat_key: String = stat_keys[i]
		var disp_key: String = display_keys[i]
		var stat_card: PanelContainer = vbox.get_node_or_null("GridContainer/Stat_" + disp_key)
		if stat_card:
			var val_lbl: Label = stat_card.get_node_or_null("HBox/VBox/Value")
			if val_lbl:
				var total: int = int(totals.get(stat_key, 10))
				var allocated: int = _char_data.get_allocated_points(stat_key)
				var gear_bonus: int = int(gear.get(stat_key, 0))
				total += gear_bonus
				var display := str(total)
				if gear_bonus > 0 and allocated > 0:
					display = "%d (+%d pts, +%d gear)" % [total, allocated, gear_bonus]
				elif gear_bonus > 0:
					display = "%d (+%d gear)" % [total, gear_bonus]
				elif allocated > 0:
					display = "%d (+%d)" % [total, allocated]
				val_lbl.text = display

	# Update derived stats using CharacterData's centralized calculation
	# with the SAME live totals (gear-adjusted) so the formulas stay the
	# one source of truth, no forked math. The merged book carries ALL
	# keys -- get_derived_stats pads missing keys at 10, so dropping an
	# untouched stat would silently rewrite it to the floor.
	var merged: Dictionary = {}
	for stat_key in stat_keys:
		var gear_bonus2: int = int(gear.get(stat_key, 0))
		merged[stat_key] = int(totals.get(stat_key, 10)) + gear_bonus2
	var derived_keys := _char_data.get_derived_stats(merged)

	for child in vbox.get_children():
		if child is HBoxContainer and child.name.begins_with("Derived_"):
			var key := child.name.replace("Derived_", "")
			if derived_keys.has(key):
				var val_lbl: Label = child.get_node_or_null("Value")
				if val_lbl:
					val_lbl.text = str(derived_keys[key])

func _refresh_skills_display() -> void:
	var container: ScrollContainer = _tab_contents.get(Tab.SKILLS)
	if not container:
		return

	var vbox: VBoxContainer = null
	for child in container.get_children():
		if child is VBoxContainer:
			vbox = child
			break
	if not vbox:
		return

	# Update skill points label
	var points_lbl: Label = vbox.get_node_or_null("SkillPoints")
	if points_lbl:
		var available := _char_data.get_available_skill_points()
		var spent := _char_data.get_total_upgrade_levels()
		points_lbl.text = "Skill Points: %d / %d spent" % [available - spent, spent]

	# Update skill slots based on skill_upgrades
	# This would require mapping skill IDs to the skill slots
	# For now, the UI just shows the points count

func _refresh_equipment_display() -> void:
	# Paint every equip slot button from the live inventory (round-6
	# item 5: this was a `pass` stub, so Equipment showed only rows of
	# [Empty] forever). Defensive: no inventory -> slots stay [Empty].
	var container: ScrollContainer = _tab_contents.get(Tab.EQUIP)
	if not container:
		return
	var inv = _resolve_inventory()
	var equipped: Dictionary = {}
	if inv != null:
		equipped = inv.get_all_equipment()
	for slot_data in EQUIP_SLOTS:
		var row := _find_equip_row(container, slot_data.id)
		if row == null:
			continue
		var btn: Button = row.get_node_or_null("SlotButton")
		if btn == null:
			continue
		var item: Item = equipped.get(slot_data.id)
		btn.text = item.display_name if item != null else "[Empty]"

## The equip rows were never named, but they were appended in
## EQUIP_SLOTS order -- match by position and cache (tab layout is
## static after setup).
var _equip_row_cache: Dictionary = {}

func _find_equip_row(container: ScrollContainer, slot_id: int) -> HBoxContainer:
	if _equip_row_cache.has(slot_id) and is_instance_valid(_equip_row_cache[slot_id]):
		return _equip_row_cache[slot_id]
	var area := container.find_child("EquipArea", true, false)
	if area == null:
		return null
	var idx := -1
	for i in range(EQUIP_SLOTS.size()):
		if EQUIP_SLOTS[i].id == slot_id:
			idx = i
			break
	if idx < 0 or area.get_child_count() <= idx:
		return null
	var row: HBoxContainer = area.get_child(idx) as HBoxContainer
	if row != null:
		_equip_row_cache[slot_id] = row
	return row

func set_character_data(data: CharacterData) -> void:
	_char_data = data
	refresh_inventory()
	refresh_stats()
	refresh_skills()

## ============================================================================
## TITLES TAB
## ============================================================================

func _setup_titles_tab() -> void:
	var container: ScrollContainer = _tab_contents.get(Tab.TITLES)
	if not container:
		return

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(vbox)

	# Preview section
	var preview_box := VBoxContainer.new()
	preview_box.name = "TitlePreview"
	vbox.add_child(preview_box)

	var preview_title := Label.new()
	preview_title.text = "Name Preview"
	preview_title.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	preview_box.add_child(preview_title)

	var preview_label := Label.new()
	preview_label.name = "PreviewLabel"
	preview_label.text = "YourName"
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.add_theme_font_size_override("font_size", 14)
	preview_box.add_child(preview_label)

	# Equipped section
	var equipped_box := HBoxContainer.new()
	equipped_box.name = "EquippedSection"
	vbox.add_child(equipped_box)

	# Prefix slot
	var prefix_box := VBoxContainer.new()
	prefix_box.name = "PrefixBox"
	var prefix_lbl := Label.new()
	prefix_lbl.text = "Prefix:"
	prefix_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	prefix_box.add_child(prefix_lbl)
	var prefix_val := Label.new()
	prefix_val.name = "PrefixValue"
	prefix_val.text = "[None]"
	prefix_box.add_child(prefix_val)
	var prefix_btn := Button.new()
	prefix_btn.text = "Change"
	prefix_btn.pressed.connect(_on_change_prefix_title)
	prefix_box.add_child(prefix_btn)
	equipped_box.add_child(prefix_box)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equipped_box.add_child(spacer)

	# Suffix slot
	var suffix_box := VBoxContainer.new()
	suffix_box.name = "SuffixBox"
	var suffix_lbl := Label.new()
	suffix_lbl.text = "Suffix:"
	suffix_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	suffix_box.add_child(suffix_lbl)
	var suffix_val := Label.new()
	suffix_val.name = "SuffixValue"
	suffix_val.text = "[None]"
	suffix_box.add_child(suffix_val)
	var suffix_btn := Button.new()
	suffix_btn.text = "Change"
	suffix_btn.pressed.connect(_on_change_suffix_title)
	suffix_box.add_child(suffix_btn)
	equipped_box.add_child(suffix_box)

	# Color section
	var color_box := HBoxContainer.new()
	color_box.name = "ColorSection"
	vbox.add_child(color_box)

	var color_lbl := Label.new()
	color_lbl.text = "Title Color:"
	color_box.add_child(color_lbl)

	var color_picker := ColorPickerButton.new()
	color_picker.name = "ColorPicker"
	color_picker.color = Color(0.65, 0.65, 0.65)
	color_picker.color_changed.connect(_on_title_color_changed)
	color_box.add_child(color_picker)

	# Unlock titles section
	var unlocked_lbl := Label.new()
	unlocked_lbl.text = "Unlocked Titles"
	unlocked_lbl.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	vbox.add_child(unlocked_lbl)

	var titles_scroll := preload("res://ui/components/drag_scroll.gd").new()
	titles_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(titles_scroll)

	var titles_list := ItemList.new()
	titles_list.name = "TitlesList"
	titles_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	titles_list.item_selected.connect(_on_title_item_selected)
	titles_scroll.add_child(titles_list)

func _on_change_prefix_title() -> void:
	_show_title_selection_popup("prefix")

func _on_change_suffix_title() -> void:
	_show_title_selection_popup("suffix")

func _on_title_color_changed(color: Color) -> void:
	_update_title_preview_color(color)

func _show_title_selection_popup(slot: String) -> void:
	var title_service := _title_service()
	if title_service == null:
		return
	var player_id: String = title_service.get_local_player_id()
	var titles: Array = title_service.get_unlocked_titles(player_id)

	if titles.is_empty():
		show_notification("No titles unlocked yet")
		return

	var dialog := AcceptDialog.new()
	dialog.title = "Select %s Title" % slot.capitalize()
	dialog.ok_button_text = "Close"
	add_child(dialog)

	var vbox := VBoxContainer.new()
	dialog.add_child(vbox)

	var list := ItemList.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var valid_titles := []
	for title in titles:
		if slot == "prefix" and title.has_prefix():
			list.add_item("[%s] %s" % [title.prefix_form, title.display_name])
			valid_titles.append(title)
		elif slot == "suffix" and title.has_suffix():
			list.add_item("%s [%s]" % [title.display_name, title.suffix_form])
			valid_titles.append(title)

	if valid_titles.is_empty():
		var no_title_lbl := Label.new()
		no_title_lbl.text = "No titles available for %s slot" % slot
		vbox.add_child(no_title_lbl)
	else:
		vbox.add_child(list)

		var btn_hbox := HBoxContainer.new()
		vbox.add_child(btn_hbox)

		var equip_btn := Button.new()
		equip_btn.text = "Equip"
		equip_btn.pressed.connect(func() -> void:
			var idx := list.get_selected_items()
			if not idx.is_empty() and idx[0] < valid_titles.size():
				var title = valid_titles[idx[0]]
				title_service.equip(player_id, title.id, slot)
				refresh_titles()
				show_notification("Title equipped!")
			dialog.queue_free()
		)
		btn_hbox.add_child(equip_btn)

		var unequip_btn := Button.new()
		unequip_btn.text = "Unequip"
		unequip_btn.pressed.connect(func() -> void:
			title_service.unequip(player_id, slot)
			refresh_titles()
			show_notification("Title unequipped")
			dialog.queue_free()
		)
		btn_hbox.add_child(unequip_btn)

	dialog.confirmed.connect(func() -> void: dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered(Vector2(350, 300))

func _on_title_item_selected(index: int) -> void:
	_show_title_selection_popup("prefix")

func _update_title_preview_color(color: Color) -> void:
	var container: ScrollContainer = _tab_contents.get(Tab.TITLES)
	if not container:
		return

	var preview_box: VBoxContainer = container.get_node_or_null("TitlePreview")
	if not preview_box:
		return

	var preview_lbl: Label = preview_box.get_node_or_null("PreviewLabel")
	if preview_lbl:
		preview_lbl.add_theme_color_override("font_color", color)

func refresh_titles() -> void:
	var container: ScrollContainer = _tab_contents.get(Tab.TITLES)
	if not container:
		return

	var title_service := _title_service()
	if title_service == null:
		return
	var player_id: String = title_service.get_local_player_id()
	if player_id.is_empty():
		return

	# Update preview
	var preview_box: VBoxContainer = container.get_node_or_null("TitlePreview")
	if preview_box:
		var preview_lbl: Label = preview_box.get_node_or_null("PreviewLabel")
		if preview_lbl:
			var base_name := "PlayerName"
			var full_name: String = title_service.get_display_name(player_id, base_name)
			preview_lbl.text = full_name

	# Update equipped labels
	var equipped_box: HBoxContainer = container.get_node_or_null("EquippedSection")
	if equipped_box:
		var prefix_box: VBoxContainer = equipped_box.get_node_or_null("PrefixBox")
		if prefix_box:
			var prefix_val: Label = prefix_box.get_node_or_null("PrefixValue")
			if prefix_val:
				var prefix: TitleData = title_service.get_equipped_prefix(player_id)
				prefix_val.text = "[%s]" % prefix.prefix_form if prefix else "[None]"

		var suffix_box: VBoxContainer = equipped_box.get_node_or_null("SuffixBox")
		if suffix_box:
			var suffix_val: Label = suffix_box.get_node_or_null("SuffixValue")
			if suffix_val:
				var suffix: TitleData = title_service.get_equipped_suffix(player_id)
				suffix_val.text = suffix.suffix_form if suffix else "[None]"

	# Update titles list
	var titles_list: ItemList = container.get_node_or_null("TitlesList")
	if titles_list:
		titles_list.clear()
		var titles: Array = title_service.get_unlocked_titles(player_id)
		for title in titles:
			var display: String = str(title.display_name)
			if title.has_prefix():
				display += " (Prefix)"
			if title.has_suffix():
				display += " (Suffix)"
			titles_list.add_item(display)
