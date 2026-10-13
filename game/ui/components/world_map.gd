


extends Control
class_name WorldMap
## Runtime autoload lookup (script-mode-safe; the bare identifier
## fails compile when autoloads are absent -- test_islands).
func _glog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null

const UIStyles = preload("res://ui/components/ui_styles.gd")
const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")

## Runtime autoload lookups (script-mode-safe; the bare identifiers
## fail compile when autoloads are absent -- test_islands).
func _targetingmanager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("TargetingManager")) if tree and tree.root else null

## WorldMap - Full-screen world map with quest waypoints
## Expanded from Minimap, supports click-to-navigate


## Singleton
static var instance: WorldMap

## Components
var _map_view: Control
var _map_texture: TextureRect
## The player-centered ORTHOGRAPHIC GLOBE view (play-day pass 3): the
## equirect canvas folds onto a sphere disk — the "map looks odd"
## report was the flat equirect stretching near the poles. The globe
## draws into its own Image (row-chunked like the flat canvas so the
## fold never blocks a frame), reprojected from the FINISHED equirect
## pixels, NOT re-running terrain_height (cheap: one Image.get_pixel
## per pixel). The mode toggles Globe/Flat; the player marker rides
## the same lat/lon math in both modes.
var _globe_texture: ImageTexture = null
var _globe_image: Image = null
var _globe_generating: bool = false
var _globe_mode: bool = false
var _globe_toggle_btn: Button = null

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
## Round-13: the world canvas is generated ONCE from the terrain law
## (the streaming globe mounts no ZoneData map texture) and the map
## registers with MenuManager's interaction stack so the Back button
## and the touch-HUD yield that every panel gets apply here too.
var _canvas_texture: ImageTexture = null
## The equirect SOURCE image (not the texture): headless build verifies
## with it (ImageTexture.get_image() has no rasterizer to read back
## under --headless) and the globe fold samples pixel data from it.
var _canvas_image: Image = null
var _registered := false
var _yield_accum := 0.0
var _player_lat := 999.0
var _player_lon := 0.0

## Quest waypoints
var _waypoints: Array = []

## Markers cache
var _entity_markers: Dictionary = {}

## Sizes
var _minimap_size: Vector2 = Vector2(150, 150)
var _world_size: Vector2 = Vector2(8192, 8192)  # 8km x 8km world

## CHUNKED CANVAS GENERATION (the menu-freeze fix): _ensure_world_canvas
## used to sample terrain_height 384 x 384 = 147,456 times in ONE
## synchronous loop; under the penrose ground backend each sample is
## far costlier (chart frame + tile lookup), so opening the map pegged
## the main thread for tens of seconds — the "opened the menu, hit
## scroll to map, nothing opens, phone hammered" report. The canvas
## now paints in ROW CHUNKS spread across frames (await), resolution
## is 192x192 (a 4x sample cut; bilinear-stretch reads fine at map
## scale), and the SOP (start of paint) shows the fallback chart so
## the map opens INSTANTLY and fills in live.
signal _canvas_row_range(first_row: int, last_row: int)
var _generating: bool = false
var _generator: RefCounted = null
class _RowBank:
	var img: Image
	var seed_bytes: PackedByteArray
	var sea: float
	var R: float
var _bank: _RowBank = null

signal waypoint_clicked(position: Vector3)
signal map_clicked(position: Vector3)

func _ready() -> void:
	instance = self
	_setup_ui()
	_set_minimap_mode()
	_bind_zone_signals()
	hide()


