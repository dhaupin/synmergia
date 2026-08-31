## Minimap - World map component
## Interactive minimap with player position and markers
class_name Minimap
extends Control

## Components
var _map_texture: TextureRect
var _player_marker: Control
var _compass_label: Label
var _zoom_slider: HSlider
var _marker_container: Control

## State
var _player_position: Vector3 = Vector3.ZERO
var _player_rotation: float = 0.0
var _zoom_level: float = 1.0
var _map_size: Vector2 = Vector2(2048, 2048)  # World size
var _minimap_size: Vector2 = Vector2(150, 150)
var _show_players: bool = true
var _show_npcs: bool = true
var _show_quests: bool = true

## Markers
var _entity_markers: Dictionary = {}  # entity_id -> marker_control

func _ready() -> void:
	_setup_ui()
	_connect_signals()

func _setup_ui() -> void:
	name = "Minimap"
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -160
	offset_top = 60
	offset_right = -10
	offset_bottom = 210
	custom_minimum_size = Vector2(150, 150)

	# Main panel
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

var style := StyleBoxFlat.new()
style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
style.border_color = UIStyles.COLORS.border
style.corner_radius_top_left = 8
style.corner_radius_top_right = 8
style.corner_radius_bottom_left = 8
style.corner_radius_bottom_right = 8
panel.add_theme_stylebox_override("panel", style)

# Map texture area
var map_container := Control.new()
map_container.name = "MapContainer"
map_container.set_anchors_preset(Control.PRESET_FULL_RECT)
panel.add_child(map_container)

_map_texture = TextureRect.new()
_map_texture.name = "MapTexture"
_map_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
_map_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
_map_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
map_container.add_child(_map_texture)

# Marker container (on top of map)
_marker_container = Control.new()
_marker_container.name = "MarkerContainer"
_marker_container.set_anchors_preset(Control.PRESET_FULL_RECT)
map_container.add_child(_marker_container)

# Player marker
_player_marker = Control.new()
_player_marker.name = "PlayerMarker"
_player_marker.custom_minimum_size = Vector2(10, 10)
_marker_container.add_child(_player_marker)

var player_style := StyleBoxFlat.new()
player_style.bg_color = UIStyles.COLORS.accent_gold
player_style.corner_radius_top_left = 5
player_style.corner_radius_top_right = 5
player_style.corner_radius_bottom_left = 5
player_style.corner_radius_bottom_right = 5
_player_marker.add_theme_stylebox_override("panel", player_style)

# Compass label (N indicator)
_compass_label = Label.new()
_compass_label.name = "Compass"
_compass_label.text = "N"
_compass_label.set_anchors_preset(Control.PRESET_TOP_HCENTER)
_compass_label.offset_top = -2
_compass_label.add_theme_font_size_override("font_size", 10)
_compass_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
panel.add_child(_compass_label)

# Zone name
var zone_label := Label.new()
zone_label.name = "ZoneName"
zone_label.text = "Zone"
zone_label.set_anchors_preset(Control.PRESET_BOTTOM_HCENTER)
zone_label.offset_bottom = -4
zone_label.add_theme_font_size_override("font_size", 9)
zone_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
panel.add_child(zone_label)

func _connect_signals() -> void:
	# TODO: Connect to zone changes
	pass

func _process(_delta: float) -> void:
	_update_player_marker()

func _update_player_marker() -> void:
	if not _player_marker:
		return

		# Calculate marker position relative to minimap center
		var minimap_center := _minimap_size / 2.0
		var map_scale := (_minimap_size.x / _map_size.x) * _zoom_level

		# Convert world position to minimap position
		var map_pos := Vector2(
		_player_position.x * map_scale,
		_player_position.z * map_scale
		)

	var marker_pos := minimap_center + map_pos

	# Clamp to minimap bounds
	marker_pos.x = clampf(marker_pos.x, 5, _minimap_size.x - 5)
	marker_pos.y = clampf(marker_pos.y, 5, _minimap_size.y - 5)

_player_marker.position = marker_pos - Vector2(5, 5)

# Rotate marker based on player rotation
_player_marker.rotation = -_player_rotation

func set_player_position(position: Vector3) -> void:
	_player_position = position

func set_player_rotation(rotation: float) -> void:
	_player_rotation = rotation

func set_zone_name(name: String) -> void:
	var panel: PanelContainer = get_node_or_null("Panel")
	if panel:
		var zone_label: Label = panel.get_node_or_null("ZoneName")
		if zone_label:
			zone_label.text = name

func add_marker(entity_id: String, position: Vector3, marker_type: int, label: String = "") -> void:
	if _entity_markers.has(entity_id):
		return

	var marker := Control.new()
	marker.name = "Marker_%s" % entity_id
	marker.custom_minimum_size = Vector2(8, 8)
	_marker_container.add_child(marker)

	# Color based on type
	var color := UIStyles.COLORS.info
	match marker_type:
		1:  # Player
		color = UIStyles.COLORS.success
		2:  # NPC
		color = UIStyles.COLORS.accent_gold
		3:  # Quest
		color = UIStyles.COLORS.warning
		4:  # Enemy
		color = UIStyles.COLORS.error
		5:  # Item
		color = UIStyles.COLORS.info

	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	marker.add_theme_stylebox_override("panel", style)

_entity_markers[entity_id] = {
"marker": marker,
"position": position,
"type": marker_type,
"label": label
}

func remove_marker(entity_id: String) -> void:
	if not _entity_markers.has(entity_id):
		return

	var data: Dictionary = _entity_markers[entity_id]
	var marker: Control = data.get("marker")
	if marker:
		marker.queue_free()

	_entity_markers.erase(entity_id)

func update_marker_position(entity_id: String, position: Vector3) -> void:
	if not _entity_markers.has(entity_id):
		return

	_entity_markers[entity_id].position = position

func set_zoom(level: float) -> void:
	_zoom_level = clampf(level, 0.5, 4.0)

func get_zoom() -> float:
	return _zoom_level

func toggle_players() -> void:
	_show_players = not _show_players
	_update_visible_markers()

func toggle_npcs() -> void:
	_show_npcs = not _show_npcs
	_update_visible_markers()

func toggle_quests() -> void:
	_show_quests = not _show_quests
	_update_visible_markers()

func _update_visible_markers() -> void:
	for entity_id in _entity_markers:
		var data: Dictionary = _entity_markers[entity_id]
		var marker_type: int = data.get("type", 0)
		var marker: Control = data.get("marker")

		match marker_type:
			1: marker.visible = _show_players
			2: marker.visible = _show_npcs
			3: marker.visible = _show_quests
