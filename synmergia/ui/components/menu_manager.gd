## MenuManager - Central HUD manager for Synmergia
class_name MenuManager
extends CanvasLayer

## Singleton
static var instance: MenuManager = null

## UI references
var _action_bar: HBoxContainer
var _quick_access_bar: HBoxContainer
var _buff_bar: HBoxContainer
var _status_bar: HBoxContainer

## State
var _is_hud_visible: bool = true
var _is_menu_open: bool = false
var _open_panels: Array = []

## Menu panels (social, inventory, etc.)
var _open_menu_callbacks: Dictionary = {}

signal menu_toggled(menu_name: String, is_open: bool)
signal hud_visibility_changed(visible: bool)

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	
	_setup_hud()
	_connect_signals()

func _setup_hud() -> void:
	# Action bar (bottom center) - skills/actions
	_action_bar = HBoxContainer.new()
	_action_bar.set_anchors_preset(Control.PRESET_BOTTOM_HCENTER)
	_action_bar.offset_top = -80
	_action_bar.offset_bottom = -10
	_action_bar.custom_minimum_size.y = 60
	_action_bar.z_index = 100
	add_child(_action_bar)
	
	# Quick access bar (bottom left) - consumables
	_quick_access_bar = HBoxContainer.new()
	_quick_access_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_quick_access_bar.offset_right = 250
	_quick_access_bar.offset_bottom = 60
	_quick_access_bar.custom_minimum_size.y = 50
	_quick_access_bar.z_index = 100
	add_child(_quick_access_bar)
	
	# Buff bar (top right)
	_buff_bar = HBoxContainer.new()
	_buff_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_buff_bar.offset_left = -200
	_buff_bar.offset_top = 50
	_buff_bar.custom_minimum_size.y = 40
	_buff_bar.z_index = 100
	add_child(_buff_bar)
	
	# Status bar (top center) - HP, MP, XP
	_status_bar = HBoxContainer.new()
	_status_bar.set_anchors_preset(Control.PRESET_TOP_HCENTER)
	_status_bar.offset_top = 10
	_status_bar.z_index = 100
	add_child(_status_bar)
	
	# Add placeholder slots
	_setup_action_slots()
	_setup_quick_slots()
	_setup_status_bar()

func _setup_action_slots() -> void:
	for i in range(8):
		var slot := _create_action_slot(i)
		_action_bar.add_child(slot)

func _setup_quick_slots() -> void:
	for i in range(4):
		var slot := _create_quick_slot(i)
		_quick_access_bar.add_child(slot)

func _setup_status_bar() -> void:
	# Health bar
	var hp_container := VBoxContainer.new()
	hp_container.custom_minimum_size.x = 150
	
	var hp_label := Label.new()
	hp_label.text = "HP"
	hp_label.add_theme_font_size_override("font_size", 10)
	hp_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	hp_container.add_child(hp_label)
	
	var hp_bar := _create_progress_bar(Color(0.8, 0.2, 0.2))
	hp_bar.name = "HPBar"
	hp_container.add_child(hp_bar)
	
	_status_bar.add_child(hp_container)
	
	# Mana bar
	var mp_container := VBoxContainer.new()
	mp_container.custom_minimum_size.x = 150
	
	var mp_label := Label.new()
	mp_label.text = "MP"
	mp_label.add_theme_font_size_override("font_size", 10)
	mp_label.add_theme_color_override("font_color", Color(0.3, 0.3, 1))
	mp_container.add_child(mp_label)
	
	var mp_bar := _create_progress_bar(Color(0.2, 0.2, 0.8))
	mp_bar.name = "MPBar"
	mp_container.add_child(mp_bar)
	
	_status_bar.add_child(mp_container)
	
	# XP bar
	var xp_container := VBoxContainer.new()
	xp_container.custom_minimum_size.x = 150
	
	var xp_label := Label.new()
	xp_label.text = "XP"
	xp_label.add_theme_font_size_override("font_size", 10)
	xp_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	xp_container.add_child(xp_label)
	
	var xp_bar := _create_progress_bar(Color(0.8, 0.6, 0.1))
	xp_bar.name = "XPBar"
	xp_container.add_child(xp_bar)
	
	_status_bar.add_child(xp_container)

