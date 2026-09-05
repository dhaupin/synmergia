## ActionBar - Skill hotbar component
## 8 skill slots with keyboard/controller bindings
extends Control
class_name ActionBar
const UIStyles = preload("res://ui/components/ui_styles.gd")
const IconResolver = preload("res://core/utils/icon_resolver.gd")
const CharacterData = preload("res://core/schemas/character_data.gd")
const DataService = preload("res://core/services/data_service.gd")

## Slots
const SLOT_COUNT: int = 8
var _slots: Array = []
var _keybinds: Array = []
var _char_data: CharacterData

## State
var _selected_slot: int = -1

signal slot_used(index: int)
signal slot_updated(index: int, skill_data: Dictionary)

func _ready() -> void:
	_setup_ui()
	_connect_signals()

func load_from_character(char_data: CharacterData) -> void:
	_char_data = char_data
	for i in range(SLOT_COUNT):
		var skill_id := char_data.get_action_slot(i)
		if not skill_id.is_empty():
			var skill_schema := DataService.get_skill(skill_id)
			if skill_schema:
				var skill_dict := _schema_to_dict(skill_schema, char_data)
				update_slot(i, skill_dict)
			else:
				update_slot(i, {})
		else:
			update_slot(i, {})

func _schema_to_dict(schema: Resource, char_data: CharacterData) -> Dictionary:
	var dict := {
		"skill_id": schema.get("skill_id", ""),
		"name": schema.get("name", ""),
		"icon_path": schema.get("icon_path", ""),
		"mana_cost": schema.get("mana_cost", 0),
		"cooldown": schema.get("cooldown", 0.0),
		"skill_type": schema.get("skill_type", 0),
	}
	# Apply upgrade level from character data
	var upgrade_level := char_data.get_skill_upgrade_level(dict.skill_id)
	dict["upgrade_level"] = upgrade_level
	return dict

func _setup_ui() -> void:
	var container := HBoxContainer.new()
	container.name = "Container"
	add_child(container)

	# Create 8 slots
	for i in range(SLOT_COUNT):
		var slot := _create_slot(i)
		container.add_child(slot)
		_slots.append(slot)

	# Keybinds
	_keybinds = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8]

func _create_slot(index: int) -> Control:
	var slot := PanelContainer.new()
	slot.name = "Slot_%d" % index
	slot.custom_minimum_size = Vector2(50, 50)
	slot.set_anchors_preset(Control.PRESET_CENTER)

	# Background style
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = UIStyles.COLORS.background_dark
	bg_style.border_color = UIStyles.COLORS.border
	bg_style.corner_radius_top_left = 6
	bg_style.corner_radius_top_right = 6
	bg_style.corner_radius_bottom_left = 6
	bg_style.corner_radius_bottom_right = 6
	slot.add_theme_stylebox_override("panel", bg_style)

	var vbox := VBoxContainer.new()
	slot.add_child(vbox)

	# Skill icon placeholder
	var icon := Panel.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(40, 40)
	vbox.add_child(icon)

	# Cooldown overlay
	var cooldown := Label.new()
	cooldown.name = "Cooldown"
	cooldown.visible = false
	cooldown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cooldown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cooldown.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	cooldown.add_theme_font_size_override("font_size", 16)
	slot.add_child(cooldown)

	# Keybind indicator
	var keybind := Label.new()
	keybind.name = "Keybind"
	keybind.text = str(index + 1)
	keybind.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	keybind.offset_left = -20
	keybind.offset_right = -4
	keybind.offset_top = -16
	keybind.offset_bottom = -4
	keybind.add_theme_font_size_override("font_size", 10)
	keybind.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	slot.add_child(keybind)

	# Mana cost
	var mana := Label.new()
	mana.name = "ManaCost"
	mana.visible = false
	mana.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mana.offset_left = 4
	mana.offset_right = 20
	mana.offset_top = -16
	mana.offset_bottom = -4
	mana.add_theme_font_size_override("font_size", 9)
	mana.add_theme_color_override("font_color", UIStyles.COLORS.info)
	slot.add_child(mana)

	return slot

