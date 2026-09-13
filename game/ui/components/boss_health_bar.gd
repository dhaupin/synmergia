## BossHealthBar - Raid boss health display
## Large HP bar with boss name, phase, enrage timer, mechanics warnings
extends Control
class_name BossHealthBar
const UIStyles = preload("res://ui/components/ui_styles.gd")
const IconResolver = preload("res://core/utils/icon_resolver.gd")


## Components
var _name_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _phase_label: Label
var _timer_label: Label
var _enrage_timer: Timer
var _mechanics_container: VBoxContainer
var _mechanics_warning: Label
var _phase_indicators: HBoxContainer
var _mechanics_icons: HBoxContainer

## State
var _boss_id: String = ""
var _current_hp: int = 0
var _max_hp: int = 100
var _phase: int = 1
var _max_phases: int = 3
var _enrage_time: float = 0
var _enrage_remaining: float = 0
var _mechanics_active: Array = []
var _phase_thresholds: Array = []
var _phase_hp_thresholds: Array = []

func _ready() -> void:
	_setup_ui()
	_setup_accessibility()
	_create_timer()
	hide()

func _setup_accessibility() -> void:
	focus_mode = Control.FOCUS_ALL
	accessible_name = "Boss Health Bar"
	accessible_description = "Displays the current raid boss health, phase, enrage timer, and mechanics warnings."

func update_accessibility_settings() -> void:
	# Update HP bar
	if _hp_bar and is_instance_valid(_hp_bar):
		_hp_bar.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	
	# Update labels
	for label in [_name_label, _hp_label, _phase_label, _timer_label, _mechanics_warning]:
		if label and is_instance_valid(label):
			var scale = UIStyles.get_text_scale()
			var current_size := label.get_theme_font_size("font_size")
			if current_size > 0:
				label.add_theme_font_size_override("font_size", int(current_size * scale))
	
	# Update mechanics container children
	if _mechanics_container:
		for child in _mechanics_container.get_children():
			if child is Label:
				var scale = UIStyles.get_text_scale()
				var current_size := child.get_theme_font_size("font_size")
				if current_size > 0:
					child.add_theme_font_size_override("font_size", int(current_size * scale))
	
	# Update phase indicators
	if _phase_indicators:
		for child in _phase_indicators.get_children():
			if child is PanelContainer:
				child.add_theme_stylebox_override("focus", UIStyles.create_focus_style())

func _setup_ui() -> void:
	name = "BossHealthBar"
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -350
	offset_top = 40
	offset_right = 350
	offset_bottom = 240
	add_theme_stylebox_override("focus", UIStyles.create_focus_style())

	# Container
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	# Boss name with special styling
	_name_label = Label.new()
	_name_label.text = "Boss Name"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", UIStyles.COLORS.error)
	_name_label.add_theme_constant_override("outline_size", 2)
	vbox.add_child(_name_label)

	# Phase indicator row
	var phase_row := HBoxContainer.new()
	phase_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(phase_row)

	var phase_icon := Label.new()
	phase_icon.text = "[Boss]"
	phase_icon.add_theme_color_override("font_color", UIStyles.COLORS.warning)
	phase_row.add_child(phase_icon)

	_phase_label = Label.new()
	_phase_label.text = " Phase 1"
	_phase_label.add_theme_font_size_override("font_size", 16)
	_phase_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	phase_row.add_child(_phase_label)

	# Phase progress indicators
	_phase_indicators = HBoxContainer.new()
	_phase_indicators.alignment = BoxContainer.ALIGNMENT_CENTER
	phase_row.add_child(_phase_indicators)

	# Health bar
	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HPBar"
	_hp_bar.min_value = 0
	_hp_bar.max_value = 100
	_hp_bar.value = 100
	_hp_bar.custom_minimum_size.y = 36
	_hp_bar.show_percentage = false
	vbox.add_child(_hp_bar)

	# Style HP bar for boss
	var hp_style := StyleBoxFlat.new()
	hp_style.bg_color = UIStyles.COLORS.background_dark
	hp_style.border_color = UIStyles.COLORS.border
	hp_style.corner_radius_top_left = 6
	hp_style.corner_radius_top_right = 6
	hp_style.corner_radius_bottom_left = 6
	hp_style.corner_radius_bottom_right = 6
	_hp_bar.add_theme_stylebox_override("background", hp_style)

	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = UIStyles.COLORS.error
	hp_fill.corner_radius_top_left = 6
	hp_fill.corner_radius_top_right = 6
	hp_fill.corner_radius_bottom_left = 6
	hp_fill.corner_radius_bottom_right = 6
	_hp_bar.add_theme_stylebox_override("fill", hp_fill)

	# HP text
	var hp_row := HBoxContainer.new()
	hp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hp_row)

	_hp_label = Label.new()
	_hp_label.text = "100%"
	_hp_label.add_theme_font_size_override("font_size", 14)
	hp_row.add_child(_hp_label)

	# Enrage timer
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 50
	hp_row.add_child(spacer)

	_timer_label = Label.new()
	_timer_label.text = ""
	_timer_label.add_theme_font_size_override("font_size", 14)
	_timer_label.add_theme_color_override("font_color", UIStyles.COLORS.warning)
	hp_row.add_child(_timer_label)

	# Mechanics warning area
	_mechanics_container = VBoxContainer.new()
	_mechanics_container.name = "MechanicsContainer"
	_mechanics_container.visible = false
	vbox.add_child(_mechanics_container)

	# Mechanics icons row (spread, stack, interrupt, dodge)
	_mechanics_icons = HBoxContainer.new()
	_mechanics_icons.alignment = BoxContainer.ALIGNMENT_CENTER
	_mechanics_container.add_child(_mechanics_icons)

	_mechanics_warning = Label.new()
	_mechanics_warning.name = "MechanicsWarning"
	_mechanics_warning.text = ""
	_mechanics_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mechanics_warning.add_theme_font_size_override("font_size", 16)
	_mechanics_warning.add_theme_color_override("font_color", UIStyles.COLORS.warning)
	_mechanics_container.add_child(_mechanics_warning)

	# Style for mechanics warning
	var warning_style := StyleBoxFlat.new()
	warning_style.bg_color = Color(0.2, 0.1, 0.0, 0.9)
	warning_style.border_color = UIStyles.COLORS.warning
	warning_style.border_width_left = 2
	warning_style.border_width_right = 2
	warning_style.border_width_top = 2
	warning_style.border_width_bottom = 2
	warning_style.corner_radius_top_left = 8
	warning_style.corner_radius_top_right = 8
	warning_style.corner_radius_bottom_left = 8
	warning_style.corner_radius_bottom_right = 8
	warning_style.content_margin_left = 16
	warning_style.content_margin_top = 8
	warning_style.content_margin_right = 16
	warning_style.content_margin_bottom = 8
	_mechanics_warning.add_theme_stylebox_override("normal", warning_style)

