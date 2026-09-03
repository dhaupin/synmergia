## CharacterPanel - Unified in-game character management
## Tabs: Inventory | Equipment | Stats | Skills
## Uses UIStyles for consistent theming
class_name CharacterPanel

const UIPanel = preload("res://ui/components/ui_panel.gd")
extends UIPanel
const CharacterData = preload("res://core/schemas/character_data.gd")


## Tab definitions
enum Tab { INVENTORY, EQUIP, STATS, SKILLS }
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

	_setup_tabs()
	_show_tab(Tab.INVENTORY)

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
		{"id": Tab.SKILLS, "name": "Skills", "key": KEY_K}
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
	# TODO: Show item selection or unequip

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
	char_name.text = "Level 1 Character"
	char_name.add_theme_font_size_override("font_size", 16)
	char_header.add_child(char_name)

	# Stats grid (2 columns)
	var stats_grid := GridContainer.new()
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
		stats_grid.add_child(stat_card)

	# Derived stats
	var derived_label := Label.new()
	derived_label.text = "Derived Stats"
	derived_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	vbox.add_child(derived_label)

	var derived := [
		{"name": "Max Health", "value": "100"},
		{"name": "Max Mana", "value": "50"},
		{"name": "Physical Attack", "value": "10"},
		{"name": "Magic Attack", "value": "10"},
		{"name": "Physical Defense", "value": "5"},
		{"name": "Magic Defense", "value": "5"}
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
	# TODO: Fetch from InventoryService
	pass

func refresh_stats() -> void:
	# TODO: Fetch from character data
	pass

func refresh_skills() -> void:
	# TODO: Fetch from skills system
	pass

func set_character_data(data: CharacterData) -> void:
	_char_data = data
	refresh_inventory()
	refresh_stats()
	refresh_skills()