func _connect_signals() -> void:
	if InputManager:
		InputManager.player_input.connect(_on_player_input)

func _on_player_input(action: String, pressed: bool) -> void:
	if not pressed:
		return

	# Map action to slot
	var slot_index := -1
	match action:
		"ability_1": slot_index = 0
		"ability_2": slot_index = 1
		"ability_3": slot_index = 2
		"ability_4": slot_index = 3
		"ability_5": slot_index = 4
		"ability_6": slot_index = 5
		"ability_7": slot_index = 6
		"ability_8": slot_index = 7

	if slot_index >= 0:
		_use_slot(slot_index)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		for i in range(_keybinds.size()):
			if event.keycode == _keybinds[i]:
				_use_slot(i)
				break

func _use_slot(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return

	var slot: Control = _slots[index]
	var cooldown: Label = slot.get_node_or_null("Cooldown")

	# Check if on cooldown
	if cooldown and cooldown.visible:
		return

	# Emit signal
	slot_used.emit(index)

	# Visual feedback
	_flash_slot(slot)

func _flash_slot(slot: Control) -> void:
	var style := slot.get_theme_stylebox("panel")
	if style:
		style.bg_color = UIStyles.COLORS.accent_gold
		await get_tree().create_timer(0.1).timeout
		style.bg_color = UIStyles.COLORS.background_dark

func update_slot(index: int, skill_data: Dictionary) -> void:
	if index < 0 or index >= _slots.size():
		return

	var slot: Control = _slots[index]
	var icon: Panel = slot.get_node_or_null("Icon")
	var mana: Label = slot.get_node_or_null("ManaCost")
	var keybind: Label = slot.get_node_or_null("Keybind")

	if skill_data.is_empty():
		# Clear slot
		if icon:
			icon.modulate = Color(1, 1, 1, 0.3)
		if mana:
			mana.visible = false
		return

	# Update icon using IconResolver
	if icon:
		icon.modulate = Color(1, 1, 1, 1)
		icon.texture = IconResolver.get_skill_icon_from_dict(skill_data)

	# Update mana cost
	if mana and skill_data.has("mana_cost"):
		mana.text = str(skill_data.mana_cost)
		mana.visible = skill_data.mana_cost > 0

	# Update keybind display
	if keybind and skill_data.has("keybind"):
		keybind.text = skill_data.keybind

	slot_updated.emit(index, skill_data)

func set_slot_cooldown(index: int, remaining: float, total: float) -> void:
	if index < 0 or index >= _slots.size():
		return

	var slot: Control = _slots[index]
	var cooldown: Label = slot.get_node_or_null("Cooldown")

	if not cooldown:
		return

	if remaining > 0:
		cooldown.visible = true
		cooldown.text = str(int(remaining))
	else:
		cooldown.visible = false

func select_slot(index: int) -> void:
	# Deselect previous
	if _selected_slot >= 0 and _selected_slot < _slots.size():
		var prev: Control = _slots[_selected_slot]
		prev.set_slot_border(UIStyles.COLORS.border)

	# Select new
	_selected_slot = index
	if index >= 0 and index < _slots.size():
		var slot: Control = _slots[index]
		slot.set_slot_border(UIStyles.COLORS.accent_gold)

func get_selected_slot() -> int:
	return _selected_slot

# Controller navigation
func get_adjacent_slot(from: int, direction: Vector2) -> int:
	if direction == Vector2.ZERO:
		return from

	var cols: int = 4  # 2 rows of 4
	var row: int = from / cols
	var col: int = from % cols

	if direction.x < 0:
		col = maxi(0, col - 1)
	elif direction.x > 0:
		col = mini(cols - 1, col + 1)

	if direction.y < 0:
		row = maxi(0, row - 1)
	elif direction.y > 0:
		row = mini(1, row + 1)

	return row * cols + col
