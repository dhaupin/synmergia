## LODManager - Level of Detail manager with predictive prefetch.
##
## Runs at 10Hz (every 100ms) to classify chunks as HOT/WARM/COLD
## based on player AOI and Markov predictions.
##
## Spec: labs/world-building.md sec.14.3, sec.14.4, sec.18.5
extends Node

const Entity = preload("res://core/entities/entity.gd")
const SpatialFragmenterScript = preload("res://core/frame/geometry/spatial_fragmenter.gd")
const MarkovScript = preload("res://core/frame/srv/markov.gd")

## LOD states
enum LODState {
	COLD,   # Not loaded, no player near or predicted
	WARM,   # Predicted to be needed within 5s
	HOT,    # In at least one player's AOI
}

## Chunk quantization (matches EntityService: 100 world units per cell)
const CHUNK_SIZE: float = 100.0

## Default AOI radius for players
const DEFAULT_AOI_RADIUS: float = 500.0

## Prediction horizon for WARM classification (5 seconds at 10Hz)
const PREDICTION_HORIZON_TICKS: int = 50

## Demotion idle time: WARM -> COLD after 5s with no prediction
const WARM_DEMOTION_TICKS: int = 50

## HOT demotion idle time: HOT -> WARM after 30s idle
const HOT_DEMOTION_TICKS: int = 300

## LOD tick interval (10Hz = 100ms)
const LOD_TICK_INTERVAL_MS: float = 100.0

## Max chunks to track per player (memory bound)
const MAX_CHUNKS_PER_PLAYER: int = 100


signal lod_tick_completed(tick_number: int, stats: Dictionary)
signal chunk_promoted(chunk_key: String, from_state: LODState, to_state: LODState)
signal chunk_demoted(chunk_key: String, from_state: LODState, to_state: LODState)
signal player_chunk_tracking_changed(player_id: String, chunk_key: String, state: LODState)


var _tick_number: int = 0
var _is_running: bool = false
var _lod_timer: Timer = null

## Per-player tracking
var _player_data: Dictionary = {}  # player_id -> PlayerLODData

## Chunk state tracking
var _chunk_states: Dictionary = {}  # chunk_key -> ChunkLODState

## Markov predictor instance
var _markov = null

## Spatial fragmenter instance
var _spatial_fragmenter = null


class PlayerLODData:
	var player_id: String = ""
	var current_chunk_key: String = ""
	var aoi_center: Vector3 = Vector3.ZERO
	var aoi_radius: float = DEFAULT_AOI_RADIUS
	var tracked_chunks: Dictionary = {}  # chunk_key -> LODState
	var last_aoi_update_tick: int = 0
	var predicted_chunks: Array[String] = []  # From Markov predictor
	var prediction_tick: int = 0


	func _init(p_player_id: String) -> void:
		player_id = p_player_id


class ChunkLODState:
	var chunk_key: String = ""
	var state: LODState = LODState.COLD
	var players_hot: Array[String] = []   # Players with this chunk in AOI
	var players_warm: Array[String] = []  # Players with this chunk predicted
	var last_hot_tick: int = 0
	var last_warm_tick: int = 0
	var last_state_change_tick: int = 0


	func _init(p_chunk_key: String) -> void:
		chunk_key = p_chunk_key
		last_state_change_tick = 0


func _ready() -> void:
	GameLog.info("LODManager: Ready")
	_markov = MarkovScript.new()
	if SpatialFragmenterScript:
		_spatial_fragmenter = SpatialFragmenterScript.new()
		GameLog.debug("LODManager: SpatialFragmenter initialized")
	else:
		GameLog.warn("LODManager: SpatialFragmenterScript not available; chunk boundaries disabled")
	_start_lod_loop()


func _exit_tree() -> void:
	_is_running = false
	if _lod_timer:
		_lod_timer.stop()
		_lod_timer.queue_free()
		_lod_timer = null
	GameLog.info("LODManager: Stopped")


