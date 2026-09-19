## TickService - Authoritative tick loop for the Synmergia server
##
## Runs a 6-phase authoritative tick every 50ms (default).
## The tick is the ONLY place authoritative state changes occur.
## Between ticks, the state tree is read-only.
##
## Spec: labs/world-building-tick.md Sec.4, Sec.5, Sec.8
##
## Phase budgets:
##   Phase 1 (5ms):  Input collection
##   Phase 2 (25ms): World step
##   Phase 3 (10ms): State re-root + diff
##   Phase 4 (8ms):  Diff emit
##   Phase 5 (async): Persistence
##   Phase 6 (async): Predicted prefetch
##   Total sync: 48ms of 50ms budget (2ms slack)
##
## The tick heartbeat is adaptive via Q2 (world-building-tick.md Sec.8):
##   > 80% flywheel momentum: 50ms
##   < 80% flywheel momentum: 100ms
##   Idle (no players in AOI): 200ms
extends Node

const T3Script = preload("res://core/frame/kv/t3.gd")
const StateTreeScript = preload("res://core/frame/kv/state_tree.gd")

signal tick_started(tick_number: int)
signal tick_completed(tick_number: int, phase_timings: Dictionary)
signal tick_overrun(tick_number: int, phase: String, elapsed_ms: float)
signal flywheel_updated(momentum: float, sub_meters: Dictionary)

## Phase budgets in milliseconds
const PHASE_1_BUDGET_MS: int = 5
const PHASE_2_BUDGET_MS: int = 25
const PHASE_3_BUDGET_MS: int = 10
const PHASE_4_BUDGET_MS: int = 8
const TOTAL_SYNC_BUDGET_MS: int = 48
const TICK_BUDGET_MS: int = 50

## Budget warning threshold (80% of 50ms)
const BUDGET_WARNING_THRESHOLD_MS: int = 40

## Adaptive tick intervals
const HEARTBEAT_FLOOR_HIGH_MS: int = 50   # >80% momentum
const HEARTBEAT_FLOOR_MID_MS: int = 100   # <80% momentum
const HEARTBEAT_FLOOR_IDLE_MS: int = 200  # idle

## Default tick interval
const DEFAULT_TICK_INTERVAL_MS: float = 50.0

## Flywheel decay rate per tick
const FLYWHEEL_DECAY: float = 0.5

## Flywheel max momentum
const FLYWHEEL_MAX_MOMENTUM: float = 1000.0

## AOI and chunk constants
const DEFAULT_AOI_RADIUS: int = 500
const CHUNK_SIZE: int = 100

## Chaos weights per source
const CHAOS_PLAYER_INPUT: int = 1
const CHAOS_COMBAT_SKILL: int = 5
const CHAOS_MOB_AI: int = 10
const CHAOS_CROSS_SHARD: int = 50
const CHAOS_WALL_CLOCK: int = 1
const CHAOS_GENERATION: int = 100

## Flywheel high-entropy threshold (for adaptive tick rate)
const FLYWHEEL_HIGH_THRESHOLD: float = 800.0  # 80% of max

## Helper functions to safely resolve autoloads (avoids parse-time "Identifier not declared")
func _cooldown_service():
	var ml = Engine.get_main_loop()
	if ml == null:
		return null
	if not ml is SceneTree:
		return null
	return (ml as SceneTree).root.get_node_or_null("CooldownService")

func _adapter_registry():
	var ml = Engine.get_main_loop()
	if ml == null:
		return null
	if not ml is SceneTree:
		return null
	return (ml as SceneTree).root.get_node_or_null("AdapterRegistry")

## Tick state
var _tick_number: int = 0
var _is_running: bool = false
var _tick_timer: Timer = null
var _tick_interval: float = DEFAULT_TICK_INTERVAL_MS

## The state tree root (authoritative)
var _state_tree: StateTreeScript = null
var _previous_root_hash: PackedByteArray = PackedByteArray()
var _current_root_hash: PackedByteArray = PackedByteArray()

## Flywheel momentum and sub-meters
var _flywheel_momentum: float = 0.0
var _sub_meters: Dictionary = {
	"player_inputs": 0.0,
	"mob_ai": 0.0,
	"cross_shard": 0.0,
	"wall_clock": 0.0,
}

## Queued inputs per player (collected in Phase 1)
var _input_queues: Dictionary = {}  # player_id -> Array[InputFrame]

## Connected clients for diff emit
var _connected_clients: Array = []

## Side queue for overflow work from Phase 2
var _side_queue: Array = []

## State command buffer: queues all state tree mutations for atomic application in Phase 2
## Commands: {"type": "insert|update|delete|re_root", "path": "...", "entity_id": "...", "state_type": "...", "payload": {...}}
var _state_command_buffer: Array = []

