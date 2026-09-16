## FollowService - Player following system
## Allows players to follow other players around the world
## Used for: Group play assistance, NPC quest followers, Mounts, etc.
extends Node

## Resolve CooldownService autoload safely.
func _cooldown():
	var ml = Engine.get_main_loop()
	if ml == null:
		return null
	if not ml is SceneTree:
		return null
	return (ml as SceneTree).root.get_node_or_null("CooldownService")

# QoSService exposes a static facade (QoSService.rate_limit(...)), so a
# const preload here resolves to the class and the static methods still
# dispatch to the singleton at runtime -- no shadow.
const QoSService = preload("res://core/autoload/qos_service.gd")
const DictStore = preload("res://adapters/persistence/dict_store.gd")
# EventHub is an autoload singleton (autoload #19, before this
# service at #77). It is accessed bare so the singleton instance is
# used, not the class -- preloading it here would shadow the
# singleton and break EventHub.player_died.connect(...).
#
# CooldownService is also an autoload singleton (autoload #32, before
# this service). Same rule: accessed bare, no preload.

const _kv_prefix := "follow:player:"

# Follow configurations
const DEFAULT_FOLLOW_RANGE: float = 10.0  # Units - max distance before follow breaks
const FOLLOW_SPEED_BUFF: float = 1.1        # Slight speed boost to catch up
const POSITION_UPDATE_INTERVAL: float = 0.1 # How often to update target position
const CATCHUP_THRESHOLD: float = 5.0       # Distance before catch-up mode activates

# Follow states
enum FollowState {
	IDLE,       # Following but within range
	CATCHING_UP,# Moving to catch up to target
	DISABLED,   # Follow not active
}

# Active follows (follower_id -> follow_data)
var _active_follows: Dictionary = {}

# Process toggle
var _is_processing: bool = false

# Signals
signal follow_started(follower_id: String, target_id: String)
signal follow_cancelled(follower_id: String, target_id: String, reason: String)
signal follow_state_changed(follower_id: String, old_state: int, new_state: int)
signal follow_target_moved(follower_id: String, target_position: Vector3)

func _ready() -> void:
	GameLog.info("FollowService: Ready")
	set_process(false)

	_load_follows()

	# Connect to EventHub for automatic follow cancellation
	if EventHub:
		EventHub.player_died.connect(_on_player_died)
		# Zone transitions - connect via entity_teleported if it exists
		# We'll check for zone_changed signal

func _on_player_died(entity, killer) -> void:
	if entity and entity.has("entity_id"):
		cancel_all_for_player(str(entity.entity_id))

## Called when a player teleports/zones - cancels follow
func _on_zone_changed(player_id: String, old_zone: String, new_zone: String) -> void:
	# Cancel follow when zoning - distance will be huge
	cancel_all_for_player(player_id)

func _process(delta: float) -> void:
	_update_all_follows()

## Request to follow a player (uses CooldownService for throttling)
func request_follow(follower_id: String, target_id: String) -> bool:
	# QoS: Rate limit follow requests
	if QoSService and not QoSService.rate_limit(follower_id, "follow_request"):
		return false

	# Cooldown check
	if _cooldown() and not _cooldown().try_start(follower_id, "follow_request"):
		return false

	# Security: Cannot follow self
	if follower_id == target_id:
		return false

	# Security: Check if already following
	if is_following(follower_id):
		_notify_player(follower_id, "You are already following someone.")
		return false

	# Security: Check if target is being followed
	if is_target_being_followed(target_id):
		_notify_player(follower_id, "%s is already being followed by someone." % target_id)
		return false

	# Security: Range check - must be in range to start following
	if not _is_in_range(follower_id, target_id):
		_notify_player(follower_id, "You must be closer to start following.")
		return false

	# Start the follow
	return _start_follow(follower_id, target_id)

## Start following a target
func _start_follow(follower_id: String, target_id: String) -> bool:
	# Create follow data
	var follow_data := {
		"follower_id": follower_id,
		"target_id": target_id,
		"state": FollowState.IDLE,
		"start_time": Time.get_unix_time_from_system(),
		"last_target_position": Vector3.ZERO,
		"range": DEFAULT_FOLLOW_RANGE,
		"catchup_speed": FOLLOW_SPEED_BUFF
	}

	_active_follows[follower_id] = follow_data

	_persist_follows(follower_id)

	# Lock the follower (blocks movement, combat) but allows skills
	if PlayerLockService:
		PlayerLockService.lock_player(follower_id, PlayerLockService.LockReason.FOLLOW, {
			"target_id": target_id
		})

	# Start processing
	_is_processing = true
	set_process(true)

	follow_started.emit(follower_id, target_id)
	GameLog.info("FollowService: %s started following %s" % [follower_id, target_id])
	return true

## Stop following
func stop_follow(follower_id: String, reason: String = "cancelled") -> bool:
	if not _active_follows.has(follower_id):
		return false

	var follow_data: Dictionary = _active_follows[follower_id]
	var target_id: String = follow_data["target_id"]

	# Unlock the follower
	if PlayerLockService:
		PlayerLockService.unlock_player(follower_id, PlayerLockService.LockReason.FOLLOW)

	_active_follows.erase(follower_id)

	_persist_follows(follower_id)

	# Stop processing if no more follows
	if _active_follows.is_empty():
		_is_processing = false
		set_process(false)

	follow_cancelled.emit(follower_id, target_id, reason)
	_notify_player(follower_id, "Stopped following %s" % target_id)
	GameLog.info("FollowService: %s stopped following %s (%s)" % [follower_id, target_id, reason])
	return true

## Check if a player is following someone
func is_following(player_id: String) -> bool:
	return _active_follows.has(player_id)

