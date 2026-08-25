## RespawnService - Manages all respawn modes
## Flexible respawn system supporting timed, ankh, revive, and PVP modes
class_name RespawnService
extends Node

signal respawn_initiated(player: Entity, mode: RespawnMode, data: Dictionary)
signal respawn_completed(player: Entity, respawn_point: Vector3)
signal respawn_canceled(player: Entity, reason: String)
signal revive_started(target: Entity, healer: Entity)
signal revive_completed(target: Entity, healer: Entity)
signal revive_interrupted(target: Entity, healer: Entity, reason: String)
signal karma_gained(entity_id: String, amount: int, reason: String)
signal karma_lost(entity_id: String, amount: int, reason: String)

## Respawn modes
enum RespawnMode {
	TIMED,           # Standard timed respawn
	ANKH,            # Respawn at bound ankh
	REVIVE,          # Resurrected by another player
	SELF_REVIVE,     # Item/spell self-resurrect
	ARENA_TEAM,      # Arena team respawn
	CONTESTED,       # Fight for respawn
	GATEWAY,         # Respawn at zone gateway
	SAFE_ZONE,       # Safe area respawn with invincibility
}

## Revive settings
const REVIVE_CAST_TIME: float = 3.0  # Seconds to cast revive
const REVIVE_RANGE: float = 5.0      # Must be this close
const REVIVE_COOLDOWN: float = 30.0  # Seconds between revives
const REVIVE_KARMA_REWARD: int = 10  # Karma for friendly revive
const REVIVE_KARMA_PENALTY_CROSS_FACTION: int = 5  # Extra karma for cross-faction revive
const REVIVE_ABUSE_THRESHOLD: int = 10  # Revives per hour = abuse flag

# State tracking
var _active_revives: Dictionary = {}  # target_id -> {healer, start_time, cast_time}
var _revive_cooldowns: Dictionary = {}  # healer_id -> last_revoke_time
var _karma: Dictionary = {}  # entity_id -> karma amount
var _revive_counts: Dictionary = {}  # entity_id -> count in last hour
var _abuse_flags: Dictionary = {}  # entity_id -> abuse_count

# Zone respawn configs
var _zone_configs: Dictionary = {}  # zone_id -> ZoneRespawnConfig

class ZoneRespawnConfig:
	var default_mode: RespawnMode = RespawnMode.ANKH
	var timed_respawn_seconds: float = 10.0
	var ankh_required: bool = true
	var arena_mode: bool = false
	var max_arena_respawns_per_team: int = 5
	var contested_respawn: bool = false
	var safe_zone_ankh_id: String = ""
	var invincibility_duration: float = 5.0
	var gateway_ids: Array[String] = []

func _ready() -> void:
	Logger.info("RespawnService: Flexible respawn system initialized")

## Register a player
func register_player(player: Entity) -> void:
	if not _karma.has(player.entity_id):
		_karma[player.entity_id] = 0
		_revive_counts[player.entity_id] = 0

## Get karma for entity
func get_karma(entity_id: String) -> int:
	return _karma.get(entity_id, 0)

## Add karma
func add_karma(entity_id: String, amount: int, reason: String) -> void:
	_karma[entity_id] = _karma.get(entity_id, 0) + amount
	karma_gained.emit(entity_id, amount, reason)

## Remove karma
func remove_karma(entity_id: String, amount: int, reason: String) -> void:
	_karma[entity_id] = max(0, _karma.get(entity_id, 0) - amount)
	karma_lost.emit(entity_id, amount, reason)

