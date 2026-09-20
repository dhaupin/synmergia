## LoadingUI - Unified loading overlay
## Spinner, progress bar, and loading states
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


func _setup_ui() -> void:
	var panel := get_panel()
	if not panel:
		return
	var main: VBoxContainer = add_content_to_panel(panel)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.custom_minimum_size = Vector2(300, 150)
	main.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(300, 150)
	if UIStyles:
		_panel.add_theme_stylebox_override("panel", UIStyles.create_panel_style())
	center.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(vbox)

	_icon_container = Control.new()
	_icon_container.custom_minimum_size = Vector2(50, 50)
	vbox.add_child(_icon_container)

	_create_spinner()

	_progress_bar = ProgressBar.new()
	_progress_bar.name = "ProgressBar"
	_progress_bar.min_value = 0
	_progress_bar.max_value = 100
	_progress_bar.value = 0
	_progress_bar.custom_minimum_size = Vector2(200, 8)
	_progress_bar.show_percentage = false
	_progress_bar.visible = false
	vbox.add_child(_progress_bar)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.text = "Loading..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_status_label)

	_sub_label = Label.new()
	_sub_label.name = "SubStatus"
	_sub_label.text = ""
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if UIStyles:
		_sub_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	vbox.add_child(_sub_label)


func _on_open() -> void:
	pass

func _on_close() -> void:
	pass

func _create_spinner() -> void:
	_spinner = Control.new()
	_spinner.name = "Spinner"
	_spinner.custom_minimum_size = Vector2(40, 40)
	_spinner.set_anchors_preset(Control.PRESET_CENTER)
	_icon_container.add_child(_spinner)


func _process(delta: float) -> void:
	if not visible:
		return

	match _current_state:
		LoadingState.LOADING:
			_spinner_rotation += 180.0 * delta
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

	if _progress_bar:
		_progress_bar.visible = false
	if _spinner:
		_spinner.visible = true

	show()

	await get_tree().create_timer(1.0).timeout
	hide()


func show_error(message: String = "Error", sub_message: String = "") -> void:
	_current_state = LoadingState.ERROR
	_status_text = message
	_sub_text = sub_message

	if _progress_bar:
		_progress_bar.visible = false
	if _spinner:
		_spinner.visible = true


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
