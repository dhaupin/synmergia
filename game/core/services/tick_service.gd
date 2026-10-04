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

## N014 tick-alignment tolerance (labs/world-building-risks.md N014): a
## recorded diff SEND may land at most this many ms past the tick's
## scheduled end before the tick counts as misaligned. Early sends are
## healthy (idle ticks run trivial phases 1-3).
const N014_TOLERANCE_MS: int = 2

## Side-queue retry cap: an overflow item is retried this many ticks,
## then dropped (a logged-off player's unappliable input must not loop
## forever). The queue drains every Phase 2, so it stays bounded.
const SIDE_QUEUE_RETRY_CAP: int = 5

## Tick-root history retained in the persistence store (N017). The
## per-tick "tick:N:root" keys have no reader today (the live-read
## keys are the latest_* pointers); without a window they grow one row
## per tick forever (~1.7M/day at 50ms ticks).
const TICK_ROOT_HISTORY: int = 100

## Root keys persisted by Phase 5, oldest first (drives the prune).
var _persisted_root_keys: Array[String] = []

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

## Diff computed by Phase 3 for THIS tick, consumed by Phase 4.
## Phase 3 rotates _previous_root_hash at the end, so Phase 4 can no
## longer recover the tick's diff from the hash pair; it reads this.
var _last_tick_diff: Array = []

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
	# The tick tree IS the shared world tree on FrameService: one tree,
	# one root hash over character projections, world entity projections
	# and tick-buffered state. FrameService loads earlier (autoload #5);
	# a missing FrameService (script mode) keeps a private tree with
	# identical semantics so the tick pipeline still runs.
	var fs: Node = get_node_or_null("/root/FrameService")
	if fs != null and fs.has_method("get_world_state_tree"):
		_state_tree = fs.get_world_state_tree()
	if _state_tree == null:
		_state_tree = StateTreeScript.new()
	_previous_root_hash = _state_tree.root_hash()
	_current_root_hash = _previous_root_hash
	# N017 boot policy: wipe the previous session's per-tick root
	# history before the loop starts (see _cleanup_orphan_root_keys).
	_cleanup_orphan_root_keys()
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

	# N014 invariant check (labs/world-building-risks.md N014): measure
	# each recorded diff SEND timestamp against the tick's scheduled END
	# (tick_start + TICK_BUDGET_MS) -- when the next tick is due. Sends
	# PAST the boundary + tolerance started the next tick late (Q1);
	# early sends are healthy. The old form compared whole-tick duration
	# against the 48ms sync budget, which false-positived every quiet
	# tick (~47ms "deviation" with one connected client).
	var worst_late_ms: float = _n014_worst_late_ms(phase4_result.get("send_times", {}), tick_start_ms)
	if worst_late_ms > float(N014_TOLERANCE_MS):
		GameLog.warn("TickService: N014 violation tick=%d diff sent %.1fms past the tick boundary" % [_tick_number, worst_late_ms])

	# Budget warning: log phase breakdown when total sync exceeds 80% of tick budget (40ms)
	if total_sync_ms > BUDGET_WARNING_THRESHOLD_MS:
		var phase1_ms: float = phase_timings.get("phase1_input", 0.0)
		var phase2_ms: float = phase_timings.get("phase2_world", 0.0)
		var phase3_ms: float = phase_timings.get("phase3_reroot", 0.0)
		var phase4_ms: float = phase_timings.get("phase4_emit", 0.0)
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
func _parse_input_frame(frame) -> Variant:
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