## Initiate respawn for a player
func initiate_respawn(player: Entity, zone_id: String = "") -> bool:
	var config := _get_zone_config(zone_id)
	var mode: RespawnMode = config.default_mode
	var respawn_data := {}
	
	# Check what modes are available
	var available_modes := get_available_respawn_modes(player, zone_id)
	
	if available_modes.is_empty():
		Logger.warn("RespawnService: No respawn modes available for %s" % player.display_name)
		return false
	
	# Priority: Revive > Ankh > Timed
	if available_modes.has(RespawnMode.REVIVE):
		mode = RespawnMode.REVIVE
	elif available_modes.has(RespawnMode.ANKH):
		mode = RespawnMode.ANKH
	elif available_modes.has(RespawnMode.TIMED):
		mode = RespawnMode.TIMED
	else:
		mode = available_modes[0]
	
	# Build respawn data
	match mode:
		RespawnMode.ANKH:
			var ankh := _get_bound_ankh(player)
			if ankh:
				respawn_data = {
					"ankh_id": ankh.ankh_id,
					"position": ankh.global_position,
					"respawn_time": ankh.get_respawn_time(config.timed_respawn_seconds)
				}
		RespawnMode.TIMED:
			respawn_data = {
				"respawn_time": config.timed_respawn_seconds,
				"position": _get_default_respawn_position(player)
			}
		RespawnMode.GATEWAY:
			respawn_data = {
				"gateway_id": _get_nearest_gateway(player, config.gateway_ids),
				"respawn_time": config.timed_respawn_seconds * 0.5
			}
		RespawnMode.SAFE_ZONE:
			respawn_data = {
				"ankh_id": config.safe_zone_ankh_id,
				"invincibility_duration": config.invincibility_duration,
				"position": _get_safe_zone_position(player, config.safe_zone_ankh_id)
			}
		RespawnMode.ARENA_TEAM:
			var team := _get_arena_team(player)
			respawn_data = {
				"team_id": team,
				"remaining_respawns": _get_team_respawns(player, config),
				"safe_zone_position": true
			}
	
	respawn_initiated.emit(player, mode, respawn_data)
	Logger.info("RespawnService: %s initiating respawn in mode %s" % [player.display_name, RespawnMode.keys()[mode]])
	
	# Start the respawn
	_start_respawn(player, mode, respawn_data)
	return true

## Get available respawn modes for a player
func get_available_respawn_modes(player: Entity, zone_id: String = "") -> Array[RespawnMode]:
	var available: Array[RespawnMode] = []
	var config := _get_zone_config(zone_id)
	
	# Timed - always available
	available.append(RespawnMode.TIMED)
	
	# Ankh - if player has bound one and zone allows
	if player.respawn_ankh_id != "" and not config.ankh_required:
		var ankh := _get_ankh_by_id(player.respawn_ankh_id)
		if ankh and ankh.can_bind(player):
			available.append(RespawnMode.ANKH)
	
	# Gateway - if in zone with gateways
	if not config.gateway_ids.is_empty():
		available.append(RespawnMode.GATEWAY)
	
	# Safe zone - always for arena/pvp
	if config.safe_zone_ankh_id != "":
		available.append(RespawnMode.SAFE_ZONE)
	
	# Arena team respawn
	if config.arena_mode:
		available.append(RespawnMode.ARENA_TEAM)
	
	# Revive - check for nearby healers
	var healers := _get_nearby_potential_healers(player)
	if not healers.is_empty():
		available.append(RespawnMode.REVIVE)
	
	return available

## Start a revival attempt (healer initiates)
func start_revival(healer: Entity, target: Entity) -> bool:
	# Check cooldown
	if _is_on_revival_cooldown(healer):
		return false
	
	# Check range
	var distance := healer.global_position.distance_to(target.global_position)
	if distance > REVIVE_RANGE:
		return false
	
	# Check target state
	if not target.health_component or not target.health_component.is_dead():
		return false
	
	# Check karma (anti-abuse)
	if _check_revive_abuse(healer):
		Logger.warn("RespawnService: Revive abuse detected for %s" % healer.display_name)
		return false
	
	# Start revive
	_active_revives[target.entity_id] = {
		"healer": healer,
		"target": target,
		"start_time": Time.get_ticks_msec(),
		"cast_time": REVIVE_CAST_TIME
	}
	
	revive_started.emit(target, healer)
	Logger.info("RespawnService: %s starting revival on %s" % [healer.display_name, target.display_name])
	
	# TODO: Start visual effect on target
	
	return true