func _bind_zone_signals() -> void:
	var _tree := Engine.get_main_loop() as SceneTree
	var zone_manager := _tree.root.get_node_or_null(NodePath("ZoneManager")) if _tree and _tree.root else null
	if zone_manager:
		if zone_manager.has_signal("zone_loaded"):
			if not zone_manager.zone_loaded.is_connected(_on_zone_loaded):
				zone_manager.zone_loaded.connect(_on_zone_loaded)


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

	# Backdrop: the globe streams per-face terrain and mounts no
	# ZoneData, so MapTexture has no texture -- without a backdrop the
	# full map drew as raw black. A dark slate canvas reads as a map
	# under the markers.
	var backdrop := ColorRect.new()
	backdrop.name = "MapBackdrop"
	backdrop.color = Color(0.04, 0.07, 0.10)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(backdrop)

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

	# Close button (for full map). Top-right sat under the web shell's
	# EDIT chip on phone layouts (round-13 screenshot: the X was there,
	# just invisible) -- drop below it so it is always tappable.
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "X"
	close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_btn.offset_left = -56
	close_btn.offset_top = 64
	close_btn.offset_right = -10
	close_btn.offset_bottom = 106
	close_btn.pressed.connect(_on_close_pressed)
	controls.add_child(close_btn)
	# The Globe/Flat toggle (pass 3): sits next to the title.
	_globe_toggle_btn = Button.new()
	_globe_toggle_btn.name = "GlobeToggle"
	_globe_toggle_btn.text = "Globe View"
	_globe_toggle_btn.position = Vector2(160, 12)
	_globe_toggle_btn.pressed.connect(_toggle_globe_mode)
	controls.add_child(_globe_toggle_btn)
	# Title + hint so the surface never reads as an empty black sheet.
	var title_lbl := Label.new()
	title_lbl.name = "MapTitle"
	title_lbl.text = "World Map"
	title_lbl.position = Vector2(16, 12)
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	title_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title_lbl.add_theme_constant_override("outline_size", 4)
	controls.add_child(title_lbl)
	var hint_lbl := Label.new()
	hint_lbl.name = "MapHint"
	hint_lbl.text = "M / Back / X closes the map"
	hint_lbl.position = Vector2(16, 40)
	hint_lbl.add_theme_font_size_override("font_size", 13)
	hint_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	hint_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint_lbl.add_theme_constant_override("outline_size", 3)
	controls.add_child(hint_lbl)

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
	# Anchors govern the size in full mode. The old 1920x1080
	# custom_minimum_size FORCED the control larger than small windows
	# (the map overflowed instead of fitting).
	custom_minimum_size = Vector2.ZERO

	# Show/hide controls
	var controls: Control = get_node_or_null("Container/Controls")
	if controls:
		controls.visible = true

		## ============================================================================
		## PUBLIC API
		## ============================================================================

static func singleton() -> WorldMap:
	return instance

func toggle() -> void:
	# OPEN = FULL MAP. The R6 note wired the minimap button to this
	# toggle, but toggle only flipped visibility: _ready had already
	# pinned the control to 150x150 corner geometry, so "the map" opened
	# as a tiny empty box in the corner (round-12 screenshot). Opening
	# now re-pins to full-rect first; closing restores the corner
	# geometry and hides.
	if visible:
		minimize_to_minimap()
	else:
		expand_to_fullscreen()

func show_map() -> void:
	expand_to_fullscreen()

func hide_map() -> void:
	hide()

func expand_to_fullscreen() -> void:
	_set_fullmap_mode()
	_ensure_world_canvas()
	# Re-open in the mode the player left: a persisted _globe_mode must
	# re-fold (or drop back to flat) here, not stay on whichever texture
	# the last close left behind.
	if _canvas_texture != null:
		if _globe_mode:
			_ensure_globe_texture()
		else:
			_map_texture.texture = _canvas_texture
	if _globe_texture != null:
		_position_player_marker()
	_register_with_menu_manager(true)
	_set_touch_hud_yield(true)
	show()

func minimize_to_minimap() -> void:
	_set_minimap_mode()
	_register_with_menu_manager(false)
	_set_touch_hud_yield(false)
	hide()

## The back gesture and the MenuManager funnel call close_modal() on
## interaction-stack entries. Without this the back gesture would
## queue_free the map (the stack's fallback).
func close_modal() -> void:
	minimize_to_minimap()

