## LoadingUI - the unified loading overlay (round-5 redesign).
## A CENTERED SPINNER on a dimmed full-screen backdrop -- not a small
## panel (play-day: "should be like a centered spinner"). The whole
## overlay covers the viewport, so whatever scene is dying underneath
## never shows through.
##
## Two owners:
##  - BootLoadingLayer (GameManager's root CanvasLayer 100): survives
##    scene swaps -- this is the one that covers menu -> world.
##  - hud_layer.tscn embeds a second LoadingUI for in-game states; the
##    static `instance` clobber risk is handled by _exit_tree.
##
## The UI is built in _setup_ui() over UIPanel's Panel path for
## compatibility, but the visible surface is the full-rect backdrop.
extends "res://ui/components/ui_panel.gd"
class_name LoadingUI


## Loading states
enum LoadingState { IDLE, LOADING, PROGRESS, SUCCESS, ERROR }

## Singleton
static var instance: LoadingUI

## State
var _current_state: LoadingState = LoadingState.IDLE
var _progress: float = 0.0
var _status_text: String = ""
var _sub_text: String = ""

## Components
var _backdrop: ColorRect
var _panel: PanelContainer
var _icon_container: Control
var _spinner: Control
var _progress_bar: ProgressBar
var _status_label: Label
var _sub_label: Label

## Animation
var _spinner_rotation: float = 0.0
var _pulse_time: float = 0.0


func _ready() -> void:
	super._ready()
	instance = self
	_setup_ui()
	hide()
	visible = false


## The static `instance` points into whatever scene owns this HUD node.
## When that scene is freed (change_scene_to_file defers the free), a
## stale pointer survives and the next hide_loading() call segfaults the
## engine -- the PLAYING -> MAIN_MENU crash. Null it on tree exit.
func _exit_tree() -> void:
	if instance == self:
		instance = null


