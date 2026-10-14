## PartyFrames - Party member frames display
## Top-left vertical stack showing party members with health/mana/role/distance
extends Control
class_name PartyFrames
const UIStyles = preload("res://ui/components/ui_styles.gd")
const IconResolver = preload("res://core/utils/icon_resolver.gd")
const ActionMenu = preload("res://ui/components/action_menu.gd")
const Entity = preload("res://core/entities/entity.gd")


## Max party size
const MAX_PARTY_SIZE: int = 5

## Party member data structure
## {
##   "player_id": String,
##   "name": String,
##   "class": String,
##   "level": int,
##   "health": int,
##   "max_health": int,
##   "mana": int,
##   "max_mana": int,
##   "role": int,  # 0=TANK, 1=HEALER, 2=DPS
##   "distance": float,
##   "is_leader": bool,
##   "ready_check": bool
## }

## Components
var _member_containers: Array[Control] = []
var _member_data: Array[Dictionary] = []
var _update_timer: Timer

## Role constants
enum Role { TANK = 0, HEALER = 1, DPS = 2 }

func _ready() -> void:
	_setup_ui()
	_create_timer()
	_setup_accessibility()
	hide()

func _setup_accessibility() -> void:
	focus_mode = Control.FOCUS_ALL
func update_accessibility_settings(high_contrast: bool, text_scale: float, reduce_motion: bool) -> void:
	# Update member containers
	for container in _member_containers:
		if container and is_instance_valid(container):
			container.add_theme_stylebox_override("focus", UIStyles.create_focus_style())

			# Update health/mana bars
			for bar_name in ["HealthBar", "ManaBar"]:
				var bar: ProgressBar = container.get_node_or_null(bar_name)
				if bar and is_instance_valid(bar):
					bar.add_theme_stylebox_override("focus", UIStyles.create_focus_style())

			# Update labels
			for label_name in ["NameLabel", "LevelLabel", "RoleLabel", "DistanceLabel"]:
				var label: Label = container.get_node_or_null(label_name)
				if label and is_instance_valid(label):
					var scale = UIStyles.get_text_scale()
					var current_size := label.get_theme_font_size("font_size")
					if current_size > 0:
						label.add_theme_font_size_override("font_size", int(current_size * scale))

	# Update ready check button
	if has_node("PartyContainer/TitleRow/ReadyCheckBtn"):
		var ready_check_btn: Button = get_node("PartyContainer/TitleRow/ReadyCheckBtn")
		if ready_check_btn and is_instance_valid(ready_check_btn):
			ready_check_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
			var scale = UIStyles.get_text_scale()
			var current_size := ready_check_btn.get_theme_font_size("font_size")
			if current_size > 0:
				ready_check_btn.add_theme_font_size_override("font_size", int(current_size * scale))

func _setup_ui() -> void:
	name = "PartyFrames"
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 20
	offset_top = 60
	offset_right = 280
	offset_bottom = 400

	# Main container
	var vbox := VBoxContainer.new()
	vbox.name = "PartyContainer"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	# Title row
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	var title_label := Label.new()
	title_label.text = "PARTY"
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	title_row.add_child(title_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)

	# Ready check button (for leader)
	var ready_check_btn := Button.new()
	ready_check_btn.text = "Ready Check"
	ready_check_btn.custom_minimum_size = Vector2(100, 24)
	ready_check_btn.add_theme_font_size_override("font_size", 10)
	ready_check_btn.focus_mode = Control.FOCUS_ALL
	ready_check_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style(4, false))
	ready_check_btn.pressed.connect(_on_ready_check_pressed)
	title_row.add_child(ready_check_btn)

	# Member frames
	for i in range(MAX_PARTY_SIZE):
		var member_frame := _create_member_frame(i)
		_member_containers.append(member_frame)
		vbox.add_child(member_frame)
		member_frame.visible = false