## Full-map re-assert: a panel opened AND closed while the map stayed
## open re-arms the touch HUD (MenuManager's "last panel closed" path
## knows nothing about us) -- re-claim the yield twice a second while
## the full map is up.
func _process(delta: float) -> void:
	if visible and not _minimap_mode:
		_yield_accum += delta
		if _yield_accum >= 0.5:
			_yield_accum = 0.0
			_set_touch_hud_yield(true)

func _register_with_menu_manager(active: bool) -> void:
	if active == _registered:
		return
	var script = load("res://ui/components/menu_manager.gd")
	if script == null:
		return
	var mm = script.instance
	if mm == null or not is_instance_valid(mm):
		return
	if active and mm.has_method("push_interaction"):
		mm.push_interaction(self)
		_registered = true
	elif not active and mm.has_method("pop_interaction"):
		mm.pop_interaction(self)
		_registered = false

func _set_touch_hud_yield(yield_now: bool) -> void:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return
	var im = (ml as SceneTree).root.get_node_or_null("InputManager")
	if im != null and im.has_method("set_touch_hud_panels_open"):
		im.set_touch_hud_panels_open(yield_now)

func is_minimap() -> bool:
	return _minimap_mode

func set_zone_name(name: String) -> void:
	var zone_label: Label = get_node_or_null("Container/ZoneName")
	if zone_label:
		zone_label.text = name

func set_player_position(world_pos: Vector3) -> void:
	if _minimap_mode:
		_update_minimap_position(world_pos)

## The globe truth line already computes the player's lat/lon at 2 Hz;
## it feeds the full map here so the gold dot rides the generated
## world canvas (equirectangular, texture aspect 1:1 letterboxed into
## the viewport).
func set_player_lat_lon(lat: float, lon: float) -> void:
	_player_lat = lat
	_player_lon = lon
	if not _minimap_mode:
		_position_player_marker()

## The ONE lat/lon -> UV convention shared by the generated world canvas
## and the player marker. Round 15: the canvas painted row 0 as the
## SOUTH pole (lat = -90 + ...) while the marker read py = (90 - lat),
## so the map rendered upside down AND the dot disagreed with it.
## u grows EAST from lon -180; v grows SOUTH from lat +90 (image row 0
## is the top row, so row 0 is the north pole).
static func lat_lon_to_uv(lat: float, lon: float) -> Vector2:
	return Vector2((lon + 180.0) / 360.0, (90.0 - lat) / 180.0)


func _position_player_marker() -> void:
	if _player_marker == null or _marker_container == null:
		return
	if _player_lat > 90.0:
		return
	if _globe_mode and _globe_texture != null:
		# GLOBE: the view IS player-centered orthographic, so the gold
		# dot is the disk CENTER of the drawn (circular) area. Source
		# is square (GLOBE_SIZE), so the drawn rect is size.y centered
		# horizontally, same letterbox law as the flat map.
		var gp_size := size
		var gdrawn := gp_size.y
		var gx0 := maxf(0.0, (gp_size.x - gdrawn) * 0.5)
		_player_marker.position = Vector2(
			gx0 + gdrawn * 0.5 - _player_marker.size.x * 0.5,
			gp_size.y * 0.5 - _player_marker.size.y * 0.5)
		return
	var uv: Vector2 = lat_lon_to_uv(_player_lat, _player_lon)
	var px: float = uv.x
	var py: float = uv.y
	# KEEP_ASPECT_CENTERED with a square canvas: drawn height = control
	# height, drawn width = height (letterbox bars left/right on wide
	# windows). Markers must sit inside the DRAWN rect, not the control.
	var vp_size := size
	var drawn := vp_size.y
	var x0 := maxf(0.0, (vp_size.x - drawn) * 0.5)
	_player_marker.position = Vector2(
		x0 + px * drawn - _player_marker.size.x * 0.5,
		py * vp_size.y - _player_marker.size.y * 0.5)