## Get player_id from peer_id via NetworkManager's peer mapping, with
## the local-player fallback for headless/single-user sessions.
func _get_player_id_from_peer(peer_id: int) -> String:
	## 1. Real peer mapping (NetworkManager.connected_peers[peer][
	## "player_id"], populated by LoginService.on_character_selected and
	## persisted through the cache adapter). In headless/script mode
	## there is no NetworkManager autoload, so this is null there.
	var nm := get_node_or_null("/root/NetworkManager")
	if nm != null and nm.has_method("get_character_for_peer"):
		var mapped: String = str(nm.get_character_for_peer(peer_id))
		if mapped != "":
			return mapped
	## 2. Local-player fallback: single-user/headless sessions have no
	## peer handshake, but the local player is still a real AOI client.
	if PlayerManager and PlayerManager.has_method("get_local_player_id"):
		var pid: String = PlayerManager.get_local_player_id()
		if pid != "":
			return pid
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

	# Step 0.5: Drain the side queue -- overflow work carried from
	# previous ticks is retried here (nothing is silently dropped).
	# Items past the retry cap are dropped with a log so a logged-off
	# player's unappliable input cannot loop forever.
	var carried: Array = _side_queue
	_side_queue = []
	for item in carried:
		if not (item is Dictionary):
			continue
		var retries: int = int(item.get("_retries", 0))
		var applied: bool = false
		if str(item.get("type", "")) == "input":
			applied = _apply_player_input(str(item.get("player_id", "")), item.get("data", {}))
		if applied:
			entity_count += 1
		elif retries >= SIDE_QUEUE_RETRY_CAP:
			GameLog.debug("TickService: side-queue item dropped after %d retries (type=%s)" % [retries, str(item.get("type", "?"))])
		else:
			item["_retries"] = retries + 1
			_side_queue.append(item)

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

	# Overflow from this tick retries next tick (the retry counter makes
	# the cap apply). The returned overflow stays informational.
	for item in overflow:
		if item is Dictionary:
			item["_retries"] = int(item.get("_retries", 0))
			_side_queue.append(item)

	return {"processed": entity_count, "overflow": overflow}

## Compare input frames by tick-local sequence for deterministic ordering.
static func _compare_input_sequence(a: Dictionary, b: Dictionary) -> bool:
	var seq_a: int = a.get("seq", 0)
	var seq_b: int = b.get("seq", 0)
	return seq_a < seq_b

## Determine if an entity should be stepped this tick.
func _should_step_entity(entity) -> bool:
	if entity == null:
		return false
	# Entities with inputs this tick or with AI decisions to make.
	# Use the `in` operator: entities are Nodes, not Dictionaries, so
	# Dictionary.has() is invalid on them.
	if "has_input" in entity and entity.has_input:
		return true
	if "needs_ai" in entity and entity.needs_ai:
		return true
	# Always step entities with active effects
	if "effect_count" in entity and entity.effect_count > 0:
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
		var cmd_type: String = command["type"]
		var success: bool = false

		match cmd_type:
			"insert", "update":
				var path: String = command["path"]
				var entity_id: String = command["entity_id"]
				var state_type: String = command["state_type"]
				var payload: Dictionary = command["payload"]
				_state_tree.insert_state(path, entity_id, state_type, payload)
				success = true

			"delete":
				var path: String = command["path"]
				_state_tree.delete_state(path)
				success = true

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

	# Announce through FrameService so world_root_hash() stays the ONE
	# authoritative hash client resync keys off (dedupes internally: no
	# emission when nothing changed between ticks).
	var fs: Node = get_node_or_null("/root/FrameService")
	if fs != null and fs.has_method("touch_world_tree"):
		fs.touch_world_tree()

	# Compute diff vs previous root (state-only diff)
	var diff: Array = []
	if _previous_root_hash != _current_root_hash:
		diff = _state_tree.diff_states(_previous_root_hash, _current_root_hash)

	# Stash for Phase 4 BEFORE rotating the hash pair below: after the
	# rotation _previous_root_hash == _current_root_hash, which used to
	# leave _compute_aoi_diff() gated to an empty diff and clients never
	# received incremental updates in the live flow.
	_last_tick_diff = diff

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

## For each connected client, compute AOI diff, apply LOD, send.
## N014 invariant: every diff is sent within +/-2ms of the tick
## boundary. Wall-clock send timestamps are recorded per client and
## checked in _on_tick against the tick's scheduled end.
func _phase4_diff_emit() -> Dictionary:
	var client_count: int = 0
	var emit_times: Dictionary = {}
	var send_times: Dictionary = {}

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
			send_times[client_id] = Time.get_ticks_msec()

		var emit_elapsed := float(Time.get_ticks_msec() - emit_start)
		emit_times[client_id] = emit_elapsed

	return {"clients_emit": client_count, "emit_times": emit_times, "send_times": send_times}

