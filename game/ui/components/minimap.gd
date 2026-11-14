## Minimap - Enhanced world map component
## Interactive minimap with zoom, waypoints, markers, layer toggles, circular mask
extends Control
class_name Minimap
const UIStyles = preload("res://ui/components/ui_styles.gd")
const IconResolver = preload("res://core/utils/icon_resolver.gd")

## Discrete zoom levels
const ZOOM_LEVELS: Array[float] = [0.5, 1.0, 2.0, 4.0]

## PLAYER-CENTERED VIEW LAW: the disk spans this many world meters at
## zoom 1.0 (the old law keyed scale off _map_size, which on the globe
## is the 2048 default -> 0.09 px/m -> a 30 m walk moved markers 2.6 px
## and nothing visibly "scrolled"). A fixed window keeps the motion
## readable at any world scale; zoom levels widen/narrow it.
const DISK_METERS: float = 512.0

## Components
var _map_texture: TextureRect
var _player_marker: Control
var _compass_label: Label
var _zoom_slider: HSlider
var _marker_container: Control
var _mask_texture: TextureRect
var _zone_label: Label
var _coords_label: Label
var _time_label: Label
var _layer_toggle_container: HBoxContainer
var _context_menu: PopupMenu
var _zoom_index: int = 1  # Index into ZOOM_LEVELS (1.0 = index 1)

## State
var _player_position: Vector3 = Vector3.ZERO
var _player_rotation: float = 0.0
var _zoom_level: float = 1.0
var _map_size: Vector2 = Vector2(2048, 2048)
var _minimap_size: Vector2 = Vector2(180, 180)

## Layer visibility toggles
var _show_party: bool = true
var _show_npcs: bool = true
var _show_enemies: bool = true
var _show_quests: bool = true
var _show_pois: bool = true
var _show_vendors: bool = true
var _show_waypoints: bool = true
var _show_gates: bool = true
var _show_ankhs: bool = true
var _show_towns: bool = true

## Markers
var _entity_markers: Dictionary = {}  # entity_id -> marker_data

## Marker type constants
const MARKER_PARTY: int = 1
const MARKER_NPC: int = 2
const MARKER_ENEMY: int = 3
const MARKER_QUEST: int = 4
const MARKER_POI: int = 5
const MARKER_VENDOR: int = 6
const MARKER_WAYPOINT: int = 7
const MARKER_PING: int = 8
const MARKER_LOOT: int = 9
const MARKER_GATE: int = 10
const MARKER_ANKH: int = 11
const MARKER_TOWN: int = 12

## Landmark markers synced from world data (towns/gates/ankhs):
## marker ids stay in _static_landmarks so the next zone sync can
## replace exactly this set without touching live entity markers.
var _static_landmarks: Array[String] = []

signal waypoint_set(position: Vector3)
signal ping_sent(position: Vector3)
signal quest_track_requested(quest_id: String)
signal map_clicked(world_position: Vector3)
## Emitted when the map button is pressed (opens the full WorldMap).
## hud_layer wires this to WorldMap.toggle (round-6: the button never
## existed before -- the connect was a silent has_signal no-op).
signal map_button_pressed

func _ready() -> void:
	_setup_ui()
	_connect_signals()
	_setup_accessibility()

func _setup_accessibility() -> void:
	focus_mode = Control.FOCUS_ALL
func update_accessibility_settings(high_contrast: bool, text_scale: float, reduce_motion: bool) -> void:
	# Update zoom slider
	if _zoom_slider and is_instance_valid(_zoom_slider):
		_zoom_slider.add_theme_stylebox_override("focus", UIStyles.create_focus_style())

	# Update layer toggle buttons
	if _layer_toggle_container:
		for child in _layer_toggle_container.get_children():
			if child is Button:
				child.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
				var scale = UIStyles.get_text_scale()
				var current_size: int = child.get_theme_font_size("font_size")
				if current_size > 0:
					child.add_theme_font_size_override("font_size", int(current_size * scale))

	# Update labels
	for label in [_compass_label, _zone_label, _coords_label, _time_label]:
		if label and is_instance_valid(label):
			var scale = UIStyles.get_text_scale()
			var current_size: int = label.get_theme_font_size("font_size")
			if current_size > 0:
				label.add_theme_font_size_override("font_size", int(current_size * scale))

	# Update context menu
	if _context_menu and is_instance_valid(_context_menu):
		_context_menu.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
		var scale = UIStyles.get_text_scale()
		var current_size := _context_menu.get_theme_font_size("font_size")
		if current_size > 0:
			_context_menu.add_theme_font_size_override("font_size", int(current_size * scale))

