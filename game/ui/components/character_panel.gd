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


func _setup_accessibility() -> void:
func update_accessibility_settings(high_contrast: bool, text_scale: float, reduce_motion: bool) -> void:
	# Update tab buttons
	if _tab_buttons:
		for btn in _tab_buttons:
			if btn and is_instance_valid(btn):
				btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
				var scale = UIStyles.get_text_scale()
				var current_size := btn.get_theme_font_size("font_size")
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
						var current_size := child.get_theme_font_size("font_size")
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

	# Create tab content containers
	for tab in Tab:
		var container := ScrollContainer.new()
		container.name = "TabContent_%d" % tab
		container.visible = false
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
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

	# Show/hide tab contents
	for tab in Tab:
		var container: Control = _tab_contents.get(tab)
		if container:
			container.visible = (tab == tab_id)

## ============================================================================
## INVENTORY TAB
## ============================================================================

func _setup_inventory_tab() -> void:
	var container: ScrollContainer = _tab_contents.get(Tab.INVENTORY)
	if not container:
		return

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	slot_btn.text = "[Empty]"
	slot_btn.custom_minimum_size = Vector2(120, 40)
	slot_btn.pressed.connect(_on_equip_slot_clicked.bind(slot_data.id))
	row.add_child(slot_btn)

	return row

func _on_equip_slot_clicked(slot_id: int) -> void:
	_selected_equip_slot = slot_id

	if not InventoryService:
		show_notification("InventoryService unavailable", false)
		return

	var player_id := str(PlayerManager.get_local_player_id()) if PlayerManager else ""
	if player_id.is_empty():
		return

	var inv: InventoryComponent = InventoryService.get_inventory(player_id)
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
	if not InventoryService:
		show_notification("InventoryService unavailable", false)
		return

	var player_id := str(PlayerManager.get_local_player_id()) if PlayerManager else ""
	if player_id.is_empty():
		return

	var inv: InventoryComponent = InventoryService.get_inventory(player_id)
	if inv == null:
		show_notification("Could not load inventory", false)
		return

	# Get slot name for display
	var slot_name := _get_slot_name(slot_id)

	# Find items that can be equipped in this slot
	var equippable: Array[Item] = []
	for slot in inv._items:
		var item: Item = inv._items[slot]
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

	var scroll := ScrollContainer.new()
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
	# Find the inventory slot containing this item
	var inv_slot: int = -1
	for slot in inv._items:
		if inv._items[slot] == item:
			inv_slot = slot
			break

	if inv_slot < 0:
		show_notification("Could not find item in inventory", false)
		return

	# Equip the item
	if inv.equip_item(inv_slot):
		show_notification("Equipped %s" % item.name, false)
		_refresh_equipment()
	else:
		show_notification("Failed to equip item", false)

func _unequip_item(slot_id: int) -> void:
	if not InventoryService:
		return

	var player_id := str(PlayerManager.get_local_player_id()) if PlayerManager else ""
	if player_id.is_empty():
		return

	var inv: InventoryComponent = InventoryService.get_inventory(player_id)
	if inv == null:
		return

	if inv.unequip_item(slot_id):
		show_notification("Item unequipped and added to inventory")
		_refresh_equipment_display()
	else:
		show_notification("Failed to unequip - inventory may be full", false)

