## RespawnUI - Death screen with respawn options
## Shows available respawn locations and allows player to choose
extends Control
class_name RespawnUI

signal respawn_selected(mode: String, location_data: Dictionary)
signal respawn_skipped()

@export var auto_show_delay: float = 0.0  # Delay before showing UI
@export var auto_respawn_timeout: float = 0.0  # 0 = no auto-respawn

var _options: Array[Dictionary] = []
var _selected_index: int = 0
var _timer: float = 0.0
var _is_visible: bool = false

@onready var _panel: PanelContainer = $PanelContainer
@onready var _title_label: Label = $PanelContainer/VBox/Title
@onready var _options_container: VBoxContainer = $PanelContainer/VBox/Options
@onready var _timer_label: Label = $PanelContainer/VBox/Timer
@onready var _skip_button: Button = $PanelContainer/VBox/SkipButton

func _ready() -> void:
	visible = false
	_is_visible = false
	# A11y: the skip action names itself for readers and agents (the
	# button text is minimal by design).
	var A11yStyles = load("res://ui/components/ui_styles.gd")
	if A11yStyles and _skip_button:
		A11yStyles.apply_accessibility(_skip_button, "Skip timer and wait it out", "Closes this screen; the zone's timed respawn completes on its own")

	# Connect signals
	respawn_skipped.connect(_on_respawn_skipped)

func show_respawn_options(options: Array[Dictionary]) -> void:
	_options = options
	_selected_index = 0
	_timer = auto_respawn_timeout

	# Populate options UI
	_populate_options()

	# Show/hide based on config
	if GameConfig.Respawn.ALLOW_SKIP_RESPAWN_UI:
		_skip_button.visible = true
		if auto_respawn_timeout > 0:
			_timer_label.visible = true
			_timer_label.text = "Auto-respawn in: %.0f" % _timer
		else:
			_timer_label.visible = false
	else:
		_skip_button.visible = false
		_timer_label.visible = false

	# Delay show if configured
	if auto_show_delay > 0:
		await get_tree().create_timer(auto_show_delay).timeout

	visible = true
	_is_visible = true
	_update_selection()

func _populate_options() -> void:
	# Clear existing options
	for child in _options_container.get_children():
		child.queue_free()

	# Add option buttons
	for i in range(_options.size()):
		var option: Dictionary = _options[i]
		var button := Button.new()
		button.text = _get_option_display(option)
		button.pressed.connect(_on_option_selected.bind(i))
		# A11y: the death screen must be navigable by every reader and
		# agent -- name the destination, detail the consequence.
		var A11yStyles = load("res://ui/components/ui_styles.gd")
		if A11yStyles:
			var mode: String = option.get("mode", "unknown")
			var label: String = String(_get_option_display(option))
			A11yStyles.apply_accessibility(
				button,
				"Respawn: %s" % label,
				"Returns you to the world via %s" % ("your bound Ankh" if mode == "ankh" else ("the closest Ankh" if mode == "nearest_ankh" else ("the death spot, faster" if mode == "near_corpse" else ("the death spot, instantly -- one Soulbinder's Ticket is spent" if mode == "soulbind" else "the zone's respawn rules"))))
			)
		_options_container.add_child(button)

func _get_option_display(option: Dictionary) -> String:
	var mode: String = option.get("mode", "unknown")
	var name: String = option.get("name", "Unknown")
	var details: String = option.get("details", "")

	match mode:
		"ankh":
			return "[ANKH] %s" % name
		"nearest_ankh":
			return "[NEAREST ANKH] %s" % name
		"near_corpse":
			return "[CORPSE] Near death location"
		"soulbind":
			return "[SOULBIND] %s" % name
		"gateway":
			return "[GATEWAY] %s" % name
		"safe_zone":
			return "[SAFE ZONE] Arena safe area"
		"timed":
			return "[TIMED] Standard respawn (%.0fs)" % option.get("time", 30)
		"revive":
			return "[AWAITING REVIVE] Waiting for rescue..."
		_:
			return "%s" % name

func _on_option_selected(index: int) -> void:
	if index >= 0 and index < _options.size():
		_selected_index = index
		var option: Dictionary = _options[index]
		respawn_selected.emit(option.get("mode", "unknown"), option)
		_hide()

func _on_skip_pressed() -> void:
	# Skip to default respawn (usually ankh or timed)
	var default_option := _get_default_respawn_option()
	if default_option.size() > 0:
		respawn_selected.emit(default_option.get("mode", "timed"), default_option)
	respawn_skipped.emit()
	_hide()

func _on_respawn_skipped() -> void:
	_hide()

func _get_default_respawn_option() -> Dictionary:
	# Find the best available option
	for option in _options:
		var mode: String = option.get("mode", "")
		if mode == "ankh":
			return option
		if mode == "safe_zone":
			return option
	return {"mode": "timed", "time": 30.0} if _options.size() > 0 else {}

func _process(delta: float) -> void:
	if not _is_visible:
		return

	# Handle keyboard navigation
	if Input.is_action_just_pressed("ui_up"):
		_selected_index = wrapi(_selected_index - 1, 0, _options.size())
		_update_selection()
	elif Input.is_action_just_pressed("ui_down"):
		_selected_index = wrapi(_selected_index + 1, 0, _options.size())
		_update_selection()
	elif Input.is_action_just_pressed("ui_accept"):
		_on_option_selected(_selected_index)
	elif Input.is_action_just_pressed("ui_cancel"):
		if GameConfig.Respawn.ALLOW_SKIP_RESPAWN_UI:
			_on_skip_pressed()

	# Auto-respawn countdown
	if auto_respawn_timeout > 0 and _timer > 0:
		_timer -= delta
		_timer_label.text = "Auto-respawn in: %.0f" % max(0, _timer)
		if _timer <= 0:
			_on_skip_pressed()

func _update_selection() -> void:
	for i in range(_options_container.get_child_count()):
		var button: Button = _options_container.get_child(i)
		if button:
			if i == _selected_index:
				button.add_theme_color_override("font_color", Color.YELLOW)
				button.text = "> " + button.text
			else:
				button.add_theme_color_override("font_color", Color.WHITE)
				if button.text.begins_with("> "):
					button.text = button.text.substr(2)

func _hide() -> void:
	visible = false
	_is_visible = false