## Generate the world canvas from the terrain law (once per session).
## Equirectangular lat/lon scan, height-band colors matching the tile
## palette; water shades by depth. 384x384 = ~147k pure-function calls,
## a one-time sub-second cost on first open.
func _ensure_world_canvas() -> void:
	if _canvas_texture != null or _generating:
		return
	var Sph = load("res://core/frame/math/spherical.gd")
	var seed_bytes: PackedByteArray = TerrainGen.world_seed_bytes()
	var sea: float = 0.0
	var ok: bool = Sph != null and seed_bytes.size() > 0
	if ok:
		sea = TerrainGen.sea_level(seed_bytes)
		_bank = _RowBank.new()
		_bank.img = Image.create(192, 192, false, Image.FORMAT_RGBA8)
		_bank.seed_bytes = seed_bytes
		_bank.sea = sea
		_bank.R = 20000.0
		_generating = true
		# Show the fallback chart IMMEDIATELY (the map opens live); rows
		# fill in as chunks complete.
		var fb := Image.create(192, 192, false, Image.FORMAT_RGBA8)
		fb.fill(Color(0.07, 0.20, 0.30))
		_canvas_image = fb
		_map_texture.texture = ImageTexture.create_from_image(fb)
		_position_player_marker()
		_run_canvas_generation(Sph)
	if _canvas_texture == null and not _generating:
		# Broken dependency (no sphere law / no seed): the fallback chart
		# stands (same law as before, minus the synchronous freeze).
		var glw := _glog()
		if glw: glw.warn("WorldMap: terrain canvas generation failed; showing fallback ocean chart")
		var fb2 := Image.create(192, 192, false, Image.FORMAT_RGBA8)
		fb2.fill(Color(0.07, 0.20, 0.30))
		_canvas_image = fb2
		_map_texture.texture = ImageTexture.create_from_image(fb2)
		_position_player_marker()
		return

## The CHUNKED generator: sampe ROWS_PER_CHUNK rows per await frame.
## Each chunk is bounded (192/4 = 48 rows * 192 px = ~9k terrain picks
## per frame -- fast even under the penrose backend), then control
## returns to the main loop so input and rendering never starve.
## Amendments: painted-coverage law and texture commit live here now.
const CANVAS_SIZE: int = 192
const ROWS_PER_CHUNK: int = 4
const PAINTED_MIN: int = (CANVAS_SIZE * CANVAS_SIZE) / 2
func _run_canvas_generation(Sph) -> void:
	var img: Image = _bank.img
	var painted := 0
	var py := 0
	while py < CANVAS_SIZE:
		var last_row: int = mini(py + ROWS_PER_CHUNK, CANVAS_SIZE)
		for row in range(py, last_row):
			# Inverse of lat_lon_to_uv: row 0 is the north pole (Image
			# row 0 is the top row; the old -90 start painted the map
			# upside down).
			var lat := 90.0 - 180.0 * (float(row) + 0.5) / float(CANVAS_SIZE)
			for px in range(CANVAS_SIZE):
				var lon := -180.0 + 360.0 * (float(px) + 0.5) / float(CANVAS_SIZE)
				var d: Vector3 = Sph.spherical_to_cartesian(lat, lon, 1.0, _bank.R).normalized()
				var h: float = TerrainGen.terrain_height(d, _bank.seed_bytes)
				var c: Color = _canvas_color(h, _bank.sea)
				img.set_pixel(px, row, c)
				if c.a > 0.5:
					painted += 1
		py = last_row
		# Commit partial texture every chunk so the map fills in live.
		_canvas_texture = ImageTexture.create_from_image(img)
		_map_texture.texture = _canvas_texture
		_position_player_marker()
		await get_tree().process_frame
	# The full painted image is the globe's source from here on (the
	# initial reference was the fallback ocean chart).
	_canvas_image = img
	# The law always returns opaque colors; a mostly-transparent image
	# means the dependency errored per pixel. Do NOT cache that.
	if painted < PAINTED_MIN:
		_canvas_texture = null
		_canvas_image = null
		var glw := _glog()
		if glw: glw.warn("WorldMap: canvas coverage law failed (%d < %d); fallback stands" % [painted, PAINTED_MIN])
	_generating = false
	# A globe fold requested while the equirect was still painting read
	# only the PARTIAL canvas; re-fold now from the finished image.
	if _globe_mode and _canvas_texture != null:
		_ensure_globe_texture()