## Complete a revival
func complete_revival(target_id: String) -> bool:
	if not _active_revives.has(target_id):
		return false
	
	var revive_data: Dictionary = _active_revives[target_id]
	var healer: Entity = revive_data["healer"]
	var target: Entity = revive_data["target"]
	
	# Remove from active
	_active_revives.erase(target_id)
	
	# Set cooldown for healer
	_revive_cooldowns[healer.entity_id] = Time.get_ticks_msec()
	
	# Track revive count
	_increment_revoke_count(healer.entity_id)
	
	# Karma reward
	var karma_amount := REVIVE_KARMA_REWARD
	
	# Cross-faction bonus
	if healer.faction_id != target.faction_id:
		karma_amount += REVIVE_KARMA_PENALTY_CROSS_FACTION
		add_karma(healer.entity_id, karma_amount, "Cross-faction revival")
	else:
		add_karma(healer.entity_id, karma_amount, "Friendly revival")
	
	# Respawn target
	_do_respawn_at(target, healer.global_position, RespawnMode.REVIVE)
	
	revive_completed.emit(target, healer)
	Logger.info("RespawnService: %s revived %s" % [healer.display_name, target.display_name])
	
	return true

## Interrupt a revival
func interrupt_revival(target_id: String, reason: String) -> void:
	if not _active_revives.has(target_id):
		return
	
	var revive_data: Dictionary = _active_revives[target_id]
	var healer: Entity = revive_data["healer"]
	var target: Entity = revive_data["target"]
	
	_active_revives.erase(target_id)
	
	# Possible karma penalty for interrupted revive?
	
	revive_interrupted.emit(target, healer, reason)
	Logger.info("RespawnService: Revival of %s interrupted by %s: %s" % [target.display_name, healer.display_name, reason])

## Cancel a revival
func cancel_revival(healer_id: String) -> void:
	for target_id in _active_revives.keys():
		var data: Dictionary = _active_revives[target_id]
		if data["healer"].entity_id == healer_id:
			_active_revives.erase(target_id)
			revive_interrupted.emit(data["target"], data["healer"], "Cancelled")
			break

## Get revival progress
func get_revival_progress(target_id: String) -> float:
	if not _active_revives.has(target_id):
		return 0.0
	
	var data: Dictionary = _active_revives[target_id]
	var elapsed_ms := Time.get_ticks_msec() - data["start_time"]
	var elapsed := elapsed_ms / 1000.0
	
	return clamp(elapsed / data["cast_time"], 0.0, 1.0)

## Internal: Start respawn
func _start_respawn(player: Entity, mode: RespawnMode, data: Dictionary) -> void:
	# This would be connected to a timer in the player's health component
	player.health_component._pending_respawn = true
	player.health_component._respawn_mode = mode
	player.health_component._respawn_data = data

## Internal: Execute respawn
func _do_respawn_at(player: Entity, position: Vector3, mode: RespawnMode) -> void:
	player.health_component._is_dead = false
	player.health_component.current_health = player.health_component.max_health
	player.global_position = position
	
	player.health_component.respawned.emit()
	EventBus.entity_spawned.emit(player)
	
	respawn_completed.emit(player, position)

## Internal: Get zone config
func _get_zone_config(zone_id: String) -> ZoneRespawnConfig:
	if not _zone_configs.has(zone_id):
		_zone_configs[zone_id] = ZoneRespawnConfig.new()
	return _zone_configs[zone_id]

## Internal: Get player's bound ankh
func _get_bound_ankh(player: Entity) -> Ankh:
	if player.respawn_ankh_id == "":
		return null
	return _get_ankh_by_id(player.respawn_ankh_id)

## Internal: Get ankh by ID
func _get_ankh_by_id(ankh_id: String) -> Ankh:
	var ankhs := get_tree().get_nodes_in_group("ankhs")
	for ankh in ankhs:
		if ankh.ankh_id == ankh_id:
			return ankh
	return null

## Internal: Get default respawn position
func _get_default_respawn_position(player: Entity) -> Vector3:
	# Fallback: zone spawn point
	return Vector3(0, 0, 0)  # TODO: Zone spawn point

