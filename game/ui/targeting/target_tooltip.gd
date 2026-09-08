## TargetTooltip - Generic tooltip for any targeting system
## Wired to TargetingManager for unified targeting display
extends Control
class_name TargetTooltip
const QoSService = preload("res://core/autoload/qos_service.gd")

const UIStyles = preload("res://ui/components/ui_styles.gd")
# Entity is not an autoload (class_name only). This component uses
# Entity.EntityType.X for color mapping, which requires Entity's
# class_name registered at parse time. Preload it here.
const Entity = preload("res://core/entities/entity.gd")

const CharacterData := preload("res://core/schemas/character_data.gd")

var _interaction_layer: InteractionLayer
var _current_target_id: String = ""
var _current_entity_type: int = 0

var _header_label: Label
var _info_label: Label
var _actions_container: HBoxContainer
var _status_label: Label
var _level_label: Label
var _pin_btn: Button
var _close_btn: Button
var _action_buttons: Array = []
var _panel: PanelContainer
var _vbox: VBoxContainer
var _is_sticky: bool = false
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _fade_tween: Tween = null

signal action_clicked(action_id: String, target_id: String)
signal tooltip_closed()
signal tooltip_opened()

func _ready() -> void:
	_setup_ui()
	_connect_signals()
	hide()

func _connect_signals() -> void:
	if TargetingManager:
		TargetingManager.target_acquired.connect(_on_target_acquired)
		TargetingManager.target_cleared.connect(_on_target_cleared)
		TargetingManager.target_updated.connect(_on_target_updated)
		TargetingManager.target_type_changed.connect(_on_target_type_changed)

	if InteractionLayer:
		_interaction_layer = InteractionLayer
		InteractionLayer.tap.connect(_on_interaction_tap)

func set_interaction_layer(layer: InteractionLayer) -> void:
	_interaction_layer = layer

## ============================================================================
## SIGNAL HANDLERS
## ============================================================================

func _on_target_acquired(target: TargetingManager.TargetInfo) -> void:
	if not TargetingManager:
		return

	# Only show tooltip for local player targeting
	var local_id: int = TargetingManager.get_local_player_id()
	if target.id == "" or not target.node:
		return

	_current_target_id = target.id
	_current_entity_type = target.entity_type

	show()
	tooltip_opened.emit()

	# Animate in
	_fade_in()

func _on_target_cleared(previous_target: TargetingManager.TargetInfo) -> void:
	if _is_sticky:
		return

	_fade_out()
	await get_tree().create_timer(0.2).timeout
	hide()
	tooltip_closed.emit()

func _on_target_updated(target: TargetingManager.TargetInfo) -> void:
	# Refresh tooltip on any update (e.g., health change)
	if _current_target_id != "" and target.id == _current_target_id:
		_refresh_tooltip()

func _on_target_type_changed(target_id: String, old_type: int, new_type: int) -> void:
	# Refresh tooltip when target type changes (e.g., player goes offline)
	if target_id == _current_target_id:
		_refresh_tooltip()

func _on_interaction_tap(position: Vector2) -> void:
	if not is_visible():
		return

	# Check if tap is on tooltip - if not, maybe close
	if not _panel:
		return

	var tooltip_rect := Rect2(_panel.global_position, _panel.size)
	if not tooltip_rect.has_point(position):
		# Tapped outside tooltip - close unless sticky
		if not _is_sticky:
			TargetingManager.clear_target()

## ============================================================================
## UI SETUP
## ============================================================================

