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

var selected_character_data: Resource = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameLog.info("GameManager initialized")
	
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
	
	GameLog.info("Game state changed: %s → %s" % [GameState.keys()[previous_state], GameState.keys()[new_state]])
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
	
	GameLog.info("Game paused")
	paused.emit()

func resume_game() -> void:
	if current_state != GameState.PAUSED:
		return
	
	is_paused = false
	get_tree().paused = false
	
	current_state = GameState.PLAYING
	
	GameLog.info("Game resumed")
	resumed.emit()

func start_game() -> void:
	GameLog.info("Starting game...")
	change_state(GameState.PLAYING)
	game_started.emit()

func end_game() -> void:
	GameLog.info("Ending game...")
	change_state(GameState.MAIN_MENU)
	game_ended.emit()

func _check_loading_complete() -> void:
	# Override in subclasses to check for resource loading
	pass

func _handle_loading_state() -> void:
	GameLog.info("Loading resources...")

func _handle_main_menu_state() -> void:
	get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")

func _handle_character_select_state() -> void:
	get_tree().change_scene_to_file("res://ui/menus/character_select.tscn")

func _handle_playing_state() -> void:
	GameLog.info("Entering gameplay")
	_initialize_world_services()
	# Load the playable world scene, replacing current scene
	get_tree().change_scene_to_file("res://scenes/world_playable.tscn")
	GameLog.info("World scene loaded")

func _initialize_world_services() -> void:
	# Only initialize once
	if _world_initialized:
		return
	_world_initialized = true
	
	GameLog.info("GameManager: Initializing world services...")
	
	# Initialize world (loads zones, factions)
	if WorldService:
		WorldService.initialize_world()
	
	# Initialize player tracking in ShardManager
	if ShardManager:
		ShardManager.start_server()
	
	# Connect EntityService player tracking to ShardManager
	if EntityService:
		EntityService.player_joined.connect(_on_player_joined)
		EntityService.player_left.connect(_on_player_left)
	
	GameLog.info("GameManager: World services initialized")

func _on_player_joined(player, _metadata: EventHub.SpawnMetadata) -> void:
	if ShardManager:
		ShardManager.player_connected()
	GameLog.info("Player joined: %s" % player.display_name)

func _on_player_left(player, _metadata: EventHub.SpawnMetadata) -> void:
	if ShardManager:
		ShardManager.player_disconnected()
	GameLog.info("Player left: %s" % player.display_name)

var _world_initialized := false

func is_gameplay_active() -> bool:
	return current_state == GameState.PLAYING and not is_paused

func get_state() -> GameState:
	return current_state
