## WorldMap - Full-screen world map with quest waypoints
## Expanded from Minimap, supports click-to-navigate
class_name WorldMap
extends Control

## Singleton
static var instance: WorldMap

## Components
var _map_view: Control
var _map_texture: TextureRect
var _marker_container: Control
var _player_marker: Control
var _compass: Control

## State
var _is_expanded: bool = false
var _minimap_mode: bool = true
var _zoom_level: float = 1.0
var _pan_offset: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO

## Quest waypoints
var _waypoints: Array = []

## Markers cache
var _entity_markers: Dictionary = {}

## Sizes
var _minimap_size: Vector2 = Vector2(150, 150)
var _fullmap_size: Vector2 = Vector2(1920, 1080)
var _world_size: Vector2 = Vector2(8192, 8192)  # 8km x 8km world

signal waypoint_clicked(position: Vector3)
signal map_clicked(position: Vector3)

func _ready() -> void:
	instance = self
	_setup_ui()
	_set_minimap_mode()
	_bind_zone_signals()
	hide()


func _bind_zone_signals() -> void:
	if ZoneManager:
		if ZoneManager.has_signal("zone_loaded"):
			if not ZoneManager.zone_loaded.is_connected(_on_zone_loaded):
				ZoneManager.zone_loaded.connect(_on_zone_loaded)


func _on_zone_loaded(zone_data) -> void:
	if zone_data and "name" in zone_data:
		set_zone_name(zone_data.name)

func _setup_ui() -> void:
	name = "WorldMap"

	# Main container
	var container := Control.new()
	container.name = "Container"
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)

	# Map viewport
	_map_view = Control.new()
	_map_view.name = "MapView"
	_map_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_child(_map_view)

	# Map texture background
	_map_texture = TextureRect.new()
	_map_texture.name = "MapTexture"
	_map_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_view.add_child(_map_texture)

	# Marker container
	_marker_container = Control.new()
	_marker_container.name = "MarkerContainer"
	_marker_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_view.add_child(_marker_container)

	# Player marker (always in center for minimap)
	_player_marker = _create_marker("Player", UIStyles.COLORS.accent_gold)
	_player_marker.custom_minimum_size = Vector2(12, 12)
	_marker_container.add_child(_player_marker)

	# Compass
	_compass = _create_compass()
	container.add_child(_compass)

	# Zone name
	var zone_label := Label.new()
	zone_label.name = "ZoneName"
	zone_label.text = "Zone"
	zone_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	zone_label.offset_bottom = -20
	zone_label.add_theme_font_size_override("font_size", 14)
	zone_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	container.add_child(zone_label)

	# Controls overlay (for full map)
	var controls := _create_controls()
	controls.name = "Controls"
	controls.visible = false
	container.add_child(controls)

	# Close button (for full map)
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "X"
	close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_btn.offset_left = -50
	close_btn.offset_top = 10
	close_btn.offset_right = -10
	close_btn.offset_bottom = 40
	close_btn.pressed.connect(_on_close_pressed)
	controls.add_child(close_btn)

func _create_marker(name: String, color: Color) -> Control:
	var marker := Control.new()
	marker.name = name
	marker.custom_minimum_size = Vector2(8, 8)

	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	marker.add_theme_stylebox_override("panel", style)
	
	return marker
	
func _create_compass() -> Control:
	var compass := Control.new()
	compass.name = "Compass"
	compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	compass.offset_top = 10
	compass.custom_minimum_size = Vector2(60, 30)

	var label := Label.new()
	label.text = "N"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	compass.add_child(label)

	return compass

func _create_controls() -> Control:
	var controls := Control.new()
	controls.set_anchors_preset(Control.PRESET_FULL_RECT)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hbox.offset_bottom = -60
	controls.add_child(hbox)

	# Zoom controls
	var zoom_label := Label.new()
	zoom_label.text = "Zoom:"
	hbox.add_child(zoom_label)

	var zoom_out := Button.new()
	zoom_out.text = "-"
	zoom_out.pressed.connect(_on_zoom_out)
	hbox.add_child(zoom_out)

	var zoom_in := Button.new()
	zoom_in.text = "+"
	zoom_in.pressed.connect(_on_zoom_in)
	hbox.add_child(zoom_in)

	# Center button
	var center_btn := Button.new()
	center_btn.text = "Center"
	center_btn.pressed.connect(_on_center_pressed)
	hbox.add_child(center_btn)

	return controls

func _set_minimap_mode() -> void:
	_minimap_mode = true
	custom_minimum_size = _minimap_size
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -160
	offset_top = 60
	offset_right = -10
	offset_bottom = 210

	# Show/hide controls
	var controls: Control = get_node_or_null("Container/Controls")
	if controls:
		controls.visible = false

func _set_fullmap_mode() -> void:
	_minimap_mode = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	custom_minimum_size = _fullmap_size

	# Show/hide controls
	var controls: Control = get_node_or_null("Container/Controls")
	if controls:
		controls.visible = true

		## ============================================================================
		## PUBLIC API
		## ============================================================================