func _create_timer() -> void:
	_enrage_timer = Timer.new()
	_enrage_timer.wait_time = 1.0
	_enrage_timer.timeout.connect(_on_enrage_tick)
	add_child(_enrage_timer)

func _create_mechanic_icon(mechanic_type: String, tooltip: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.tooltip_text = tooltip
	icon.focus_mode = Control.FOCUS_ALL
	icon.accessible_name = "Mechanic: %s" % mechanic_type
	icon.accessible_description = tooltip
	icon.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	
	# Use IconResolver to get appropriate icon
	var icon_path := "res://ui/textures/mechanics/%s.png" % mechanic_type.to_lower()
	var texture := IconResolver.get_icon_for_path(icon_path)
	if texture:
		icon.texture = texture
	else:
		# Fallback: colored square with letter
		var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
		match mechanic_type:
			"SPREAD":
				img.fill(Color(0.0, 1.0, 0.0, 1.0))  # Green
			"STACK":
				img.fill(Color(0.0, 0.5, 1.0, 1.0))  # Blue
			"INTERRUPT":
				img.fill(Color(1.0, 0.5, 0.0, 1.0))  # Orange
			"DODGE":
				img.fill(Color(1.0, 0.0, 1.0, 1.0))  # Magenta
			_:
				img.fill(Color(0.8, 0.8, 0.8, 1.0))
		icon.texture = ImageTexture.create_from_image(img)
	
	# Add pulsing animation (respect reduce motion)
	if not UIStyles.is_reduce_motion_enabled():
		var tween := icon.create_tween()
		tween.set_loops()
		tween.tween_property(icon, "modulate:a", 0.5, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(icon, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	return icon

func set_target(target) -> void:
	if target == null:
		clear_boss()
		return

	var boss_id := target.entity_id if target and "entity_id" in target else ""
	var name := ""
	var max_hp := 100

	if target is Dictionary:
		name = target.get("display_name", target.get("name", "Boss"))
		max_hp = target.get("max_health", target.get("health", 100))
	else:
		if "display_name" in target:
			name = target.display_name
		elif "name" in target:
			name = target.name
		if "max_health" in target:
			max_hp = target.max_health
		elif "health" in target:
			max_hp = target.health

	set_boss(boss_id, name, max_hp)

func _on_enrage_tick() -> void:
	if _enrage_remaining > 0:
		_enrage_remaining -= 1.0
		_update_timer_display()

func _update_timer_display() -> void:
	if _enrage_remaining <= 0:
		_timer_label.text = ""
		_enrage_timer.stop()
		return

	var minutes := int(_enrage_remaining) / 60
	var seconds := int(_enrage_remaining) % 60
	_timer_label.text = "Enrage: %d:%02d" % [minutes, seconds]

	# Flash when low
	if _enrage_remaining < 60:
		_timer_label.add_theme_color_override("font_color", UIStyles.COLORS.error)
	elif _enrage_remaining < 180:
		_timer_label.add_theme_color_override("font_color", UIStyles.COLORS.warning)
	else:
		_timer_label.add_theme_color_override("font_color", UIStyles.COLORS.info)

func set_boss(boss_id: String, name: String, max_hp: int, enrage_time: float = 0, max_phases: int = 3) -> void:
	_boss_id = boss_id
	_name_label.text = name
	_max_hp = max_hp
	_current_hp = max_hp
	_enrage_time = enrage_time
	_enrage_remaining = enrage_time
	_phase = 1
	_max_phases = max_phases
	_mechanics_active.clear()

	_hp_bar.max_value = _max_hp
	_hp_bar.value = _current_hp
	_hp_label.text = "100%"

	_phase_label.text = " Phase %d" % _phase
	_build_phase_indicators()
	_update_timer_display()

	if enrage_time > 0:
		_enrage_timer.start()

	show()

func _build_phase_indicators() -> void:
	# Clear existing indicators
	for child in _phase_indicators.get_children():
		child.queue_free()
	
	# Build phase indicators based on max phases
	for i in range(_max_phases):
		var indicator := PanelContainer.new()
		indicator.custom_minimum_size = Vector2(12, 12)
		
		var style := StyleBoxFlat.new()
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		
		if i + 1 == _phase:
			style.bg_color = UIStyles.COLORS.accent_gold
			style.border_color = UIStyles.COLORS.accent_gold
		elif i + 1 < _phase:
			style.bg_color = UIStyles.COLORS.success
			style.border_color = UIStyles.COLORS.success
		else:
			style.bg_color = UIStyles.COLORS.background_dark
			style.border_color = UIStyles.COLORS.border
		
		indicator.add_theme_stylebox_override("panel", style)
		_phase_indicators.add_child(indicator)

func update_health(current: int, maximum: int) -> void:
	_current_hp = current
	_max_hp = maximum if maximum > 0 else 1

	_hp_bar.max_value = _max_hp
	_hp_bar.value = _current_hp

	var percent := int((float(_current_hp) / float(_max_hp)) * 100)
	_hp_label.text = "%d%%" % percent

	# Check for phase transitions based on health thresholds
	_check_phase_transition(percent)

func _check_phase_transition(percent: int) -> void:
	# Default phase thresholds: 75%, 50%, 25%
	var thresholds := [75, 50, 25]
	
	# Check if we crossed a threshold
	for i, threshold in enumerate(thresholds):
		if percent <= threshold and _phase == i + 1:
			set_phase(i + 2)
			break

func set_phase(phase: int) -> void:
	_phase = clampi(phase, 1, _max_phases)
	_phase_label.text = " Phase %d" % _phase
	_build_phase_indicators()
	
	# Show phase change announcement
	_show_mechanics_warning("PHASE %d" % _phase, 3.0, UIStyles.COLORS.accent_gold)
	
	# Emit signal for phase change
	emit_signal("phase_changed", _phase)

func show_mechanics_warning(message: String, duration: float = 5.0, color: Color = null) -> void:
	_show_mechanics_warning(message, duration, color)

func _show_mechanics_warning(message: String, duration: float, color: Color) -> void:
	if color == null:
		color = UIStyles.COLORS.warning
	
	_mechanics_warning.text = message
	_mechanics_warning.add_theme_color_override("font_color", color)
	_mechanics_container.visible = true
	
	var fade_dur = UIStyles.get_animation_duration(0.2)
	
	# Flash animation (respect reduce motion)
	var tween := UIStyles.create_accessible_tween(_mechanics_warning, "modulate:a", 1.0, fade_dur)
	tween.tween_interval(duration - fade_dur * 2)
	tween.tween_property(_mechanics_warning, "modulate:a", 0.0, fade_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		_mechanics_container.visible = false
		_mechanics_warning.modulate = Color(1, 1, 1, 1)
	)

func add_mechanic(mechanic_name: String, warning_text: String, duration: float = 10.0) -> void:
	_mechanics_active.append({
		"name": mechanic_name,
		"warning": warning_text,
		"time": duration,
		"start_time": Time.get_ticks_msec() / 1000.0
	})
	_show_mechanics_warning(warning_text, duration, UIStyles.COLORS.warning)

func add_mechanic_icons(mechanic_types: Array[String]) -> void:
	# Clear existing icons
	for child in _mechanics_icons.get_children():
		child.queue_free()
	
	# Add icons for each mechanic type
	for mechanic in mechanic_types:
		var tooltip := _get_mechanic_tooltip(mechanic)
		var icon := _create_mechanic_icon(mechanic, tooltip)
		_mechanics_icons.add_child(icon)
	
	_mechanics_container.visible = true

func _get_mechanic_tooltip(mechanic: String) -> String:
	match mechanic.to_upper():
		"SPREAD":
			return "Spread Out - Move away from other players"
		"STACK":
			return "Stack Up - Group together with your team"
		"INTERRUPT":
			return "Interruptible - Use interrupt abilities now"
		"DODGE":
			return "Dodge - Avoid incoming attack"
		_:
			return "Unknown mechanic"

func clear_boss() -> void:
	_boss_id = ""
	_enrage_timer.stop()
	_mechanics_active.clear()
	_phase_thresholds.clear()
	hide()

func get_boss_id() -> String:
	return _boss_id

func is_active() -> bool:
	return not _boss_id.is_empty()

signal phase_changed(phase: int)
