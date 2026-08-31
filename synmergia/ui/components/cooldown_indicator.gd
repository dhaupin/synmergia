## CooldownIndicator - Visual feedback for rate-limited actions
## Uses UIStyles for default styling
## Shows a countdown timer when an action is on cooldown
class_name CooldownIndicator
extends Control

## Emitted when cooldown completes
signal cooldown_complete(action_type: String)

## Active cooldowns: action_type -> {end_time, progress_bar}
var _active_cooldowns: Dictionary = {}

## Configurable appearance
@export var bar_color: Color = UIStyles.COLORS.error  # Default from UIStyles
@export var bar_background: Color = UIStyles.COLORS.background_dark
@export var text_color: Color = UIStyles.COLORS.text_primary
@export var icon_size: Vector2 = Vector2(24, 24)
@export var bar_height: float = 4.0
@export var show_action_name: bool = true
@export var auto_hide_delay: float = 0.5  # Hide bar this long after cooldown ends

## Container for cooldown bars
var _container: HBoxContainer
var _bar_scene: PackedScene

func _ready() -> void:
	# Create container if not set
	if not _container:
		_container = HBoxContainer.new()
		add_child(_container)
		_container.alignment = BoxContainer.ALIGNMENT_END
	
	# Load bar scene
	_bar_scene = preload("res://ui/components/cooldown_bar.tscn")
	
	# Listen to QoS rate limit events
	var qos: Node = QoSService.get_instance()
	if qos != null:
		qos.rate_limited.connect(_on_rate_limited)
	
	hide()

## Called when a player action is rate limited
func _on_rate_limited(player_id: String, action_type: String, current_rate: float, max_rate: float) -> void:
	# Calculate cooldown time
	var cooldown := _calculate_cooldown(action_type, max_rate)
	if cooldown <= 0:
		return
	
	# Get player-specific cooldown
	# In a real implementation, you'd check if this is for the local player
	# For now, we'll show all cooldowns
	_show_cooldown(action_type, cooldown)

## Show cooldown bar for an action
func _show_cooldown(action_type: String, duration: float) -> void:
	var end_time := Time.get_ticks_msec() + (duration * 1000)
	
	if not _active_cooldowns.has(action_type):
		# Create new cooldown bar
		var bar := _create_cooldown_bar(action_type)
		_container.add_child(bar)
		_active_cooldowns[action_type] = {
			"bar": bar,
			"end_time": end_time,
			"duration": duration
		}
		show()
	else:
		# Update existing cooldown
		_active_cooldowns[action_type]["end_time"] = end_time
		_active_cooldowns[action_type]["duration"] = duration
	
	# Start/update animation
	if not is_inside_tree():
		return
	
	var tween := create_tween()
	tween.tween_callback(func(): _update_cooldown_bar(action_type)).set_delay(0.05)

## Create a cooldown bar for an action type
func _create_cooldown_bar(action_type: String) -> Control:
	var container := VBoxContainer.new()
	container.custom_minimum_size.y = 30
	
	# Action name label (optional)
	if show_action_name:
		var label := Label.new()
		label.text = _get_action_display_name(action_type)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.add_theme_color_override("font_color", text_color)
		label.custom_minimum_size.y = 16
		container.add_child(label)
	
	# Progress bar container
	var bar_container := HBoxContainer.new()
	bar_container.custom_minimum_size.y = bar_height
	
	# Background
	var bg := ColorRect.new()
	bg.color = bar_background
	bg.custom_minimum_size.y = bar_height
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_container.add_child(bg)
	
	# Progress fill
	var fill := ColorRect.new()
	fill.color = bar_color
	fill.custom_minimum_size.y = bar_height
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.position = Vector2.ZERO
	bar_container.add_child(fill)
	
	# Store reference to fill for updates
	bar_container.set_meta("fill", fill)
	bar_container.set_meta("bg", bg)
	
	container.add_child(bar_container)
	
	return container

## Update cooldown bar progress
func _update_cooldown_bar(action_type: String) -> void:
	if not _active_cooldowns.has(action_type):
		return
	
	var data: Dictionary = _active_cooldowns[action_type]
	var bar: Control = data["bar"]
	var end_time: int = data["end_time"]
	var duration: float = data["duration"]
	
	var now := Time.get_ticks_msec()
	var remaining := (end_time - now) / 1000.0
	
	if remaining <= 0:
		# Cooldown complete
		_finish_cooldown(action_type)
		return
	
	# Update progress bar fill width
	var bar_container: HBoxContainer = bar.get_node_or_null("VBoxContainer/HSBoxContainer")
	if bar_container:
		var fill: ColorRect = bar_container.get_meta("fill")
		var bg: ColorRect = bar_container.get_meta("bg")
		if fill and bg:
			var progress: float = remaining / duration
			fill.size.x = bg.size.x * progress
	
	# Schedule next update
	if is_inside_tree():
		var tween := create_tween()
		tween.tween_callback(func(): _update_cooldown_bar(action_type)).set_delay(0.05)

## Finish cooldown and clean up
func _finish_cooldown(action_type: String) -> void:
	if not _active_cooldowns.has(action_type):
		return
	
	var data: Dictionary = _active_cooldowns[action_type]
	var bar: Control = data["bar"]
	
	# Animate out
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(bar, "modulate:a", 0.0, auto_hide_delay)
	tween.tween_callback(bar.queue_free).set_delay(auto_hide_delay)
	
	_active_cooldowns.erase(action_type)
	cooldown_complete.emit(action_type)
	
	# Hide container if no more cooldowns
	if _active_cooldowns.is_empty():
		var hide_tween := create_tween()
		hide_tween.tween_callback(hide).set_delay(auto_hide_delay)

## Calculate cooldown time for action type
func _calculate_cooldown(action_type: String, max_rate: float) -> float:
	if max_rate <= 0:
		return 1.0
	return 1.0 / max_rate

## Get human-readable action name
func _get_action_display_name(action_type: String) -> String:
	var names := {
		"chat": "Chat",
		"whisper": "Whisper",
		"trade": "Trade",
		"party": "Party",
		"guild": "Guild",
		"inventory_transfer": "Items",
		"gold_transfer": "Gold",
		"inventory_trade": "Trading",
		"loot_roll": "Loot Roll",
		"loot_pickup": "Loot Pickup",
		"loot_abandon": "Loot Abandon",
		"movement": "Movement",
		"combat": "Combat",
		"item_action": "Item"
	}
	return names.get(action_type, action_type.capitalize())

## Clear all cooldowns
func clear_all() -> void:
	for action_type in _active_cooldowns.keys():
		_finish_cooldown(action_type)

## Add cooldown manually (for testing or external use)
func add_cooldown(action_type: String, duration: float) -> void:
	_show_cooldown(action_type, duration)