func _create_action_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(50, 50)
	slot.name = "ActionSlot%d" % index
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.8)
	style.border_color = Color(0.3, 0.3, 0.35)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	slot.add_theme_stylebox_override("panel", style)
	
	# Keybind label
	var keybind := Label.new()
	keybind.text = str(index + 1)
	keybind.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	keybind.add_theme_font_size_override("font_size", 10)
	keybind.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	keybind.offset_left = -15
	keybind.offset_right = -3
	keybind.offset_top = -12
	keybind.offset_bottom = -2
	slot.add_child(keybind)
	
	return slot

func _create_quick_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(40, 40)
	slot.name = "QuickSlot%d" % index
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.8)
	style.border_color = Color(0.3, 0.3, 0.35)
	slot.add_theme_stylebox_override("panel", style)
	
	return slot

func _create_progress_bar(color: Color) -> PanelContainer:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(150, 12)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("panel", style)
	
	# Fill
	var fill := Panel.new()
	fill.custom_minimum_size = Vector2(150, 12)
	fill.name = "Fill"
	
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	fill.add_theme_stylebox_override("panel", fill_style)
	
	bar.add_child(fill)
	
	return bar

func _connect_signals() -> void:
	# ESC to toggle menu
	pass  # Handled in input

## ============================================================================
## PUBLIC API
## ============================================================================

static func get_instance() -> MenuManager:
	return instance

static func toggle_menu(menu_name: String) -> void:
	if instance:
		instance._toggle_menu_internal(menu_name)

static func open_menu(menu_name: String) -> void:
	if instance:
		instance._open_menu_internal(menu_name)

static func close_menu(menu_name: String) -> void:
	if instance:
		instance._close_menu_internal(menu_name)

static func close_all_menus() -> void:
	if instance:
		instance._close_all_menus_internal()

static func set_hud_visible(visible: bool) -> void:
	if instance:
		instance._set_hud_visible_internal(visible)

static func update_hp(current: int, maximum: int) -> void:
	if instance:
		instance._update_hp_internal(current, maximum)

static func update_mp(current: int, maximum: int) -> void:
	if instance:
		instance._update_mp_internal(current, maximum)

static func update_xp(current: int, maximum: int) -> void:
	if instance:
		instance._update_xp_internal(current, maximum)

## ============================================================================
## INTERNAL
## ============================================================================

func _toggle_menu_internal(menu_name: String) -> void:
	if _open_panels.has(menu_name):
		_close_menu_internal(menu_name)
	else:
		_open_menu_internal(menu_name)

func _open_menu_internal(menu_name: String) -> void:
	if not _open_panels.has(menu_name):
		_open_panels.append(menu_name)
	_is_menu_open = true
	menu_toggled.emit(menu_name, true)

func _close_menu_internal(menu_name: String) -> void:
	if _open_panels.has(menu_name):
		_open_panels.erase(menu_name)
	if _open_panels.is_empty():
		_is_menu_open = false
	menu_toggled.emit(menu_name, false)

func _close_all_menus_internal() -> void:
	for panel in _open_panels:
		menu_toggled.emit(panel, false)
	_open_panels.clear()
	_is_menu_open = false

func _set_hud_visible_internal(visible: bool) -> void:
	_is_hud_visible = visible
	_action_bar.visible = visible
	_quick_access_bar.visible = visible
	_buff_bar.visible = visible
	_status_bar.visible = visible
	hud_visibility_changed.emit(visible)

func _update_hp_internal(current: int, maximum: int) -> void:
	_update_bar("HPBar", current, maximum, Color(0.8, 0.2, 0.2))

func _update_mp_internal(current: int, maximum: int) -> void:
	_update_bar("MPBar", current, maximum, Color(0.2, 0.2, 0.8))

func _update_xp_internal(current: int, maximum: int) -> void:
	_update_bar("XPBar", current, maximum, Color(0.8, 0.6, 0.1))

func _update_bar(bar_name: String, current: int, maximum: int, color: Color) -> void:
	var bar: PanelContainer = _status_bar.get_node_or_null(bar_name)
	if not bar:
		return
	
	var fill: Panel = bar.get_node_or_null("Fill")
	if not fill:
		return
	
	var ratio := float(current) / float(maximum) if maximum > 0 else 0.0
	var bar_width := 150.0 * ratio
	
	fill.custom_minimum_size.x = bar_width
	
	var style := fill.get_theme_stylebox("panel")
	if style:
		style.bg_color = color

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				if _is_menu_open:
					_close_all_menus_internal()
			KEY_I:
				_toggle_menu_internal("inventory")
			KEY_P:
				_toggle_menu_internal("social")
			KEY_M:
				_toggle_menu_internal("map")