## Check if a player is being followed
func is_target_being_followed(target_id: String) -> bool:
	for follow_data in _active_follows.values():
		if follow_data["target_id"] == target_id:
			return true
	return false

## Get follow data
func get_follow_data(follower_id: String) -> Dictionary:
	return _active_follows.get(follower_id, {})

## Get who a player is following
func get_follow_target(follower_id: String) -> String:
	if _active_follows.has(follower_id):
		return _active_follows[follower_id]["target_id"]
	return ""

## Get the follower's target position
func get_target_position(follower_id: String) -> Vector3:
	if not _active_follows.has(follower_id):
		return Vector3.INF

	var target_id: String = _active_follows[follower_id]["target_id"]
	return _get_entity_position(target_id)

## Get distance to follow target
func get_distance_to_target(follower_id: String) -> float:
	if not _active_follows.has(follower_id):
		return -1.0

	var follow_data: Dictionary = _active_follows[follower_id]
	var target_pos: Vector3 = _get_entity_position(follow_data["target_id"])
	var follower_pos: Vector3 = _get_entity_position(follower_id)

	if target_pos == Vector3.INF or follower_pos == Vector3.INF:
		return -1.0

	return follower_pos.distance_to(target_pos)

## Get follow state
func get_follow_state(follower_id: String) -> int:
	if not _active_follows.has(follower_id):
		return FollowState.DISABLED
	return _active_follows[follower_id]["state"]

## Process: Update all active follows
func _update_all_follows() -> void:
	var to_remove := []

	for follower_id in _active_follows.keys():
		var follow_data: Dictionary = _active_follows[follower_id]
		var target_id: String = follow_data["target_id"]

		# Get positions
		var target_pos: Vector3 = _get_entity_position(target_id)
		var follower_pos: Vector3 = _get_entity_position(follower_id)

		# Check if target still exists
		if target_pos == Vector3.INF:
			to_remove.append(follower_id)
			follow_cancelled.emit(follower_id, target_id, "target_not_found")
			continue

		# Check if follower still exists
		if follower_pos == Vector3.INF:
			to_remove.append(follower_id)
			follow_cancelled.emit(follower_id, target_id, "follower_not_found")
			continue

		# Calculate distance
		var distance: float = follower_pos.distance_to(target_pos)
		var follow_range: float = follow_data["range"]

		# Check range
		if distance > follow_range:
			# Out of range - cancel follow
			to_remove.append(follower_id)
			_notify_player(follower_id, "You are too far from %s to continue following." % target_id)
			follow_cancelled.emit(follower_id, target_id, "out_of_range")
			continue

		# Update state based on distance
		var old_state: int = follow_data["state"]
		var new_state: int

		if distance > CATCHUP_THRESHOLD:
			new_state = FollowState.CATCHING_UP
		else:
			new_state = FollowState.IDLE

		if old_state != new_state:
			follow_data["state"] = new_state
			follow_state_changed.emit(follower_id, old_state, new_state)

		# Update target position for movement system
		if target_pos != follow_data["last_target_position"]:
			follow_data["last_target_position"] = target_pos
			follow_target_moved.emit(follower_id, target_pos)

	# Clean up removed follows
	for follower_id in to_remove:
		stop_follow(follower_id, "auto_cancelled")

## Cancel all follows for a player (called when they die, teleport, etc.)
func cancel_all_for_player(player_id: String) -> void:
	# If player is a follower
	if is_following(player_id):
		stop_follow(player_id, "player_state_changed")

	# If player is being followed
	if is_target_being_followed(player_id):
		var followers_to_remove := []
		for follow_data in _active_follows.values():
			if follow_data["target_id"] == player_id:
				followers_to_remove.append(follow_data["follower_id"])

		for follower_id in followers_to_remove:
			stop_follow(follower_id, "target_state_changed")

## Get all active follows (for debug/UI)
func get_all_follows() -> Dictionary:
	return _active_follows.duplicate(true)

## Helper: Check if two entities are in range
func _is_in_range(entity1_id: String, entity2_id: String) -> bool:
	var pos1: Vector3 = _get_entity_position(entity1_id)
	var pos2: Vector3 = _get_entity_position(entity2_id)
	if pos1 == Vector3.INF or pos2 == Vector3.INF:
		return false
	return pos1.distance_to(pos2) <= DEFAULT_FOLLOW_RANGE

## Helper: Get entity position
func _get_entity_position(entity_id: String) -> Vector3:
	if EntityService:
		var entity = EntityService.get_entity(entity_id)
		if entity and is_instance_valid(entity) and entity.has("global_position"):
			var pos = entity.global_position
			# Validate position (prevent NaN/Inf exploits)
			if is_finite(pos):
				return pos
	return Vector3.INF

## Helper: Notify player
func _notify_player(player_id: String, message: String) -> void:
	if NotificationService:
		NotificationService.notify(
			NotificationService.NotificationType.INFO,
			message,
			"FollowService",
			"follow:%s:%s" % [player_id, message.hash()],
			{},
			player_id
		)

func _load_follows() -> void:
	var store := DictStore.new()
	var keys := store.all_keys()
	for key in keys:
		if key.begins_with(_kv_prefix):
			var player_id: String = key.substr(_kv_prefix.length())
			var data: Dictionary = store.get_kv(key)
			if data:
				_active_follows[player_id] = data

func _persist_follows(player_id: String) -> void:
	var store := DictStore.new()
	var key := _kv_prefix + player_id
	if _active_follows.has(player_id) and not _active_follows[player_id].is_empty():
		store.set_kv(key, _active_follows[player_id])
	else:
		store.erase(key)