func _start_lod_loop() -> void:
	_lod_timer = Timer.new()
	_lod_timer.name = "LODLoop"
	_lod_timer.wait_time = LOD_TICK_INTERVAL_MS / 1000.0
	_lod_timer.timeout.connect(_on_lod_tick)
	_lod_timer.one_shot = false
	add_child(_lod_timer)
	_lod_timer.start()
	_is_running = true
	GameLog.info("LODManager: LOD loop started at %.1fms interval (%.1fHz)" % [LOD_TICK_INTERVAL_MS, 1000.0 / LOD_TICK_INTERVAL_MS])


## Main LOD tick - runs at 10Hz
func _on_lod_tick() -> void:
	_tick_number += 1

	# Update player data (AOI, current chunk)
	_update_all_players()

	# Get predictions from Markov for each player
	_update_predictions()

	# Classify all chunks based on player AOI and predictions
	_classify_chunks()

	# Apply promotions and demotions
	_apply_lod_changes()

	# Emit stats
	var stats := _compute_stats()
	lod_tick_completed.emit(_tick_number, stats)
	GameLog.debug("LODManager: Tick %d complete. Stats: %s" % [_tick_number, stats])


## Update all tracked players' AOI and current chunk
func _update_all_players() -> void:
	if EntityService == null:
		return

	var players := EntityService.get_all_players()
	for player in players:
		if not is_instance_valid(player):
			continue
		# Players torn out of the tree by a scene change still sit in the
		# registry for a frame or two; global_position on them throws
		# "!is_inside_tree()" engine errors every tick (and once segfaulted
		# the engine mid scene-change).
		if player is Node3D and not player.is_inside_tree():
			continue
		_update_player(player)


## Update a single player's data
func _update_player(player) -> void:
	var player_id: String = player.entity_id
	var pos: Vector3 = player.global_position

	var player_data := _get_or_create_player_data(player_id)
	player_data.aoi_center = pos
	player_data.last_aoi_update_tick = _tick_number

	# Compute current chunk key
	var chunk_key := _position_to_chunk_key(pos)

	# Record movement for Markov learning
	if _markov and player_data.current_chunk_key != "" and player_data.current_chunk_key != chunk_key:
		_markov.record_movement(player_id, player_data.current_chunk_key, chunk_key)

	player_data.current_chunk_key = chunk_key

	# Update tracked chunks for this player
	_update_player_tracked_chunks(player_data)


## Update tracked chunks for a player based on AOI
func _update_player_tracked_chunks(player_data: PlayerLODData) -> void:
	var aoi_min_x := int((player_data.aoi_center.x - player_data.aoi_radius) / CHUNK_SIZE)
	var aoi_max_x := int((player_data.aoi_center.x + player_data.aoi_radius) / CHUNK_SIZE)
	var aoi_min_z := int((player_data.aoi_center.z - player_data.aoi_radius) / CHUNK_SIZE)
	var aoi_max_z := int((player_data.aoi_center.z + player_data.aoi_radius) / CHUNK_SIZE)

	var new_tracked: Dictionary = {}

	for x in range(aoi_min_x, aoi_max_x + 1):
		for z in range(aoi_min_z, aoi_max_z + 1):
			var y := 0
			var address: int = _spatial_fragmenter.make_address(x, y, z, 0, 0)
			var chunk_key: String = _spatial_fragmenter.generate_key(address)
			# Check if chunk center is within AOI radius
			var chunk_center_x := x * CHUNK_SIZE + CHUNK_SIZE * 0.5
			var chunk_center_z := z * CHUNK_SIZE + CHUNK_SIZE * 0.5
			var dist_sq := (chunk_center_x - player_data.aoi_center.x) ** 2 + (chunk_center_z - player_data.aoi_center.z) ** 2
			if dist_sq <= player_data.aoi_radius ** 2:
				new_tracked[chunk_key] = LODState.HOT

	# Add predicted chunks as WARM (if not HOT)
	for pred_key in player_data.predicted_chunks:
		if not new_tracked.has(pred_key):
			new_tracked[pred_key] = LODState.WARM

	player_data.tracked_chunks = new_tracked


## Get Markov predictions for all players
func _update_predictions() -> void:
	if _markov == null:
		return

	_markov.tick()

	for player_id in _player_data.keys():
		var player_data: PlayerLODData = _player_data[player_id]
		if player_data.current_chunk_key == "":
			continue

		# Get predictions
		var predictions: Array = _markov.predict_next(player_id)
		var new_predicted: Array[String] = []
		for pred in predictions:
			new_predicted.append(pred["chunk_key"])
		player_data.predicted_chunks = new_predicted
		player_data.prediction_tick = _tick_number


