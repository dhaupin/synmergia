## PlayerLockService - Reusable player locking system
const DictStore = preload("res://adapters/persistence/dict_store.gd")
## Prevents player movement, skills, and other actions during locked states
## Used by: Trade, Mounts, Follow, Cinematics, Cutscenes, Dialogues, etc.
extends Node

# Lock reasons enum
enum LockReason {
	NONE = 0,
	TRADE = 1,
	MOUNT = 2,
	FOLLOW = 4,
	CINEMATIC = 8,
	DIALOGUE = 16,
	CAPTURE = 32,
	STUNNED = 64,
	CUSTOM = 128,
}

# Player locks (player_id -> lock_data)
var _player_locks: Dictionary = {}

## DictStore key prefix
const _kv_prefix := "player_lock:"

# Lock configurations
const LOCK_CONFIG: Dictionary = {
	LockReason.TRADE: {
		"blocks_movement": true,
		"blocks_skills": true,
		"blocks_combat": true,
		"blocks_items": false,
		"cancel_on_death": true,
		"cancel_on_teleport": true,
		"priority": 10
	},
	LockReason.MOUNT: {
		"blocks_movement": false,  # Controlled by mount
		"blocks_skills": true,
		"blocks_combat": false,
		"blocks_items": true,
		"cancel_on_death": true,
		"cancel_on_teleport": true,
		"priority": 5
	},
	LockReason.FOLLOW: {
		"blocks_movement": true,
		"blocks_skills": false,
		"blocks_combat": true,
		"blocks_items": false,
		"cancel_on_death": true,
		"cancel_on_teleport": true,
		"priority": 8
	},
	LockReason.CINEMATIC: {
		"blocks_movement": true,
		"blocks_skills": true,
		"blocks_combat": true,
		"blocks_items": true,
		"cancel_on_death": false,
		"cancel_on_teleport": false,
		"priority": 20
	},
	LockReason.DIALOGUE: {
		"blocks_movement": true,
		"blocks_skills": true,
		"blocks_combat": true,
		"blocks_items": true,
		"cancel_on_death": true,
		"cancel_on_teleport": true,
		"priority": 15
	},
	LockReason.CAPTURE: {
		"blocks_movement": true,
		"blocks_skills": true,
		"blocks_combat": true,
		"blocks_items": true,
		"cancel_on_death": true,
		"cancel_on_teleport": true,
		"priority": 25
	},
	LockReason.STUNNED: {
		"blocks_movement": true,
		"blocks_skills": true,
		"blocks_combat": true,
		"blocks_items": true,
		"cancel_on_death": false,
		"cancel_on_teleport": false,
		"priority": 30
	},
}

# Signals
signal player_locked(player_id: String, reason: int, context: Dictionary)
signal player_unlocked(player_id: String, reason: int, context: Dictionary)
signal lock_updated(player_id: String, reason: int, context: Dictionary)

func _ready() -> void:
	GameLog.info("PlayerLockService: Ready")
	_load_state()

## Lock a player
func lock_player(player_id: String, reason: int, context: Dictionary = {}) -> bool:
	if reason == LockReason.NONE:
		return false

	var lock_data := _get_or_create_lock(player_id)

	# Check if already locked with this reason
	if lock_data["reasons"].has(reason):
		GameLog.debug("PlayerLockService: %s already locked with reason %d" % [player_id, reason])
		return false

	# Add lock reason
	lock_data["reasons"][reason] = {
		"context": context,
		"timestamp": Time.get_unix_time_from_system()
	}

	# Update active flags
	_update_lock_flags(lock_data)

	# Emit signals
	player_locked.emit(player_id, reason, context)
	lock_updated.emit(player_id, _get_highest_priority_reason(lock_data), context)

	GameLog.info("PlayerLockService: %s locked for reason %d" % [player_id, reason])
	return true

## Unlock a player
func unlock_player(player_id: String, reason: int) -> bool:
	if not _player_locks.has(player_id):
		return false

	var lock_data: Dictionary = _player_locks[player_id]
	if not lock_data["reasons"].has(reason):
		return false

	var context: Dictionary = lock_data["reasons"][reason].get("context", {})
	lock_data["reasons"].erase(reason)

	# Update flags
	_update_lock_flags(lock_data)

	# Clean up if no more locks
	if lock_data["reasons"].is_empty():
		_player_locks.erase(player_id)

	# Emit signals
	player_unlocked.emit(player_id, reason, context)
	if _player_locks.has(player_id):
		lock_updated.emit(player_id, _get_highest_priority_reason(_player_locks[player_id]), {})

	GameLog.info("PlayerLockService: %s unlocked from reason %d" % [player_id, reason])
	return true

## Check if player is locked
func is_locked(player_id: String) -> bool:
	return _player_locks.has(player_id) and not _player_locks[player_id]["reasons"].is_empty()

## Check if player has a specific lock reason
func has_lock_reason(player_id: String, reason: int) -> bool:
	if not _player_locks.has(player_id):
		return false
	return _player_locks[player_id]["reasons"].has(reason)