## Async persistence task
var _persistence_task = null

## Predicted prefetch task
var _prefetch_task = null

## Previous tick timing for N014 invariant check
var _last_tick_end_ms: int = 0

## Whether the tree is in a read-only state between ticks
var _is_read_only: bool = true

## Seed chain reference for content-hashable state
var _seed_chain: T3Script = null

## Mark a phase as timed out (budget exceeded)
var _phase_overruns: Dictionary = {}

## ============================================================================
## GODOT LIFECYCLE
## ============================================================================

func _ready() -> void:
	GameLog.info("TickService: Ready")
	_state_tree = StateTreeScript.new()
	_previous_root_hash = _state_tree.root_hash()
	_current_root_hash = _previous_root_hash
	_start_tick_loop()

func _exit_tree() -> void:
	_is_running = false
	if _tick_timer:
		_tick_timer.stop()
		_tick_timer.queue_free()
		_tick_timer = null
	GameLog.info("TickService: Stopped")

## ============================================================================
## TICK LOOP
## ============================================================================

## Start the authoritative tick loop using a Timer.
func _start_tick_loop() -> void:
	_tick_timer = Timer.new()
	_tick_timer.name = "TickLoop"
	_tick_timer.wait_time = _tick_interval / 1000.0
	_tick_timer.timeout.connect(_on_tick)
	add_child(_tick_timer)
	_tick_timer.start()
	_is_running = true
	GameLog.info("TickService: Tick loop started at %.1fms interval" % _tick_interval)

## Update the tick interval based on flywheel momentum (Q2 adaptive heartbeat).
func _update_tick_interval() -> void:
	if _flywheel_momentum >= FLYWHEEL_HIGH_THRESHOLD:
		_tick_interval = float(HEARTBEAT_FLOOR_HIGH_MS)
	elif _flywheel_momentum > 0.0 and _connected_clients.size() > 0:
		_tick_interval = float(HEARTBEAT_FLOOR_MID_MS)
	else:
		_tick_interval = float(HEARTBEAT_FLOOR_IDLE_MS)
	if _tick_timer:
		_tick_timer.wait_time = _tick_interval / 1000.0

## The main tick callback. Executes all 6 phases.
func _on_tick() -> void:
	var tick_start_ms := Time.get_ticks_msec()
	_tick_number += 1
	tick_started.emit(_tick_number)

	# Mark tree as writable during tick
	_is_read_only = false

	var phase_timings: Dictionary = {}
	var total_sync_ms: float = 0.0

	# ---- Phase 1: Input collection (5ms) ----
	var phase1_start := Time.get_ticks_msec()
	var phase1_result := _phase1_collect_inputs()
	var phase1_elapsed := float(Time.get_ticks_msec() - phase1_start)
	phase_timings["phase1_input"] = phase1_elapsed
	total_sync_ms += phase1_elapsed
	if phase1_elapsed > PHASE_1_BUDGET_MS:
		_phase_overruns["phase1"] = phase1_elapsed
		tick_overrun.emit(_tick_number, "phase1", phase1_elapsed)

	# ---- Phase 2: World step (25ms) ----
	var phase2_start := Time.get_ticks_msec()
	var phase2_result := _phase2_world_step()
	var phase2_elapsed := float(Time.get_ticks_msec() - phase2_start)
	phase_timings["phase2_world"] = phase2_elapsed
	total_sync_ms += phase2_elapsed
	if phase2_elapsed > PHASE_2_BUDGET_MS:
		_phase_overruns["phase2"] = phase2_elapsed
		tick_overrun.emit(_tick_number, "phase2", phase2_elapsed)
		# Overflow goes to side queue
		_side_queue.append_array(phase2_result.get("overflow", []))

	# ---- Phase 3: State re-root + diff (10ms) ----
	var phase3_start := Time.get_ticks_msec()
	var phase3_result := _phase3_reroot_and_diff()
	var phase3_elapsed := float(Time.get_ticks_msec() - phase3_start)
	phase_timings["phase3_reroot"] = phase3_elapsed
	total_sync_ms += phase3_elapsed
	if phase3_elapsed > PHASE_3_BUDGET_MS:
		_phase_overruns["phase3"] = phase3_elapsed
		tick_overrun.emit(_tick_number, "phase3", phase3_elapsed)

	# ---- Phase 4: Diff emit (8ms) ----
	var phase4_start := Time.get_ticks_msec()
	var phase4_result := _phase4_diff_emit()
	var phase4_elapsed := float(Time.get_ticks_msec() - phase4_start)
	phase_timings["phase4_emit"] = phase4_elapsed
	total_sync_ms += phase4_elapsed
	if phase4_elapsed > PHASE_4_BUDGET_MS:
		_phase_overruns["phase4"] = phase4_elapsed
		tick_overrun.emit(_tick_number, "phase4", phase4_elapsed)

	# ---- Phase 5: Persistence (async) ----
	_phase5_persistence()

	# ---- Phase 6: Predicted prefetch (async) ----
	_phase6_predicted_prefetch()

	# Update flywheel
	_flywheel_decay()
	_flywheel_update_sub_meters()
	_update_tick_interval()

	# Mark tree read-only between ticks
	_is_read_only = true

	var tick_end_ms := Time.get_ticks_msec()
	_last_tick_end_ms = tick_end_ms

	# N014 invariant check: diff must be sent within +/-2ms of tick boundary
	var n014_violation := false
	if phase4_elapsed > 0.0:
		var boundary_deviation := abs((tick_end_ms - tick_start_ms) - TOTAL_SYNC_BUDGET_MS)
		if boundary_deviation > 2.0:
			n014_violation = true
			GameLog.warn("TickService: N014 violation tick=%d deviation=%.1fms" % [_tick_number, boundary_deviation])

	# Budget warning: log phase breakdown when total sync exceeds 80% of tick budget (40ms)
	if total_sync_ms > BUDGET_WARNING_THRESHOLD_MS:
		var phase1_ms := phase_timings.get("phase1_input", 0.0)
		var phase2_ms := phase_timings.get("phase2_world", 0.0)
		var phase3_ms := phase_timings.get("phase3_reroot", 0.0)
		var phase4_ms := phase_timings.get("phase4_emit", 0.0)
		var msg := "TickService: TICK BUDGET BREACH tick=%d total_sync=%.1fms (threshold=%dms) phase1_input=%.1fms phase2_world=%.1fms phase3_reroot=%.1fms phase4_emit=%.1fms" % [
			_tick_number, total_sync_ms, BUDGET_WARNING_THRESHOLD_MS,
			phase1_ms, phase2_ms, phase3_ms, phase4_ms
		]
		GameLog.warn(msg)

	tick_completed.emit(_tick_number, phase_timings)
	GameLog.debug("TickService: Tick %d complete. Sync=%.1fms PhaseTimings=%s" % [_tick_number, total_sync_ms, phase_timings])