## Classify all chunks based on player tracking
func _classify_chunks() -> void:
	# Reset all chunk state player lists
	for chunk_state in _chunk_states.values():
		chunk_state.players_hot.clear()
		chunk_state.players_warm.clear()

	# Aggregate player tracking
	for player_id in _player_data.keys():
		var player_data: PlayerLODData = _player_data[player_id]
		for chunk_key in player_data.tracked_chunks.keys():
			var lod_state: LODState = player_data.tracked_chunks[chunk_key]
			var chunk_state: ChunkLODState = _get_or_create_chunk_state(chunk_key)

			if lod_state == LODState.HOT:
				if not chunk_state.players_hot.has(player_id):
					chunk_state.players_hot.append(player_id)
				chunk_state.last_hot_tick = _tick_number
			elif lod_state == LODState.WARM:
				if not chunk_state.players_warm.has(player_id):
					chunk_state.players_warm.append(player_id)
				chunk_state.last_warm_tick = _tick_number


## Apply LOD state changes (promote/demote)
func _apply_lod_changes() -> void:
	var chunks_to_remove: Array[String] = []

	for chunk_key in _chunk_states.keys():
		var chunk_state: ChunkLODState = _chunk_states[chunk_key]
		var old_state: LODState = chunk_state.state
		var new_state := _compute_desired_lod(chunk_state)

		if new_state != old_state:
			chunk_state.state = new_state
			chunk_state.last_state_change_tick = _tick_number

			if new_state > old_state:
				chunk_promoted.emit(chunk_key, old_state, new_state)
			else:
				chunk_demoted.emit(chunk_key, old_state, new_state)

			# Notify per-player tracking changes
			for player_id in chunk_state.players_hot:
				player_chunk_tracking_changed.emit(player_id, chunk_key, new_state)
			for player_id in chunk_state.players_warm:
				player_chunk_tracking_changed.emit(player_id, chunk_key, new_state)

		# Clean up chunks with no tracking for too long
		if chunk_state.players_hot.is_empty() and chunk_state.players_warm.is_empty():
			var idle_ticks: int = _tick_number - chunk_state.last_state_change_tick
			if idle_ticks > HOT_DEMOTION_TICKS:
				chunks_to_remove.append(chunk_key)

	for key in chunks_to_remove:
		_chunk_states.erase(key)


## Compute desired LOD for a chunk based on player tracking
func _compute_desired_lod(chunk_state: ChunkLODState) -> LODState:
	# HOT: at least one player has this in AOI
	if not chunk_state.players_hot.is_empty():
		return LODState.HOT

	# WARM: predicted by at least one player
	if not chunk_state.players_warm.is_empty():
		return LODState.WARM

	# Check demotion timers
	var idle_ticks: int = _tick_number - chunk_state.last_state_change_tick

	if chunk_state.state == LODState.HOT:
		if idle_ticks > HOT_DEMOTION_TICKS:
			return LODState.WARM
	elif chunk_state.state == LODState.WARM:
		if idle_ticks > WARM_DEMOTION_TICKS:
			return LODState.COLD

	return chunk_state.state


## Compute and return current stats
func _compute_stats() -> Dictionary:
	var stats := {
		"tick": _tick_number,
		"players_tracked": _player_data.size(),
		"chunks_tracked": _chunk_states.size(),
		"hot_chunks": 0,
		"warm_chunks": 0,
		"cold_chunks": 0,
	}

	for chunk_state in _chunk_states.values():
		match chunk_state.state:
			LODState.HOT:
				stats["hot_chunks"] += 1
			LODState.WARM:
				stats["warm_chunks"] += 1
			LODState.COLD:
				stats["cold_chunks"] += 1

	return stats


## Get the current LOD state of a chunk
func get_chunk_lod(chunk_key: String) -> LODState:
	var chunk_state: ChunkLODState = _chunk_states.get(chunk_key)
	if chunk_state == null:
		return LODState.COLD
	return chunk_state.state


