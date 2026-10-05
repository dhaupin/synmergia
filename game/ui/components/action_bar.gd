## ActionBar - Enhanced skill hotbar component
## 12 skill slots per bar, 3 bars (main, bar2, bar3) with page buttons
## Cooldown spiral animation + text, keybind display, drag-drop, right-click clear, stack counts, glow on proc, range indicator
extends "res://ui/components/ui_panel.gd"
class_name ActionBar
# NOTE: DataService is an autoload; reference it directly.
const IconResolver = preload("res://core/utils/icon_resolver.gd")
const CharacterData = preload("res://core/schemas/character_data.gd")

## Configuration
const SLOTS_PER_BAR: int = 12
const BAR_COUNT: int = 3
const TOTAL_SLOTS: int = SLOTS_PER_BAR * BAR_COUNT

## Slots data
var _slots: Array = []
var _slot_data: Dictionary = {}
var _keybinds: Array = []
var _char_data: CharacterData

## State
var _current_bar: int = 0
var _selected_slot: int = -1
var _dragging: bool = false
var _drag_source_index: int = -1
var _drag_preview: Control = null

## Page buttons
var _page_buttons: Array = []
var _page_container: HBoxContainer = null

## Signals
signal slot_used(index: int)
signal slot_updated(index: int, skill_data: Dictionary)
signal bar_changed(bar_index: int)
signal slot_cleared(index: int)

func _ready() -> void:
	super._ready()
	set_title("Action Bar")
	set_panel_size(Vector2(720, 100))
	_setup_ui()
	_connect_signals()
	_build_keybinds()
	_setup_accessibility()

func _setup_accessibility() -> void:
	focus_mode = Control.FOCUS_ALL
	# Apply default accessibility settings via the settings updater.
	update_accessibility_settings(false, 1.0, false)
func update_accessibility_settings(high_contrast: bool, text_scale: float, reduce_motion: bool) -> void:
	# Update focus styles for all slots (_slots is a flat array of slot
	# controls for the visible bar, not per-bar sub-arrays)
	for slot in _slots:
		if slot and is_instance_valid(slot):
			slot.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
			var style: StyleBoxFlat = slot.get_theme_stylebox("panel")
			if style:
				if high_contrast:
					style.bg_color = UIStyles.HIGH_CONTRAST_COLORS.background
					style.border_color = UIStyles.HIGH_CONTRAST_COLORS.border
				else:
					style.bg_color = UIStyles.COLORS.background_dark
					style.border_color = UIStyles.COLORS.border
			
			# Update text sizes
			var scale = UIStyles.get_text_scale()
			for label_name in ["Keybind", "StackCount", "CooldownText"]:
				var label: Label = slot.get_node_or_null(label_name)
				if label:
					var current_size := label.get_theme_font_size("font_size")
					if current_size > 0:
						label.add_theme_font_size_override("font_size", int(current_size * scale))

func _on_open() -> void:
	pass

func _on_close() -> void:
	pass

func _build_keybinds() -> void:
	_keybinds = []
	for i in range(SLOTS_PER_BAR):
		var key: int = 0
		match i:
			0: key = KEY_1
			1: key = KEY_2
			2: key = KEY_3
			3: key = KEY_4
			4: key = KEY_5
			5: key = KEY_6
			6: key = KEY_7
			7: key = KEY_8
			8: key = KEY_9
			9: key = KEY_0
			10: key = KEY_MINUS
			11: key = KEY_EQUAL
		_keybinds.append(key)

func load_from_character(char_data: CharacterData) -> void:
	_char_data = char_data
	for bar in range(BAR_COUNT):
		for i in range(SLOTS_PER_BAR):
			var global_index = bar * SLOTS_PER_BAR + i
			var skill_id := char_data.get_action_slot(global_index)
			if not skill_id.is_empty():
				var skill_schema := DataService.get_skill(skill_id)
				if skill_schema:
					var skill_dict := _schema_to_dict(skill_schema, char_data)
					update_slot(global_index, skill_dict)
				else:
					update_slot(global_index, {})
			else:
				update_slot(global_index, {})