func _setup_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -320
	_panel.offset_top = 10
	_panel.offset_right = -10
	_panel.offset_bottom = 500
	_panel.z_index = 1000
	_panel.modulate = Color.WHITE

	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
	style.border_color = UIStyles.COLORS.border
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_top = 12
	style.content_margin_right = 12
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)

	_panel.gui_input.connect(_on_panel_input)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_vbox = vbox
	_panel.add_child(vbox)
	_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Header with name and type
	var header := HBoxContainer.new()
	_vbox.add_child(header)

	_header_label = Label.new()
	_header_label.text = "Target"
	_header_label.add_theme_font_size_override("font_size", 20)
	_header_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_header_label)

	_level_label = Label.new()
	_level_label.text = "Lv.1"
	_level_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_level_label)

	_close_btn = Button.new()
	_close_btn.text = ""
	_close_btn.custom_minimum_size = Vector2(32, 32)
	_close_btn.pressed.connect(close_tooltip)
	header.add_child(_close_btn)

	_pin_btn = Button.new()
	_pin_btn.text = ""
	_pin_btn.custom_minimum_size = Vector2(32, 32)
	_pin_btn.pressed.connect(_toggle_sticky)
	header.add_child(_pin_btn)

	# Entity type/status
	_info_label = Label.new()
	_info_label.add_theme_color_override("font_color", UIStyles.COLORS.info)
	_info_label.add_theme_font_size_override("font_size", 14)
	_vbox.add_child(_info_label)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", UIStyles.COLORS.success)
	_status_label.add_theme_font_size_override("font_size", 12)
	_vbox.add_child(_status_label)

	var sep := Label.new()
	sep.custom_minimum_size.y = 8
	_vbox.add_child(sep)

	# Actions container
	_actions_container = HBoxContainer.new()
	_actions_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_child(_actions_container)

## ============================================================================
## TOOLTIP UPDATE
## ============================================================================

func _refresh_tooltip() -> void:
	var target: Variant = TargetingManager.get_current_target()
	if not target:
		return

	# Check if this is a GM player
	var is_gm_player: bool = false
	var char_data = target.node.get("character_data") if target.node else null
	if char_data and char_data.has("is_gm"):
		is_gm_player = char_data.is_gm()
	elif target.node and target.node.has("class_id"):
		is_gm_player = CharacterData.is_gm_class(target.node.get("class_id"))

	# Build display name with GM prefix
	var display_name: String = target.display_name
	if is_gm_player:
		display_name = "[GM] " + display_name

	_header_label.text = display_name

	# Set color based on entity type (gold for GM players)
	_header_label.add_theme_color_override("font_color", _get_name_color(target.entity_type, is_gm_player))

	# Entity type info
	var type_str: String = TargetingManager.entity_type_to_string(target.entity_type)
	if is_gm_player:
		type_str = " GAME MASTER"
	_info_label.text = type_str

	# Status
	_status_label.text = _get_status_text(target, is_gm_player)

	# Update action buttons
	_update_action_buttons_from_schema(target.schema_id)

	# Update level if available
	if target.node and target.node.has("level"):
		_level_label.text = "Lv.%d" % target.node.level
	else:
		_level_label.text = ""

func _get_name_color(entity_type: int, is_gm: bool = false) -> Color:
	if is_gm:
		return UIStyles.COLORS.accent_gold
	match entity_type:
		Entity.EntityType.PLAYER: return UIStyles.COLORS.info
		Entity.EntityType.ENEMY: return UIStyles.COLORS.error
		Entity.EntityType.NPC: return UIStyles.COLORS.success
		Entity.EntityType.LOOT: return Color(1.0, 0.8, 0.3)     # Gold
		Entity.EntityType.TELEPORT: return Color(0.6, 0.3, 1.0) # Purple
		_: return Color(1.0, 1.0, 1.0)

func _get_status_text(target: TargetingManager.TargetInfo, is_gm: bool = false) -> String:
	match target.entity_type:
		Entity.EntityType.PLAYER:
			var online_val = target.node.get("is_online") if target.node else null
			if is_gm:
				return "* Online "
			return "* Online" if online_val else "o Offline"
		Entity.EntityType.ENEMY:
			if target.node and target.node.has("health"):
				var hp_val = target.node.get("health")
				var hp: int = hp_val if hp_val != null else 0
				var max_hp_val = target.node.get("max_health")
				var max_hp: int = max_hp_val if max_hp_val != null else 1
				return " %d/%d HP" % [hp, max_hp]
			return " Hostile"
		Entity.EntityType.NPC:
			return " Click to interact"
		Entity.EntityType.LOOT:
			return " Press to loot"
		Entity.EntityType.TELEPORT:
			return " Enter to teleport"
		Entity.EntityType.OBJECT:
			return " Interact"
		_:
			return ""