## Internal: Check revive cooldown
func _is_on_revival_cooldown(healer: Entity) -> bool:
	if not _revive_cooldowns.has(healer.entity_id):
		return false
	var last_revoke_ms: int = _revive_cooldowns[healer.entity_id]
	var elapsed := Time.get_ticks_msec() - last_revoke_ms
	return elapsed < (REVIVE_COOLDOWN * 1000)

## Internal: Check revive abuse
func _check_revoke_abuse(healer: Entity) -> bool:
	_cleanup_old_revoke_counts()
	var count := _revive_counts.get(healer.entity_id, 0)
	return count >= REVIVE_ABUSE_THRESHOLD

## Internal: Increment revive count
func _increment_revoke_count(entity_id: String) -> void:
	_cleanup_old_revoke_counts()
	_revive_counts[entity_id] = _revive_counts.get(entity_id, 0) + 1

## Internal: Cleanup old counts
func _cleanup_old_revoke_counts() -> void:
	# Reset counts hourly (simplified)
	var now := Time.get_unix_time_from_system()
	# TODO: Implement hourly reset

## Internal: Get nearby healers
func _get_nearby_potential_healers(player: Entity) -> Array[Entity]:
	var nearby: Array[Entity] = []
	var entities := EntityService.get_entities_in_radius(player.global_position, REVIVE_RANGE)
	for entity in entities:
		if entity != player and entity.health_component and not entity.health_component.is_dead():
			if entity is Player or entity.controller_type == Entity.ControllerType.HUMAN:
				nearby.append(entity)
	return nearby

## Internal: Get arena team
func _get_arena_team(player: Entity) -> int:
	# TODO: Get from party/raid system
	return player.team_id

## Internal: Get team respawns remaining
func _get_team_respawns(player: Entity, config: ZoneRespawnConfig) -> int:
	# TODO: Per-team tracking
	return config.max_arena_respawns_per_team

## Internal: Get nearest gateway
func _get_nearest_gateway(player: Entity, gateway_ids: Array[String]) -> String:
	# TODO: Implement gateway lookup
	return gateway_ids[0] if not gateway_ids.is_empty() else ""

## Internal: Get safe zone position
func _get_safe_zone_position(player: Entity, safe_zone_ankh_id: String) -> Vector3:
	var ankh := _get_ankh_by_id(safe_zone_ankh_id)
	if ankh:
		return ankh.global_position
	return player.global_position

## Process revival timers (call from _process)
func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	var to_remove: Array[String] = []
	
	for target_id in _active_revives.keys():
		var data: Dictionary = _active_revives[target_id]
		var elapsed := now - data["start_time"]
		
		# Check if healer moved too far
		var healer: Entity = data["healer"]
		var target: Entity = data["target"]
		var distance := healer.global_position.distance_to(target.global_position)
		
		if distance > REVIVE_RANGE:
			interrupt_revival(target_id, "Healer moved out of range")
			to_remove.append(target_id)
			continue
		
		# Check if complete
		if elapsed >= data["cast_time"] * 1000:
			complete_revival(target_id)
			to_remove.append(target_id)
	
	for target_id in to_remove:
		_active_revives.erase(target_id)

## Configure a zone's respawn settings
func configure_zone(zone_id: String, config: Dictionary) -> void:
	var zone_config := _get_zone_config(zone_id)
	
	if config.has("default_mode"):
		zone_config.default_mode = config["default_mode"]
	if config.has("timed_respawn_seconds"):
		zone_config.timed_respawn_seconds = config["timed_respawn_seconds"]
	if config.has("ankh_required"):
		zone_config.ankh_required = config["ankh_required"]
	if config.has("arena_mode"):
		zone_config.arena_mode = config["arena_mode"]
	if config.has("max_arena_respawns_per_team"):
		zone_config.max_arena_respawns_per_team = config["max_arena_respawns_per_team"]
	if config.has("contested_respawn"):
		zone_config.contested_respawn = config["contested_respawn"]
	if config.has("safe_zone_ankh_id"):
		zone_config.safe_zone_ankh_id = config["safe_zone_ankh_id"]
	if config.has("invincibility_duration"):
		zone_config.invincibility_duration = config["invincibility_duration"]
	if config.has("gateway_ids"):
		zone_config.gateway_ids = config["gateway_ids"]