func _schema_to_dict(schema: SkillSchema, char_data: CharacterData) -> Dictionary:
	# Skill properties are accessed directly (Resource.get(key, default) is
	# removed in 4.7.2); id falls back to display_name.
	var dict := {
		"skill_id": schema.id if schema.id != "" else schema.display_name,
		"name": schema.display_name,
		"icon_path": schema.icon_path,
		"mana_cost": schema.mana_cost,
		"cooldown": schema.cooldown,
		"skill_type": schema.skill_type,
		"range": schema.range,
	}
	var upgrade_level := char_data.get_skill_upgrade_level(dict.skill_id)
	dict["upgrade_level"] = upgrade_level
	return dict

func _setup_ui() -> void:
	var panel := get_panel()
	if not panel:
		return
	var main: VBoxContainer = add_content_to_panel(panel)
	
	_page_container = HBoxContainer.new()
	_page_container.name = "PageContainer"
	_page_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_page_container.custom_minimum_size.y = 24
	main.add_child(_page_container)

	for bar_idx in range(BAR_COUNT):
		var btn := Button.new()
		btn.name = "PageBtn_%d" % bar_idx
		btn.text = "Bar %d" % (bar_idx + 1)
		btn.toggle_mode = true
		btn.button_pressed = (bar_idx == 0)
		btn.custom_minimum_size = Vector2(80, 20)
		btn.focus_mode = Control.FOCUS_ALL
		btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style(4, false))
		btn.pressed.connect(_on_page_button_pressed.bind(bar_idx))
		UIStyles.apply_accessibility(
			btn,
			"Show skill bar %d" % (bar_idx + 1),
			"Pages the action bar to its skill set %d" % (bar_idx + 1)
		)
		_page_buttons.append(btn)
		_page_container.add_child(btn)

	var bar_container := HBoxContainer.new()
	bar_container.name = "BarContainer"
	bar_container.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_child(bar_container)

	for i in range(SLOTS_PER_BAR):
		var slot := _create_slot(i)
		bar_container.add_child(slot)
		_slots.append(slot)

	_update_visible_bar()

