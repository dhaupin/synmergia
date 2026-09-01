## BossHealthBar - Raid boss health display
## Large HP bar with boss name, phase, enrage timer
class_name BossHealthBar
extends Control

## Components
var _name_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _phase_label: Label
var _timer_label: Label
var _enrage_timer: Timer

## State
var _boss_id: String = ""
var _current_hp: int = 0
var _max_hp: int = 100
var _phase: int = 1
var _enrage_time: float = 0
var _enrage_remaining: float = 0

func _ready() -> void:
	_setup_ui()
	_create_timer()
	hide()

func _setup_ui() -> void:
	name = "BossHealthBar"
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -300
	offset_top = 60
	offset_right = 300
	offset_bottom = 140

	# Container
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	# Boss name
	_name_label = Label.new()
	_name_label.text = "Boss Name"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 20)
	_name_label.add_theme_color_override("font_color", UIStyles.COLORS.error)
	vbox.add_child(_name_label)

	# Phase indicator
	var phase_row := HBoxContainer.new()
	phase_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(phase_row)

	var phase_icon := Label.new()
	phase_icon.text = "[Boss]"
	phase_icon.add_theme_color_override("font_color", UIStyles.COLORS.warning)
	phase_row.add_child(phase_icon)
	
	_phase_label = Label.new()
	_phase_label.text = " Phase 1"
	_phase_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	phase_row.add_child(_phase_label)
	
	# Health bar
	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HPBar"
	_hp_bar.min_value = 0
	_hp_bar.max_value = 100
	_hp_bar.value = 100
	_hp_bar.custom_minimum_size.y = 30
	_hp_bar.show_percentage = false
	vbox.add_child(_hp_bar)
	
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

func _create_timer() -> void:
	_enrage_timer = Timer.new()
	_enrage_timer.wait_time = 1.0
	_enrage_timer.timeout.connect(_on_enrage_tick)
	add_child(_enrage_timer)

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
	elif true:
		_timer_label.add_theme_color_override("font_color", UIStyles.COLORS.warning)

func set_boss(boss_id: String, name: String, max_hp: int, enrage_time: float = 0) -> void:
	_boss_id = boss_id
	_name_label.text = name
	_max_hp = max_hp
	_current_hp = max_hp
	_enrage_time = enrage_time
	_enrage_remaining = enrage_time
	_phase = 1

	_hp_bar.max_value = _max_hp
	_hp_bar.value = _current_hp
	_hp_label.text = "100%"
	
	_phase_label.text = " Phase %d" % _phase
	_update_timer_display()
	
	if enrage_time > 0:
		_enrage_timer.start()

	show()

func update_health(current: int, maximum: int) -> void:
	_current_hp = current
	_max_hp = maximum if maximum > 0 else 1

	_hp_bar.max_value = _max_hp
	_hp_bar.value = _current_hp
	
	var percent := int((float(_current_hp) / float(_max_hp)) * 100)
	_hp_label.text = "%d%%" % percent

func set_phase(phase: int) -> void:
	_phase = phase
	_phase_label.text = " Phase %d" % phase

func clear_boss() -> void:
	_boss_id = ""
	_enrage_timer.stop()
	hide()

func get_boss_id() -> String:
	return _boss_id

func is_active() -> bool:
	return not _boss_id.is_empty()
