## PlayerTargetController - Integrates PlayerTargetSystem with game input
## Handles player selection via mouse clicks and keyboard shortcuts
class_name PlayerTargetController
extends Node

## Reference to target system
var _target_system: PlayerTargetSystem

## Reference to tooltip UI
var _tooltip_ui: Control

## Local player ID
var _local_player_id: String = ""

## Target selection mode
var _selection_enabled: bool = true

## Mouse hover highlight
var _hovered_player_id: String = ""
var _hover_label: Label

signal target_selected(target_type: int, target_id: String)

func _ready() -> void:
	_target_system = PlayerTargetSystem
	
	# Create hover label
	_hover_label = Label.new()
	_hover_label.text = ""
	_hover_label.add_theme_color_override("font_color", Color(1, 1, 0.8))
	_hover_label.z_index = 500
	_hover_label.hide()
	add_child(_hover_label)
	
	# Connect to target system
	if _target_system:
		_target_system.target_changed.connect(_on_target_changed)
	
	Logger.info("PlayerTargetController: Initialized")

func _input(event: InputEvent) -> void:
	if not _selection_enabled:
		return
	
	# Mouse click to select target
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click(event.position)
	
	# Escape to clear target
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			clear_target()
		# Tab to cycle targets (nearest enemy/npc)
		elif event.keycode == KEY_TAB:
			_cycle_to_next_target()
		# F key to target focus (focus last target)
		elif event.keycode == KEY_F:
			_refocus_last_target()

func _handle_left_click(position: Vector2) -> void:
	# Raycast or check UI to see if we clicked on a player
	var clicked := _get_player_at_position(position)
	
	if clicked.size() > 0:
		var player_id: String = clicked.get("id", "")
		var player_name: String = clicked.get("name", player_id)
		var world_pos: Vector3 = clicked.get("position", Vector3.ZERO)
		
		_select_target(PlayerTargetSystem.TargetType.PLAYER, player_id, player_name, world_pos)
	else:
		# Clicked on empty space - clear target if clicking away from UI
		if not _is_click_on_ui(position):
			clear_target()

func _handle_right_click(position: Vector2) -> void:
	# Right click while targeting opens context menu
	var current := _target_system.get_current_target()
	if current.id != "" and current.type == PlayerTargetSystem.TargetType.PLAYER:
		# Show tooltip if not visible
		if _tooltip_ui and not _tooltip_ui.visible:
			_show_tooltip()

func _get_player_at_position(screen_pos: Vector2) -> Dictionary:
	# This would integrate with your game's raycasting/selection system
	# For now, we'll check if we're hovering over a player in the world
	
	# Placeholder - would use Camera3D.unproject_position + collision
	# or check nearby entities within range
	
	return {}

func _is_click_on_ui(position: Vector2) -> bool:
	# Check if click is over any UI element
	var tree := get_tree()
	if not tree:
		return false
	
	var root := tree.root
	if not root:
		return false
	
	# Get all controls under the click position
	var controls := root.get_nodes_in_group("clickable")
	for control in controls:
		if control is Control:
			var rect := Rect2(control.global_position, control.size)
			if rect.has_point(position):
				return true
	
	return false

func _select_target(type: int, target_id: String, target_name: String, position: Vector3) -> void:
	_target_system.set_target(type, target_id, target_name, position)
	target_selected.emit(type, target_id)
	
	# Show tooltip
	_show_tooltip()

func _show_tooltip() -> void:
	if not _tooltip_ui:
		# Create tooltip instance
		var scene_path := "res://ui/player/player_target_tooltip.tscn"
		var packed_scene := load(scene_path)
		if packed_scene:
			_tooltip_ui = packed_scene.instantiate()
			add_child(_tooltip_ui)
	
	if _tooltip_ui:
		_tooltip_ui.set_source_player(_local_player_id)
		_tooltip_ui.show()

func clear_target() -> void:
	_target_system.clear_target()
	
	if _tooltip_ui:
		_tooltip_ui.hide()

func _on_target_changed(type: int, target_id: String, target_name: String) -> void:
	# Update hover label
	if type == PlayerTargetSystem.TargetType.PLAYER and target_id != "":
		_hover_label.text = "[%s]" % target_name
		_hover_label.show()
	else:
		_hover_label.hide()

func _cycle_to_next_target() -> void:
	# Find nearest targetable entity
	# This would use spatial queries based on camera direction
	# For now, placeholder
	pass

func _refocus_last_target() -> void:
	# Re-select the last target
	# Would track in a history stack
	pass

## ============================================================================
## PUBLIC API
## ============================================================================

## Set the local player (who is doing the targeting)
func set_local_player(player_id: String) -> void:
	_local_player_id = player_id
	
	# Update tooltip with player
	if _tooltip_ui:
		_tooltip_ui.set_source_player(player_id)

## Enable/disable selection
func set_selection_enabled(enabled: bool) -> void:
	_selection_enabled = enabled
	if not enabled:
		clear_target()

## Get available actions for current target
func get_available_actions() -> Array:
	if not _target_system:
		return []
	return _target_system.get_available_actions(_local_player_id)

## Execute an action on current target
func execute_action(action_id: String) -> Dictionary:
	if not _target_system:
		return {"success": false, "message": "Target system not available"}
	return _target_system.execute_action(_local_player_id, action_id)

## Target a specific player by ID
func target_player(player_id: String) -> void:
	if not _target_system:
		return
	
	var info := _target_system.get_target_player_info()
	var name := info.get("name", player_id)
	
	_select_target(PlayerTargetSystem.TargetType.PLAYER, player_id, name, Vector3.ZERO)