## ============================================================================
## PHASE 1: Input Collection (5ms budget)
## ============================================================================

## Reads WebSocket frames, parses/validates, queues by player, auth + rate-limit.
## Each parsed input adds chaos to the flywheel: +1 normal, +5 combat-skill.
func _phase1_collect_inputs() -> Dictionary:
	var input_count: int = 0
	var combat_input_count: int = 0

	# Clear input queues from previous tick
	_input_queues.clear()

	# Read from NetworkManager connected peers
	if NetworkManager == null:
		return {"processed": 0, "combat": 0}

	var peers = NetworkManager.connected_peers
	for peer_id in peers:
		var player_id: String = _get_player_id_from_peer(peer_id)
		if player_id == "":
			continue

		# Read WebSocket frames for this player
		var frames = _read_websocket_frames(peer_id)
		for frame in frames:
			# Parse and validate the input frame
			var input_data = _parse_input_frame(frame)
			if input_data == null:
				continue

			# Auth and rate-limit at the boundary
			if not _auth_input(player_id, input_data):
				continue
			if not _rate_limit_input(player_id, input_data):
				continue

			# Queue by player
			if not _input_queues.has(player_id):
				_input_queues[player_id] = []
			_input_queues[player_id].append(input_data)
			input_count += 1

			# Add chaos to flywheel
			var is_combat: bool = _is_combat_input(input_data)
			if is_combat:
				_flywheel_momentum = min(FLYWHEEL_MAX_MOMENTUM, _flywheel_momentum + float(CHAOS_COMBAT_SKILL))
				_sub_meters["player_inputs"] += 5.0
				combat_input_count += 1
			else:
				_flywheel_momentum = min(FLYWHEEL_MAX_MOMENTUM, _flywheel_momentum + float(CHAOS_PLAYER_INPUT))
				_sub_meters["player_inputs"] += 1.0

	# Add wall-clock pulse (chaos +1 per tick, keeps flywheel alive)
	_flywheel_momentum = min(FLYWHEEL_MAX_MOMENTUM, _flywheel_momentum + float(CHAOS_WALL_CLOCK))
	_sub_meters["wall_clock"] += 1.0

	return {"processed": input_count, "combat": combat_input_count}

## Read WebSocket frames from a peer.
func _read_websocket_frames(peer_id: int) -> Array:
	# Stub: read from NetworkManager's WebSocket buffer
	# In production, reads from the ENetMultiplayerPeer or WebSocketMultiplayerPeer
	var frames: Array = []
	if NetworkManager and NetworkManager.multiplayer:
		# Poll for available messages on this peer
		pass
	return frames