func _update_action_buttons_from_schema(schema_id: String) -> void:
	# Clear existing buttons
	for btn in _action_buttons:
		btn.queue_free()
	_action_buttons.clear()

	if not TargetingManager:
		return

	var schema: Variant = TargetingManager.get_schema(schema_id)
	if not schema:
		return

	var button_size := Vector2(90, 40)
	if _interaction_layer:
		button_size = _interaction_layer.get_button_size()

	for action_id in schema.available_actions:
		var btn := _create_action_button(action_id, button_size)
		_actions_container.add_child(btn)
		_action_buttons.append(btn)

func _create_action_button(action_id: String, size: Vector2) -> Button:
	var action_def: Variant = TargetingManager.get_action_definition(action_id)

	var btn := Button.new()
	btn.text = _get_action_icon(action_id) + " " + _get_action_name(action_id)
	btn.custom_minimum_size = size
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	# Style based on action type
	var style := StyleBoxFlat.new()
	match _get_action_category(action_id):
		"moderation":
			style.bg_color = UIStyles.COLORS.error
		"admin":
			style.bg_color = UIStyles.COLORS.warning
		"social":
			style.bg_color = Color(0.2, 0.4, 0.6)  # Blue
		"interaction":
			style.bg_color = Color(0.2, 0.5, 0.3)  # Green
		_:
			style.bg_color = Color(0.2, 0.3, 0.4)  # Default

	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", style)

	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = style.bg_color.lightened(0.2)
	pressed_style.corner_radius_top_left = 6
	pressed_style.corner_radius_top_right = 6
	pressed_style.corner_radius_bottom_left = 6
	pressed_style.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("pressed", pressed_style)

	# Connect action with QoS check
	btn.pressed.connect(_on_action_button_pressed.bind(action_id, _current_target_id))

	return btn

func _get_action_icon(action_id: String) -> String:
	match action_id:
		"whisper": return ""
		"party": return ""
		"guild": return ""
		"trade": return ""
		"report": return ""
		"kick": return ""
		"ban": return ""
		"teleport": return ""
		"loot": return ""
		"talk": return ""
		"use": return ""
		"resurrect": return ""
		"revive": return ""
		_: return "*"

func _get_action_name(action_id: String) -> String:
	match action_id:
		"whisper": return "Whisper"
		"party": return "Party"
		"guild": return "Guild"
		"trade": return "Trade"
		"report": return "Report"
		"kick": return "Kick"
		"ban": return "Ban"
		"teleport": return "Teleport"
		"loot": return "Loot"
		"talk": return "Talk"
		"use": return "Use"
		"resurrect": return "Resurrect"
		"revive": return "Revive"
		_: return action_id.capitalize()

func _get_action_category(action_id: String) -> String:
	match action_id:
		"whisper", "party", "guild", "trade":
			return "social"
		"report", "kick", "ban":
			return "moderation"
		"teleport", "loot", "talk", "use":
			return "interaction"
		"spawn", "kill", "freeze", "invisible":
			return "admin"
		_:
			return "default"

## ============================================================================
## ACTION EXECUTION WITH QOS & PERMISSIONS
## ============================================================================

