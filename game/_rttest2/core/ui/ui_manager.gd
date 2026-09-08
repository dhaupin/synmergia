## UIManager - Manages game UI elements including targeting UI
## Handles instantiation and lifecycle of UI components
extends Node

# TargetTooltip is not an autoload (class_name only). UIManager
# calls TargetTooltip.new() in _ready(), which requires the
# class_name registered at parse time. Preload it here.
const TargetTooltip = preload("res://ui/targeting/target_tooltip.gd")

var _tooltip = null
var _initialized: bool = false

func _ready() -> void:
	# Connect to game state changes. GameManager may not be ready yet
	# (autoload ordering); guard each access so a missing singleton
	# does not abort _ready.
	if GameManager and GameManager.has_method("game_started"):
		GameManager.game_started.connect(_on_game_started)
	if GameManager and GameManager.has_method("game_ended"):
		GameManager.game_ended.connect(_on_game_ended)
	if GameManager and GameManager.has_method("game_state_changed"):
		GameManager.game_state_changed.connect(_on_game_state_changed)

func _on_game_state_changed(state: GameManager.GameState) -> void:
	match state:
		GameManager.GameState.PLAYING:
			_show_game_ui()
		GameManager.GameState.MAIN_MENU:
			_hide_game_ui()

func _on_game_started() -> void:
	_initialize_ui()

func _on_game_ended() -> void:
	_cleanup_ui()

## Initialize game UI
func _initialize_ui() -> void:
	if _initialized:
		return
	_initialized = true

	# Create TargetTooltip
	_tooltip = TargetTooltip.new()
	_tooltip.name = "TargetTooltip"

	# Add to root (CanvasLayer would be better, but keeping simple)
	get_tree().root.add_child(_tooltip)

	GameLog.debug("UIManager: Initialized TargetTooltip")

## Show game UI elements
func _show_game_ui() -> void:
	if not _initialized:
		_initialize_ui()

	if _tooltip:
		_tooltip.show()

## Hide game UI elements
func _hide_game_ui() -> void:
	if _tooltip:
		_tooltip.hide()

## Cleanup UI elements
func _cleanup_ui() -> void:
	if _tooltip:
		_tooltip.queue_free()
		_tooltip = null
	_initialized = false

func get_tooltip():
	return _tooltip

## Show tooltip with target (convenience method)
func show_target_tooltip(target_id: String) -> void:
	if not _tooltip:
		return

	var target: Variant = TargetingManager.get_target_info(target_id)
	if target:
		_tooltip.show()
		_tooltip._refresh_tooltip()

## Hide tooltip (convenience method)
func hide_target_tooltip() -> void:
	if _tooltip:
		_tooltip.hide()
