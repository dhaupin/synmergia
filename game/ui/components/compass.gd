## Compass - Directional indicator for waypoints and points of interest
## Shows waypoints in a horizontal arc around the player
extends Control

const WaypointService = preload("res://core/services/waypoint_service.gd")

# Configuration
const INDICATOR_COUNT: int = 9  # Number of indicator slots
const INDICATOR_SPACING: float = 15.0  # Degrees per slot
const MAX_WAYPOINT_DISTANCE: float = 1000.0  # Max distance to show waypoints
const WAYPOINT_MIN_DISTANCE: float = 20.0  # Min distance to show (don't show right at player)

# Waypoint indicator colors (matching minimap)
const WAYPOINT_COLORS: Array[Color] = [
	Color(1.0, 0.3, 0.3),   # Red = 0
	Color(1.0, 0.6, 0.2),   # Orange = 1
	Color(1.0, 0.9, 0.3),   # Yellow = 2
	Color(0.3, 1.0, 0.3),   # Green = 3
	Color(0.3, 0.6, 1.0),   # Blue = 4
	Color(0.8, 0.3, 1.0),   # Purple = 5
	Color(1.0, 0.4, 0.7),   # Pink = 6
	Color(1.0, 1.0, 1.0)    # White = 7
]

# State
var _indicators: Array[Control] = []
var _player_rotation: float = 0.0
var _player_position: Vector3 = Vector3.ZERO
var _is_visible: bool = false

# UI Elements
@onready var center_marker: Control = $CenterMarker
@onready var direction_labels: HBoxContainer = $DirectionLabels
@onready var waypoint_container: Control = $WaypointContainer

func _ready() -> void:
	_setup_ui()
	visible = false

	# Connect to WaypointService
	if WaypointService:
		WaypointService.waypoint_activated.connect(_on_waypoint_activated)
		WaypointService.waypoint_deactivated.connect(_on_waypoint_deactivated)

func _setup_ui() -> void:
	# Create center marker (player's current direction)
	center_marker = Control.new()
	center_marker.name = "CenterMarker"
	var marker_style := StyleBoxFlat.new()
	marker_style.bg_color = Color(1, 1, 1, 0.9)
	marker_style.corner_radius_top_left = 2
	marker_style.corner_radius_top_right = 2
	marker_style.corner_radius_bottom_left = 2
	marker_style.corner_radius_bottom_right = 2
	center_marker.add_theme_stylebox_override("panel", marker_style)
	center_marker.custom_minimum_size = Vector2(4, 20)
	center_marker.set_anchors_preset(Control.PRESET_CENTER)
	add_child(center_marker)

	# Create direction labels (N, NE, E, SE, S, SW, W, NW)
	direction_labels = HBoxContainer.new()
	direction_labels.name = "DirectionLabels"
	direction_labels.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	direction_labels.offset_bottom = 20
	direction_labels.alignment = BoxContainer.ALIGNMENT_CENTER

	var directions := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	for i in range(8):
		var label := Label.new()
		label.text = directions[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size.x = 60
		direction_labels.add_child(label)

	add_child(direction_labels)

	# Create waypoint indicator container
	waypoint_container = Control.new()
	waypoint_container.name = "WaypointContainer"
	waypoint_container.set_anchors_preset(Control.PRESET_CENTER)
	add_child(waypoint_container)

func _process(delta: float) -> void:
	if not visible or not _is_visible:
		return

	_update_compass()

func _update_compass() -> void:
	if not WaypointService or not PlayerManager:
		return

	var player_id := str(PlayerManager.get_local_player_id())
	var active_wp := WaypointService.get_active_waypoint(player_id)

	if active_wp.is_empty():
		_clear_waypoint_indicators()
		return

	# Get waypoint position
	var wp_pos := Vector3(
		active_wp.get("position_x", 0.0),
		active_wp.get("position_y", 0.0),
		active_wp.get("position_z", 0.0)
	)

	# Calculate direction to waypoint
	var to_waypoint: Vector3 = wp_pos - _player_position
	var distance: float = to_waypoint.length()

	# Don't show if too close or too far
	if distance < WAYPOINT_MIN_DISTANCE or distance > MAX_WAYPOINT_DISTANCE:
		_clear_waypoint_indicators()
		return

	# Get horizontal direction
	to_waypoint.y = 0
	to_waypoint = to_waypoint.normalized()

	# Get player's forward direction
	var player_forward := Vector3(0, 0, -1).rotated(Vector3.UP, _player_rotation)

	# Calculate angle between player forward and waypoint direction
	var angle := rad_to_deg(player_forward.signed_angle_to(to_waypoint, Vector3.UP))

	# Show indicator at angle position
	_show_waypoint_indicator(angle, distance, active_wp)

func _show_waypoint_indicator(angle: float, distance: float, wp_data: Dictionary) -> void:
	# Remove old indicators
	_clear_waypoint_indicators()

	# Calculate X position based on angle
	# Map angle from -180..180 to 0..size.x
	var screen_width := size.x
	var normalized_x: float = (angle + 180) / 360.0
	var x_pos: float = normalized_x * screen_width

	# Clamp to visible area
	x_pos = clamp(x_pos, 20, screen_width - 20)

	# Get color
	var color_idx: int = wp_data.get("color", 4)
	if color_idx < 0 or color_idx >= WAYPOINT_COLORS.size():
		color_idx = 4
	var color := WAYPOINT_COLORS[color_idx]

	# Create indicator
	var indicator := Control.new()
	indicator.name = "WaypointIndicator"
	indicator.position = Vector2(x_pos, size.y / 2 - 30)

	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	indicator.add_theme_stylebox_override("panel", style)
	indicator.custom_minimum_size = Vector2(16, 16)

	# Add distance label
	var dist_label := Label.new()
	dist_label.text = _format_distance(distance)
	dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist_label.add_theme_font_size_override("font_size", 10)
	dist_label.position = Vector2(-10, -20)
	indicator.add_child(dist_label)

	# Add icon
	var icon := Label.new()
	var icon_str := WaypointService.get_icon_string(wp_data.get("icon", 0)) if WaypointService else "📍"
	icon.text = icon_str
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.position = Vector2(-2, 18)
	indicator.add_child(icon)

	waypoint_container.add_child(indicator)

func _clear_waypoint_indicators() -> void:
	for child in waypoint_container.get_children():
		child.queue_free()

func _format_distance(distance: float) -> String:
	if distance < 100:
		return "%.0fm" % distance
	elif distance < 1000:
		return "%.0fm" % distance
	else:
		return "%.1fkm" % (distance / 1000.0)

func show_compass() -> void:
	visible = true
	_is_visible = true

func hide_compass() -> void:
	visible = false
	_is_visible = false

func toggle_compass() -> void:
	visible = not visible
	_is_visible = visible

func set_player_position(position: Vector3) -> void:
	_player_position = position

func set_player_rotation(rotation: float) -> void:
	_player_rotation = rotation
	# Rotate direction labels
	if direction_labels:
		direction_labels.rotation = -rotation

func _on_waypoint_activated(player_id: String, waypoint_id: String) -> void:
	if PlayerManager and str(PlayerManager.get_local_player_id()) == player_id:
		show_compass()

func _on_waypoint_deactivated(player_id: String, waypoint_id: String) -> void:
	if PlayerManager and str(PlayerManager.get_local_player_id()) == player_id:
		_clear_waypoint_indicators()
		hide_compass()
