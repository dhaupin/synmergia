## GameManager - Master game state controller
##
## Handles game state transitions and overall game flow
extends Node


const SpawnMetadata = preload("res://core/events/spawn_metadata.gd")
const CharacterData = preload("res://core/schemas/character_data.gd")
# LoadingUI loaded at runtime to avoid preload issues

## Defensive logger - get GameLog at runtime to avoid compile-time circular deps
func _log(level: int, msg: String) -> void:
	var log_node = get_node_or_null("/root/GameLog")
	if log_node and log_node.has_method("info"):
		match level:
			0: log_node.debug(msg)
			1: log_node.info(msg)
			2: log_node.warn(msg)
			3: log_node.error(msg)

signal game_state_changed(state: GameState)
signal paused
signal resumed
signal game_started
signal game_ended
signal player_entered_world(player_id: String, character_data: Resource)

enum GameState {
	LOADING,
	LOGIN,
	MAIN_MENU,
	LOBBY,
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
	if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").info("GameManager initialized")

func _process(delta: float) -> void:
	if current_state == GameState.LOADING:
		_check_loading_complete()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if current_state == GameState.PLAYING:
			# ESC is also the "close top panel" key. _input runs BEFORE
			# the unhandled-input phase where HudHotkeys lives, so an
			# immediate pause here froze the game with panels open (they
			# could never receive ESC). Defer one frame: if a panel closes
			# on ESC this frame, the pause is skipped; if nothing is open,
			# the game pauses (Esc-to-pause preserved).
			var open: Array = MenuManager.get_open_panels() if MenuManager.instance != null else []
			if not open.is_empty():
				return  # HudHotkeys closes the top panel via unhandled input
			pause_game()
		elif current_state == GameState.PAUSED:
			resume_game()

func change_state(new_state: GameState) -> void:
	if new_state == current_state:
		return

	previous_state = current_state
	current_state = new_state

	if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").info("Game state changed: %s -> %s" % [GameState.keys()[previous_state], GameState.keys()[new_state]])
	game_state_changed.emit(new_state)

	match new_state:
		GameState.LOADING:
			_handle_loading_state()
		GameState.LOGIN:
			_handle_login_state()
		GameState.MAIN_MENU:
			_handle_main_menu_state()
		GameState.LOBBY:
			_handle_lobby_state()
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

	if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").info("Game paused")
	paused.emit()

func resume_game() -> void:
	if current_state != GameState.PAUSED:
		return

	is_paused = false
	get_tree().paused = false

	current_state = GameState.PLAYING

	if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").info("Game resumed")
	resumed.emit()

func start_game() -> void:
	if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").info("Starting game...")
	change_state(GameState.PLAYING)
	game_started.emit()

func end_game() -> void:
	if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").info("Ending game...")
	change_state(GameState.MAIN_MENU)
	game_ended.emit()

func _check_loading_complete() -> void:
	# Override in subclasses to check for resource loading
	pass

func _handle_loading_state() -> void:
	if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").info("Loading resources...")
	var overlay := _ensure_boot_loading_overlay()
	if overlay != null:
		overlay.show_loading("Loading resources...")
		await get_tree().process_frame
		overlay.hide_loading()

func _handle_login_state() -> void:
	_show_loading_and_change_scene("res://ui/menus/login.tscn", "Loading login screen...")

func _handle_main_menu_state() -> void:
	_show_loading_and_change_scene("res://ui/menus/main_menu.tscn", "Loading main menu...")

func _handle_lobby_state() -> void:
	var _ls = get_node_or_null("/root/LoginService"); if not _ls or not _ls.is_logged_in():
		# Defensive: route to login if state machine was reached without auth
		if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").warn("GameManager: LOBBY reached without login, redirecting")
		change_state(GameState.LOGIN)
		return
	_show_loading_and_change_scene("res://ui/menus/lobby.tscn", "Loading lobby...")

func _handle_character_select_state() -> void:
	if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").info("Loading character_select scene...")
	_show_loading_and_change_scene("res://ui/menus/character_select.tscn", "Loading character select...")

func _handle_playing_state() -> void:
	if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").info("Entering gameplay")
	_initialize_world_services()
	# Load the playable world scene, replacing current scene.
	# Map shape chooses the world (world-building.md sec 1.6: shape is a
	# parameter): planar (default) = the classic world, spherical = the
	# spherical world scene (globe prototype; the 20 km planet later).
	var WorldShapeResolver = load("res://core/frame/math/world_shape.gd")
	var world_scene: String = "res://scenes/world_playable.tscn"
	if WorldShapeResolver.is_spherical():
		world_scene = "res://scenes/worlds/globe_world.tscn"
		if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").info("Spherical world shape: loading globe scene")
	# Skip 3D scene change in headless mode (no rendering context available)
	var is_headless := OS.has_feature("headless") or DisplayServer.get_name() == "headless"
	if is_headless:
		if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").info("Headless mode: skipping world scene load")
	else:
		_show_loading_and_change_scene(world_scene, "Loading world...")
		if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").info("World scene loaded")