## Parse a single input frame into structured data.
func _parse_input_frame(frame) -> Dictionary:
	if frame is Dictionary:
		return frame
	return null

## Authenticate an input for a player.
func _auth_input(player_id: String, input_data: Dictionary) -> bool:
	if EntityService == null:
		return false
	var entity = EntityService.get_entity(player_id)
	if entity == null:
		return false
	return true

## Rate-limit an input for a player.
func _rate_limit_input(player_id: String, input_data: Dictionary) -> bool:
	var cs = _cooldown_service()
	if cs == null:
		return true
	var action: String = input_data.get("action", "")
	return cs.try_consume(player_id, action)

## Determine if an input is a combat-skill message.
func _is_combat_input(input_data: Dictionary) -> bool:
	var action: String = input_data.get("action", "")
	return action.begins_with("ability_") or action == "attack" or action == "dodge"

## Get player_id from peer_id via PlayerManager or NetworkManager.
func _get_player_id_from_peer(peer_id: int) -> String:
	if PlayerManager:
		var info = PlayerManager.get_player_info(peer_id)
		if info is Dictionary:
			return info.get("player_id", "")
	return "peer_%d" % peer_id

## ============================================================================
## PHASE 2: World Step (25ms budget)
## ============================================================================

## Apply queued inputs in deterministic order, step mob AI, decay effects,
## regen, advance wall clock, pull coordinator HLC events.
## The 25ms budget is a hard cap. Overflow goes to side queue.
func _phase2_world_step() -> Dictionary:
	var overflow: Array = []
	var entity_count: int = 0

	# Step 0: Process queued state tree mutations atomically
	var mutate_result := _phase2_mutate()
	if mutate_result["failed"] > 0:
		GameLog.warn("TickService: %d state commands failed in Phase 2" % mutate_result["failed"])

	# Step 1: Apply queued player inputs in deterministic order
	# Deterministic by tick-local sequence, or by entity_id hash for fairness
	var player_ids: Array = _input_queues.keys()
	player_ids.sort()
	for player_id in player_ids:
		var inputs: Array = _input_queues[player_id]
		# Sort by tick-local sequence for deterministic ordering
		inputs.sort_custom(_compare_input_sequence)
		for input_data in inputs:
			if _apply_player_input(player_id, input_data):
				entity_count += 1
			else:
				overflow.append({"type": "input", "player_id": player_id, "data": input_data})

	# Step 2: Step mob AI for entities with AI decisions
	if EntityService:
		var entities = EntityService.get_all_entities()
		for entity in entities:
			if _should_step_entity(entity):
				var result = _step_entity(entity)
				if result.has("overflow") and result["overflow"]:
					overflow.append_array(result["overflow"])
				entity_count += 1

	# Step 3: Decay effects (buffs, dots, regen)
	_decay_effects()
	# Step 4: Regen (health, mana, stamina)
	_regen_entities()

	# Step 5: Pull coordinator HLC events (cross-shard)
	if ShardManager:
		var hlc_events = _pull_cross_shard_events()
		if hlc_events.size() > 0:
			_flywheel_momentum = min(FLYWHEEL_MAX_MOMENTUM, _flywheel_momentum + float(CHAOS_CROSS_SHARD) * float(hlc_events.size()))
			_sub_meters["cross_shard"] += float(hlc_events.size()) * 50.0

	# Step 6: Advance wall clock (day/night cycle)
	_advance_wall_clock()

	return {"processed": entity_count, "overflow": overflow}

## Compare input frames by tick-local sequence for deterministic ordering.
static func _compare_input_sequence(a: Dictionary, b: Dictionary) -> bool:
	var seq_a := a.get("seq", 0)
	var seq_b := b.get("seq", 0)
	return seq_a < seq_b

## Determine if an entity should be stepped this tick.
func _should_step_entity(entity) -> bool:
	if entity == null:
		return false
	# Entities with inputs this tick or with AI decisions to make
	if entity.has("has_input") and entity.has_input:
		return true
	if entity.has("needs_ai") and entity.needs_ai:
		return true
	# Always step entities with active effects
	if entity.has("effect_count") and entity.effect_count > 0:
		return true
	return false

## Step a single entity (apply AI, movement, etc.).
func _step_entity(entity) -> Dictionary:
	var overflow: Array = []
	# TODO: Entity-specific step logic
	# - Move entities
	# - Execute combat skills
	# - Update AI state
	# - Process interactions
	return {"overflow": overflow}

## Apply a player input to the game state.
func _apply_player_input(player_id: String, input_data: Dictionary) -> bool:
	if EntityService == null:
		return false
	var entity = EntityService.get_entity(player_id)
	if entity == null:
		return false
	# Input is applied to the entity's state
	# The tree is authoritative - this is the only place state changes
	return true