func _setup_ui() -> void:
	# STRAY PANEL KILL (play-test round 6, item 1): the boot overlay is
	# built with LUI.new() straight on the CanvasLayer, so no scene
	# provides a "Panel" -- UIPanel._ready's safety net auto-built its
	# standard centered 400x500 PanelContainer on top of the backdrop,
	# which read as "the loading screen is contained in a panel". The
	# overlay is ONLY the full-rect backdrop + spinner stack; any auto
	# panel dies here (both the boot instance and the hud_layer.tscn
	# embed run this path).
	var stray := get_node_or_null("Panel")
	if stray != null:
		stray.queue_free()

	# FULL-SCREEN BACKDROP (round 7, item 1 -- measured, not guessed):
	# this overlay is a ROOT control (a CanvasLayer child, no parent
	# Control). set_anchors_preset(PRESET_FULL_RECT) PRESERVES the
	# node's current rect when applied, and on the boot path that rect
	# is 0x0 -- the preset froze offsets at minus-viewport and the whole
	# overlay collapsed to 0x0, leaving the spinner at its content size
	# (169x222) in the top-left corner ("loading small in upper left").
	# Assign anchors AND zero offsets explicitly; grow both so viewport
	# changes (orientation flip) keep tracking.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(0.03, 0.04, 0.07, 0.94)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_backdrop.grow_vertical = Control.GROW_DIRECTION_BOTH
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	# The centered spinner stack: emblem, spinner, status, substatus.
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.add_child(center)

	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 14)
	center.add_child(stack)

	# Emblem above the spinner when the logo pack is present.
	var BrandScript = load("res://core/utils/branding.gd")
	var emblem: Texture2D = BrandScript.emblem_small() if BrandScript else null
	if emblem != null:
		var emblem_rect := TextureRect.new()
		emblem_rect.name = "Emblem"
		emblem_rect.texture = emblem
		emblem_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		emblem_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		emblem_rect.custom_minimum_size = Vector2(72, 72)
		emblem_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		stack.add_child(emblem_rect)

	_icon_container = Control.new()
	_icon_container.custom_minimum_size = Vector2(64, 64)
	_icon_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(_icon_container)

	_create_spinner()

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.text = "Loading..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 18)
	if UIStyles:
		_status_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	stack.add_child(_status_label)

	_sub_label = Label.new()
	_sub_label.name = "SubStatus"
	_sub_label.text = ""
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.add_theme_font_size_override("font_size", 13)
	if UIStyles:
		_sub_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	stack.add_child(_sub_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.name = "ProgressBar"
	_progress_bar.min_value = 0
	_progress_bar.max_value = 100
	_progress_bar.value = 0
	_progress_bar.custom_minimum_size = Vector2(260, 8)
	_progress_bar.show_percentage = false
	_progress_bar.visible = false
	_progress_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(_progress_bar)


func _on_open() -> void:
	pass

func _on_close() -> void:
	pass

func _create_spinner() -> void:
	_spinner = Control.new()
	_spinner.name = "Spinner"
	_spinner.custom_minimum_size = Vector2(56, 56)
	# A visible arc ring: four rotating cards around a hub. Simple
	# _process rotation drives it (no AnimationPlayer in overlays).
	var ring := Control.new()
	ring.name = "Ring"
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_spinner.add_child(ring)
	for i in range(4):
		var card := ColorRect.new()
		card.name = "Card%d" % i
		card.color = Color(0.95, 0.82, 0.45) if i % 2 == 0 else Color(0.45, 0.62, 0.85)
		card.custom_minimum_size = Vector2(10, 22)
		card.set_anchors_preset(Control.PRESET_CENTER_TOP)
		card.position = Vector2(-5, 0)
		# Fan the four cards around the hub; the ring rotates the fan.
		card.pivot_offset = Vector2(5, 28)
		card.rotation = TAU * float(i) / 4.0
		ring.add_child(card)
	_icon_container.add_child(_spinner)


func _process(delta: float) -> void:
	if not visible:
		return

	match _current_state:
		LoadingState.LOADING:
			_spinner_rotation += 220.0 * delta
			if _spinner:
				_spinner.rotation = deg_to_rad(_spinner_rotation)
			_pulse_time += delta
		LoadingState.PROGRESS:
			_pulse_time += delta
		_:
			pass

	_update_display()


func _update_display() -> void:
	if _progress_bar:
		_progress_bar.value = _progress

	if _status_label:
		_status_label.text = _status_text
		if _current_state == LoadingState.ERROR and UIStyles:
			_status_label.add_theme_color_override("font_color", UIStyles.COLORS.error)
		elif _current_state == LoadingState.SUCCESS and UIStyles:
			_status_label.add_theme_color_override("font_color", UIStyles.COLORS.success)
		elif UIStyles:
			_status_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)

	if _sub_label:
		_sub_label.text = _sub_text


static func singleton() -> LoadingUI:
	return instance


func show_loading(message: String = "Loading...", sub_message: String = "") -> void:
	_current_state = LoadingState.LOADING
	_status_text = message
	_sub_text = sub_message
	_progress = 0.0

	if _progress_bar:
		_progress_bar.visible = false
	if _spinner:
		_spinner.visible = true

	show()


func show_progress(progress: float, message: String = "", sub_message: String = "") -> void:
	_current_state = LoadingState.PROGRESS
	_progress = clampf(progress, 0, 100)
	_status_text = message if not message.is_empty() else "Loading..."
	_sub_text = sub_message

	if _progress_bar:
		_progress_bar.visible = true
	if _spinner:
		_spinner.visible = true

	show()


func show_success(message: String = "Complete!", sub_message: String = "") -> void:
	_current_state = LoadingState.SUCCESS
	_status_text = message
	_sub_text = sub_message
	show()


func hide_loading() -> void:
	_current_state = LoadingState.IDLE
	hide()


func set_status(message: String) -> void:
	_status_text = message


func set_sub_status(message: String) -> void:
	_sub_text = message


func set_progress(value: float) -> void:
	_progress = clampf(value, 0, 100)
	if _progress_bar:
		_progress_bar.value = _progress


func is_loading() -> bool:
	return visible and (_current_state == LoadingState.LOADING or _current_state == LoadingState.PROGRESS)


func get_state() -> LoadingState:
	return _current_state