	# Emit player_entered_world for services like StarterKitService
	if selected_character_data:
		var cd := selected_character_data as CharacterData
		var player_id := cd.character_id if cd else ""
		if not player_id.is_empty():
			notify_player_entered_world(player_id, selected_character_data)

## Emit player_entered_world exactly once per player per boot. Both the
## login flow and direct world_playable scene runs route through here so
## services listening on this signal (StarterKitService, the achievement
## onboarding chain) never double-fire.
var _entered_world_ids: Dictionary = {}

func notify_player_entered_world(player_id: String, character_data = null) -> void:
	if player_id.is_empty():
		return
	if _entered_world_ids.has(player_id):
		return
	_entered_world_ids[player_id] = true
	player_entered_world.emit(player_id, character_data)
	if get_node_or_null("/root/GameLog"):
		get_node_or_null("/root/GameLog").info("Emitted player_entered_world for: %s" % player_id)

## Play-day feedback #1: LOADING SCREENS. The old path read the static
## LoadingUI.instance -- which lives INSIDE hud_layer.tscn, i.e. inside
## the scene being replaced -- so it was null exactly when a loading
## screen is needed (character select -> world). The boot overlay is a
## persistent root-level CanvasLayer (layer 100, above every HUD): it
## survives scene changes and shows for every transition.
var _loading_layer: CanvasLayer = null
var _loading_overlay: Control = null

func _ensure_boot_loading_overlay() -> Control:
	if _loading_overlay != null and is_instance_valid(_loading_overlay):
		return _loading_overlay
	if _loading_layer == null or not is_instance_valid(_loading_layer):
		_loading_layer = CanvasLayer.new()
		_loading_layer.name = "BootLoadingLayer"
		_loading_layer.layer = 100
		get_tree().root.add_child(_loading_layer)
	var LUI = load("res://ui/components/loading_ui.gd")
	if LUI == null:
		return null
	_loading_overlay = LUI.new()
	_loading_overlay.name = "BootLoadingOverlay"
	_loading_layer.add_child(_loading_overlay)
	return _loading_overlay

func _show_loading_and_change_scene(scene_path: String, status_text: String) -> void:
	var overlay := _ensure_boot_loading_overlay()
	if overlay != null:
		overlay.show_loading(status_text)
		await get_tree().process_frame
	var err = get_tree().change_scene_to_file(scene_path)
	if err != OK:
		if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").error("Failed to load %s: %s" % [scene_path, err])
	if overlay != null:
		await get_tree().process_frame
		overlay.hide_loading()

func _initialize_world_services() -> void:
	# Only initialize once
	if _world_initialized:
		return
	_world_initialized = true

	if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").info("GameManager: Initializing world services...")

	# Initialize world (loads zones, factions)
	var _ws = get_node_or_null("/root/WorldService"); if _ws:
		_ws.initialize_world()

	# Initialize player tracking in ShardManager
	if ShardManager:
		ShardManager.start_server()

	# Connect EntityService player tracking to ShardManager
	if EntityService:
		EntityService.player_joined.connect(_on_player_joined)
		EntityService.player_left.connect(_on_player_left)

	if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").info("GameManager: World services initialized")

func _on_player_joined(player, _metadata: SpawnMetadata) -> void:
	if ShardManager:
		ShardManager.player_connected()
	if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").info("Player joined: %s" % player.display_name)

func _on_player_left(player, _metadata: SpawnMetadata) -> void:
	if ShardManager:
		ShardManager.player_disconnected()
	if get_node_or_null("/root/GameLog"): get_node_or_null("/root/GameLog").info("Player left: %s" % player.display_name)

var _world_initialized := false

func is_gameplay_active() -> bool:
	return current_state == GameState.PLAYING and not is_paused

func get_state() -> GameState:
	return current_state