func _setup_ui() -> void:
	name = "Minimap"
	# Placement authority is the host scene (hud_layer.tscn pins the
	# minimap top-right at y12..182). The old self-anchor moved the
	# widget DOWN 60px over the BuffBar/QuickAccessBar stack, which is
	# why the corner read as a garbled pile on the globe (feedback #4).
	# Only self-place when nothing anchored us yet (standalone/code
	# use): the scene root is a CanvasLayer, so parent-type checks do
	# not work here.
	var placed: bool = anchor_left != 0.0 or anchor_top != 0.0 or anchor_right != 0.0
	if not placed:
		set_anchors_preset(Control.PRESET_TOP_RIGHT)
		offset_left = -190
		offset_top = 60
		offset_right = -10
		offset_bottom = 240
	custom_minimum_size = Vector2(180, 180)

	# Main panel with circular mask
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.95)
	style.border_color = UIStyles.COLORS.border
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 90
	style.corner_radius_top_right = 90
	style.corner_radius_bottom_left = 90
	style.corner_radius_bottom_right = 90
	panel.add_theme_stylebox_override("panel", style)

	# Map container with clipping
	var map_container := Control.new()
	map_container.name = "MapContainer"
	map_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_container.clip_contents = true
	panel.add_child(map_container)

	# Circular mask for the map
	_mask_texture = TextureRect.new()
	_mask_texture.name = "MaskTexture"
	_mask_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mask_texture.texture = _create_circular_mask()
	map_container.add_child(_mask_texture)

	_map_texture = TextureRect.new()
	_map_texture.name = "MapTexture"
	_map_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map_container.add_child(_map_texture)

	_marker_container = Control.new()
	_marker_container.name = "MarkerContainer"
	_marker_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_container.add_child(_marker_container)

	# Player marker (arrow with heading)
	_player_marker = _create_player_arrow()
	_player_marker.name = "PlayerMarker"
	_marker_container.add_child(_player_marker)

	# Compass label (N indicator)
	_compass_label = Label.new()
	_compass_label.name = "Compass"
	_compass_label.text = "N"
	_compass_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_compass_label.offset_top = 8
	_compass_label.add_theme_font_size_override("font_size", 11)
	_compass_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	_compass_label.add_theme_constant_override("outline_size", 2)
	_compass_label.add_theme_color_override("outline_color", Color(0, 0, 0, 1))
	panel.add_child(_compass_label)

	# Zone name
	_zone_label = Label.new()
	_zone_label.name = "ZoneName"
	_zone_label.text = "Zone"
	_zone_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_zone_label.offset_bottom = -30
	_zone_label.add_theme_font_size_override("font_size", 10)
	_zone_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	_zone_label.add_theme_constant_override("outline_size", 1)
	_zone_label.add_theme_color_override("outline_color", Color(0, 0, 0, 1))
	panel.add_child(_zone_label)

	# Coordinates display
	_coords_label = Label.new()
	_coords_label.name = "CoordsLabel"
	_coords_label.text = "X: 0, Y: 0"
	_coords_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_coords_label.offset_bottom = -16
	_coords_label.add_theme_font_size_override("font_size", 8)
	_coords_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	_coords_label.add_theme_constant_override("outline_size", 1)
	_coords_label.add_theme_color_override("outline_color", Color(0, 0, 0, 1))
	panel.add_child(_coords_label)

	# Time of day indicator
	_time_label = Label.new()
	_time_label.name = "TimeLabel"
	_time_label.text = "12:00"
	_time_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_time_label.offset_left = 8
	_time_label.offset_top = 8
	_time_label.add_theme_font_size_override("font_size", 8)
	_time_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	_time_label.add_theme_constant_override("outline_size", 1)
	_time_label.add_theme_color_override("outline_color", Color(0, 0, 0, 1))
	panel.add_child(_time_label)

	# Layer toggle buttons row. MUST live inside the map container (a
	# plain Control), never as a direct child of the PanelContainer:
	# containers stretch every child to fill their rect, which turned
	# this HBox row into a column of screen-tall color bars over the
	# map (play-day feedback #4 -- the "garbled minimap").
	_layer_toggle_container = HBoxContainer.new()
	_layer_toggle_container.name = "LayerToggles"
	_layer_toggle_container.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# A zero-size control + only an offset_bottom left this row at a
	# NEGATIVE height: the toggles rendered 0 px tall -- "minimap
	# buttons aren't there" (play-test round 6). Pin a real 20 px strip
	# above the bottom edge instead.
	_layer_toggle_container.offset_top = -26
	_layer_toggle_container.offset_bottom = -6
	_layer_toggle_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_layer_toggle_container.add_theme_constant_override("separation", 1)
	map_container.add_child(_layer_toggle_container)

	_build_layer_toggles()

	# World Map button (round-6, item 9): the full map had NO opener --
	# hud_layer connected a map_button_pressed signal that never existed
	# (a silent has_signal no-op). A real button at the end of the toggle
	# row emits it; hud_layer toggles the WorldMap. Keyboard users have
	# the M hotkey; this is the visible (touch) path.
	var map_btn := Button.new()
	map_btn.name = "MapButton"
	map_btn.text = "M"
	map_btn.tooltip_text = "Open World Map (M)"
	map_btn.custom_minimum_size = Vector2(20, 20)
	map_btn.focus_mode = Control.FOCUS_ALL
	map_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style(3, false))
	var map_style := StyleBoxFlat.new()
	map_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	map_style.border_color = UIStyles.COLORS.accent_gold
	map_style.set_border_width_all(1)
	map_style.set_corner_radius_all(3)
	map_btn.add_theme_stylebox_override("normal", map_style)
	map_btn.add_theme_stylebox_override("hover", map_style)
	map_btn.add_theme_stylebox_override("pressed", map_style)
	map_btn.pressed.connect(func(): map_button_pressed.emit())
	_layer_toggle_container.add_child(map_btn)

	# Zoom slider
	_zoom_slider = HSlider.new()
	_zoom_slider.name = "ZoomSlider"
	_zoom_slider.min_value = 0
	_zoom_slider.max_value = ZOOM_LEVELS.size() - 1
	_zoom_slider.value = _zoom_index
	_zoom_slider.step = 1
	_zoom_slider.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_zoom_slider.offset_top = 2
	_zoom_slider.offset_left = 20
	_zoom_slider.offset_right = -20
	_zoom_slider.focus_mode = Control.FOCUS_ALL
	_zoom_slider.add_theme_stylebox_override("focus", UIStyles.create_focus_style(4, false))
	_zoom_slider.value_changed.connect(_on_zoom_changed)
	panel.add_child(_zoom_slider)

	# Context menu for right-click
	_context_menu = PopupMenu.new()
	_context_menu.name = "MapContextMenu"
	_context_menu.add_item("Set Waypoint", 1)
	_context_menu.add_item("Ping Location", 2)
	_context_menu.add_separator()
	_context_menu.add_item("Track Quest", 3)
	_context_menu.add_item("Show on World Map", 4)
	_context_menu.id_pressed.connect(_on_context_menu_action)
	add_child(_context_menu)

	# Handle mouse input for zoom and right-click
	map_container.gui_input.connect(_on_map_gui_input)

func _create_circular_mask() -> Texture2D:
	var size = int(_minimap_size.x)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size / 2.0, size / 2.0)
	var radius = size / 2.0 - 2
	var inner := Color(0.05, 0.05, 0.08, 1.0)
	for x in range(size):
		for y in range(size):
			var dist = Vector2(x, y).distance_to(center)
			if dist <= radius:
				# The face must be the panel's dark backdrop, never
				# white: a white mask disk shown through an empty
				# MapTexture was the "minimap white circle" bug.
				img.set_pixel(x, y, inner)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)

