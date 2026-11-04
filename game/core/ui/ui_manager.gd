## UIManager - Manages game UI elements including targeting UI
## Handles instantiation and lifecycle of UI components
extends Node

# TargetTooltip is not an autoload (class_name only). UIManager
# calls TargetTooltip.new() in _ready(), which requires the
# class_name registered at parse time. Preload it here.
const TargetTooltip = preload("res://ui/targeting/target_tooltip.gd")

var _tooltip = null
var _initialized: bool = false

## Runtime autoload lookups (script-mode-safe: the bare identifiers fail
## to compile when autoloads are absent, e.g. --script runs / test_islands).
func _gm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameManager")) if tree and tree.root else null

func _tm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("TargetingManager")) if tree and tree.root else null

func _glog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null

func _ready() -> void:
	# Connect to game state changes. GameManager may not be ready yet
	# (autoload ordering); guard each access so a missing singleton
	# does not abort _ready.
	#
	# These are SIGNALS, not methods: has_method() is always false for a
	# signal name, so the old guard silently skipped every connect and
	# UIManager never initialized (the TargetTooltip island was never
	# created). Guard with has_signal() and de-dupe with is_connected().
	var gm := _gm()
	if gm == null:
		return
	if gm.has_signal("game_started") and not gm.game_started.is_connected(_on_game_started):
		gm.game_started.connect(_on_game_started)
	if gm.has_signal("game_ended") and not gm.game_ended.is_connected(_on_game_ended):
		gm.game_ended.connect(_on_game_ended)
	if gm.has_signal("game_state_changed") \
			and not gm.game_state_changed.is_connected(_on_game_state_changed):
		gm.game_state_changed.connect(_on_game_state_changed)

func _on_game_state_changed(state: int) -> void:
	# GameState is an inner enum on GameManager's script; read it off the
	# instance so this file never needs GameManager's class at parse time.
	# (A `match` with enum values as bare variables would bind them as
	# catch-all patterns, so compare with ==.)
	var gm := _gm()
	if gm == null:
		return
	if state == gm.GameState.PLAYING:
		_show_game_ui()
	elif state == gm.GameState.MAIN_MENU:
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

	if _glog():
		_glog().debug("UIManager: Initialized TargetTooltip")

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

## Show tooltip with target (convenience method). Targets are held by
## TargetingManager; this shows the panel only when the requested id IS
## the current target (the previous body called get_target_info(), a
## method TargetingManager never had, so the call always errored).
func show_target_tooltip(target_id: String) -> void:
	if _tooltip == null:
		return
	var tm := _tm()
	if tm == null or not tm.has_method("get_current_target"):
		return
	var target = tm.get_current_target()
	if target == null or target.id != target_id:
		return
	_tooltip.show()
	if _tooltip.has_method("_refresh_tooltip"):
		_tooltip._refresh_tooltip()

## Hide tooltip (convenience method)
func hide_target_tooltip() -> void:
	if _tooltip:
		_tooltip.hide()