## Globe/Flat toggle.
func _toggle_globe_mode() -> void:
	_globe_mode = not _globe_mode
	_globe_toggle_btn.text = "Flat View" if _globe_mode else "Globe View"
	if _globe_mode:
		_ensure_globe_texture()
	else:
		_map_texture.texture = _canvas_texture
		_position_player_marker()

## ORTHOGRAPHIC FOLD: draw the equirect canvas as a player-centered
## sphere disk. For each disk pixel: invert to the visible sphere
## point (x,y,z), derive (lat, lon), sample the EQUIRECT image at that
## (lat, lon), paint. Cheap per pixel (no terrain calls); row-chunked
## exactly like the canvas generator so no frame blocks.
const GLOBE_SIZE: int = 192
const GLOBE_ROWS_PER_CHUNK: int = 8
func _ensure_globe_texture() -> void:
	var src: Image = _canvas_image
	if src == null and _canvas_texture != null:
		src = _canvas_texture.get_image()
	if src == null or _globe_generating:
		return
	if _globe_image == null:
		_globe_image = Image.create(GLOBE_SIZE, GLOBE_SIZE, false, Image.FORMAT_RGBA8)
	_globe_generating = true
	var center_lat: float = _player_lat if _player_lat <= 90.0 else 0.0
	var center_lon: float = _player_lon if _player_lat <= 90.0 else 0.0
	# Center reference frame (yaw around y, roll around east axis):
	var cr: float = cos(deg_to_rad(90.0 - center_lat))
	var sr: float = sin(deg_to_rad(90.0 - center_lat))
	var cy: float = cos(deg_to_rad(center_lon))
	var sy: float = sin(deg_to_rad(center_lon))
	# Center basis: n = sphere point for (lat0, lon0); e/n basis for
	# lon/lat corrections in the disk plane.
	var n := Vector3(sr * cy, cr, sr * sy)
	var e := Vector3(-sy, 0.0, cy)
	var up := n.cross(e).normalized()
	_run_globe_generation(src, n, e, up)

func _run_globe_generation(src: Image, n: Vector3, e: Vector3, up: Vector3) -> void:
	var half: float = GLOBE_SIZE * 0.5
	var sw: float = float(src.get_width())
	var sh: float = float(src.get_height())
	var painted := 0
	var py := 0
	while py < GLOBE_SIZE:
		var last_row: int = mini(py + GLOBE_ROWS_PER_CHUNK, GLOBE_SIZE)
		for row in range(py, last_row):
			var dy: float = (float(GLOBE_SIZE - 1 - row) - half + 0.5) / half  # +1 top
			for px in range(GLOBE_SIZE):
				var dx: float = (float(px) - half + 0.5) / half
				var r2: float = dx * dx + dy * dy
				if r2 > 1.0:
					_globe_image.set_pixel(px, row, Color(0, 0, 0, 0))
					continue
				var dz: float = sqrt(1.0 - r2)  # front hemisphere
				# Disk plane -> sphere direction, then to lat/lon.
				var d: Vector3 = (n + dx * e + dy * up).normalized()
				var lat: float = rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
				var lon: float = rad_to_deg(atan2(d.z, d.x))
				# Equirect sample: u = (lon+180)/360, v = (90-lat)/180.
				var u: int = clampi(int((lon + 180.0) / 360.0 * sw), 0, int(sw) - 1)
				var v: int = clampi(int((90.0 - lat) / 180.0 * sh), 0, int(sh) - 1)
				var c: Color = src.get_pixel(u, v)
				# Limb darkening reads as a sphere (cheap shading).
				var shade: float = 0.55 + 0.45 * dz
				c = Color(c.r * shade, c.g * shade, c.b * shade, 1.0)
				_globe_image.set_pixel(px, row, c)
				painted += 1
		py = last_row
		# The view flipped back to flat mid-fold: stop painting (the next
		# chunk would otherwise overwrite the restored equirect texture).
		if not _globe_mode:
			break
		_globe_texture = ImageTexture.create_from_image(_globe_image)
		_map_texture.texture = _globe_texture
		_position_player_marker()
		await get_tree().process_frame
	_globe_generating = false