func _create_slot(index: int) -> Control:
	var slot := PanelContainer.new()
	slot.name = "Slot_%d" % index
	slot.custom_minimum_size = Vector2(52, 52)
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	slot.focus_mode = Control.FOCUS_ALL

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = UIStyles.COLORS.background_dark
	bg_style.border_color = UIStyles.COLORS.border
	bg_style.border_width_left = 2
	bg_style.border_width_right = 2
	bg_style.border_width_top = 2
	bg_style.border_width_bottom = 2
	bg_style.corner_radius_top_left = 6
	bg_style.corner_radius_top_right = 6
	bg_style.corner_radius_bottom_left = 6
	bg_style.corner_radius_bottom_right = 6
	slot.add_theme_stylebox_override("panel", bg_style)
	
	# Add focus style
	slot.add_theme_stylebox_override("focus", UIStyles.create_focus_style(6, false))

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(vbox)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(1, 1, 1, 0.3)
	vbox.add_child(icon)

	var cooldown_spiral := TextureProgressBar.new()
	cooldown_spiral.name = "CooldownSpiral"
	cooldown_spiral.visible = false
	cooldown_spiral.set_anchors_preset(Control.PRESET_FULL_RECT)
	cooldown_spiral.min_value = 0
	cooldown_spiral.max_value = 100
	cooldown_spiral.value = 100
	cooldown_spiral.texture_under = _create_spiral_under()
	cooldown_spiral.texture_progress = _create_spiral_progress()
	cooldown_spiral.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	cooldown_spiral.radial_initial_angle = -90
	cooldown_spiral.radial_fill_degrees = 360.0
	cooldown_spiral.clip_contents = true
	slot.add_child(cooldown_spiral)

	var cooldown_text := Label.new()
	cooldown_text.name = "CooldownText"
	cooldown_text.visible = false
	cooldown_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cooldown_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cooldown_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	cooldown_text.add_theme_font_size_override("font_size", 14)
	cooldown_text.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	cooldown_text.add_theme_constant_override("outline_size", 2)
	cooldown_text.add_theme_color_override("outline_color", Color(0, 0, 0, 1))
	slot.add_child(cooldown_text)

	var keybind := Label.new()
	keybind.name = "Keybind"
	keybind.text = _get_keybind_text(index, 0)
	keybind.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	keybind.offset_left = -35
	keybind.offset_right = -2
	keybind.offset_top = 2
	keybind.offset_bottom = 14
	keybind.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keybind.add_theme_font_size_override("font_size", 9)
	keybind.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	keybind.add_theme_constant_override("outline_size", 1)
	keybind.add_theme_color_override("outline_color", Color(0, 0, 0, 1))
	slot.add_child(keybind)

	var stack_label := Label.new()
	stack_label.name = "StackCount"
	stack_label.visible = false
	stack_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	stack_label.offset_left = -35
	stack_label.offset_right = -2
	stack_label.offset_top = -14
	stack_label.offset_bottom = -2
	stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	stack_label.add_theme_font_size_override("font_size", 11)
	stack_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	stack_label.add_theme_constant_override("outline_size", 2)
	stack_label.add_theme_color_override("outline_color", Color(0, 0, 0, 1))
	slot.add_child(stack_label)

	var mana := Label.new()
	mana.name = "ManaCost"
	mana.visible = false
	mana.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mana.offset_left = 2
	mana.offset_right = 25
	mana.offset_top = -14
	mana.offset_bottom = -2
	mana.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mana.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	mana.add_theme_font_size_override("font_size", 8)
	mana.add_theme_color_override("font_color", UIStyles.COLORS.info)
	mana.add_theme_constant_override("outline_size", 1)
	mana.add_theme_color_override("outline_color", Color(0, 0, 0, 1))
	slot.add_child(mana)

	var range_overlay := ColorRect.new()
	range_overlay.name = "RangeOverlay"
	range_overlay.visible = false
	range_overlay.color = Color(1, 0.2, 0.2, 0.4)
	range_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(range_overlay)

	var glow_overlay := ColorRect.new()
	glow_overlay.name = "GlowOverlay"
	glow_overlay.visible = false
	glow_overlay.color = Color(1, 0.8, 0.2, 0)
	glow_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.add_child(glow_overlay)

	slot.gui_input.connect(_on_slot_gui_input.bind(index))
	return slot

func _create_spiral_under() -> Texture2D:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.1, 0.15, 0.8))
	return ImageTexture.create_from_image(img)

func _create_spiral_progress() -> Texture2D:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	var center := Vector2(24, 24)
	var radius: float = 22.0
	for x in range(48):
		for y in range(48):
			var pos := Vector2(x, y)
			var dist := pos.distance_to(center)
			if dist <= radius and dist >= radius - 3:
				var angle := atan2(pos.y - center.y, pos.x - center.x)
				var deg := rad_to_deg(angle) + 90
				if deg < 0:
					deg += 360
				var alpha: float = 0.6 * (1.0 - (dist - (radius - 3)) / 3.0)
				img.set_pixel(x, y, Color(1, 0.8, 0.2, alpha))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)

func _get_keybind_text(index: int, bar_index: int = 0) -> String:
	match index:
		0: return "1" if bar_index == 0 else "Shift+1"
		1: return "2" if bar_index == 0 else "Shift+2"
		2: return "3" if bar_index == 0 else "Shift+3"
		3: return "4" if bar_index == 0 else "Shift+4"
		4: return "5" if bar_index == 0 else "Shift+5"
		5: return "6" if bar_index == 0 else "Shift+6"
		6: return "7" if bar_index == 0 else "Shift+7"
		7: return "8" if bar_index == 0 else "Shift+8"
		8: return "9" if bar_index == 0 else "Shift+9"
		9: return "0"
		10: return "-"
		11: return "="
	return str(index + 1)