func _on_action_button_pressed(action_id: String, target_id: String) -> void:
	if not TargetingManager or not QoSService:
		action_clicked.emit(action_id, target_id)
		return

	# Rate limit check
	if QoSService.rate_limit(_current_target_id, "tooltip_action"):
		GameLog.debug("TargetTooltip: Rate limited action %s" % action_id)
		_flash_rate_limit_warning()
		return

	# Permission check for sensitive actions (scaffold: wire to PermissionManager
	# once player-id propagation is in place). For now, let all actions through.
	if _requires_permission(action_id) and false:
		if not PermissionManager or not PermissionManager.has_permission(action_id, PermissionManager.Level.PLAYER):
			_show_permission_denied(action_id)
			return

	# Execute action through TargetingManager
	var result: Dictionary = TargetingManager.execute_action_on(action_id, target_id)
	var success: bool = result.get("success") if result.get("success") != null else false

	if success:
		action_clicked.emit(action_id, target_id)
		# Emit to EventBus for other systems
		EventHub.target_action_executed.emit(
			TargetingManager.get_local_player_id(),
			target_id,
			action_id,
			true
		)
	else:
		_show_action_failed(action_id)

func _requires_permission(action_id: String) -> bool:
	return action_id in ["report", "kick", "ban", "teleport", "freeze", "invisible", "spawn", "resurrect", "revive"]

func _flash_rate_limit_warning() -> void:
	var original_color: Color = _panel.get_theme_stylebox("panel").bg_color
	var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style.bg_color = Color(0.8, 0.2, 0.2)
		await get_tree().create_timer(0.3).timeout
		style.bg_color = original_color

func _show_permission_denied(action_id: String) -> void:
	_status_label.text = " Permission denied"
	_status_label.add_theme_color_override("font_color", UIStyles.COLORS.error)

func _show_action_failed(action_id: String) -> void:
	_status_label.text = " Action failed"
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))

## ============================================================================
## UI INTERACTION
## ============================================================================

func _toggle_sticky() -> void:
	_is_sticky = not _is_sticky
	_pin_btn.text = "" if _is_sticky else ""

	var tween := create_tween()
	if _is_sticky:
		tween.tween_property(_panel, "modulate", Color(1, 1, 0.8, 1), 0.2)
	else:
		tween.tween_property(_panel, "modulate", Color.WHITE, 0.2)

func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		if not _is_dragging:
			_is_dragging = true
			_drag_offset = event.position - _panel.global_position
		_panel.global_position = event.position - _drag_offset

	if event is InputEventScreenTouch and not event.pressed:
		_is_dragging = false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_bring_to_front()
		else:
			_is_dragging = false

func _bring_to_front() -> void:
	if _panel:
		_panel.z_index = 1001

func _fade_in() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_panel.modulate = Color.WHITE.lerp(Color(1, 1, 1, 0), 1.0)
	_panel.modulate = Color(1, 1, 1, 0)
	_fade_tween.tween_property(_panel, "modulate:a", 1.0, 0.15)

func _fade_out() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_panel, "modulate:a", 0.0, 0.15)

func close_tooltip() -> void:
	_is_sticky = false
	_pin_btn.text = ""
	TargetingManager.clear_target()
	hide()
	tooltip_closed.emit()

func open_sticky() -> void:
	_is_sticky = true
	_pin_btn.text = ""
	show()

	var header := HBoxContainer.new()
	_vbox.add_child(header)

	_header_label = Label.new()
	_header_label.text = "Target"
	_header_label.add_theme_font_size_override("font_size", 18)
	_header_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	header.add_child(_header_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_close_btn = Button.new()
	_close_btn.text = ""
	_close_btn.custom_minimum_size = Vector2(40, 40)
	_close_btn.pressed.connect(close_tooltip)
	header.add_child(_close_btn)

	_pin_btn = Button.new()
	_pin_btn.text = ""
	_pin_btn.custom_minimum_size = Vector2(40, 40)
	_pin_btn.pressed.connect(_toggle_sticky)
	header.add_child(_pin_btn)

	_info_label = Label.new()
	_info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_info_label)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", UIStyles.COLORS.success)
	_vbox.add_child(_status_label)

	var sep := Label.new()
	sep.custom_minimum_size.y = 8
	_vbox.add_child(sep)

	_actions_container = HBoxContainer.new()
	_actions_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_child(_actions_container)