## Check if movement is blocked
func is_movement_blocked(player_id: String) -> bool:
	if not is_locked(player_id):
		return false

	var lock_data: Dictionary = _player_locks[player_id]
	return lock_data["blocks_movement"]

## Check if skills are blocked
func are_skills_blocked(player_id: String) -> bool:
	if not is_locked(player_id):
		return false

	var lock_data: Dictionary = _player_locks[player_id]
	return lock_data["blocks_skills"]

## Check if combat is blocked
func is_combat_blocked(player_id: String) -> bool:
	if not is_locked(player_id):
		return false

	var lock_data: Dictionary = _player_locks[player_id]
	return lock_data["blocks_combat"]

## Check if items are blocked
func are_items_blocked(player_id: String) -> bool:
	if not is_locked(player_id):
		return false

	var lock_data: Dictionary = _player_locks[player_id]
	return lock_data["blocks_items"]

## Get all lock reasons for a player
func get_lock_reasons(player_id: String) -> Array:
	if not _player_locks.has(player_id):
		return []
	var reasons: Array = []
	for reason in _player_locks[player_id]["reasons"].keys():
		reasons.append(reason)
	return reasons

## Get lock context for a reason
func get_lock_context(player_id: String, reason: int) -> Dictionary:
	if not _player_locks.has(player_id):
		return {}
	if not _player_locks[player_id]["reasons"].has(reason):
		return {}
	return _player_locks[player_id]["reasons"][reason].get("context", {})

## Force unlock all (use carefully - typically for cleanup)
func force_unlock_all(player_id: String) -> void:
	if not _player_locks.has(player_id):
		return

	var lock_data: Dictionary = _player_locks[player_id]
	for reason in lock_data["reasons"].keys():
		player_unlocked.emit(player_id, reason, {})

	_player_locks.erase(player_id)
	GameLog.info("PlayerLockService: %s force unlocked all reasons" % player_id)

## Cancel locks for specific events (called by HealthComponent, ZoneManager, etc.)
func cancel_on_death(player_id: String) -> void:
	if not _player_locks.has(player_id):
		return

	var lock_data: Dictionary = _player_locks[player_id]
	var to_remove := []

	for reason in lock_data["reasons"].keys():
		var config: Dictionary = LOCK_CONFIG.get(reason, {})
		if config.get("cancel_on_death", true):
			to_remove.append(reason)

	for reason in to_remove:
		unlock_player(player_id, reason)

func cancel_on_teleport(player_id: String) -> void:
	if not _player_locks.has(player_id):
		return

	var lock_data: Dictionary = _player_locks[player_id]
	var to_remove := []

	for reason in lock_data["reasons"].keys():
		var config: Dictionary = LOCK_CONFIG.get(reason, {})
		if config.get("cancel_on_teleport", true):
			to_remove.append(reason)

	for reason in to_remove:
		unlock_player(player_id, reason)

## Helper: Get or create lock data
func _get_or_create_lock(player_id: String) -> Dictionary:
	if not _player_locks.has(player_id):
		_player_locks[player_id] = {
			"reasons": {},
			"blocks_movement": false,
			"blocks_skills": false,
			"blocks_combat": false,
			"blocks_items": false,
			"highest_priority": 0
		}
	return _player_locks[player_id]

## Helper: Update lock flags based on active reasons
func _update_lock_flags(lock_data: Dictionary) -> void:
	lock_data["blocks_movement"] = false
	lock_data["blocks_skills"] = false
	lock_data["blocks_combat"] = false
	lock_data["blocks_items"] = false
	lock_data["highest_priority"] = 0

	for reason in lock_data["reasons"].keys():
		var config: Dictionary = LOCK_CONFIG.get(reason, {})
		if config.get("blocks_movement", false):
			lock_data["blocks_movement"] = true
		if config.get("blocks_skills", false):
			lock_data["blocks_skills"] = true
		if config.get("blocks_combat", false):
			lock_data["blocks_combat"] = true
		if config.get("blocks_items", false):
			lock_data["blocks_items"] = true

		var priority: int = config.get("priority", 0)
		if priority > lock_data["highest_priority"]:
			lock_data["highest_priority"] = priority

## Helper: Get highest priority reason
func _get_highest_priority_reason(lock_data: Dictionary) -> int:
	var highest: int = LockReason.NONE
	var highest_priority: int = 0

	for reason in lock_data["reasons"].keys():
		var config: Dictionary = LOCK_CONFIG.get(reason, {})
		var priority: int = config.get("priority", 0)
		if priority > highest_priority:
			highest_priority = priority
			highest = reason

	return highest

## == Persistence ============================================================

func _load_state() -> void:
	var store := DictStore.new()
	_player_locks = {}
	for key in store.all_keys():
		if key.begins_with(_kv_prefix):
			var player_id = key.substr(_kv_prefix.length())
			_player_locks[player_id] = store.get(key)

func _persist_lock(player_id: String) -> void:
	var store := DictStore.new()
	if _player_locks.has(player_id):
		store.set(_kv_prefix + player_id, _player_locks[player_id])
	else:
		store.erase(_kv_prefix + player_id)
