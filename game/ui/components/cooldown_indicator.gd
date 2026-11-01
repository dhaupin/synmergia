


extends Control

## CooldownIndicator - Visual feedback for rate-limited actions
## Uses UIStyles for default styling
## Shows a countdown timer when an action is on cooldown

class_name CooldownIndicator
## Runtime autoload lookup (script-mode-safe; the bare identifier
## fails compile when autoloads are absent -- test_islands).
func _notify_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("NotificationService")) if tree and tree.root else null

const UIStyles = preload("res://ui/components/ui_styles.gd")


const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

## Runtime autoload lookups (script-mode-safe; the bare identifiers
## fail compile when autoloads are absent -- test_islands).
func _gamelog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null



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

	# Wire via _notify_svc() to catch RATE_LIMITED toasts (the legacy
	# reverse-engineered path; kept as a fallback for service frames
	# that never called start_cooldown through the service).
	if _notify_svc():
		if _notify_svc().has_signal("notification_sent"):
			if not _notify_svc().notification_sent.is_connected(_on_notification_sent):
				_notify_svc().notification_sent.connect(_on_notification_sent)

	# PRIMARY truth: CooldownService now emits cooldown_started/tick/
	# ended on its own sweep. The indicator was BUILT for this and had
	# zero listeners wired anywhere -- bars were keying off toasts
	# while the service state sat unwatched. Tick keeps the fill
	# honest (the tween's self-managed countdown stays as fallback);
	# ended retires a CANCELLED bar instantly instead of waiting out
	# the display's own end_time. All player scopes shown by design
	# (same as the toast path -- client frames carry one local player).
	var cooldown_svc := _cooldown_svc()
	if cooldown_svc:
		if cooldown_svc.has_signal("cooldown_started") and not cooldown_svc.cooldown_started.is_connected(_on_cooldown_started):
			cooldown_svc.cooldown_started.connect(_on_cooldown_started)
		if cooldown_svc.has_signal("cooldown_tick") and not cooldown_svc.cooldown_tick.is_connected(_on_cooldown_tick):
			cooldown_svc.cooldown_tick.connect(_on_cooldown_tick)
		if cooldown_svc.has_signal("cooldown_ended") and not cooldown_svc.cooldown_ended.is_connected(_on_cooldown_ended):
			cooldown_svc.cooldown_ended.connect(_on_cooldown_ended)

	hide()


## Script-mode-safe resolve of the CooldownService autoload
## (same pattern as _notify_svc above: bare identifier fails
## compile when autoloads are absent -- the test_islands law).
func _cooldown_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("CooldownService")) if tree and tree.root else null


func _on_cooldown_started(player_id: String, action_type: String, duration: float) -> void:
	# A fresh service-level cooldown is the earlier truth the toast
	# path used to wait for the FIRST retry to see.
	if not _active_cooldowns.has(action_type):
		_show_cooldown(action_type, duration)

func _on_cooldown_tick(player_id: String, action_type: String, remaining: float) -> void:
	# Authoritative fill: override the tween's self-managed countdown
	# with the service's own remaining read. The fill/bg metas live on
	# the inner barContainer (the same store _create_cooldown_bar
	# writes, and _update_cooldown_bar walks), so find that child.
	if not _active_cooldowns.has(action_type):
		return
	var data: Dictionary = _active_cooldowns[action_type]
	var _bar: Control = data.get("bar")
	var bar_container := _find_bar_container(_bar)
	if bar_container == null:
		return
	var fill: ColorRect = bar_container.get_meta("fill") if bar_container.has_meta("fill") else null
	var bg: ColorRect = bar_container.get_meta("bg") if bar_container.has_meta("bg") else null
	if fill == null or bg == null:
		return
	var duration: float = maxf(float(data.get("duration", remaining)), 0.001)
	fill.size.x = bg.size.x * clampf(remaining / duration, 0.0, 1.0)

func _find_bar_container(bar: Control) -> Control:
	if bar == null or not is_instance_valid(bar):
		return null
	for child in bar.get_children():
		if child is Control and child.has_meta("fill"):
			return child
	return null

func _on_cooldown_ended(player_id: String, action_type: String) -> void:
	# Cancel/expire: retire the bar NOW rather than waiting for the
	# display's own end_time to count out.
	if _active_cooldowns.has(action_type):
		_finish_cooldown(action_type)

func _on_notification_sent(entity_id: String, notification: Dictionary) -> void:
	var kind: int = notification.get("kind", -1)
	if kind != NotifKind.RATE_LIMITED:
		return
	var data: Dictionary = notification.get("data", {})
	var action_type: String = data.get("action", "unknown")
	var cooldown: float = data.get("cooldown", 1.0)
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