func _connect_signals() -> void:
	if InputManager:
		InputManager.player_input.connect(_on_player_input)

func _on_page_button_pressed(bar_index: int) -> void:
	if bar_index == _current_bar:
		return
	_current_bar = bar_index
	_update_visible_bar()
	bar_changed.emit(bar_index)

func _update_visible_bar() -> void:
	for i in range(SLOTS_PER_BAR):
		var slot: Control = _slots[i]
		var global_index = _current_bar * SLOTS_PER_BAR + i
		var data: Dictionary = _slot_data.get(global_index, {})
		
		var keybind: Label = slot.get_node_or_null("Keybind")
		if keybind:
			keybind.text = _get_keybind_text(i, _current_bar)
		
		if slot and not data.is_empty():
			var icon: TextureRect = slot.get_node_or_null("VBox/Icon")
			if icon:
				icon.texture = IconResolver.get_skill_icon_from_dict(data)
				icon.modulate = Color(1, 1, 1, 1)
			var cooldown_spiral: TextureProgressBar = slot.get_node_or_null("CooldownSpiral")
			var cooldown_text: Label = slot.get_node_or_null("CooldownText")
			if cooldown_spiral:
				cooldown_spiral.visible = false
			if cooldown_text:
				cooldown_text.visible = false
			var range_overlay: ColorRect = slot.get_node_or_null("RangeOverlay")
			if range_overlay:
				range_overlay.visible = false
		elif slot:
			var icon: TextureRect = slot.get_node_or_null("VBox/Icon")
			if icon:
				icon.modulate = Color(1, 1, 1, 0.3)
				icon.texture = null
			var cooldown_spiral: TextureProgressBar = slot.get_node_or_null("CooldownSpiral")
			var cooldown_text: Label = slot.get_node_or_null("CooldownText")
			if cooldown_spiral:
				cooldown_spiral.visible = false
			if cooldown_text:
				cooldown_text.visible = false
			var range_overlay: ColorRect = slot.get_node_or_null("RangeOverlay")
			if range_overlay:
				range_overlay.visible = false

	for bar_idx in range(BAR_COUNT):
		if _page_buttons[bar_idx]:
			_page_buttons[bar_idx].button_pressed = (bar_idx == _current_bar)

func _on_player_input(action: String, pressed: bool) -> void:
	if not pressed:
		return

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
		"ability_9": slot_index = 8
		"ability_10": slot_index = 9
		"ability_11": slot_index = 10
		"ability_12": slot_index = 11

	if slot_index >= 0:
		_use_slot(slot_index)
		# Route to the local player's skillbar: keys 1-8 cast the bound
		# skill via PlayerController.use_skill (CombatSystem resolves
		# target/damage from there). Was visual-only before this.
		var player = get_tree().get_first_node_in_group("players")
		if player != null and player.has_method("use_skill"):
			player.use_skill(slot_index)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		for i in range(_keybinds.size()):
			if event.keycode == _keybinds[i]:
				if event.shift_pressed and i < 9:
					var shift_index = i + SLOTS_PER_BAR
					if shift_index < TOTAL_SLOTS:
						_use_slot(shift_index)
				else:
					var global_index = _current_bar * SLOTS_PER_BAR + i
					_use_slot(global_index)
				break

func _use_slot(global_index: int) -> void:
	var local_index = global_index % SLOTS_PER_BAR
	if local_index < 0 or local_index >= _slots.size():
		return

	var slot: Control = _slots[local_index]
	var cooldown_spiral: TextureProgressBar = slot.get_node_or_null("CooldownSpiral")
	var cooldown_text: Label = slot.get_node_or_null("CooldownText")

	if cooldown_spiral and cooldown_spiral.visible:
		return

	slot_used.emit(global_index)
	_flash_slot(slot)
	_play_glow_animation(slot)