## Worst lateness (ms) of any recorded diff send relative to the tick
## boundary -- the tick's scheduled END (tick_start + TICK_BUDGET_MS),
## when the next tick is due. 0.0 when nothing was sent or every send
## was early/on time. N014 violates when this exceeds N014_TOLERANCE_MS.
func _n014_worst_late_ms(send_times: Dictionary, tick_start_ms: int) -> float:
	var worst: float = 0.0
	for client_id in send_times:
		var send_ms: float = float(send_times[client_id])
		var late: float = send_ms - float(tick_start_ms + TICK_BUDGET_MS)
		if late > worst:
			worst = late
	return worst

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
## Under high flywheel load the server degrades detail globally: a real,
## deterministic lever (per-client distance tiering arrives with client
## position tracking in Phase 4).
func _get_client_lod_level(client_id: int) -> int:
	# Global load override: degraded service trumps everything.
	if _flywheel_momentum >= FLYWHEEL_HIGH_THRESHOLD:
		return 1
	# Distance tiering: clients with a resolvable AOI whose player is
	# FAR from an active horde zone get L1 summaries (the horde's live
	# half is high-volume); in/near the horde they keep full detail.
	var player_id: String = _get_player_id_from_peer(client_id)
	if _client_far_from_any_horde_zone(player_id):
		return 1
	return 0

## True when the player sits in a zone with an active horde that is NOT
## the player's own -- far clients summarize, participants keep detail.
## Unknown players/missing services degrade to false (full detail).
func _client_far_from_any_horde_zone(player_id: String) -> bool:
	var horde := get_node_or_null("/root/HordeEventService")
	if horde == null or not horde.has_method("active_horde_zones"):
		return false
	var active_zones: Array = horde.active_horde_zones()
	if active_zones.is_empty():
		return false
	var es := get_node_or_null("/root/EntityService")
	var zm := get_node_or_null("/root/ZoneManager")
	if es == null or zm == null or not zm.has_method("get_entity_zone_id"):
		return false
	var player = es.get_entity(player_id)
	if player == null:
		return false
	var player_zone: Variant = zm.get_entity_zone_id(player)
	if player_zone == null or str(player_zone) == "":
		return false
	return not active_zones.has(str(player_zone))

## Extract the instance scope token from a diff path
## "/world/instances/<scope>/..." -> "<scope>" ("" otherwise).
func _instance_scope_from_path(path: String) -> String:
	var p := path.strip_edges()
	if not p.begins_with("/"):
		p = "/" + p
	if not p.begins_with("/world/instances/"):
		return ""
	var rest: String = p.trim_prefix("/world/instances/")
	var slash: int = rest.find("/")
	return rest.substr(0, slash) if slash > 0 else ""