## Procedural zone backdrop for zones without a baked minimap
## texture: a subtle dark field with a faint border so the disk
## always reads as a map, never as a blank circle.
func _procedural_zone_texture() -> Texture2D:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for x in range(size):
		for y in range(size):
			var shade := 0.07 + 0.03 * sin(float(x) * 0.4) * sin(float(y) * 0.35)
			img.set_pixel(x, y, Color(0.09 + shade, 0.16 + shade, 0.13 + shade, 1.0))
	# Border grain
	for i in range(size):
		img.set_pixel(i, 0, Color(0.2, 0.35, 0.25, 1.0))
		img.set_pixel(i, size - 1, Color(0.2, 0.35, 0.25, 1.0))
		img.set_pixel(0, i, Color(0.2, 0.35, 0.25, 1.0))
		img.set_pixel(size - 1, i, Color(0.2, 0.35, 0.25, 1.0))
	return ImageTexture.create_from_image(img)

func _create_player_arrow() -> Control:
	var container = Control.new()
	container.custom_minimum_size = Vector2(16, 16)
	container.set_pivot_offset(Vector2(8, 8))

	var arrow := Polygon2D.new()
	arrow.name = "Arrow"
	var points = PackedVector2Array([Vector2(0, -8), Vector2(5, 4), Vector2(0, 2), Vector2(-5, 4)])
	arrow.polygon = points
	var arrow_color = UIStyles.COLORS.accent_gold
	arrow.color = arrow_color
	container.add_child(arrow)

	# Outline
	var outline := Polygon2D.new()
	outline.name = "Outline"
	var outline_points = PackedVector2Array([Vector2(0, -9), Vector2(6, 5), Vector2(0, 3), Vector2(-6, 5)])
	outline.polygon = outline_points
	outline.color = Color(0, 0, 0, 1)
	container.add_child(outline)
	outline.z_index = -1

	return container

func _build_layer_toggles() -> void:
	var layers = [
		{"key": "party", "label": "P", "tooltip": "Party Members", "color": UIStyles.COLORS.info, "default": true},
		{"key": "npcs", "label": "N", "tooltip": "NPCs", "color": UIStyles.COLORS.success, "default": true},
		{"key": "enemies", "label": "E", "tooltip": "Enemies", "color": UIStyles.COLORS.error, "default": true},
		{"key": "quests", "label": "Q", "tooltip": "Quest Objectives", "color": UIStyles.COLORS.warning, "default": true},
		{"key": "pois", "label": "*", "tooltip": "Points of Interest", "color": UIStyles.COLORS.accent_gold, "default": true},
		{"key": "vendors", "label": "$", "tooltip": "Vendors", "color": Color(0.8, 1.0, 0.4), "default": true},
		{"key": "waypoints", "label": "W", "tooltip": "Waypoints", "color": UIStyles.COLORS.accent_gold, "default": true},
		{"key": "gates", "label": "G", "tooltip": "Gates & Stones", "color": Color(0.65, 0.85, 1.0), "default": true},
		{"key": "ankhs", "label": "A", "tooltip": "Ankhs", "color": Color(0.85, 0.7, 1.0), "default": true},
		{"key": "towns", "label": "T", "tooltip": "Towns", "color": Color(0.95, 0.85, 0.5), "default": true},
	]

	for layer in layers:
		var btn := Button.new()
		btn.name = "Toggle_%s" % layer.key
		btn.text = layer.label
		btn.toggle_mode = true
		btn.button_pressed = layer.default
		btn.custom_minimum_size = Vector2(20, 20)
		btn.tooltip_text = layer.tooltip
		btn.focus_mode = Control.FOCUS_ALL
		btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style(3, false))

		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
		style.border_color = layer.color
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.corner_radius_top_left = 3
		style.corner_radius_top_right = 3
		style.corner_radius_bottom_left = 3
		style.corner_radius_bottom_right = 3
		btn.add_theme_stylebox_override("normal", style)

		var pressed_style = style.duplicate()
		pressed_style.bg_color = layer.color
		btn.add_theme_stylebox_override("pressed", pressed_style)

		btn.toggled.connect(_on_layer_toggled.bind(layer.key))
		_layer_toggle_container.add_child(btn)

func _on_layer_toggled(key: String, pressed: bool) -> void:
	match key:
		"party": _show_party = pressed
		"npcs": _show_npcs = pressed
		"enemies": _show_enemies = pressed
		"quests": _show_quests = pressed
		"pois": _show_pois = pressed
		"vendors": _show_vendors = pressed
		"waypoints": _show_waypoints = pressed
		"gates": _show_gates = pressed
		"ankhs": _show_ankhs = pressed
		"towns": _show_towns = pressed
	_update_visible_markers()

func _on_zoom_changed(value: float) -> void:
	_zoom_index = int(value)
	_zoom_index = clampi(_zoom_index, 0, ZOOM_LEVELS.size() - 1)
	_zoom_level = ZOOM_LEVELS[_zoom_index]
	_zoom_slider.value = _zoom_index
	_update_marker_positions()