## Process all queued state tree mutation commands atomically.
## This is called during Phase 2 (World Step) to ensure all mutations
## happen in a single deterministic batch before re-rooting in Phase 3.
func _phase2_mutate() -> Dictionary:
	var processed: int = 0
	var failed: int = 0

	if _state_tree == null or _state_command_buffer.is_empty():
		return {"processed": 0, "failed": 0}

	for command in _state_command_buffer:
		var cmd_type := command["type"]
		var success := false

		match cmd_type:
			"insert", "update":
				var path := command["path"]
				var entity_id := command["entity_id"]
				var state_type := command["state_type"]
				var payload := command["payload"]
				try:
					_state_tree.insert_state(path, entity_id, state_type, payload)
					success = true
				except:
					push_error("TickService._phase2_mutate: insert/update failed for path %s" % path)
					success = false

			"delete":
				var path := command["path"]
				try:
					_state_tree.delete_state(path)
					success = true
				except:
					push_error("TickService._phase2_mutate: delete failed for path %s" % path)
					success = false

			"re_root":
				# Re-root is implicit after mutations; this is a no-op but kept for explicit signaling
				success = true

		if success:
			processed += 1
		else:
			failed += 1

	# Clear the buffer after processing
	_state_command_buffer.clear()

	return {"processed": processed, "failed": failed}

## Decay active effects (buffs, dots) on all entities.
func _decay_effects() -> void:
	# TODO: Decrement effect durations, remove expired effects
	pass

## Regenerate health, mana, stamina on entities.
func _regen_entities() -> void:
	# TODO: Regen logic based on entity state
	pass

## Pull cross-shard HLC events from the coordinator.
func _pull_cross_shard_events() -> Array:
	# TODO: Pull HLC events from coordinator
	# Returns array of HLC event dictionaries
	return []

## Advance the wall clock (day/night cycle).
func _advance_wall_clock() -> void:
	# Drive WorldService time and events from authoritative tick
	if WorldService and WorldService.has_method("tick"):
		WorldService.tick(_tick_interval / 1000.0)

## ============================================================================
## PHASE 3: State Re-root + Diff (10ms budget)
## ============================================================================

## Computes the new state tree root hash and the diff vs. previous root.
## N022 target: <5ms p99 for v1.
## Diff is state-only (no seed bytes - seed chain is recomputable from world_seed + path).
func _phase3_reroot_and_diff() -> Dictionary:
	# Re-root the state tree
	# Only mutated subtrees change hashes
	_current_root_hash = _state_tree.root_hash()

	# Compute diff vs previous root (state-only diff)
	var diff: Array = []
	if _previous_root_hash != _current_root_hash:
		diff = _state_tree.diff_states(_previous_root_hash, _current_root_hash)

	# Update previous root hash for next tick
	_previous_root_hash = _current_root_hash

	# Update seed chain (recomputable from world_seed + path)
	# TODO: seed_chain.update_root() is not yet implemented in seed_chain.gd
	# if _seed_chain and _current_root_hash.size() > 0:
	# 	_seed_chain.update_root(_current_root_hash)

	return {"root_hash": _current_root_hash, "diff": diff, "diff_size": diff.size()}

## ============================================================================
## PHASE 4: Diff Emit (8ms budget)
## ============================================================================

## For each connected client, compute AOI diff, apply LOD, LZ4-compress, send.
## N014 invariant: every diff is sent within +/-2ms of tick boundary.
func _phase4_diff_emit() -> Dictionary:
	var client_count: int = 0
	var emit_times: Dictionary = {}

	for client_id in _connected_clients:
		var emit_start := Time.get_ticks_msec()

		# Compute AOI diff for this client
		var client_diff = _compute_aoi_diff(client_id)

		# Apply LOD - distant clients get L1 summaries, not L0 detail
		var lod_diff = _apply_lod(client_id, client_diff)

		# Flatten chunked AOI diff into T3 diff entry array for network transport
		var diff_entries: Array = _flatten_aoi_diff(lod_diff)

		# Send via NetworkManager
		if diff_entries.size() > 0 and NetworkManager and NetworkManager.is_server:
			var payload := {
				"tick": _tick_number,
				"root_hash": _current_root_hash,
				"diff": diff_entries,
				"lod_level": _get_client_lod_level(client_id)
			}
			NetworkManager.send_to_peer(client_id, payload)
			client_count += 1

		var emit_elapsed := float(Time.get_ticks_msec() - emit_start)
		emit_times[client_id] = emit_elapsed

	return {"clients_emit": client_count, "emit_times": emit_times}