## Compute the AOI diff for a specific client.
## Zone-aware: entries under /world/zones/<z>/... flow to a client when
## the client is IN zone z or z's spatial box overlaps the client's AOI
## chunk square (horde state reaches everyone in/around the horde zone,
## and never leaks to unrelated zones). Position-bearing legacy payloads
## keep the chunk-box filter; everything else (character progress) rides
## the client's center chunk.
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
	var aoi_box: Array = [min_cx, max_cx, min_cz, max_cz]
	var center_key: String = "%d_%d" % [int(floor(pos.x / float(CHUNK_SIZE))), int(floor(pos.z / float(CHUNK_SIZE)))]

	var player_zone := ""
	var zm := get_node_or_null("/root/ZoneManager")
	if zm != null and zm.has_method("get_entity_zone_id"):
		var zid: Variant = zm.get_entity_zone_id(player)
		if zid != null:
			player_zone = str(zid)

	# Prefer the diff Phase 3 computed for this tick (the hash pair is
	# rotated at the end of Phase 3, so the recompute below only serves
	# direct Phase 4 entry that never ran Phase 3 -- e.g. tests that set
	# the hash pair by hand).
	var full_diff: Array = _last_tick_diff
	if full_diff.is_empty() and _previous_root_hash.size() > 0 and _current_root_hash.size() > 0 and _previous_root_hash != _current_root_hash:
		full_diff = _state_tree.diff_states(_previous_root_hash, _current_root_hash)

	var result: Dictionary = {}
	for cx in range(min_cx, max_cx + 1):
		for cz in range(min_cz, max_cz + 1):
			result["%d_%d" % [cx, cz]] = []

	var zone_boxes: Dictionary = {}
	for entry in full_diff:
		if not entry is Array or entry.size() < 4:
			continue
		# T3 diff paths carry no leading slash (e.g. "world/zones/...");
		# normalize so the zone prefix checks below are shape-agnostic.
		var path: String = str(entry[0])
		if not path.begins_with("/"):
			path = "/" + path

		# --- Zone-scoped half (horde entities + player live state) ---
		if path.begins_with("/world/zones/"):
			var zone_id: String = _zone_id_from_path(path)
			if zone_id == "":
				continue
			if not zone_boxes.has(zone_id):
				zone_boxes[zone_id] = _zone_chunk_box(zone_id)
			var box: Array = zone_boxes[zone_id]
			var include: bool = zone_id == player_zone
			if not include and not box.is_empty() and _chunk_boxes_overlap(box, aoi_box):
				include = true
			if include:
				if not result.has(center_key):
					result[center_key] = []
				result[center_key].append(entry)
			continue

		# --- Instance-scoped half (dungeon/arena hordes) ---
		if path.begins_with("/world/instances/"):
			var scope: String = _instance_scope_from_path(path)
			if scope == "":
				continue
			# Deliver when the client's player is pinned to this instance
			# (horde participants) or inside it via zone membership
			# (ZoneManager tracks dungeon zones as instance:<scope> for
			# these hordes' residents). Everyone else never sees it.
			var pinned: String = "instance:" + scope
			var proj := get_node_or_null("/root/WorldStateProjection")
			if proj != null and proj.has_method("get_entity_scope_override"):
				var player_override: String = str(proj.get_entity_scope_override(player_id))
				if player_override == pinned:
					if not result.has(center_key):
						result[center_key] = []
					result[center_key].append(entry)
			continue

		# --- Everything else ---
		var value_bytes: PackedByteArray = entry[3]
		if value_bytes == null or value_bytes.size() == 0:
			continue
		var value: Variant = bytes_to_var(value_bytes)
		if value is Dictionary and value.has("position_x"):
			var ex: float = float(value.get("position_x", 0.0))
			var ez: float = float(value.get("position_z", 0.0))
			var cx := int(floor(ex / float(CHUNK_SIZE)))
			var cz := int(floor(ez / float(CHUNK_SIZE)))
			if cx >= min_cx and cx <= max_cx and cz >= min_cz and cz <= max_cz:
				var key: String = "%d_%d" % [cx, cz]
				if not result.has(key):
					result[key] = []
				result[key].append(entry)
		else:
			# Character progress and other non-spatial state always
			# reaches its owner.
			if not result.has(center_key):
				result[center_key] = []
			result[center_key].append(entry)

	return result

## Extract the zone id from a zone-scoped tree path:
## "/world/zones/<zone>/..." -> "<zone>" ("" when the shape is wrong).
func _zone_id_from_path(path: String) -> String:
	var prefix := "/world/zones/"
	if not path.begins_with(prefix):
		return ""
	var rest := path.substr(prefix.length())
	var slash := rest.find("/")
	return rest.substr(0, slash) if slash >= 0 else rest

## Chunk box [min_cx, max_cx, min_cz, max_cz] covering a zone's extent
## (center +/- radius, snapped to chunks); empty when the zone is
## unknown to ZoneManager.
func _zone_chunk_box(zone_id: String) -> Array:
	var zm := get_node_or_null("/root/ZoneManager")
	if zm == null or not zm.has_method("get_zone"):
		return []
	var zone: Variant = zm.get_zone(zone_id)
	if zone == null:
		return []
	# ZoneData carries zone_center/zone_radius; stub dictionaries in
	# tests may use center/radius. Duck-type both shapes.
	var center: Vector3 = Vector3.ZERO
	var radius: float = 0.0
	if "zone_center" in zone:
		center = zone.zone_center
	elif "center" in zone:
		center = zone.center
	if "zone_radius" in zone:
		radius = float(zone.zone_radius)
	elif "radius" in zone:
		radius = float(zone.radius)
	if radius <= 0.0:
		return []
	return [
		int(floor((center.x - radius) / float(CHUNK_SIZE))),
		int(floor((center.x + radius) / float(CHUNK_SIZE))),
		int(floor((center.z - radius) / float(CHUNK_SIZE))),
		int(floor((center.z + radius) / float(CHUNK_SIZE))),
	]

## Component-wise overlap of two [min_cx, max_cx, min_cz, max_cz] boxes.
func _chunk_boxes_overlap(a: Array, b: Array) -> bool:
	if a.size() != 4 or b.size() != 4:
		return false
	return int(a[0]) <= int(b[1]) and int(b[0]) <= int(a[1]) \
			and int(a[2]) <= int(b[3]) and int(b[2]) <= int(a[3])

