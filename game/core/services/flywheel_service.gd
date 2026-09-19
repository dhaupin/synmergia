## FlywheelService - Centralized load tracking and anomaly detection
##
## Implements the flywheel pattern for both shard-level and per-player chaos accumulation.
##
## The flywheel measures work (chaos) accumulated over time and triggers snapshots
## when the system becomes "hot" (near capacity). It serves two purposes:
## 1. **Shard-level**: Load profiling for performance tuning, postmortem analysis
## 2. **Per-player**: Security/anticheat by detecting anomalous player behavior
##
## The flywheel is the awareness layer for the system - it tells us
## *how much* work is happening, *where* it's happening, and *who* is driving it.
extends Node

const DictStore = preload("res://adapters/persistence/dict_store.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

## ============================================================================
## SIGNALS
## ============================================================================

signal player_suspicious(player_id: String, snapshot: Dictionary)
signal shard_hot(shard_id: String, snapshot: Dictionary)

## ============================================================================
## CONFIGURATION
## ============================================================================

const DEFAULT_DECAY_PER_TICK: float = 0.5
const MAX_MOMENTUM: int = 1000
const SNAPSHOT_TTL_HOURS: float = 1.0
const SNAPSHOT_KEY_TTL_SECONDS: int = int(SNAPSHOT_TTL_HOURS * 3600)

## Sub-meter weights for chaos sources
## Maps from chaos source kind to weight
const CHAOS_WEIGHTS: Dictionary = {
	"player_input": 1,
	"player_input_combat": 5,
	"mob_ai": 10,
	"cross_shard_hlc": 50,
	"wall_clock": 1,
	"generation": 100,
	"npc_event": 1,
	"entity_signal": 1,
	"other_observable": 1,
}

## ============================================================================
## STATE
## ============================================================================

## Shard-level flywheel state
var _shard_flywheels: Dictionary = {}
var _shard_momenta: Dictionary = {}  # shard_id -> current momentum

## Per-player flywheel state (in-memory cache)
var _player_flywheels: Dictionary = {}  # player_id -> PlayerFlywheelState

## Track recent snapshots for dedupe
var _last_snapshot_trigger: Dictionary = {}  # player_id -> trigger type

## Track system-wide resource pressure
var _resource_pressure: Dictionary = {
	"cpu_high": false,
	"cpu_high_start": 0,
	"memory_high": false,
	"backlog_growing": false,
	"last_check": 0
}

## Track shutdown signals
var _shutdown_requested: bool = false
var _boot_count: int = 0

## ============================================================================
## LIFECYCLE
## ============================================================================

func _ready() -> void:
	GameLog.info("FlywheelService: Initializing flywheel tracking")
	_boot_count += 1
	_load_recent_snapshots()

func _process(delta: float) -> void:
	_update_resource_pressure()

## ============================================================================
## SHARD-LEVEL FLYWHEEL
## ============================================================================

## Update the shard-level flywheel with accumulated chaos
func update_shard_flywheel(shard_id: String, chaos_delta: float, source_kind: String, source_id: String = "") -> void:
	if not _shard_momenta.has(shard_id):
		_shard_momenta[shard_id] = 0

	# Apply source weight
	var weight: float = CHAOS_WEIGHTS.get(source_kind, CHAOS_WEIGHTS["other_observable"])
	var weighted_delta: float = chaos_delta * weight

	# Add to momentum (can't exceed max)
	_shard_momenta[shard_id] = min(_shard_momenta[shard_id] + weighted_delta, MAX_MOMENTUM)

	# Decay the momentum
	_shard_momenta[shard_id] = max(_shard_momenta[shard_id] - DEFAULT_DECAY_PER_TICK, 0)

	# Update sub-meters
	_update_shard_sub_meters(shard_id, source_kind)

	# Check for snapshot triggers
	_check_shard_snapshot_triggers(shard_id)

## Add wall-clock pulse (heartbeat) - always +1 per tick
func tick_heartbeat(shard_id: String) -> void:
	update_shard_flywheel(shard_id, 1.0, "wall_clock", "")

func _update_shard_sub_meters(shard_id: String, source_kind: String) -> void:
	if not _shard_flywheels.has(shard_id):
		_shard_flywheels[shard_id] = {
			"player_inputs": 0,
			"mob_ai": 0,
			"cross_shard": 0,
			"wall_clock": 0,
			"generation": 0,
			"npc_events": 0,
			"entity_signals": 0,
			"other": 0
		}

	var sub = _shard_flywheels[shard_id]

	match source_kind:
		"player_input":
			if "player_input_combat".is_subsequence_of(source_kind):
				sub["player_inputs"] += 5
			else:
				sub["player_inputs"] += 1
		"mob_ai":
			sub["mob_ai"] += 10
		"cross_shard_hlc":
			sub["cross_shard"] += 50
		"wall_clock":
			sub["wall_clock"] += 1
		"generation":
			sub["generation"] += 100
		"npc_event":
			sub["npc_events"] += CHAOS_WEIGHTS["npc_event"]
		"entity_signal":
			sub["entity_signals"] += CHAOS_WEIGHTS["entity_signal"]
		"other_observable":
			sub["other"] += CHAOS_WEIGHTS["other_observable"]

func _check_shard_snapshot_triggers(shard_id: String) -> void:
	var momentum: float = _shard_momenta[shard_id]
	var max_momentum: float = MAX_MOMENTUM
	var momentum_ratio: float = momentum / max_momentum

	# Check triggers (OR logic - any true fires snapshot)
	var trigger: String = ""

	# 1. High-entropy threshold crossed
	if momentum_ratio > 0.8:
		trigger = "high_entropy"

	# 2. Resource pressure (checked elsewhere, but can trigger here)
	if _is_resource_pressure_high():
		trigger = "resource_pressure"

	# 3. Shutdown requested
	if _shutdown_requested:
		trigger = "sigterm"

	if trigger != "":
		_take_shard_snapshot(shard_id, trigger, momentum_ratio)

func _take_shard_snapshot(shard_id: String, trigger: String, momentum_ratio: float) -> void:
	var momentum: float = _shard_momenta[shard_id]
	var max_momentum: float = MAX_MOMENTUM
	var now: int = Time.get_unix_time_from_system() * 1000

	# Build snapshot record
	var snapshot: Dictionary = {
		"shard_id": shard_id,
		"tick": _get_current_tick(),
		"timestamp_ms": now,
		"trigger": trigger,
		"momentum": momentum,
		"max_momentum": max_momentum,
		"sub_meters": _shard_flywheels.get(shard_id, {}),
		"top_contributors": _get_top_shard_contributors(shard_id),
		"boot_count": _boot_count,
		"since_boot_seconds": _get_uptime_seconds()
	}

	# Persist to Redis
	_persist_shard_snapshot(shard_id, snapshot)

	# Emit signal
	shard_hot.emit(shard_id, snapshot)

	# Log snapshot
	GameLog.info("FlywheelService: Shard %s snapshot - trigger: %s, momentum: %d/%d (%.1f%%)" % [
		shard_id, trigger, momentum, max_momentum, momentum_ratio * 100.0
	])

func _get_top_shard_contributors(shard_id: String) -> Array:
	# Simplified - return empty list (could be expanded with actual contribution tracking)
	return []

func _persist_shard_snapshot(shard_id: String, snapshot: Dictionary) -> void:
	var store := DictStore.new()
	var key := "flywheel:shard:" + shard_id
	store.set_value(key, snapshot, SNAPSHOT_KEY_TTL_SECONDS)

func _load_recent_snapshots() -> void:
	var store := DictStore.new()
	for key in store.all_keys():
		if key.begins_with("flywheel:shard:"):
			var shard_id = key.substr("flywheel:shard:".length())
			var snapshot = store.get_value(key)
			if snapshot is Dictionary:
				_restore_shard_flywheel(shard_id, snapshot)

func _restore_shard_flywheel(shard_id: String, snapshot: Dictionary) -> void:
	var momentum: float = snapshot.get("momentum", 0)
	var now: int = Time.get_unix_time_from_system() * 1000
	var age_seconds: float = (now - snapshot.get("timestamp_ms", now)) / 1000.0

	# Only restore if snapshot is fresh (< 1 hour old)
	if age_seconds < SNAPSHOT_KEY_TTL_SECONDS:
		_shard_momenta[shard_id] = momentum

		# Restore sub-meters
		var sub_meters = snapshot.get("sub_meters", {})
		if sub_meters and _shard_flywheels.has(shard_id):
			for meter in sub_meters.keys():
				if _shard_flywheels[shard_id].has(meter):
					_shard_flywheels[shard_id][meter] = sub_meters[meter]

		GameLog.info("FlywheelService: Restored shard %s from snapshot (momentum: %d)" % [shard_id, momentum])

## ============================================================================
## PER-PLAYER FLYWHEEL (SECURITY/ANTICHEAT)
## ============================================================================

## Update player flywheel with activity
func update_player_flywheel(player_id: String, sub_meter: String, value: float, details: Dictionary = {}) -> void:
	if not _player_flywheels.has(player_id):
		_player_flywheels[player_id] = {
			"movement": {"distance": 0.0, "speed": 0.0, "teleport_count": 0, "fast_travel": 0},
			"combat_hits": {"count": 0, "crit_rate": 0.0, "hit_timing": []},
			"combat_cooldowns": {"uses": 0, "gaps": [], "downtime": 0.0},
			"chat": {"messages": 0, "channel_switches": 0},
			"trade": {"trades": 0, "items_per_trade": 0, "gold_moved": 0},
			"loot": {"rolls": 0, "rare_drop_rate": 0.0},
			"instances": {"enters": 0}
		}

	var flywheel = _player_flywheels[player_id]

	match sub_meter:
		"movement_distance":
			flywheel["movement"]["distance"] += value
			_check_player_movement_threshold(player_id, flywheel)
		"movement_speed":
			flywheel["movement"]["speed"] += value
			_check_player_movement_threshold(player_id, flywheel)
		"teleport":
			flywheel["movement"]["teleport_count"] += 1
			_check_player_movement_threshold(player_id, flywheel)
		"fast_travel":
			flywheel["movement"]["fast_travel"] += 1
			_check_player_movement_threshold(player_id, flywheel)
		"combat_hit":
			flywheel["combat_hits"]["count"] += 1
			_check_player_combat_thresholds(player_id, flywheel, details)
		"combat_crit":
			flywheel["combat_hits"]["crit_rate"] += value
			_check_player_combat_thresholds(player_id, flywheel, details)
		"combat_hit_timing":
			flywheel["combat_hits"]["hit_timing"].append(details.get("interval_ms", 0))
			_check_player_combat_thresholds(player_id, flywheel, details)
		"combat_cooldown":
			flywheel["combat_cooldowns"]["uses"] += 1
			_check_player_combat_thresholds(player_id, flywheel, details)
		"combat_cooldown_gap":
			flywheel["combat_cooldowns"]["gaps"].append(value)
			_check_player_combat_thresholds(player_id, flywheel, details)
		"chat_message":
			flywheel["chat"]["messages"] += 1
			_check_player_chat_threshold(player_id, flywheel)
		"channel_switch":
			flywheel["chat"]["channel_switches"] += 1
			_check_player_chat_threshold(player_id, flywheel)
		"trade_open":
			flywheel["trade"]["trades"] += 1
			_check_player_trade_threshold(player_id, flywheel)
		"trade_items":
			flywheel["trade"]["items_per_trade"] += value
			_check_player_trade_threshold(player_id, flywheel)
		"trade_gold":
			flywheel["trade"]["gold_moved"] += value
			_check_player_trade_threshold(player_id, flywheel)
		"loot_roll":
			flywheel["loot"]["rolls"] += 1
			_check_player_loot_threshold(player_id, flywheel)
		"loot_rare_drop":
			flywheel["loot"]["rare_drop_rate"] += value
			_check_player_loot_threshold(player_id, flywheel)
		"instance_enter":
			flywheel["instances"]["enters"] += 1
			_check_player_instance_threshold(player_id, flywheel)

func _check_player_movement_threshold(player_id: String, flywheel: Dictionary) -> void:
	var movement = flywheel["movement"]
	var warn_triggered: bool = false
	var trigger_triggered: bool = false

	# Check for excessive speed (warn/trigger)
	var speed: float = movement["speed"]
	var normal_speed_threshold: float = 1.0
	var warn_threshold: float = 1.2
	var trigger_threshold: float = 1.5

	if speed >= trigger_threshold:
		_check_and_trigger_player_snapshot(player_id, "movement", speed, {"normal_threshold": normal_speed_threshold})
	elif speed >= warn_threshold:
		warn_triggered = true
		GameLog.warn("FlywheelService: Player %s movement speed warning (%.1f%%)" % [player_id, (speed / normal_speed_threshold) * 100])

	# Check teleport count
	var teleport_count: int = movement["teleport_count"]
	var normal_teleport_threshold: int = 5
	if teleport_count >= normal_teleport_threshold * 2:
		_check_and_trigger_player_snapshot(player_id, "teleport", teleport_count, {"normal_threshold": normal_teleport_threshold})
	elif teleport_count >= normal_teleport_threshold:
		warn_triggered = true
		GameLog.warn("FlywheelService: Player %s teleport count warning (%d)" % [player_id, teleport_count])

func _check_player_combat_thresholds(player_id: String, flywheel: Dictionary, details: Dictionary) -> void:
	var combat = flywheel["combat_hits"]
	var cooldowns = flywheel["combat_cooldowns"]

	# Check hit timing
	var hit_timing: Array = combat["hit_timing"]
	if hit_timing.size() >= 3:
		var last_three = hit_timing.slice(-3)
		var avg_interval: float = last_three.reduce(func(sum, x): return sum + x, 0.0) / last_three.size()

		# Hit timing thresholds
		var warn_threshold: float = 200.0
		var trigger_threshold: float = 100.0

		if avg_interval <= trigger_threshold:
			_check_and_trigger_player_snapshot(player_id, "combat_hit_timing", avg_interval, {"threshold_ms": avg_interval})
		elif avg_interval <= warn_threshold:
			GameLog.warn("FlywheelService: Player %s combat hit timing warning (%.1fms)" % [player_id, avg_interval])

	# Check cooldown violations
	var now: int = Time.get_unix_time_from_system()
	var recent_gaps: Array = cooldowns["gaps"].filter(func(gap): return gap <= now)

	if recent_gaps.size() >= 5:
		GameLog.warn("FlywheelService: Player %s combat cooldown patterns suspicious" % [player_id])

func _check_player_chat_threshold(player_id: String, flywheel: Dictionary) -> void:
	var chat = flywheel["chat"]
	var message_count: int = chat["messages"]
	var normal_threshold: int = 30
	var warn_threshold: int = 60
	var trigger_threshold: int = 120

	if message_count >= trigger_threshold:
		_check_and_trigger_player_snapshot(player_id, "chat", message_count, {"threshold": trigger_threshold})
	elif message_count >= warn_threshold:
		GameLog.warn("FlywheelService: Player %s chat volume warning (count: %d)" % [player_id, message_count])

func _check_player_trade_threshold(player_id: String, flywheel: Dictionary) -> void:
	var trade = flywheel["trade"]
	var trade_count: int = trade["trades"]
	var normal_threshold: int = 5
	var warn_threshold: int = 10
	var trigger_threshold: int = 20

	if trade_count >= trigger_threshold:
		_check_and_trigger_player_snapshot(player_id, "trade", trade_count, {"threshold": trigger_threshold})
	elif trade_count >= warn_threshold:
		GameLog.warn("FlywheelService: Player %s trade volume warning (count: %d)" % [player_id, trade_count])

func _check_player_loot_threshold(player_id: String, flywheel: Dictionary) -> void:
	var loot = flywheel["loot"]
	var roll_count: int = loot["rolls"]
	var rare_drop_rate: float = loot["rare_drop_rate"]

	var normal_threshold: int = 3
	var warn_multiplier: float = 3.0
	var trigger_multiplier: float = 3.0

	if roll_count >= normal_threshold * 3:
		_check_and_trigger_player_snapshot(player_id, "loot", roll_count, {"rolls": roll_count})
	elif roll_count >= normal_threshold:
		GameLog.warn("FlywheelService: Player %s loot roll volume warning (count: %d)" % [player_id, roll_count])

func _check_player_instance_threshold(player_id: String, flywheel: Dictionary) -> void:
	var instances = flywheel["instances"]
	var enter_count: int = instances["enters"]
	var normal_threshold: int = 5
	var warn_threshold: int = 10
	var trigger_threshold: int = 15

	if enter_count >= trigger_threshold:
		_check_and_trigger_player_snapshot(player_id, "instance", enter_count, {"threshold": trigger_threshold})
	elif enter_count >= warn_threshold:
		GameLog.warn("FlywheelService: Player %s instance enter volume warning (count: %d)" % [player_id, enter_count])

func _check_and_trigger_player_snapshot(player_id: String, sub_meter: String, value: float, details: Dictionary) -> void:
	var now: int = Time.get_unix_time_from_system() * 1000

	# Build snapshot record
	var snapshot: Dictionary = {
		"player_id": player_id,
		"tick": _get_current_tick(),
		"timestamp_ms": now,
		"trigger_submeter": sub_meter,
		"trigger_value": value,
		"recent_activity": _get_recent_player_activity(player_id, sub_meter),
		"sub_meter_values": _get_player_sub_meter_values(player_id),
		"session_minutes": _get_session_minutes(player_id),
		"previous_snapshots_in_session": _get_player_snapshot_count(player_id)
	}
	if GameManager != null:
		snapshot["shard_id"] = GameManager.get_current_shard_id()
	else:
		snapshot["shard_id"] = "shard_unknown"

	# Persist snapshot to Redis (suspicious player key)
	_persist_player_snapshot(player_id, snapshot)

	# Emit signal for AutoResponseService
	player_suspicious.emit(player_id, snapshot)

	# Log suspicious activity
	GameLog.warn("FlywheelService: Player %s suspicious activity - %s: %.2f" % [player_id, sub_meter, value])

	# Reset per-session counters to avoid spamming snapshots
	_reset_player_per_session_counters(player_id)

func _get_recent_player_activity(player_id: String, sub_meter: String) -> Array:
	var flywheel = _player_flywheels.get(player_id, {})
	match sub_meter:
		"movement":
			return [flywheel.get("movement", {})]
		"combat_hit_timing":
			return flywheel.get("combat_hits", {}).get("hit_timing", [])
		"chat":
			return [flywheel.get("chat", {})]
		"trade":
			return [flywheel.get("trade", {})]
		"loot":
			return [flywheel.get("loot", {})]
		"instance":
			return [flywheel.get("instances", {})]
		_ :
			return []

func _get_player_sub_meter_values(player_id: String) -> Dictionary:
	var flywheel = _player_flywheels.get(player_id, {})
	var result: Dictionary = {}

	for meter in flywheel.keys():
		result[meter] = flywheel[meter]

	return result

func _get_session_minutes(player_id: String) -> float:
	# This would need session tracking in practice
	return 0.0

func _get_player_snapshot_count(player_id: String) -> int:
	# This would need to track snapshots per session in practice
	return 0

func _reset_player_per_session_counters(player_id: String) -> void:
	var flywheel = _player_flywheels.get(player_id)
	if flywheel:
		flywheel["combat_hits"]["hit_timing"] = []

func _persist_player_snapshot(player_id: String, snapshot: Dictionary) -> void:
	var store := DictStore.new()
	var key := "flywheel:suspicious:" + player_id
	store.set_value(key, snapshot, SNAPSHOT_KEY_TTL_SECONDS)

func _get_current_tick() -> int:
	return 0

func _get_uptime_seconds() -> float:
	return Time.get_unix_time_from_system()

func _is_resource_pressure_high() -> bool:
	var now: int = Time.get_unix_time_from_system()
	var resource_pressure = _resource_pressure

	if resource_pressure["cpu_high"]:
		if resource_pressure["cpu_high_start"] == 0:
			resource_pressure["cpu_high_start"] = now
		elif now - resource_pressure["cpu_high_start"] >= 30:
			return true
	else:
		resource_pressure["cpu_high_start"] = 0

	return resource_pressure["memory_high"] or resource_pressure["backlog_growing"]

func _update_resource_pressure() -> void:
	var now: int = Time.get_unix_time_from_system()
	var resource_pressure = _resource_pressure
	resource_pressure["last_check"] = now

	resource_pressure["cpu_high"] = false
	resource_pressure["memory_high"] = false
	resource_pressure["backlog_growing"] = false

## ============================================================================
## PUBLIC API
## ============================================================================

## Get whether a player's flywheel is currently hot (suspicious)
func get_flywheel_hot(player_id: String) -> bool:
	var store := DictStore.new()
	var key := "flywheel:suspicious:" + player_id

	if store.has_key(key):
		var snapshot = store.get_value(key)
		if snapshot is Dictionary:
			var snapshot_time = snapshot.get("timestamp_ms", 0)
			var age_seconds = (Time.get_unix_time_from_system() * 1000 - snapshot_time) / 1000.0

			if age_seconds < SNAPSHOT_KEY_TTL_SECONDS:
				return true

	return false

## Check if a player has recent suspicious activity
func has_recent_suspicious_activity(player_id: String) -> bool:
	return get_flywheel_hot(player_id)

## Get current momentum for a shard
func get_shard_momentum(shard_id: String) -> float:
	return _shard_momenta.get(shard_id, 0.0)

## Get current sub-meter values for a shard
func get_shard_sub_meters(shard_id: String) -> Dictionary:
	return _shard_flywheels.get(shard_id, {})

## Get current sub-meter values for a player
func get_player_flywheel_state(player_id: String) -> Dictionary:
	return _player_flywheels.get(player_id, {})