func _on_map_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_index = clampi(_zoom_index + 1, 0, ZOOM_LEVELS.size() - 1)
			_zoom_level = ZOOM_LEVELS[_zoom_index]
			_zoom_slider.value = _zoom_index
			_update_marker_positions()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_index = clampi(_zoom_index - 1, 0, ZOOM_LEVELS.size() - 1)
			_zoom_level = ZOOM_LEVELS[_zoom_index]
			_zoom_slider.value = _zoom_index
			_update_marker_positions()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_show_context_menu(event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_left_click(event.position)

func _handle_left_click(local_pos: Vector2) -> void:
	var map_container: Control = get_node("Panel/MapContainer")
	if not map_container:
		return

	var center = _minimap_size / 2.0
	var map_scale = _disk_scale()

	# Inverse of the player-centered law: screen offset from the disk
	# center maps back to world offsets AROUND THE PLAYER, not around
	# the world origin.
	var rel_pos = (local_pos - center) / map_scale
	var world_pos = Vector3(_player_position.x + rel_pos.x, 0, _player_position.z + rel_pos.y)

	map_clicked.emit(world_pos)

func _show_context_menu(local_pos: Vector2) -> void:
	var map_container: Control = get_node("Panel/MapContainer")
	if not map_container:
		return

	var center = _minimap_size / 2.0
	var map_scale = _disk_scale()

	# Same inverse as _handle_left_click (player-centered law).
	var rel_pos = (local_pos - center) / map_scale
	var world_pos = Vector3(_player_position.x + rel_pos.x, 0, _player_position.z + rel_pos.y)

	_context_menu.global_position = get_viewport().get_mouse_position()
	_context_menu.popup()
	_context_menu.set_meta("world_pos", world_pos)

func _on_context_menu_action(item_id: int) -> void:
	var world_pos: Vector3 = _context_menu.get_meta("world_pos", Vector3.ZERO)
	match item_id:
		1: waypoint_set.emit(world_pos)
		2: ping_sent.emit(world_pos)
		3: _open_quest_tracker(world_pos)
		4: _open_world_map(world_pos)


## Map click law: a waypoint_set click creates + activates a waypoint
## through WaypointService, which lights the world beacon (the sky
## pillar) and refreshes the active-waypoint map marker.
func _on_waypoint_set(world_pos: Vector3) -> void:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return
	var ws: Node = (ml as SceneTree).root.get_node_or_null("WaypointService")
	if ws == null or PlayerManager == null:
		return
	var pid := str(PlayerManager.get_local_player_id()) if PlayerManager.has_method("get_local_player_id") else ""
	if pid == "":
		return
	var created: Dictionary = ws.call("create_waypoint", pid, "Marker", world_pos, "")
	if not bool(created.get("success", false)):
		_created_failed_toast(pid, str(created.get("message", "Waypoint failed")))
		return
	var wpid := str(created.get("waypoint", {}).get("id", ""))
	if wpid != "" and ws.has_method("activate_waypoint"):
		ws.call("activate_waypoint", pid, wpid)
	# Landmark sync law: the active waypoint's map marker refreshes
	# immediately (the next zone sync repacks the whole list).
	if not _static_landmarks.has("LANDMARK_active_waypoint"):
		_static_landmarks.append("LANDMARK_active_waypoint")
	add_marker("LANDMARK_active_waypoint", world_pos, MARKER_WAYPOINT, "Marker")


## The creation failure needs to surface even when the service's own
## notify misses (rate-limit returns a message, not a toast).
func _created_failed_toast(_pid: String, text: String) -> void:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return
	var notif: Node = (ml as SceneTree).root.get_node_or_null("NotificationService")
	if notif != null and notif.has_method("notify"):
		# Kind 0 = INFO (NotificationService.NotificationType.INFO, kept
		# numeric so a missing autoload cannot poison script boots).
		notif.notify(0, text, "Minimap", "waypoint_fail", {})

func _open_quest_tracker(position: Vector3) -> void:
	var _tree := Engine.get_main_loop() as SceneTree
	var quest_service := _tree.root.get_node_or_null(NodePath("QuestService")) if _tree and _tree.root else null
	if quest_service and quest_service.has_method("get_quests_near_position"):
		var quests = quest_service.get_quests_near_position(position, 50.0)
		if quests.size() > 0:
			quest_track_requested.emit(quests[0].get("id", ""))

func _open_world_map(position: Vector3) -> void:
	# WorldMap is a class_name singleton (static instance), not an autoload.
	if WorldMap.instance and WorldMap.instance.has_method("show_position"):
		WorldMap.instance.show_position(position)

func _connect_signals() -> void:
	# Map-click waypoint law: clicks own the waypoint set flow.
	if not waypoint_set.is_connected(_on_waypoint_set):
		waypoint_set.connect(_on_waypoint_set)
	var _tree := Engine.get_main_loop() as SceneTree
	var zone_manager := _tree.root.get_node_or_null(NodePath("ZoneManager")) if _tree and _tree.root else null
	if not zone_manager:
		return
	if zone_manager.has_signal("zone_loaded"):
		if not zone_manager.zone_loaded.is_connected(_on_zone_loaded):
			zone_manager.zone_loaded.connect(_on_zone_loaded)
	if zone_manager.has_signal("player_entered_zone"):
		if not zone_manager.player_entered_zone.is_connected(_on_player_entered_zone):
			zone_manager.player_entered_zone.connect(_on_player_entered_zone)

	# Time of day comes from WorldService (no TimeOfDay service exists).
	var world_service := _tree.root.get_node_or_null(NodePath("WorldService")) if _tree and _tree.root else null
	if world_service and world_service.has_signal("time_changed"):
		if not world_service.time_changed.is_connected(_on_time_changed):
			world_service.time_changed.connect(_on_time_changed)

	var entity_service := _tree.root.get_node_or_null(NodePath("EntityService")) if _tree and _tree.root else null
	if entity_service and entity_service.has_signal("entity_spawned"):
		entity_service.entity_spawned.connect(_on_entity_spawned)
	# The despawn-side signal is entity_unregistered(entity, metadata)
	# -- EntityService has no "entity_despawned" signal, so the old
	# guarded connect silently never fired and markers piled up.
	if entity_service and entity_service.has_signal("entity_unregistered"):
		if not entity_service.entity_unregistered.is_connected(_on_entity_despawned):
			entity_service.entity_unregistered.connect(_on_entity_despawned)

func _on_zone_loaded(zone_data) -> void:
	_apply_zone_backdrop(zone_data)

func _on_player_entered_zone(_player, zone) -> void:
	_apply_zone_backdrop(zone)

## Shared backdrop + landmark sync for both zone-entry routes.
func _sync_static_landmarks(zone_data) -> void:
	if not _marker_container:
		return
	for lid in _static_landmarks:
		remove_marker(lid)
	_static_landmarks.clear()
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return
	var tree := ml as SceneTree
	var root := tree.root
	# Window has no get_nodes_in_group -- the GROUPS live on the
	# SceneTree itself (the root-node call threw on every sync).
	var current_zone_id := ""
	if zone_data != null and "id" in zone_data:
		current_zone_id = str(zone_data.get("id"))
	var seen := {}

	# Towns: safe, non-instanced zones with a bind point read as
	# settlements. Name rides the marker label.
	if ZoneManager != null and ZoneManager.has_method("get_all_zones"):
		for zone in ZoneManager.get_all_zones():
			if zone == null:
				continue
			var zid := str(zone.get("id"))
			if zid == "":
				continue
			# Two-arg Resource.get() throws in 4.7 (single-arg only).
			var is_instanced_v: Variant = zone.get("is_instanced")
			var pvp_mode_v: Variant = zone.get("pvp_mode")
			if (is_instanced_v != null and bool(is_instanced_v)) \
					or (pvp_mode_v != null and int(pvp_mode_v) != 0):
				continue
			var bind: Vector3 = Vector3.ZERO
			if "bind_point" in zone:
				bind = zone.bind_point
			if bind == Vector3.ZERO:
				continue
			var tm_name: String = "Town"
			if "display_name" in zone:
				tm_name = str(zone.display_name)
			var tm_lm = _atlas_landmark_for_zone(zid)
			if tm_lm != null:
				tm_name = str(tm_lm.get("display_name"))
			var key := "LANDMARK_town_" + zid
			if seen.has(key):
				continue
			seen[key] = true
			add_marker(key, bind, MARKER_TOWN, tm_name)
			_static_landmarks.append(key)

	# Gates: data-placed gateways whose source zone matches the map's
	# zone. Unset source positions fall back to the zone bind point
	# (the .tres files ship Vector3(0,0,0) until placements are tuned).
	if DataService != null and DataService.has_method("get_all_gateways"):
		for g in DataService.get_all_gateways():
			if g == null:
				continue
			var src_zone := str(g.get("source_zone_id"))
			if current_zone_id != "" and src_zone != current_zone_id:
				continue
			var gname: String = "Gateway"
			if "display_name" in g:
				gname = str(g.display_name)
			var pos: Vector3 = Vector3.ZERO
			if "source_position" in g:
				pos = g.source_position
			if pos == Vector3.ZERO and ZoneManager != null and current_zone_id != "":
				var znode = ZoneManager.get_zone(current_zone_id)
				if znode != null and "bind_point" in znode:
					pos = znode.bind_point + Vector3(0, 0, 6)
			var gate_id: String = gname
			if "id" in g:
				var gid = g.id
				if gid != null and str(gid) != "":
					gate_id = str(gid)
			# The atlas names the place when one exists (identity wins).
			var gw_lm = _atlas_landmark_for_gateway(gate_id)
			if gw_lm != null:
				gname = str(gw_lm.get("display_name"))
			var gkey := "LANDMARK_gate_%s" % gate_id
			if seen.has(gkey):
				continue
			seen[gkey] = true
			add_marker(gkey, pos, MARKER_GATE, gname)
			_static_landmarks.append(gkey)

	# Ankhs: live respawn anchors in the running scene.
	for ankh in tree.get_nodes_in_group("ankhs"):
		if ankh == null or not is_instance_valid(ankh):
			continue
		var ak_id: String = str(ankh.ankh_id) if "ankh_id" in ankh else ankh.name
		var ak_name: String = str(ankh.display_name) if "display_name" in ankh else "Ankh"
		var akey := "LANDMARK_ankh_" + ak_id
		if seen.has(akey):
			continue
		seen[akey] = true
		add_marker(akey, ankh.global_position, MARKER_ANKH, ak_name)
		_static_landmarks.append(akey)

	# The active waypoint rides the waypoint layer, BotW-style.
	if WaypointService != null and PlayerManager != null:
		var pid := str(PlayerManager.get_local_player_id()) if PlayerManager.has_method("get_local_player_id") else ""
		var active: Dictionary = WaypointService.get_active_waypoint(pid) if pid != "" else {}
		if not active.is_empty():
			var wpos := Vector3(float(active.get("position_x", 0.0)), float(active.get("position_y", 0.0)), float(active.get("position_z", 0.0)))
			add_marker("LANDMARK_active_waypoint", wpos, MARKER_WAYPOINT, str(active.get("name", "Waypoint")))
			_static_landmarks.append("LANDMARK_active_waypoint")


## ATLAS LAW (labs/prd-world.md sec. 2.1): the minimap is a player-centred
## radar, so it does not plot sphere directions -- but the NAME on a zone
## or gateway marker comes from the atlas when one exists, so a place is
## never labelled two different ways by two systems.
func _atlas_landmark_for_zone(zid: String):
	if zid == "" or DataService == null or not DataService.has_method("get_all_landmarks"):
		return null
	for lm in DataService.get_all_landmarks():
		if lm != null and str(lm.get("zone_id")) == zid:
			return lm
	return null

func _atlas_landmark_for_gateway(gid: String):
	if gid == "" or DataService == null or not DataService.has_method("get_all_landmarks"):
		return null
	for lm in DataService.get_all_landmarks():
		if lm != null and str(lm.get("gateway_id")) == gid:
			return lm
	return null


func _apply_zone_backdrop(zone_data) -> void:
	if zone_data != null and "bounds" in zone_data:
		_map_size = _v3_to_v2((zone_data.bounds as AABB).size)
	var has_texture: bool = false
	if zone_data != null and "minimap_texture" in zone_data:
		has_texture = zone_data.minimap_texture != null
	if has_texture:
		_map_texture.texture = zone_data.minimap_texture
	else:
		# The white-circle fix's other half: an empty TextureRect let
		# the mask show through blank. Paint the procedural backdrop.
		if _map_texture.texture == null or not (_map_texture.texture is ImageTexture):
			_map_texture.texture = _procedural_zone_texture()
	_sync_static_landmarks(zone_data)

## AABB.size is a Vector3; the minimap works in XZ-plane Vector2 space.
func _v3_to_v2(v3: Vector3) -> Vector2:
	return Vector2(v3.x, v3.z)

## WorldService.time_changed emits (time_of_day: String, hour: int);
## the local set_time_of_day(hour, minute) path reuses this slot. Both
## args arrive as Variant here and are coerced, so one slot serves both
## callers without the String->int conversion error seen in full boot.
func _on_time_changed(time_of_day, hour) -> void:
	if _time_label:
		var h := int(hour)
		var am_pm := "AM" if h < 12 else "PM"
		var display_hour := h % 12
		if display_hour == 0:
			display_hour = 12
		_time_label.text = "%02d:00 %s" % [display_hour, am_pm]

func _on_entity_spawned(entity, metadata) -> void:
	if not is_instance_valid(entity):
		return
	var _spawn_tree := Engine.get_main_loop() as SceneTree
	var party_service := _spawn_tree.root.get_node_or_null(NodePath("PartyService")) if _spawn_tree and _spawn_tree.root else null

	var entity_type = entity.get("entity_type", 0)
	var marker_type = 0

	match entity_type:
		Entity.EntityType.PLAYER:
			if party_service and party_service.is_in_same_party(entity.entity_id):
				marker_type = MARKER_PARTY
			else:
				return
		Entity.EntityType.NPC:
			marker_type = _npc_marker_type(entity)
		Entity.EntityType.ENEMY:
			marker_type = MARKER_ENEMY
		_: return

	add_marker(entity.entity_id, entity.global_position, marker_type, entity.get("display_name", ""))

func _on_entity_despawned(entity, _metadata = null) -> void:
	# Payload is (entity Node, SpawnMetadata): pull the marker key off
	# the node, not a bare id string.
	if entity == null or not ("entity_id" in entity):
		return
	remove_marker(entity.entity_id)

func _process(_delta: float) -> void:
	_update_player_marker()
	_update_marker_positions()

func _update_player_marker() -> void:
	if not _player_marker:
		return

	var minimap_center := _minimap_size / 2.0
	var map_scale := _disk_scale()

	# PLAYER-CENTERED LAW (the spawn-stuck fix): the player rides the
	# disk center and the WORLD scrolls under them, so the disk always
	# mirrors "around the player" and never pins to spawn coords. The
	# old math was absolute-world (center + pos*scale), which at planet
	# scale clamped every read to the rim instantly and read as "the
	# minimap sticks to the spawn area".
	_player_marker.position = minimap_center - Vector2(8, 8)
	_player_marker.rotation = -_player_rotation

	# The backdrop scrolls with the same law: the texture is displaced
	# by -player_pos so the world visibly glides under the player.
	if _map_texture:
		_map_texture.position = minimap_center \
			- Vector2(_player_position.x, _player_position.z) * map_scale \
			- _minimap_size / 2.0

	# Update coordinates
	if _coords_label:
		_coords_label.text = "X: %d, Y: %d" % [_player_position.x, _player_position.z]

## The disk's world-to-pixel scale (player-centered view law).
func _disk_scale() -> float:
	return (_minimap_size.x / DISK_METERS) * _zoom_level

func _update_marker_positions() -> void:
	if not _marker_container:
		return

	var minimap_center := _minimap_size / 2.0
	var map_scale := _disk_scale()

	for entity_id in _entity_markers:
		var data: Dictionary = _entity_markers[entity_id]
		var marker: Control = data.get("marker")
		var position: Vector3 = data.get("position", Vector3.ZERO)

		if not marker or not is_instance_valid(marker):
			continue

		# PLAYER-RELATIVE offset: marker screen pos = (world pos -
		# player pos) * scale, mirrored around the disk center. The N
		# column stays north-up; the world (not the player) carries the
		# motion so the disk scrolls under the player as they walk.
		var rel := Vector2(position.x - _player_position.x, position.z - _player_position.z)
		var marker_pos := minimap_center + rel * map_scale

		var radius = _minimap_size.x / 2.0 - 6
		var dist = marker_pos.distance_to(minimap_center)
		if dist > radius:
			marker_pos = minimap_center + (marker_pos - minimap_center).normalized() * radius

		marker.position = marker_pos - marker.custom_minimum_size / 2.0

func set_player_position(position: Vector3) -> void:
	_player_position = position

func set_player_rotation(rotation: float) -> void:
	_player_rotation = rotation

func set_zone_name(name: String) -> void:
	if _zone_label:
		_zone_label.text = name

## Classify an NPC marker from its REAL vendor truth (NPCEntity.is_vendor,
## resolved from the offering model). An entity without the method is a plain
## NPC -- never assume a vendor.
func _npc_marker_type(entity) -> int:
	if entity != null and entity.has_method("is_vendor") and entity.is_vendor():
		return MARKER_VENDOR
	return MARKER_NPC


func add_marker(entity_id: String, position: Vector3, marker_type: int, label: String = "") -> void:
	if _entity_markers.has(entity_id):
		_entity_markers[entity_id].position = position
		_entity_markers[entity_id].type = marker_type
		_entity_markers[entity_id].label = label
		return

	var marker = _create_marker(marker_type, label)
	marker.name = "Marker_%s" % entity_id
	_marker_container.add_child(marker)

	_entity_markers[entity_id] = {
		"marker": marker,
		"position": position,
		"type": marker_type,
		"label": label
	}

	_update_visible_markers()

func _create_marker(marker_type: int, label: String) -> Control:
	var marker = Control.new()
	var size: Vector2
	var color: Color
	var shape: String = "circle"

	match marker_type:
		MARKER_PARTY:
			size = Vector2(10, 10)
			color = UIStyles.COLORS.info
		MARKER_NPC:
			size = Vector2(8, 8)
			color = UIStyles.COLORS.success
		MARKER_ENEMY:
			size = Vector2(8, 8)
			color = UIStyles.COLORS.error
			shape = "diamond"
		MARKER_QUEST:
			size = Vector2(12, 12)
			color = UIStyles.COLORS.warning
			shape = "exclamation"
		MARKER_POI:
			size = Vector2(10, 10)
			color = UIStyles.COLORS.accent_gold
			shape = "star"
		MARKER_VENDOR:
			size = Vector2(10, 10)
			color = Color(0.8, 1.0, 0.4)
			shape = "coin"
		MARKER_WAYPOINT:
			size = Vector2(12, 12)
			color = UIStyles.COLORS.accent_gold
			shape = "flag"
		MARKER_PING:
			size = Vector2(16, 16)
			color = Color(0.3, 1.0, 0.5)
			shape = "pulse"
		MARKER_LOOT:
			size = Vector2(8, 8)
			color = Color(1.0, 0.85, 0.3)
			shape = "loot"
		MARKER_GATE:
			size = Vector2(10, 10)
			color = Color(0.65, 0.85, 1.0)
			shape = "gate"
		MARKER_ANKH:
			size = Vector2(10, 10)
			color = Color(0.85, 0.7, 1.0)
			shape = "ankh"
		MARKER_TOWN:
			size = Vector2(12, 12)
			color = Color(0.95, 0.85, 0.5)
			shape = "town"
		_:
			size = Vector2(8, 8)
			color = UIStyles.COLORS.info

	marker.custom_minimum_size = size

	var visual = _create_marker_visual(shape, size, color, label)
	marker.add_child(visual)

	return marker

func _create_marker_visual(shape: String, size: Vector2, color: Color, label: String) -> Control:
	var container = Control.new()
	container.custom_minimum_size = size
	container.set_pivot_offset(size / 2.0)

	match shape:
		"circle":
			var circle := TextureRect.new()
			circle.custom_minimum_size = size
			circle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			circle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var img := Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)
			var center = Vector2(size.x / 2.0, size.y / 2.0)
			var radius = min(size.x, size.y) / 2.0
			for x in range(int(size.x)):
				for y in range(int(size.y)):
					if Vector2(x, y).distance_to(center) <= radius:
						img.set_pixel(x, y, color)
					else:
						img.set_pixel(x, y, Color(0, 0, 0, 0))
			circle.texture = ImageTexture.create_from_image(img)
			container.add_child(circle)

		"diamond":
			var diamond := Polygon2D.new()
			var s = min(size.x, size.y) / 2.0
			diamond.polygon = PackedVector2Array([Vector2(0, -s), Vector2(s, 0), Vector2(0, s), Vector2(-s, 0)])
			diamond.color = color
			container.add_child(diamond)

		"exclamation":
			var vbox := VBoxContainer.new()
			vbox.custom_minimum_size = size
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			var exclaim := Label.new()
			exclaim.text = "!"
			exclaim.add_theme_font_size_override("font_size", int(size.y * 0.8))
			exclaim.add_theme_color_override("font_color", color)
			exclaim.add_theme_constant_override("outline_size", 2)
			exclaim.add_theme_color_override("outline_color", Color(0, 0, 0, 1))
			exclaim.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(exclaim)
			container.add_child(vbox)

		"star":
			var star := Polygon2D.new()
			var s = min(size.x, size.y) / 2.0
			var points = PackedVector2Array()
			for i in range(10):
				var angle = deg_to_rad(i * 36 - 90)
				var r = s if i % 2 == 0 else s * 0.4
				points.append(Vector2(cos(angle) * r, sin(angle) * r))
			star.polygon = points
			star.color = color
			container.add_child(star)

		"coin":
			var circle := TextureRect.new()
			circle.custom_minimum_size = size
			circle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			circle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var img := Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)
			var center = Vector2(size.x / 2.0, size.y / 2.0)
			var radius = min(size.x, size.y) / 2.0
			for x in range(int(size.x)):
				for y in range(int(size.y)):
					if Vector2(x, y).distance_to(center) <= radius:
						img.set_pixel(x, y, color)
					else:
						img.set_pixel(x, y, Color(0, 0, 0, 0))
			circle.texture = ImageTexture.create_from_image(img)
			container.add_child(circle)

			var dollar := Label.new()
			dollar.text = "$"
			dollar.custom_minimum_size = size
			dollar.add_theme_font_size_override("font_size", int(size.y * 0.7))
			dollar.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
			dollar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			dollar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			container.add_child(dollar)

		"flag":
			var vbox := VBoxContainer.new()
			vbox.custom_minimum_size = size
			vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			var flag := Label.new()
			flag.text = "W"
			flag.add_theme_font_size_override("font_size", int(size.y * 0.9))
			flag.add_theme_color_override("font_color", color)
			flag.add_theme_constant_override("outline_size", 2)
			flag.add_theme_color_override("outline_color", Color(0, 0, 0, 1))
			flag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(flag)
			container.add_child(vbox)

		"pulse":
			var pulse := TextureRect.new()
			pulse.custom_minimum_size = size
			pulse.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pulse.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var img := Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)
			var center = Vector2(size.x / 2.0, size.y / 2.0)
			var radius = min(size.x, size.y) / 2.0
			for x in range(int(size.x)):
				for y in range(int(size.y)):
					var d = Vector2(x, y).distance_to(center)
					if d <= radius:
						var alpha = 1.0 - (d / radius)
						img.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
					else:
						img.set_pixel(x, y, Color(0, 0, 0, 0))
			pulse.texture = ImageTexture.create_from_image(img)
			container.add_child(pulse)

			# Respect reduce motion setting
			if not UIStyles.is_reduce_motion_enabled():
				var tween = container.create_tween()
				tween.set_loops()
				tween.tween_property(pulse, "modulate:a", 0.3, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				tween.tween_property(pulse, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

		"loot":
			var loot := Polygon2D.new()
			var s = min(size.x, size.y) / 2.0
			# 4-point star: a loot glint.
			var points = PackedVector2Array()
			for i in range(8):
				var angle = deg_to_rad(i * 45 - 90)
				var r = s if i % 2 == 0 else s * 0.35
				points.append(Vector2(cos(angle) * r, sin(angle) * r))
			loot.polygon = points
			loot.color = color
			container.add_child(loot)

		"gate":
			# An arch: two pillars + a lintel bar.
			var s_g: float = min(size.x, size.y) / 2.0
			var pillars := Polygon2D.new()
			pillars.color = color
			pillars.polygon = PackedVector2Array([
				Vector2(-s_g * 0.7, -s_g), Vector2(-s_g * 0.3, -s_g),
				Vector2(-s_g * 0.3, s_g), Vector2(-s_g * 0.7, s_g),
				Vector2(s_g * 0.3, -s_g), Vector2(s_g * 0.7, -s_g),
				Vector2(s_g * 0.7, s_g), Vector2(s_g * 0.3, s_g),
			])
			container.add_child(pillars)
			var lintel := Polygon2D.new()
			lintel.color = color
			lintel.polygon = PackedVector2Array([
				Vector2(-s_g * 0.8, -s_g), Vector2(s_g * 0.8, -s_g),
				Vector2(s_g * 0.8, -s_g * 0.5), Vector2(-s_g * 0.8, -s_g * 0.5),
			])
			container.add_child(lintel)

		"ankh":
			# A looped cross, the classic ankh sign.
			var a_s: float = min(size.x, size.y) / 2.0
			var stem := Polygon2D.new()
			stem.color = color
			stem.polygon = PackedVector2Array([
				Vector2(-a_s * 0.18, 0), Vector2(a_s * 0.18, 0),
				Vector2(a_s * 0.18, a_s), Vector2(-a_s * 0.18, a_s),
			])
			stem.position = Vector2(0, -a_s * 0.5)
			container.add_child(stem)
			var arms := Polygon2D.new()
			arms.color = color
			arms.polygon = PackedVector2Array([
				Vector2(-a_s * 0.6, 0), Vector2(a_s * 0.6, 0),
				Vector2(a_s * 0.6, a_s * 0.36), Vector2(-a_s * 0.6, a_s * 0.36),
			])
			arms.position = Vector2(0, -a_s * 0.9)
			container.add_child(arms)

		"town":
			# A little house: base + roof + door.
			var t_s: float = min(size.x, size.y) / 2.0
			var base := Polygon2D.new()
			base.color = color
			base.polygon = PackedVector2Array([
				Vector2(-t_s * 0.7, 0), Vector2(t_s * 0.7, 0),
				Vector2(t_s * 0.7, t_s), Vector2(-t_s * 0.7, t_s),
			])
			container.add_child(base)
			var roof := Polygon2D.new()
			roof.color = color
			roof.polygon = PackedVector2Array([
				Vector2(-t_s * 0.9, 0), Vector2(t_s * 0.9, 0), Vector2(0, -t_s * 0.9),
			])
			roof.position = Vector2(0, 0)
			container.add_child(roof)

		_:
			var circle := TextureRect.new()
			circle.custom_minimum_size = size
			circle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			circle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var img := Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)
			var center = Vector2(size.x / 2.0, size.y / 2.0)
			var radius = min(size.x, size.y) / 2.0
			for x in range(int(size.x)):
				for y in range(int(size.y)):
					if Vector2(x, y).distance_to(center) <= radius:
						img.set_pixel(x, y, color)
					else:
						img.set_pixel(x, y, Color(0, 0, 0, 0))
			circle.texture = ImageTexture.create_from_image(img)
			container.add_child(circle)

	if label != "":
		var lbl := Label.new()
		lbl.text = label
		lbl.custom_minimum_size = Vector2(100, 16)
		lbl.offset_top = size.y + 2
		lbl.add_theme_font_size_override("font_size", 8)
		lbl.add_theme_color_override("font_color", color)
		lbl.add_theme_constant_override("outline_size", 1)
		lbl.add_theme_color_override("outline_color", Color(0, 0, 0, 1))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		container.add_child(lbl)

	return container

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
	# Snap to nearest discrete zoom level
	var closest_index := 0
	var closest_diff: float = abs(ZOOM_LEVELS[0] - level)
	for i in range(1, ZOOM_LEVELS.size()):
		var diff: float = abs(ZOOM_LEVELS[i] - level)
		if diff < closest_diff:
			closest_diff = diff
			closest_index = i
	_zoom_index = closest_index
	_zoom_level = ZOOM_LEVELS[_zoom_index]
	if _zoom_slider:
		_zoom_slider.value = _zoom_index
	_update_marker_positions()

func get_zoom() -> float:
	return _zoom_level

func toggle_party() -> void:
	_show_party = not _show_party
	_update_layer_button("party", _show_party)
	_update_visible_markers()

func toggle_npcs() -> void:
	_show_npcs = not _show_npcs
	_update_layer_button("npcs", _show_npcs)
	_update_visible_markers()

func toggle_enemies() -> void:
	_show_enemies = not _show_enemies
	_update_layer_button("enemies", _show_enemies)
	_update_visible_markers()

func toggle_quests() -> void:
	_show_quests = not _show_quests
	_update_layer_button("quests", _show_quests)
	_update_visible_markers()

func toggle_pois() -> void:
	_show_pois = not _show_pois
	_update_layer_button("pois", _show_pois)
	_update_visible_markers()

func toggle_vendors() -> void:
	_show_vendors = not _show_vendors
	_update_layer_button("vendors", _show_vendors)
	_update_visible_markers()

func toggle_waypoints() -> void:
	_show_waypoints = not _show_waypoints
	_update_layer_button("waypoints", _show_waypoints)
	_update_visible_markers()

func _update_layer_button(key: String, pressed: bool) -> void:
	var btn: Button = _layer_toggle_container.get_node_or_null("Toggle_%s" % key)
	if btn:
		btn.button_pressed = pressed

func set_markers_visible(party: bool, npcs: bool, enemies: bool, quests: bool, pois: bool, vendors: bool, waypoints: bool) -> void:
	_show_party = party
	_show_npcs = npcs
	_show_enemies = enemies
	_show_quests = quests
	_show_pois = pois
	_show_vendors = vendors
	_show_waypoints = waypoints

	_update_layer_button("party", party)
	_update_layer_button("npcs", npcs)
	_update_layer_button("enemies", enemies)
	_update_layer_button("quests", quests)
	_update_layer_button("pois", pois)
	_update_layer_button("vendors", vendors)
	_update_layer_button("waypoints", waypoints)

	_update_visible_markers()

func get_visible_markers() -> Dictionary:
	return {
		"party": _show_party,
		"npcs": _show_npcs,
		"enemies": _show_enemies,
		"quests": _show_quests,
		"pois": _show_pois,
		"vendors": _show_vendors,
		"waypoints": _show_waypoints
	}

func _update_visible_markers() -> void:
	for entity_id in _entity_markers:
		var data: Dictionary = _entity_markers[entity_id]
		var marker_type: int = data.get("type", 0)
		var marker: Control = data.get("marker")

		if not marker or not is_instance_valid(marker):
			continue

		marker.visible = true

		match marker_type:
			MARKER_PARTY: marker.visible = _show_party
			MARKER_NPC: marker.visible = _show_npcs
			MARKER_ENEMY: marker.visible = _show_enemies
			MARKER_QUEST: marker.visible = _show_quests
			MARKER_POI: marker.visible = _show_pois
			MARKER_VENDOR: marker.visible = _show_vendors
			MARKER_WAYPOINT: marker.visible = _show_waypoints
			MARKER_GATE: marker.visible = _show_gates
			MARKER_ANKH: marker.visible = _show_ankhs
			MARKER_TOWN: marker.visible = _show_towns
			MARKER_PING: marker.visible = true

func add_ping(position: Vector3, duration: float = 5.0) -> void:
	var ping_id = "ping_%d" % Time.get_ticks_msec()
	add_marker(ping_id, position, MARKER_PING, "")

	var ping_marker = _entity_markers[ping_id].marker
	if ping_marker:
		var tween = ping_marker.create_tween()
		tween.tween_interval(duration)
		tween.tween_callback(func(): remove_marker(ping_id))

		# Pulse animation for ping (respect reduce motion)
		if not UIStyles.is_reduce_motion_enabled():
			var pulse_tween = ping_marker.create_tween()
			pulse_tween.set_loops()
			pulse_tween.tween_property(ping_marker, "modulate:a", 0.3, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			pulse_tween.tween_property(ping_marker, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func set_time_of_day(hour: int, minute: int) -> void:
	# Signature-compatible shim over the WorldService slot; minute is
	# display-rounded here (time_of_day granularity is the hour).
	_on_time_changed("", hour)