func _create_member_frame(index: int) -> Control:
	var frame := PanelContainer.new()
	frame.name = "MemberFrame_%d" % index
	frame.custom_minimum_size = Vector2(240, 52)
	frame.focus_mode = Control.FOCUS_ALL
	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
	style.border_color = UIStyles.COLORS.border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	frame.add_theme_stylebox_override("panel", style)

	# Add focus style
	frame.add_theme_stylebox_override("focus", UIStyles.create_focus_style(4, false))

	var hbox := HBoxContainer.new()
	frame.add_child(hbox)

	# Class icon
	var class_icon := TextureRect.new()
	class_icon.name = "ClassIcon"
	class_icon.custom_minimum_size = Vector2(32, 32)
	class_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	class_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hbox.add_child(class_icon)

	# Role icon
	var role_icon := TextureRect.new()
	role_icon.name = "RoleIcon"
	role_icon.custom_minimum_size = Vector2(20, 20)
	role_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	role_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hbox.add_child(role_icon)

	# Info column (name, level, distance)
	var info_vbox := VBoxContainer.new()
	info_vbox.name = "InfoColumn"
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	info_vbox.add_child(name_row)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = "Player"
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	name_row.add_child(name_label)

	var level_label := Label.new()
	level_label.name = "LevelLabel"
	level_label.text = "Lv.1"
	level_label.add_theme_font_size_override("font_size", 10)
	level_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	name_row.add_child(level_label)

	var distance_label := Label.new()
	distance_label.name = "DistanceLabel"
	distance_label.text = ""
	distance_label.add_theme_font_size_override("font_size", 9)
	distance_label.add_theme_color_override("font_color", UIStyles.COLORS.info)
	name_row.add_child(distance_label)

	# Leader crown
	var leader_icon := Label.new()
	leader_icon.name = "LeaderIcon"
	leader_icon.text = ""
	leader_icon.add_theme_font_size_override("font_size", 12)
	leader_icon.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	name_row.add_child(leader_icon)

	# Ready check status
	var ready_icon := Label.new()
	ready_icon.name = "ReadyIcon"
	ready_icon.text = ""
	ready_icon.add_theme_font_size_override("font_size", 12)
	ready_icon.add_theme_color_override("font_color", UIStyles.COLORS.success)
	name_row.add_child(ready_icon)

	# Health bar
	var hp_bar := ProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.min_value = 0
	hp_bar.max_value = 100
	hp_bar.value = 100
	hp_bar.custom_minimum_size = Vector2(150, 10)
	hp_bar.show_percentage = false
	hp_bar.focus_mode = Control.FOCUS_ALL
	hp_bar.add_theme_stylebox_override("focus", UIStyles.create_focus_style(2, false))
	info_vbox.add_child(hp_bar)

	var hp_style := StyleBoxFlat.new()
	hp_style.bg_color = UIStyles.COLORS.background
	hp_style.border_color = UIStyles.COLORS.border
	hp_style.corner_radius_top_left = 2
	hp_style.corner_radius_top_right = 2
	hp_style.corner_radius_bottom_left = 2
	hp_style.corner_radius_bottom_right = 2
	hp_bar.add_theme_stylebox_override("background", hp_style)

	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = UIStyles.COLORS.success
	hp_fill.corner_radius_top_left = 2
	hp_fill.corner_radius_top_right = 2
	hp_fill.corner_radius_bottom_left = 2
	hp_fill.corner_radius_bottom_right = 2
	hp_bar.add_theme_stylebox_override("fill", hp_fill)

	# Mana bar
	var mp_bar := ProgressBar.new()
	mp_bar.name = "MPBar"
	mp_bar.min_value = 0
	mp_bar.max_value = 100
	mp_bar.value = 100
	mp_bar.custom_minimum_size = Vector2(150, 6)
	mp_bar.show_percentage = false
	mp_bar.focus_mode = Control.FOCUS_ALL
	mp_bar.add_theme_stylebox_override("focus", UIStyles.create_focus_style(2, false))
	info_vbox.add_child(mp_bar)

	# Mouse input
	frame.mouse_filter = Control.MOUSE_FILTER_PASS

	return frame

func _create_timer() -> void:
	_update_timer = Timer.new()
	_update_timer.wait_time = 0.5
	_update_timer.timeout.connect(_on_update_timer)
	_update_timer.autostart = true
	add_child(_update_timer)