## Get all chunks in a given state
func get_chunks_by_state(state: LODState) -> Array[String]:
	var result: Array[String] = []
	for chunk_key in _chunk_states.keys():
		if _chunk_states[chunk_key].state == state:
			result.append(chunk_key)
	return result


## Get chunks tracked by a specific player
func get_player_chunks(player_id: String) -> Dictionary:
	var player_data: PlayerLODData = _player_data.get(player_id)
	if player_data == null:
		return {}
	return player_data.tracked_chunks.duplicate()


## Get current LOD tick number
func get_tick_number() -> int:
	return _tick_number


## Get the Markov predictor instance (public access)
func get_markov() -> Object:
	return _markov


## Register a player's movement for Markov learning
func record_movement(player_id: String, from_chunk_key: String, to_chunk_key: String) -> void:
	if _markov:
		_markov.record_movement(player_id, from_chunk_key, to_chunk_key)


## Force a chunk to be promoted (for testing or manual override)
func promote_chunk(chunk_key: String, target_state: LODState = LODState.HOT) -> void:
	var chunk_state: ChunkLODState = _get_or_create_chunk_state(chunk_key)
	var old_state: LODState = chunk_state.state
	if target_state > old_state:
		chunk_state.state = target_state
		chunk_state.last_state_change_tick = _tick_number
		chunk_promoted.emit(chunk_key, old_state, target_state)


## Force a chunk to be demoted
func demote_chunk(chunk_key: String, target_state: LODState = LODState.COLD) -> void:
	var chunk_state: ChunkLODState = _chunk_states.get(chunk_key)
	if chunk_state and target_state < chunk_state.state:
		var old_state: LODState = chunk_state.state
		chunk_state.state = target_state
		chunk_state.last_state_change_tick = _tick_number
		chunk_demoted.emit(chunk_key, old_state, target_state)


## Clear all tracking data
func clear_all() -> void:
	_player_data.clear()
	_chunk_states.clear()
	_tick_number = 0
	if _markov:
		_markov.clear_all()


## ============================================================================
## INTERNAL HELPERS
## ============================================================================

func _get_or_create_player_data(player_id: String) -> PlayerLODData:
	if not _player_data.has(player_id):
		_player_data[player_id] = PlayerLODData.new(player_id)
	return _player_data[player_id] as PlayerLODData


func _get_or_create_chunk_state(chunk_key: String) -> ChunkLODState:
	if not _chunk_states.has(chunk_key):
		_chunk_states[chunk_key] = ChunkLODState.new(chunk_key)
	return _chunk_states[chunk_key] as ChunkLODState


## Convert world position to chunk key (x,z)
func _position_to_chunk_key(pos: Vector3) -> String:
	if _spatial_fragmenter == null:
		return "0000-0000-0000-d0-f0"
	var x := int(floor(pos.x / CHUNK_SIZE))
	var y := int(floor(pos.y / CHUNK_SIZE))
	var z := int(floor(pos.z / CHUNK_SIZE))
	var address: int = _spatial_fragmenter.make_address(x, y, z, 0, 0)
	return _spatial_fragmenter.generate_key(address)


func get_chunk_key_from_position(pos: Vector3) -> String:
	return _position_to_chunk_key(pos)


## Convert chunk key to world position (center of chunk)
func _chunk_key_to_position(chunk_key: String) -> Vector3:
	var parts := chunk_key.split("-")
	if parts.size() < 3:
		return Vector3.ZERO
	var x: int = int("0x" + parts[0])
	var z: int = int("0x" + parts[2])
	return Vector3(
		x * CHUNK_SIZE + CHUNK_SIZE * 0.5,
		0,
		z * CHUNK_SIZE + CHUNK_SIZE * 0.5
	)


## Convert world position to SpatialFragmenter address
func _position_to_spatial_address(pos: Vector3, depth: int = 0, face: int = 0) -> int:
	if _spatial_fragmenter == null:
		return 0
	var x := int(floor(pos.x / CHUNK_SIZE))
	var y := int(floor(pos.y / CHUNK_SIZE))
	var z := int(floor(pos.z / CHUNK_SIZE))
	return _spatial_fragmenter.make_address(x, y, z, depth, face)
