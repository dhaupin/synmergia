## StormBar - ROYALE fog-wall HUD widget (S13).
##
## Sits under HudLayer (name: StormBar) next to HordeBar: shows the
## storm phase ("Phase 2 / 5"), the closing safe radius, and whether
## the wall is armed. Hidden outside a live ROYALE bout. Wire-only:
## driven by ArenaRoomService storm signals via set_storm_state()
## (tests drive it without the service). ASCII copy only; the wall's
## damage is the room's job, this just tells the truth about it.
extends Control

const UIStyles = preload("res://ui/components/ui_styles.gd")

var _title_label: Label
var _phase_label: Label
var _radius_bar: ProgressBar
var _radius_label: Label

var _instance_id: String = ""
var _phase: int = 0
var _total_phases: int = 5
var _radius: float = 0.0
var _room_half: float = 200.0
var _armed: bool = false

func _ready() -> void:
	_setup_ui()
	visible = false

## ---------------------------------------------------------------------------
## Public API (ArenaRoomService relay / tests)
## ---------------------------------------------------------------------------

## The bout opened: show the chip before the wall arms (the countdown
## is part of the tension). room_half drives the radius bar's scale.
func show_storm(instance_id: String, total_phases: int, room_half: float) -> void:
	_instance_id = instance_id
	_total_phases = maxi(total_phases, 1)
	_room_half = maxf(room_half, 1.0)
	_phase = 0
	_radius = _room_half
	_armed = false
	_refresh()
	visible = true

## A shrink started (storm_phase_advanced relay).
func show_phase_advanced(radius: float, phase_index: int) -> void:
	_armed = true
	_phase = phase_index
	_radius = radius
	_refresh()
	visible = true

## Per-bite feedback (storm_damage_applied relay): flash the radius
## label so standing in the fog FEELS like a mistake.
func show_fog_bite() -> void:
	if _radius_label != null:
		_radius_label.text = "THE FOG BITES - get inside the ring"
		_radius_label.modulate = Color(1.0, 0.35, 0.3)

## The bout closed.
func hide_storm() -> void:
	visible = false
	_instance_id = ""
	_phase = 0
	_radius = 0.0
	_armed = false

func active_instance_id() -> String:
	return _instance_id

## ---------------------------------------------------------------------------
## UI
## ---------------------------------------------------------------------------

func _refresh() -> void:
	if _title_label == null:
		return
	_title_label.text = "LAST LIGHT - THE FOG"
	if _armed:
		_phase_label.text = "Phase %d / %d" % [_phase + 1, _total_phases]
	else:
		_phase_label.text = "The fog waits... (%d phases)" % _total_phases
	_radius_bar.max_value = _room_half
	_radius_bar.value = _radius
	_radius_label.text = "Safe ring: %.0f m" % _radius
	_radius_label.modulate = Color(0.85, 0.9, 0.8)

func _setup_ui() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	custom_minimum_size = Vector2(360, 64)
	position = Vector2(-180, 192)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_title_label)

	_phase_label = Label.new()
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_phase_label)

	_radius_bar = ProgressBar.new()
	_radius_bar.min_value = 0.0
	_radius_bar.max_value = 100.0
	_radius_bar.show_percentage = false
	vbox.add_child(_radius_bar)

	_radius_label = Label.new()
	_radius_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radius_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_radius_label)
