## HordeBar - wave/encounter HUD widget for horde events.
##
## Sits under HudLayer (name: HordeBar) next to BossHealthBar: shows the
## active horde's zone, wave progress ("Wave 2 / 3"), and living enemies
## remaining. Hidden when no horde is running. Wire-only: driven by
## HordeEventService signals via set_horde_state() (tests can drive it
## without the service).
extends Control

const UIStyles = preload("res://ui/components/ui_styles.gd")

var _title_label: Label
var _wave_label: Label
var _remaining_bar: ProgressBar
var _remaining_label: Label

var _horde_id: String = ""
var _zone_id: String = ""
var _wave_number: int = 0
var _total_waves: int = 0
var _remaining: int = -1

func _ready() -> void:
	_setup_ui()
	visible = false

## ---------------------------------------------------------------------------
## Public API (service signals / tests)
## ---------------------------------------------------------------------------

func set_horde_state(state: Dictionary) -> void:
	if state.is_empty():
		hide()
		return
	_horde_id = str(state.get("horde_id", _horde_id))
	_zone_id = str(state.get("zone_id", _zone_id))
	_wave_number = int(state.get("wave_number", _wave_number))
	_total_waves = int(state.get("total_waves", _total_waves))
	_remaining = int(state.get("remaining", _remaining))
	_refresh()

func show_horde_started(horde_id: String, zone_id: String, total_waves: int) -> void:
	_horde_id = horde_id
	_zone_id = zone_id
	_wave_number = 0
	_total_waves = total_waves
	_remaining = -1
	_refresh()
	visible = true

func show_wave_started(wave_number: int, total_waves: int) -> void:
	_wave_number = wave_number
	_total_waves = total_waves
	_remaining = -1
	_refresh()
	visible = true

func show_wave_progress(remaining: int) -> void:
	_remaining = remaining
	_refresh()
	visible = true

func show_wave_cleared() -> void:
	_remaining = 0
	_refresh()
	visible = true

func show_boss() -> void:
	_wave_number = _total_waves
	_remaining = -1
	_refresh()
	visible = true

func hide_horde() -> void:
	visible = false
	_horde_id = ""
	_zone_id = ""
	_wave_number = 0
	_total_waves = 0
	_remaining = -1

func active_horde_id() -> String:
	return _horde_id

## ---------------------------------------------------------------------------
## UI
## ---------------------------------------------------------------------------

func _refresh() -> void:
	if _title_label == null:
		return
	_title_label.text = "HORDE - %s" % (_zone_id.to_upper() if _zone_id != "" else "INCOMING")
	_wave_label.text = "Wave %d / %d" % [_wave_number, _total_waves] if _total_waves > 0 else "Incoming..."
	if _remaining >= 0:
		_remaining_bar.visible = true
		_remaining_label.visible = true
		_remaining_bar.max_value = 100.0
		_remaining_bar.value = 100.0
		_remaining_label.text = "%d remaining" % _remaining
	else:
		_remaining_bar.visible = false
		_remaining_label.visible = false

func _setup_ui() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	custom_minimum_size = Vector2(360, 64)
	position = Vector2(-180, 120)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_title_label)

	_wave_label = Label.new()
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_wave_label)

	_remaining_bar = ProgressBar.new()
	_remaining_bar.min_value = 0.0
	_remaining_bar.max_value = 100.0
	_remaining_bar.show_percentage = false
	vbox.add_child(_remaining_bar)

	_remaining_label = Label.new()
	_remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_remaining_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_remaining_label)