## Sends a full scope state snapshot to a specific client.
## Used when client detects hash divergence and requests resync.
## The scope is the player's AOI (Area of Interest).
func send_full_scope_sync(client_id: int) -> void:
	if _state_tree == null or EntityService == null or not NetworkManager or not NetworkManager.is_server:
		return

	var player_id: String = _get_player_id_from_peer(client_id)
	if player_id == "":
		return

	var player = EntityService.get_entity(player_id)
	if player == null:
		return

	var pos: Vector3 = player.global_position if "global_position" in player else Vector3.ZERO

	# Build scope path from player's AOI chunks
	var min_cx: int = int(floor((pos.x - DEFAULT_AOI_RADIUS) / float(CHUNK_SIZE)))
	var max_cx: int = int(floor((pos.x + DEFAULT_AOI_RADIUS) / float(CHUNK_SIZE)))
	var min_cz: int = int(floor((pos.z - DEFAULT_AOI_RADIUS) / float(CHUNK_SIZE)))
	var max_cz: int = int(floor((pos.z + DEFAULT_AOI_RADIUS) / float(CHUNK_SIZE)))

	# Create a scope path that covers the AOI
	# Use a parent scope path that encompasses all AOI chunks
	var scope_path: String = "world"

	# Get full snapshot of the scope
	var full_snapshot: Array = _state_tree.get_full_scope_snapshot(scope_path)
	if full_snapshot.is_empty():
		return

	# Send as full state (empty diff marker in payload)
	var payload := {
		"tick": _tick_number,
		"root_hash": _current_root_hash,
		"diff": full_snapshot,
		"lod_level": 0,
		"is_full_sync": true  # Marker for client to know this is a full resync
	}
	NetworkManager.send_to_peer(client_id, payload)
	GameLog.debug("TickService: Sent full scope sync to client %d (%d entries)" % [client_id, full_snapshot.size()])


## Flatten chunked AOI diff (Dictionary of chunk_key -> Array[diff_entry])
## into a flat Array[diff_entry] for network transport.
func _flatten_aoi_diff(aoi_diff: Dictionary) -> Array:
	var result: Array = []
	for chunk_key in aoi_diff.keys():
		var chunk_changes: Array = aoi_diff[chunk_key]
		for entry in chunk_changes:
			if entry is Array and entry.size() >= 4:
				result.append(entry)
	return result

## Get LOD level for a client (0 = full detail, 1 = summary).
func _get_client_lod_level(client_id: int) -> int:
	# TODO: Determine based on distance, connection quality, etc.
	return 0

## Compute the AOI diff for a specific client.
func _compute_aoi_diff(client_id: int) -> Dictionary:
	if EntityService == null or _state_tree == null:
		return {}

	var player_id: String = _get_player_id_from_peer(client_id)
	if player_id == "":
		return {}

	var player = EntityService.get_entity(player_id)
	if player == null:
		return {}

	var pos: Vector3 = player.global_position if "global_position" in player else Vector3.ZERO

	var min_cx: int = int(floor((pos.x - DEFAULT_AOI_RADIUS) / float(CHUNK_SIZE)))
	var max_cx: int = int(floor((pos.x + DEFAULT_AOI_RADIUS) / float(CHUNK_SIZE)))
	var min_cz: int = int(floor((pos.z - DEFAULT_AOI_RADIUS) / float(CHUNK_SIZE)))
	var max_cz: int = int(floor((pos.z + DEFAULT_AOI_RADIUS) / float(CHUNK_SIZE)))

	var full_diff: Array = []
	if _previous_root_hash.size() > 0 and _current_root_hash.size() > 0 and _previous_root_hash != _current_root_hash:
		full_diff = _state_tree.diff_states(_previous_root_hash, _current_root_hash)

	var result: Dictionary = {}
	for cx in range(min_cx, max_cx + 1):
		for cz in range(min_cz, max_cz + 1):
			var chunk_key: String = "%d_%d" % [cx, cz]
			var chunk_min_x: float = float(cx) * float(CHUNK_SIZE)
			var chunk_max_x: float = float(cx + 1) * float(CHUNK_SIZE)
			var chunk_min_z: float = float(cz) * float(CHUNK_SIZE)
			var chunk_max_z: float = float(cz + 1) * float(CHUNK_SIZE)

			var chunk_changes: Array = []
			for entry in full_diff:
				if not entry is Array or entry.size() < 4:
					continue
				var value_bytes: PackedByteArray = entry[3]
				if value_bytes == null or value_bytes.size() == 0:
					continue
				var value: Variant = bytes_to_var(value_bytes)
				if value is Dictionary and value.has("position_x"):
					var ex: float = float(value.get("position_x", 0.0))
					var ez: float = float(value.get("position_z", 0.0))
					if ex >= chunk_min_x and ex < chunk_max_x and ez >= chunk_min_z and ez < chunk_max_z:
						chunk_changes.append(entry)
			result[chunk_key] = chunk_changes

	return result