static func get_instance() -> WorldMap:
	return instance

func toggle() -> void:
	if visible:
		hide()
	else:
		show()

func show_map() -> void:
	show()

func hide_map() -> void:
	hide()

func expand_to_fullscreen() -> void:
	_set_fullmap_mode()
	show()

func minimize_to_minimap() -> void:
	_set_minimap_mode()
	hide()

func is_minimap() -> bool:
	return _minimap_mode

func set_zone_name(name: String) -> void:
	var zone_label: Label = get_node_or_null("Container/ZoneName")
	if zone_label:
		zone_label.text = name

func set_player_position(world_pos: Vector3) -> void:
	if _minimap_mode:
		_update_minimap_position(world_pos)

func _update_minimap_position(world_pos: Vector3) -> void:
	# In minimap mode, player is always centered
	# Other markers move relative to player
	_player_marker.position = Vector2(_minimap_size.x / 2 - 6, _minimap_size.y / 2 - 6)

	## ============================================================================
	## WAYPOINTS
	## ============================================================================

func add_waypoint(quest_id: String, position: Vector3, label: String = "", icon_type: int = 0) -> void:
	var waypoint := {
	"id": quest_id,
	"position": position,
	"label": label,
	"icon_type": icon_type,
	"marker": null
	}

	# Create marker
	var marker_color := UIStyles.COLORS.warning  # Quest yellow
	if icon_type == 1:  # Boss
		marker_color = UIStyles.COLORS.error
	elif icon_type == 2:  # NPC
		marker_color = UIStyles.COLORS.accent_gold

	var marker := _create_marker(quest_id, marker_color)
	marker.custom_minimum_size = Vector2(10, 10)
	_marker_container.add_child(marker)

	waypoint.marker = marker
	_waypoints.append(waypoint)
	_entity_markers[quest_id] = waypoint

func remove_waypoint(quest_id: String) -> void:
	for i in range(_waypoints.size()):
		if _waypoints[i].id == quest_id:
			var marker: Control = _waypoints[i].marker
			if marker:
				marker.queue_free()
				_waypoints.remove_at(i)
				_entity_markers.erase(quest_id)
				break

func clear_waypoints() -> void:
	for waypoint in _waypoints:
		var marker: Control = waypoint.marker
		if marker:
			marker.queue_free()
			_waypoints.clear()
			_entity_markers.clear()

func update_waypoint_position(quest_id: String, position: Vector3) -> void:
	if _entity_markers.has(quest_id):
		_entity_markers[quest_id].position = position

		## ============================================================================
		## MARKERS
		## ============================================================================

func add_marker(entity_id: String, world_pos: Vector3, marker_type: int, label: String = "") -> void:
	if _entity_markers.has(entity_id):
		return

	var color := UIStyles.COLORS.info
	if marker_type == 1:
		color = UIStyles.COLORS.success
	elif marker_type == 2:
		color = UIStyles.COLORS.accent_gold
	elif marker_type == 3:
		color = UIStyles.COLORS.warning
	elif marker_type == 4:
		color = UIStyles.COLORS.error
	elif marker_type == 5:
		color = UIStyles.COLORS.info
	else:
		color = UIStyles.COLORS.info

	var marker := _create_marker(entity_id, color)
	_marker_container.add_child(marker)

	_entity_markers[entity_id] = {
	"marker": marker,
	"position": world_pos,
	"type": marker_type,
	"label": label
	}

func remove_marker(entity_id: String) -> void:
	if not _entity_markers.has(entity_id):
		return

	var marker: Control = _entity_markers[entity_id].marker
	if marker:
		marker.queue_free()
		_entity_markers.erase(entity_id)

		## ============================================================================
		## INPUT
		## ============================================================================

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if _minimap_mode:
				expand_to_fullscreen()
			else:
				_handle_map_click(event.position)
	elif event is InputEventMouseMotion and _is_dragging:
		_pan_offset += event.relative

func _handle_map_click(screen_pos: Vector2) -> void:
	var map_pos := _screen_to_world(screen_pos)
	map_clicked.emit(map_pos)

func _screen_to_world(screen_pos: Vector2) -> Vector3:
	# Convert screen position to world position
	var world_x := (screen_pos.x / custom_minimum_size.x) * _world_size.x
	var world_z := (screen_pos.y / custom_minimum_size.y) * _world_size.y
	return Vector3(world_x, 0, world_z)

	## ============================================================================
	## ACTIONS
	## ============================================================================

func _on_close_pressed() -> void:
	minimize_to_minimap()

func _on_zoom_in() -> void:
	_zoom_level = mini(_zoom_level * 1.5, 4.0)

func _on_zoom_out() -> void:
	_zoom_level = maxi(_zoom_level / 1.5, 0.5)

func _on_center_pressed() -> void:
	_pan_offset = Vector2.ZERO