func _on_update_timer() -> void:
	if not visible:
		return
	_update_all_frames()

func _update_all_frames() -> void:
	for i in range(_member_containers.size()):
		if i < _member_data.size():
			_update_member_frame(i, _member_data[i])
		else:
			_member_containers[i].visible = false

func _update_member_frame(index: int, data: Dictionary) -> void:
	var frame := _member_containers[index]
	if not frame:
		return

	frame.visible = true

	# Named widgets live under the HBox built in _create_member_frame();
	# get_node_or_null so a rebuilt/foreign frame never crashes the
	# update tick (missing pieces are just skipped).
	var class_icon := frame.get_node_or_null("HBoxContainer/ClassIcon") as TextureRect
	var role_icon := frame.get_node_or_null("HBoxContainer/RoleIcon") as TextureRect
	var info_vbox: VBoxContainer = frame.get_node_or_null("HBoxContainer/InfoColumn") as VBoxContainer
	if info_vbox == null:
		var hbox: Node = frame.get_node_or_null("HBoxContainer")
		if hbox != null:
			for child in hbox.get_children():
				if child is VBoxContainer:
					info_vbox = child
					break
	var name_label: Label = info_vbox.get_node_or_null("NameRow/NameLabel") as Label if info_vbox != null else null
	var level_label: Label = info_vbox.get_node_or_null("NameRow/LevelLabel") as Label if info_vbox != null else null
	var distance_label: Label = info_vbox.get_node_or_null("NameRow/DistanceLabel") as Label if info_vbox != null else null
	var leader_icon: Label = info_vbox.get_node_or_null("NameRow/LeaderIcon") as Label if info_vbox != null else null
	var ready_icon: Label = info_vbox.get_node_or_null("NameRow/ReadyIcon") as Label if info_vbox != null else null
	var hp_bar: ProgressBar = info_vbox.get_node_or_null("HPBar") as ProgressBar if info_vbox != null else null
	var mp_bar: ProgressBar = info_vbox.get_node_or_null("MPBar") as ProgressBar if info_vbox != null else null

	# Name and level
	if name_label:
		name_label.text = str(data.get("name", "Unknown"))
	if level_label:
		level_label.text = "Lv.%d" % data.get("level", 1)

	# Distance
	if distance_label:
		var distance: float = data.get("distance", 0.0)
		if distance > 0:
			distance_label.text = "%.1fm" % distance
			# Dim if out of range (>40m)
			if distance > 40.0:
				distance_label.add_theme_color_override("font_color", UIStyles.COLORS.warning)
				frame.modulate = Color(1, 1, 1, 0.5)
			else:
				distance_label.add_theme_color_override("font_color", UIStyles.COLORS.info)
				frame.modulate = Color(1, 1, 1, 1)
		else:
			distance_label.text = ""

	# Class icon
	if class_icon:
		var class_name_str: String = data.get("class", "").to_lower()
		if class_name_str != "":
			var icon_path := "res://ui/textures/classes/%s.png" % class_name_str
			var texture := IconResolver.get_icon_for_path(icon_path)
			class_icon.texture = texture
		else:
			class_icon.texture = null

	# Role icon
	if role_icon:
		var role: int = data.get("role", Role.DPS)
		role_icon.texture = _get_role_icon(role)

	# Leader crown
	if leader_icon:
		leader_icon.text = "[LEADER]" if data.get("is_leader", false) else ""

	# Ready check
	if ready_icon:
		ready_icon.text = "[READY]" if data.get("ready_check", false) else ""

	# Health bar
	if hp_bar:
		var current_hp: int = data.get("health", 100)
		var max_hp: int = data.get("max_health", 100)
		hp_bar.max_value = max_hp if max_hp > 0 else 1
		hp_bar.value = current_hp

		var hp_percent: float = 0.0
		if max_hp > 0:
			hp_percent = float(current_hp) / float(max_hp)

		# Low health flash (<30%)
		if hp_percent < 0.3 and hp_percent > 0:
			# Pulse animation
			if not hp_bar.has_meta("pulsing"):
				hp_bar.set_meta("pulsing", true)
				var tween := hp_bar.create_tween()
				tween.set_loops()
				tween.tween_property(hp_bar, "modulate:a", 0.3, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				tween.tween_property(hp_bar, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		else:
			hp_bar.modulate = Color(1, 1, 1, 1)
			hp_bar.remove_meta("pulsing")

		# HP bar color based on percentage
		var hp_fill_style: StyleBoxFlat = hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if hp_fill_style:
			if hp_percent > 0.5:
				hp_fill_style.bg_color = UIStyles.COLORS.success
			elif hp_percent > 0.25:
				hp_fill_style.bg_color = UIStyles.COLORS.warning
			else:
				hp_fill_style.bg_color = UIStyles.COLORS.error

	# Mana bar
	if mp_bar:
		var max_mp: int = data.get("max_mana", 100)
		mp_bar.max_value = max_mp if max_mp > 0 else 1
		mp_bar.value = data.get("mana", 100)

	# Store data for click handling
	frame.set_meta("player_id", data.get("player_id", ""))
	if not frame.gui_input.is_connected(_on_member_gui_input):
		frame.gui_input.connect(_on_member_gui_input.bind(frame))

func _get_role_icon(role: int) -> Texture2D:
	var icon_path := ""
	match role:
		Role.TANK:
			icon_path = "res://ui/textures/icons/role_tank.png"
		Role.HEALER:
			icon_path = "res://ui/textures/icons/role_healer.png"
		Role.DPS:
			icon_path = "res://ui/textures/icons/role_dps.png"
		_:
			icon_path = "res://ui/textures/icons/role_dps.png"

	var texture := IconResolver.get_icon_for_path(icon_path)
	if not texture:
		# Fallback: create simple colored square
		var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
		match role:
			Role.TANK:
				img.fill(Color(0.5, 0.8, 1.0, 1.0))  # Blue shield
			Role.HEALER:
				img.fill(Color(0.2, 1.0, 0.5, 1.0))  # Green cross
			Role.DPS:
				img.fill(Color(1.0, 0.4, 0.4, 1.0))  # Red sword
		texture = ImageTexture.create_from_image(img)
	return texture

func _on_member_gui_input(frame: Control, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Left click - target the party member
			var player_id: String = frame.get_meta("player_id", "")
			if player_id != "" and TargetingManager:
				TargetingManager.set_target(player_id, "player")
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Right click - show action menu
			var player_id: String = frame.get_meta("player_id", "")
			if player_id != "" and ActionMenu:
				var action_menu: ActionMenu = ActionMenu.new()
				add_child(action_menu)
				action_menu.show_menu(get_global_mouse_position(), player_id, Entity.EntityType.PLAYER)

func _on_ready_check_pressed() -> void:
	if PartyService:
		PartyService.start_ready_check()

func update_party(party_members: Array) -> void:
	# Untyped parameter: scene-tree callers (HUD integrator, PartyService
	# bridges, probes) pass plain arrays; re-type locally so older
	# Godot 4.x Array/Array[Dictionary] mixed callers all still bind.
	var typed_members: Array[Dictionary] = []
	for m in party_members:
		if m is Dictionary:
			typed_members.append(m)
	_member_data = typed_members
	_update_all_frames()

	if _member_data.size() > 0:
		show()
	else:
		hide()

func update_member(player_id: String, data: Dictionary) -> void:
	for i in range(_member_data.size()):
		if _member_data[i].get("player_id", "") == player_id:
			_member_data[i] = data
			_update_member_frame(i, data)
			return
	# Add new member if not found
	if _member_data.size() < MAX_PARTY_SIZE:
		_member_data.append(data)
		_update_all_frames()

func remove_member(player_id: String) -> void:
	for i in range(_member_data.size()):
		if _member_data[i].get("player_id", "") == player_id:
			_member_data.remove_at(i)
			_update_all_frames()
			return

func set_ready_status(player_id: String, ready: bool) -> void:
	for i in range(_member_data.size()):
		if _member_data[i].get("player_id", "") == player_id:
			_member_data[i].ready_check = ready
			_update_member_frame(i, _member_data[i])
			return

func get_member_count() -> int:
	return _member_data.size()