## Height-band canvas colors (the tile palette, map-styled).
func _canvas_color(h: float, sea: float) -> Color:
	if h < sea - 4.0:
		return Color(0.07, 0.20, 0.30)  # deep water
	if h < sea:
		return Color(0.13, 0.33, 0.44)  # shallow water
	if h < sea + 1.5:
		return Color(0.76, 0.70, 0.50)  # shore sand
	if h < 15.0:
		return Color(0.30, 0.46, 0.26)  # lowland
	if h < 28.0:
		return Color(0.24, 0.36, 0.21)  # highland
	if h < 38.0:
		return Color(0.45, 0.43, 0.40)  # mountain
	return Color(0.88, 0.90, 0.92)  # snow cap

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

# Marker visibility toggles
var _show_players: bool = true
var _show_npcs: bool = true
var _show_quests: bool = true
var _show_enemies: bool = true
var _show_waypoints: bool = true

func toggle_players() -> void:
	_show_players = not _show_players
	_update_markers_visibility()

func toggle_npcs() -> void:
	_show_npcs = not _show_npcs
	_update_markers_visibility()

func toggle_quests() -> void:
	_show_quests = not _show_quests
	_update_markers_visibility()

func toggle_enemies() -> void:
	_show_enemies = not _show_enemies
	_update_markers_visibility()

func toggle_waypoints() -> void:
	_show_waypoints = not _show_waypoints
	_update_markers_visibility()

func set_markers_visible(players: bool, npcs: bool, quests: bool, enemies: bool = true, waypoints: bool = true) -> void:
	_show_players = players
	_show_npcs = npcs
	_show_quests = quests
	_show_enemies = enemies
	_show_waypoints = waypoints
	_update_markers_visibility()

func get_visible_markers() -> Dictionary:
	return {
		"players": _show_players,
		"npcs": _show_npcs,
		"quests": _show_quests,
		"enemies": _show_enemies,
		"waypoints": _show_waypoints
	}

func _update_markers_visibility() -> void:
	for entity_id in _entity_markers:
		var data: Dictionary = _entity_markers[entity_id]
		var marker_type: int = data.get("type", 0)
		var marker: Control = data.get("marker")

		marker.visible = true
		match marker_type:
			1: marker.visible = _show_players
			2: marker.visible = _show_npcs
			3: marker.visible = _show_quests
			4: marker.visible = _show_enemies
			# Waypoint types
			10, 11, 12, 13, 14, 15, 16, 17:
				marker.visible = _show_waypoints

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
	# Convert screen position to world position. The denominator is the
	# control's REAL size -- custom_minimum_size is ZERO in full-map
	# mode (anchors govern there), and dividing by it was INF/garbage.
	var denom := size
	if denom.x <= 1.0 or denom.y <= 1.0:
		denom = custom_minimum_size
	if denom.x <= 1.0 or denom.y <= 1.0:
		return Vector3.ZERO
	var world_x := (screen_pos.x / denom.x) * _world_size.x
	var world_z := (screen_pos.y / denom.y) * _world_size.y
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