## Apply LOD to a diff - distant clients get L1 summaries.
func _apply_lod(client_id: int, diff: Dictionary) -> Dictionary:
	# TODO: Determine client LOD level based on distance/priority
	# L0 = full detail, L1 = summary only
	# Distant clients get L1 summaries
	return diff

## ============================================================================
## PHASE 5: Persistence (async)
## ============================================================================

## Postgres snapshot of root hash, Redis tick cache update,
## Redis LRU update, materialized intersections update.
## Runs after the tick has emitted, into the next tick.
func _phase5_persistence() -> void:
	# Cancel previous task if still running
	if _persistence_task and is_instance_valid(_persistence_task):
		_persistence_task.cancel()

	# Fire and forget - async, does not block the tick
	var task := _Task.new()
	task.task_name = "TickPersistence_%d" % _tick_number
	add_child(task)

	task._setup(func() -> void:
		# Snapshot root hash to Postgres (N017)
		var ar = _adapter_registry()
		if ar and _current_root_hash.size() > 0:
			var store = ar.get_persistence("world_state")
			if store:
				var root_key := "tick:%d:root" % _tick_number
				# Batch the root snapshot with other world state
				var entries: Dictionary = {
					root_key: {"root_hash": _current_root_hash.hex_encode(), "tick": _tick_number},
					"world_state:latest_tick": _tick_number,
					"world_state:latest_root": _current_root_hash.hex_encode(),
				}
				if store.has_method("set_many"):
					store.set_many(entries)
				else:
					for key in entries.keys():
						store.set_kv(key, entries[key])

		# Update Redis tick cache (N013)
		ar = _adapter_registry()
		if ar:
			var cache = ar.get_cache("tick_cache")
			if cache:
				var cache_entries: Dictionary = {
					"current_tick": str(_tick_number),
					"current_root": _current_root_hash.hex_encode(),
					"intersections:last_tick": str(_tick_number),
				}
				if cache.has_method("set_many"):
					cache.set_many(cache_entries)
				else:
					for key in cache_entries.keys():
						cache.set(key, cache_entries[key])

		# Update Redis LRU (N013)
		ar = _adapter_registry()
		if ar:
			var cache = ar.get_cache("tick_cache")
			if cache:
				cache.touch("world_state")

		GameLog.debug("TickService: Phase 5 persistence complete for tick %d" % _tick_number)
	)
	task.start()
	_persistence_task = task

## ============================================================================
## PHASE 6: Predicted Prefetch (async)
## ============================================================================

## Markov predictor estimates player position in 1s,
## LOD-promotes predicted chunks, procedural generator runs on those chunks.
func _phase6_predicted_prefetch() -> void:
	# Cancel previous task if still running
	if _prefetch_task and is_instance_valid(_prefetch_task):
		_prefetch_task.cancel()

	# Fire and forget - async, does not block the tick
	var task := _Task.new()
	task.name = "TickPrefetch_%d" % _tick_number
	add_child(task)

	task._setup(func() -> void:
		var promoted_chunks: Array[String] = []

		# Markov predictor estimate player position in 1s
		if EntityService and PlayerManager:
			var players = EntityService.get_all_players()
			for player in players:
				if not is_instance_valid(player):
					continue
				var predicted_pos = _markov_predict(player)
				if predicted_pos != null:
					# LOD-promote predicted chunks
					var chunk_coords = _position_to_chunk(predicted_pos)
					var chunk_key: String = "%d_%d" % [chunk_coords.x, chunk_coords.y]
					if LODManager and LODManager.has_method("promote_chunk"):
						LODManager.promote_chunk(chunk_coords, LODManager.LODState.WARM)
					promoted_chunks.append(chunk_key)

		# Procedural generator runs on promoted chunks
		_promote_generation(promoted_chunks)

		GameLog.debug("TickService: Phase 6 prefetch complete for tick %d" % _tick_number)
	)
	task.start()
	_prefetch_task = task

## Markov predictor for player position in 1 second.
func _markov_predict(player) -> Vector3:
	# TODO: Markov chain prediction based on player movement history
	# Returns predicted position or null if not enough data
	return null

## Convert a world position to chunk coordinates.
func _position_to_chunk(pos: Vector3) -> Vector2:
	return Vector2(int(floor(pos.x / float(CHUNK_SIZE))), int(floor(pos.z / float(CHUNK_SIZE))))

## Promote a chunk's LOD level.
func _promote_generation(chunk_keys: Array[String]) -> void:
	if WorldService == null:
		return
	for chunk_key in chunk_keys:
		if WorldService.has_method("generate_chunk"):
			WorldService.generate_chunk(chunk_key)
		else:
			GameLog.debug("TickService: WorldService.generate_chunk not available for chunk %s" % chunk_key)