func _show_item_details(item: Item) -> void:
	var stats_text := ""
	if item.has("stats"):
		var stats: Dictionary = item.get("stats", {})
		for key in stats.keys():
			stats_text += "\n%s: %s" % [key.capitalize(), stats[key]]

	var dialog := AcceptDialog.new()
	dialog.title = item.name if item.name else "Item Details"
	dialog.dialog_text = "Type: %s\nRarity: %s%s" % [
		item.get("item_type", "Unknown"),
		item.get("rarity", "Common"),
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
		{"name": "Strength", "key": "str", "icon": "\U0001F4AA"},
		{"name": "Intelligence", "key": "int", "icon": "\U0001F4DA"},
		{"name": "Wisdom", "key": "wis", "icon": "\U0001F4DD"},
		{"name": "Agility", "key": "agi", "icon": "\U0001F3C3"},
		{"name": "Vitality", "key": "vit", "icon": "\U00002764"},
		{"name": "Endurance", "key": "end", "icon": "\U0001F4AA"}
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

		var name := Label.new()
		name.text = stat.name
		row.add_child(name)

		var val := Label.new()
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
	card.add_child(hbox)

	var icon := Label.new()
	icon.text = stat.icon
	hbox.add_child(icon)

	var info := VBoxContainer.new()
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
	if _char_data == null:
		return
	# Equipment slots will be populated from InventoryService
	# For now, just refresh the grid if it exists
	_refresh_equipment_display()

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

	# Update character name/level header
	var char_header: HBoxContainer = null
	for child in vbox.get_children():
		if child is HBoxContainer and child.has_node("CharName"):
			char_header = child
			break
	if char_header:
		var name_lbl: Label = char_header.get_node("CharName")
		var species_name := _char_data.species_id.capitalize()
		var class_name := _char_data.class_id.capitalize()
		name_lbl.text = "%s %s - Level %d" % [species_name, class_name, _char_data.level]

	# Get stats from character
	var stats: Dictionary = _char_data.get_stats()
	var allocated: Dictionary = _char_data.allocated_stats

	# Update stat cards (str, int, wis, agi, vit, end)
	var stat_keys := ["strength", "intelligence", "wisdom", "agility", "vitality", "endurance"]
	var display_keys := ["str", "int", "wis", "agi", "vit", "end"]

	for i in range(stat_keys.size()):
		var stat_key := stat_keys[i]
		var disp_key := display_keys[i]
		var stat_card: PanelContainer = vbox.get_node_or_null("GridContainer/Stat_" + disp_key)
		if stat_card:
			var val_lbl: Label = stat_card.get_node_or_null("VBox/Value")
			if val_lbl:
				var base: int = stats.get(stat_key, 10)
				var bonus: int = allocated.get(stat_key, 0)
				var total: int = base + bonus
				var display := str(total)
				if bonus > 0:
					display = "%d (+%d)" % [total, bonus]
				elif base != total:
					display = "%d (%d)" % [total, base]
				val_lbl.text = display

	# Update derived stats using CharacterData's centralized calculation
	var derived_keys := _char_data.get_derived_stats()

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
	# This would be called when inventory changes
	# The actual implementation would query InventoryService for equipped items
	pass

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

	var titles_scroll := ScrollContainer.new()
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
	var player_id := TitleService.get_local_player_id()
	var titles: Array = TitleService.get_unlocked_titles(player_id)

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
				TitleService.equip(player_id, title.id, slot)
				refresh_titles()
				show_notification("Title equipped!")
			dialog.queue_free()
		)
		btn_hbox.add_child(equip_btn)

		var unequip_btn := Button.new()
		unequip_btn.text = "Unequip"
		unequip_btn.pressed.connect(func() -> void:
			TitleService.unequip(player_id, slot)
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

	var player_id := TitleService.get_local_player_id()
	if player_id.is_empty():
		return

	# Update preview
	var preview_box: VBoxContainer = container.get_node_or_null("TitlePreview")
	if preview_box:
		var preview_lbl: Label = preview_box.get_node_or_null("PreviewLabel")
		if preview_lbl:
			var base_name := "PlayerName"
			var full_name := TitleService.get_display_name(player_id, base_name)
			preview_lbl.text = full_name

	# Update equipped labels
	var equipped_box: HBoxContainer = container.get_node_or_null("EquippedSection")
	if equipped_box:
		var prefix_box: VBoxContainer = equipped_box.get_node_or_null("PrefixBox")
		if prefix_box:
			var prefix_val: Label = prefix_box.get_node_or_null("PrefixValue")
			if prefix_val:
				var prefix: TitleData = TitleService.get_equipped_prefix(player_id)
				prefix_val.text = "[%s]" % prefix.prefix_form if prefix else "[None]"

		var suffix_box: VBoxContainer = equipped_box.get_node_or_null("SuffixBox")
		if suffix_box:
			var suffix_val: Label = suffix_box.get_node_or_null("SuffixValue")
			if suffix_val:
				var suffix: TitleData = TitleService.get_equipped_suffix(player_id)
				suffix_val.text = suffix.suffix_form if suffix else "[None]"

	# Update titles list
	var titles_list: ItemList = container.get_node_or_null("TitlesList")
	if titles_list:
		titles_list.clear()
		var titles: Array = TitleService.get_unlocked_titles(player_id)
		for title in titles:
			var display := title.display_name
			if title.has_prefix():
				display += " (Prefix)"
			if title.has_suffix():
				display += " (Suffix)"
			titles_list.add_item(display)
