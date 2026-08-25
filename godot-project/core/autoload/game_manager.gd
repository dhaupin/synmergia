## GameManager - Master game state controller
## Handles game state transitions and overall game flow
extends Node

signal game_state_changed(state: GameState)
signal paused
signal resumed
signal game_started
signal game_ended

enum GameState {
	LOADING,
	MAIN_MENU,
	CHARACTER_SELECT,
	PLAYING,
	PAUSED
}

var current_state: GameState = GameState.LOADING
var previous_state: GameState = GameState.LOADING
var is_paused: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Logger.info("GameManager initialized")
	
func _process(delta: float) -> void:
	if current_state == GameState.LOADING:
		_check_loading_complete()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if current_state == GameState.PLAYING:
			pause_game()
		elif current_state == GameState.PAUSED:
			resume_game()

func change_state(new_state: GameState) -> void:
	if new_state == current_state:
		return
	
	previous_state = current_state
	current_state = new_state
	
	Logger.info("Game state changed: %s → %s" % [GameState.keys()[previous_state], GameState.keys()[new_state]])
	game_state_changed.emit(new_state)
	
	match new_state:
		GameState.LOADING:
			_handle_loading_state()
		GameState.MAIN_MENU:
			_handle_main_menu_state()
		GameState.CHARACTER_SELECT:
			_handle_character_select_state()
		GameState.PLAYING:
			_handle_playing_state()
		GameState.PAUSED:
			pass  # Handled by pause_game/resume_game

func pause_game() -> void:
	if current_state != GameState.PLAYING:
		return
	
	is_paused = true
	get_tree().paused = true
	
	previous_state = current_state
	current_state = GameState.PAUSED
	
	Logger.info("Game paused")
	paused.emit()

func resume_game() -> void:
	if current_state != GameState.PAUSED:
		return
	
	is_paused = false
	get_tree().paused = false
	
	current_state = GameState.PLAYING
	
	Logger.info("Game resumed")
	resumed.emit()

func start_game() -> void:
	Logger.info("Starting game...")
	change_state(GameState.PLAYING)
	game_started.emit()

func end_game() -> void:
	Logger.info("Ending game...")
	change_state(GameState.MAIN_MENU)
	game_ended.emit()

func _check_loading_complete() -> void:
	# Override in subclasses to check for resource loading
	pass

func _handle_loading_state() -> void:
	Logger.info("Loading resources...")

func _handle_main_menu_state() -> void:
	get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")

func _handle_character_select_state() -> void:
	get_tree().change_scene_to_file("res://ui/menus/character_select.tscn")

func _handle_playing_state() -> void:
	Logger.info("Entering gameplay")

func is_gameplay_active() -> bool:
	return current_state == GameState.PLAYING and not is_paused

func get_state() -> GameState:
	return current_state