func _flash_slot(slot: Control) -> void:
	# Respect reduce motion setting
	if UIStyles.is_reduce_motion_enabled():
		return
	var style := slot.get_theme_stylebox("panel")
	if style:
		style.border_color = UIStyles.COLORS.accent_gold
		await get_tree().create_timer(0.1).timeout
		if is_instance_valid(slot):
			style.border_color = UIStyles.COLORS.border

func _play_glow_animation(slot: Control) -> void:
	var glow: ColorRect = slot.get_node_or_null("GlowOverlay")
	if not glow:
		return
	
	# Respect reduce motion setting
	if UIStyles.is_reduce_motion_enabled():
		glow.visible = false
		return

	glow.visible = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(glow, "color:a", 0.6, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(glow, "color:a", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): glow.visible = false)

func _on_slot_gui_input(index: int, event: InputEvent) -> void:
	var global_index = _current_bar * SLOTS_PER_BAR + index

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag(global_index, event.position)
			else:
				_end_drag(global_index, event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_clear_slot(global_index)

	if event is InputEventMouseMotion and _dragging:
		_update_drag_preview(event.position)

func _start_drag(global_index: int, position: Vector2) -> void:
	if _slot_data.get(global_index, {}).is_empty():
		return

	_dragging = true
	_drag_source_index = global_index

	_drag_preview = PanelContainer.new()
	_drag_preview.name = "DragPreview"
	_drag_preview.custom_minimum_size = Vector2(48, 48)
	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
	style.border_color = UIStyles.COLORS.accent_gold
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_drag_preview.add_theme_stylebox_override("panel", style)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(36, 36)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var source_slot: Control = _get_slot_control(global_index)
	if source_slot:
		var src_icon: TextureRect = source_slot.get_node_or_null("VBox/Icon")
		if src_icon:
			icon.texture = src_icon.texture
	_drag_preview.add_child(icon)

	get_viewport().gui_add_child(_drag_preview)
	_drag_preview.global_position = position - Vector2(24, 24)
	_drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_preview.z_index = 1000

	var source_slot_ctrl: Control = _get_slot_control(global_index)
	if source_slot_ctrl:
		source_slot_ctrl.modulate = Color(1, 1, 1, 0.5)

func _update_drag_preview(position: Vector2) -> void:
	if _drag_preview and is_instance_valid(_drag_preview):
		_drag_preview.global_position = position - Vector2(24, 24)

func _end_drag(source_global_index: int, position: Vector2) -> void:
	if not _dragging:
		return

	_dragging = false

	if _drag_preview and is_instance_valid(_drag_preview):
		_drag_preview.queue_free()
		_drag_preview = null

	var source_slot_ctrl: Control = _get_slot_control(source_global_index)
	if source_slot_ctrl:
		source_slot_ctrl.modulate = Color(1, 1, 1, 1)

	var target_global_index: int = -1
	for i in range(SLOTS_PER_BAR):
		var slot: Control = _slots[i]
		if slot and slot.has_point(slot.get_local_mouse_position()):
			target_global_index = _current_bar * SLOTS_PER_BAR + i
			break

	if target_global_index >= 0 and target_global_index != source_global_index:
		_swap_slots(source_global_index, target_global_index)

	_drag_source_index = -1

func _get_slot_control(global_index: int) -> Control:
	var local_index = global_index % SLOTS_PER_BAR
	if local_index >= 0 and local_index < _slots.size():
		return _slots[local_index]
	return null

func _swap_slots(index_a: int, index_b: int) -> void:
	var data_a: Dictionary = _slot_data.get(index_a, {})
	var data_b: Dictionary = _slot_data.get(index_b, {})

	_slot_data[index_a] = data_b
	_slot_data[index_b] = data_a

	if _char_data:
		_char_data.set_action_slot(index_a, data_b.get("skill_id", ""))
		_char_data.set_action_slot(index_b, data_a.get("skill_id", ""))

	var local_a = index_a % SLOTS_PER_BAR
	var local_b = index_b % SLOTS_PER_BAR

	if index_a >= _current_bar * SLOTS_PER_BAR and index_a < (_current_bar + 1) * SLOTS_PER_BAR:
		update_slot(local_a, data_b)
	if index_b >= _current_bar * SLOTS_PER_BAR and index_b < (_current_bar + 1) * SLOTS_PER_BAR:
		update_slot(local_b, data_a)

	slot_updated.emit(index_a, data_b)
	slot_updated.emit(index_b, data_a)

func _clear_slot(global_index: int) -> void:
	if _slot_data.get(global_index, {}).is_empty():
		return

	_slot_data.erase(global_index)

	if _char_data:
		_char_data.set_action_slot(global_index, "")

	var local_index = global_index % SLOTS_PER_BAR
	if global_index >= _current_bar * SLOTS_PER_BAR and global_index < (_current_bar + 1) * SLOTS_PER_BAR:
		update_slot(local_index, {})

	slot_cleared.emit(global_index)

func update_slot(local_index: int, skill_data: Dictionary) -> void:
	if local_index < 0 or local_index >= _slots.size():
		return

	var global_index = _current_bar * SLOTS_PER_BAR + local_index
	_slot_data[global_index] = skill_data

	var slot: Control = _slots[local_index]
	var icon: TextureRect = slot.get_node_or_null("VBox/Icon")
	var mana: Label = slot.get_node_or_null("ManaCost")
	var keybind: Label = slot.get_node_or_null("Keybind")
	var stack: Label = slot.get_node_or_null("StackCount")
	var cooldown_spiral: TextureProgressBar = slot.get_node_or_null("CooldownSpiral")
	var cooldown_text: Label = slot.get_node_or_null("CooldownText")
	var range_overlay: ColorRect = slot.get_node_or_null("RangeOverlay")

	if skill_data.is_empty():
		if icon:
			icon.modulate = Color(1, 1, 1, 0.3)
			icon.texture = null
		if mana:
			mana.visible = false
		if stack:
			stack.visible = false
		if cooldown_spiral:
			cooldown_spiral.visible = false
		if cooldown_text:
			cooldown_text.visible = false
		if range_overlay:
			range_overlay.visible = false
		# A11y: empty slots announce themselves as empty so the snapshot
		# explains the bar instead of showing mystery boxes.
		UIStyles.apply_accessibility(slot, "Empty skill slot %d" % (local_index + 1), "Drag a skill here to bind it")
		slot.disabled = false
		return

	if icon:
		icon.modulate = Color(1, 1, 1, 1)
		icon.texture = IconResolver.get_skill_icon_from_dict(skill_data)

	if mana and skill_data.has("mana_cost"):
		mana.text = str(skill_data.mana_cost)
		mana.visible = skill_data.mana_cost > 0

	if keybind and skill_data.has("keybind"):
		keybind.text = skill_data.keybind
	else:
		keybind.text = _get_keybind_text(local_index)

	# A11y: name the SKILL and its cost, state the key and the cast verb.
	var skill_label: String = str(skill_data.name) if skill_data.has("name") else str(skill_data.get("skill_id", "Skill"))
	var cost_piece := " " + str(skill_data["mana_cost"]) + " mana" if skill_data.has("mana_cost") and float(skill_data["mana_cost"]) > 0.0 else ""
	var key_text: String = keybind.text if keybind else ""
	UIStyles.apply_accessibility(
		slot,
		"Cast %s" % skill_label,
		("%s. Key %s. Click to cast." % [cost_piece, key_text]).replace(". .", ".")
	)

	if stack and skill_data.has("charges"):
		var charges: int = skill_data.charges
		stack.text = str(charges)
		stack.visible = charges > 1

	if cooldown_spiral:
		cooldown_spiral.visible = false
	if cooldown_text:
		cooldown_text.visible = false
	if range_overlay:
		range_overlay.visible = false

	slot_updated.emit(global_index, skill_data)

func set_slot_cooldown(global_index: int, remaining: float, total: float) -> void:
	var local_index = global_index % SLOTS_PER_BAR
	if local_index < 0 or local_index >= _slots.size():
		return

	if global_index < _current_bar * SLOTS_PER_BAR or global_index >= (_current_bar + 1) * SLOTS_PER_BAR:
		return

	var slot: Control = _slots[local_index]
	var cooldown_spiral: TextureProgressBar = slot.get_node_or_null("CooldownSpiral")
	var cooldown_text: Label = slot.get_node_or_null("CooldownText")

	if not cooldown_spiral or not cooldown_text:
		return

	if remaining > 0:
		cooldown_spiral.visible = true
		cooldown_text.visible = true
		cooldown_spiral.max_value = total
		cooldown_spiral.value = remaining
		cooldown_text.text = str(int(ceil(remaining)))
	else:
		cooldown_spiral.visible = false
		cooldown_text.visible = false
		_play_glow_animation(slot)

func set_slot_range_indicator(global_index: int, in_range: bool) -> void:
	var local_index = global_index % SLOTS_PER_BAR
	if local_index < 0 or local_index >= _slots.size():
		return

	if global_index < _current_bar * SLOTS_PER_BAR or global_index >= (_current_bar + 1) * SLOTS_PER_BAR:
		return

	var slot: Control = _slots[local_index]
	var range_overlay: ColorRect = slot.get_node_or_null("RangeOverlay")
	if range_overlay:
		range_overlay.visible = not in_range

func set_slot_stack_count(global_index: int, count: int) -> void:
	var local_index = global_index % SLOTS_PER_BAR
	if local_index < 0 or local_index >= _slots.size():
		return

	if global_index < _current_bar * SLOTS_PER_BAR or global_index >= (_current_bar + 1) * SLOTS_PER_BAR:
		return

	var slot: Control = _slots[local_index]
	var stack: Label = slot.get_node_or_null("StackCount")
	if stack:
		if count > 1:
			stack.text = str(count)
			stack.visible = true
		else:
			stack.visible = false

func select_slot(global_index: int) -> void:
	if _selected_slot >= 0:
		var prev_local = _selected_slot % SLOTS_PER_BAR
		if _selected_slot >= _current_bar * SLOTS_PER_BAR and _selected_slot < (_current_bar + 1) * SLOTS_PER_BAR:
			var prev_slot: Control = _slots[prev_local]
			if prev_slot:
				var style := prev_slot.get_theme_stylebox("panel")
				if style:
					style.border_color = UIStyles.COLORS.border

	_selected_slot = global_index

	if global_index >= _current_bar * SLOTS_PER_BAR and global_index < (_current_bar + 1) * SLOTS_PER_BAR:
		var local_index = global_index % SLOTS_PER_BAR
		var slot: Control = _slots[local_index]
		if slot:
			var style := slot.get_theme_stylebox("panel")
			if style:
				style.border_color = UIStyles.COLORS.accent_gold

func get_selected_slot() -> int:
	return _selected_slot

func get_current_bar() -> int:
	return _current_bar

func get_bar_count() -> int:
	return BAR_COUNT

func get_slots_per_bar() -> int:
	return SLOTS_PER_BAR

func get_slot_data(global_index: int) -> Dictionary:
	return _slot_data.get(global_index, {})

func clear_all_slots() -> void:
	for i in range(TOTAL_SLOTS):
		_slot_data.erase(i)
		if _char_data:
			_char_data.set_action_slot(i, "")

	for i in range(SLOTS_PER_BAR):
		update_slot(i, {})

func get_page_button(bar_index: int) -> Button:
	if bar_index >= 0 and bar_index < _page_buttons.size():
		return _page_buttons[bar_index]
	return null