## ============================================================================
## FLYWHEEL MANAGEMENT
## ============================================================================

## Decay the flywheel momentum.
func _flywheel_decay() -> void:
	_flywheel_momentum = max(0.0, _flywheel_momentum - FLYWHEEL_DECAY)

## Update sub-meters based on the current tick's activity.
func _flywheel_update_sub_meters() -> void:
	# Decay sub-meters
	for key in _sub_meters.keys():
		_sub_meters[key] = max(0.0, _sub_meters[key] - 0.1)

	var flywheel_data := {
		"momentum": _flywheel_momentum,
		"sub_meters": _sub_meters.duplicate(),
	}
	flywheel_updated.emit(_flywheel_momentum, _sub_meters)

## Get current flywheel momentum.
func get_flywheel_momentum() -> float:
	return _flywheel_momentum

## Get current sub-meters.
func get_sub_meters() -> Dictionary:
	return _sub_meters.duplicate()

## ============================================================================
## PUBLIC API
## ============================================================================

## Returns the current authoritative state tree root hash.
func get_root_hash() -> PackedByteArray:
	return _current_root_hash

## Returns the state tree (read-only between ticks).
func get_state_tree() -> StateTreeScript:
	return _state_tree

## Returns whether the tree is currently read-only.
func is_read_only() -> bool:
	return _is_read_only

## Returns the current tick number.
func get_tick_number() -> int:
	return _tick_number

## Returns the current tick interval in milliseconds.
func get_tick_interval() -> float:
	return _tick_interval

## Register a connected client for diff emission.
func register_client(client_id: int) -> void:
	if not _connected_clients.has(client_id):
		_connected_clients.append(client_id)
		GameLog.debug("TickService: Client %d registered" % client_id)

## Unregister a connected client.
func unregister_client(client_id: int) -> void:
	_connected_clients.erase(client_id)
	_input_queues.erase(client_id)
	GameLog.debug("TickService: Client %d unregistered" % client_id)

## Queue a state tree mutation command for atomic application in Phase 2.
## This is the ONLY way to mutate the state tree. Direct mutations from RPC callbacks,
## agent connectors, or timers are forbidden.
##
## Command types:
##   insert: {"type": "insert", "path": String, "entity_id": String, "state_type": String, "payload": Dictionary}
##   update: {"type": "update", "path": String, "entity_id": String, "state_type": String, "payload": Dictionary}
##   delete: {"type": "delete", "path": String}
##   re_root: {"type": "re_root"} (triggers re-root; normally automatic after mutations)
func queue_state_command(command: Dictionary) -> void:
	if command == null or not command.has("type"):
		push_error("TickService.queue_state_command: invalid command (missing type)")
		return
	var cmd_type := command["type"]
	if cmd_type not in ["insert", "update", "delete", "re_root"]:
		push_error("TickService.queue_state_command: unknown command type '%s'" % cmd_type)
		return
	if cmd_type in ["insert", "update"] and (not command.has("path") or not command.has("entity_id") or not command.has("state_type") or not command.has("payload")):
		push_error("TickService.queue_state_command: insert/update command missing required fields")
		return
	if cmd_type == "delete" and not command.has("path"):
		push_error("TickService.queue_state_command: delete command missing path")
		return
	_state_command_buffer.append(command)

## Returns the number of pending state commands.
func get_pending_command_count() -> int:
	return _state_command_buffer.size()

## Submit chaos to the flywheel from external sources (NPC events, entity signals).
func add_chaos(source: String, amount: float) -> void:
	_flywheel_momentum = min(FLYWHEEL_MAX_MOMENTUM, _flywheel_momentum + amount)
	match source:
		"mob_ai":
			_sub_meters["mob_ai"] += amount
		"cross_shard":
			_sub_meters["cross_shard"] += amount
		"generation":
			_sub_meters["wall_clock"] += amount
		_:
			_sub_meters["wall_clock"] += amount

## ============================================================================
## INTERNAL HELPERS
## ============================================================================

## Task helper class for async phase execution.
class _Task:
	var name: String = ""
	var _task_func: Callable = Callable()
	var _is_running: bool = false

	func _setup(callback: Callable) -> void:
		_task_func = callback

	func start() -> void:
		_is_running = true
		# Use call_deferred to run async after the current frame
		call_deferred("_execute")

	func _execute() -> void:
	if not _is_running or not _task_func.is_valid():
		if is_instance_valid(self):
			queue_free()
		return
	_is_running = false
	_task_func.call()
	if is_instance_valid(self):
		queue_free()

	func cancel() -> void:
		_is_running = false
		if is_instance_valid(self):
			queue_free()
