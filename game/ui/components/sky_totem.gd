## SkyTotem - aurora-window HUD widget.
##
## Sits under HudLayer (name: SkyTotem) beside HordeBar: when a weather
## aurora window is open, shows the mystery it lights, a countdown, and
## the "look up" affordance ("LOOK UP — the sky writes"). Hidden when no
## window is open. Wire-only, driven by WeatherEventService signals via
## show_window()/hide_window() (tests can drive it without the service;
## the countdown advances on _process seconds).
extends Control

const UIStyles = preload("res://ui/components/ui_styles.gd")

var _title_label: Label
var _mystery_label: Label
var _countdown_label: Label
var _affordance_label: Label

var _mystery_id: String = ""
var _close_at_ms: int = 0
var _total_ms: int = 1


func _ready() -> void:
	_setup_ui()
	visible = false


## ---------------------------------------------------------------------------
## Public API (WeatherEventService signals / tests)
## ---------------------------------------------------------------------------

func show_window(mystery_id: String) -> void:
	_mystery_id = mystery_id
	_close_at_ms = 0  # unresolved until set_window_remaining arrives
	_total_ms = 1
	_refresh()
	visible = true


## The service knows the authoritative close time; HUD just renders it.
func set_window_remaining(mystery_id: String, sec_remaining: float, sec_total: float) -> void:
	if mystery_id != _mystery_id:
		if mystery_id != "":
			show_window(mystery_id)
	_mystery_id = mystery_id
	_close_at_ms = Time.get_ticks_msec() + int(sec_remaining * 1000.0)
	_total_ms = maxi(1, int(sec_total * 1000.0))
	_refresh()
	visible = true


func hide_window() -> void:
	visible = false
	_mystery_id = ""
	_close_at_ms = 0


func active_mystery() -> String:
	return _mystery_id


## ---------------------------------------------------------------------------
## UI
## ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not visible:
		return
	_tick_countdown()


func _tick_countdown() -> void:
	if _title_label == null:
		return
	if _close_at_ms <= 0:
		_countdown_label.text = "aurora burning"
		return
	var remaining: int = maxi(0, (_close_at_ms - Time.get_ticks_msec()) / 1000)
	if remaining <= 0:
		hide_window()
		return
	_countdown_label.text = "window closes in %d:%02d" % [remaining / 60, remaining % 60]
	# Dim as it burns down (the affordance fades with the sky).
	var burn_frac := float(remaining * 1000) / float(_total_ms)
	modulate.a = 0.5 + 0.5 * clampf(burn_frac, 0.0, 1.0)


func _refresh() -> void:
	if _title_label == null:
		return
	_title_label.text = "SKY WRITING"
	_mystery_label.text = "the aurora lights %s" % _mystery_id.replace("mystery_", "").replace("_", " ") if _mystery_id != "" else "an observation margin"
	modulate.a = 1.0


func _setup_ui() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	custom_minimum_size = Vector2(320, 84)
	position = Vector2(-160, 196)

	var panel := PanelContainer.new()
	# Aurora tint: pale green over slate — the sky-writing color.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.14, 0.12, 0.88)
	sb.border_color = Color(0.45, 0.85, 0.65, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.75))
	vbox.add_child(_title_label)

	_mystery_label = Label.new()
	_mystery_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mystery_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_mystery_label)

	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_countdown_label)

	_affordance_label = Label.new()
	_affordance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_affordance_label.add_theme_font_size_override("font_size", 11)
	_affordance_label.add_theme_color_override("font_color", Color(0.75, 0.95, 0.85))
	_affordance_label.text = "LOOK UP — and answer while it burns"
	vbox.add_child(_affordance_label)