## Apply LOD to a diff - distant/degraded clients get L1 summaries.
func _apply_lod(client_id: int, diff: Dictionary) -> Dictionary:
	var level := _get_client_lod_level(client_id)
	if level <= 0:
		return diff
	# L1 summary: strip payload bytes on the high-volume live half
	# (/world/zones/...). Structure (path + hashes) survives so clients
	# can still count changes and request a targeted zone resync;
	# low-volume entries (character progress) keep full detail.
	var result: Dictionary = {}
	for chunk_key in diff.keys():
		var entries: Array = []
		for entry in diff[chunk_key]:
			if entry is Array and entry.size() >= 4 and str(entry[0]).begins_with("/world/zones/"):
				entries.append([entry[0], entry[1], entry[2], PackedByteArray()])
			else:
				entries.append(entry)
		result[chunk_key] = entries
	return result

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

				# Bound the per-tick root history: prune keys older
				# than the retention window (nothing reads them back;
				# the latest_* pointers above are the live reads).
				_persisted_root_keys.append(root_key)
				var stale: Array = []
				while _persisted_root_keys.size() > TICK_ROOT_HISTORY:
					stale.append(_persisted_root_keys.pop_front())
				if stale.size() > 0 and store.has_method("delete_many"):
					store.delete_many(stale)

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
					# LOD-promote predicted chunks. The key MUST be in
					# LODManager's own fragmenter format or the promoted
					# state lands under a key nothing ever reads back
					# (the old call passed a Vector2 where promote_chunk
					# wants a String chunk key).
					if LODManager and LODManager.has_method("promote_chunk") and LODManager.has_method("get_chunk_key_from_position"):
						var lod_key: String = LODManager.get_chunk_key_from_position(predicted_pos)
						LODManager.promote_chunk(lod_key, LODManager.LODState.WARM)
					var chunk_coords = _position_to_chunk(predicted_pos)
					var chunk_key: String = "%d_%d" % [chunk_coords.x, chunk_coords.y]
					promoted_chunks.append(chunk_key)

		# Procedural generator runs on promoted chunks
		_promote_generation(promoted_chunks)

		GameLog.debug("TickService: Phase 6 prefetch complete for tick %d" % _tick_number)
	)
	task.start()
	_prefetch_task = task

## Markov predictor for player position in 1 second.
func _markov_predict(player) -> Variant:
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

## N017 boot policy: the per-tick root history keys ("tick:N:root")
## are write-only telemetry -- nothing reads them back; the live reads
## are the world_state:latest_* pointers -- and the retention window
## (TICK_ROOT_HISTORY) only covers the CURRENT session. Any such key
## present at boot is therefore an orphan of a previous session:
## delete them all, once, for a clean slate. Best-effort: stores
## without the query shim skip cleanup (the session window still
## bounds current growth).
func _cleanup_orphan_root_keys() -> void:
	var ar = _adapter_registry()
	if ar == null:
		return
	var store = ar.get_persistence("world_state")
	if store == null or not store.has_method("query"):
		return
	var rows: Array = store.query("SELECT key FROM kv WHERE key LIKE 'tick:%'", [])
	var orphan_keys: Array = []
	for row in rows:
		if row is Dictionary and row.has("key"):
			var k: String = str(row["key"])
			if k.begins_with("tick:") and k.ends_with(":root"):
				orphan_keys.append(k)
	if orphan_keys.is_empty():
		return
	var removed: int = 0
	if store.has_method("delete_many"):
		removed = store.delete_many(orphan_keys)
	else:
		for k in orphan_keys:
			store.delete(k)
			removed += 1
	GameLog.info("TickService: N017 boot cleanup removed %d orphan tick-root key(s)" % removed)

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
	# Queued inputs are keyed by player_id, not peer id; resolve before
	# erasing. Phase 1 clears the queues every tick, so a failed
	# resolution self-heals next tick either way.
	var player_id: String = _get_player_id_from_peer(client_id)
	if player_id != "":
		_input_queues.erase(player_id)
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
	var cmd_type: String = command["type"]
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

## Returns the number of overflow items waiting in the side queue
## (carried work from previous ticks; drains each Phase 2).
func get_side_queue_size() -> int:
	return _side_queue.size()

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
class _Task extends Node:
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
