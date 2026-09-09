## ShardManager - Multi-shard/multi-server support
## Manages shard ID, player routing, and cross-shard awareness
extends Node
const DictStore = preload("res://adapters/persistence/dict_store.gd")

# Shard identification
var shard_id: String = "shard_1"
var shard_name: String = "Alpha"
var is_primary: bool = true

# World configuration
var world_name: String = "Synmergia"
var world_size_km2: float = 200.0  # ~200 sq km default (bigger than RYL2, massive)
var max_players_per_shard: int = 5000  # Soft cap per shard

# Shard state
var _online_players: int = 0
var _server_status: String = "online"  # online, maintenance, full

# Cross-shard awareness (for future meshing)
var _connected_shards: Array[String] = []
var _shard_info: Dictionary = {}  # shard_id -> {name, players, status}
const _kv_prefix := "shard:"

signal shard_status_changed(shard_id: String, status: String)
signal player_count_changed(count: int)

func _ready() -> void:
	_load_shards()
	GameLog.info("ShardManager: Ready as %s (%s)" % [shard_id, shard_name])

## Configure this shard
func configure(config: Dictionary) -> void:
	shard_id = config.get("shard_id", "shard_1")
	shard_name = config.get("shard_name", "Alpha")
	is_primary = config.get("is_primary", true)
	world_name = config.get("world_name", "Synmergia")
	world_size_km2 = config.get("world_size_km2", 200.0)
	max_players_per_shard = config.get("max_players_per_shard", 5000)

	GameLog.info("ShardManager: Configured as %s (%s), world size: %.0f km2" % [shard_id, shard_name, world_size_km2])

## Start the shard server (initialize state, accept players)
func start_server() -> void:
	_server_status = "online"
	shard_status_changed.emit(shard_id, _server_status)
	GameLog.info("ShardManager: Server started for %s" % shard_id)


## Player tracking
func player_connected() -> void:
	_online_players += 1
	player_count_changed.emit(_online_players)

func player_disconnected() -> void:
	_online_players = max(0, _online_players - 1)
	player_count_changed.emit(_online_players)

func get_player_count() -> int:
	return _online_players

func is_full() -> bool:
	return _online_players >= max_players_per_shard

## Server status
func set_status(status: String) -> void:
	_server_status = status
	shard_status_changed.emit(shard_id, status)
	GameLog.info("ShardManager: Status changed to %s" % status)

func get_status() -> String:
	return _server_status

## Cross-shard info (for future meshing)
func register_connected_shard(other_shard_id: String, info: Dictionary = {}) -> void:
	if not _connected_shards.has(other_shard_id):
		_connected_shards.append(other_shard_id)
	_shard_info[other_shard_id] = info
	_persist_shard(other_shard_id)
	GameLog.debug("ShardManager: Connected to shard %s" % other_shard_id)

func unregister_shard(other_shard_id: String) -> void:
	_connected_shards.erase(other_shard_id)
	_shard_info.erase(other_shard_id)
	_persist_shard(other_shard_id)
	GameLog.debug("ShardManager: Disconnected from shard %s" % other_shard_id)

func get_connected_shards() -> Array[String]:
	return _connected_shards

func get_shard_info(shard_id: String) -> Dictionary:
	return _shard_info.get(shard_id, {})

## For transferring players between shards (future)
func can_transfer_to(target_shard_id: String) -> bool:
	if target_shard_id == shard_id:
		return true  # Local transfer

	if not _connected_shards.has(target_shard_id):
		return false

	var info = _shard_info.get(target_shard_id, {})
	return info.get("status", "") == "online" and info.get("players", 0) < info.get("max_players", 5000)

## World coordinates (for seamless world)
# Converts local position to world-wide coordinates
var _world_offset_x: float = 0.0
var _world_offset_z: float = 0.0

func set_world_offset(offset_x: float, offset_z: float) -> void:
	_world_offset_x = offset_x
	_world_offset_z = offset_z

func get_world_offset() -> Vector2:
	return Vector2(_world_offset_x, _world_offset_z)

func local_to_world(local_pos: Vector3) -> Vector3:
	return Vector3(local_pos.x + _world_offset_x, local_pos.y, local_pos.z + _world_offset_z)

func world_to_local(world_pos: Vector3) -> Vector3:
	return Vector3(world_pos.x - _world_offset_x, world_pos.y, world_pos.z - _world_offset_z)

## Generate shard config for new shards (admin tool)
static func generate_shard_config(shard_number: int, total_shards: int, world_size: float) -> Dictionary:
	var row = (shard_number - 1) / 4
	var col = (shard_number - 1) % 4

	# Divide world into grid for sharding
	var world_per_shard = world_size / sqrt(total_shards)
	var offset_x = col * world_per_shard * 1000  # Convert km to units (assuming 1 unit = 1m)
	var offset_z = row * world_per_shard * 1000

	return {
		"shard_id": "shard_%d" % shard_number,
		"shard_name": "Shard %d" % shard_number,
		"is_primary": shard_number == 1,
		"world_offset_x": offset_x,
		"world_offset_z": offset_z,
		"world_size_km2": world_per_shard * world_per_shard
	}

func _load_shards() -> void:
	var ds := DictStore.new()
	var keys: Array = ds.all_keys()
	for key in keys:
		if key.begins_with(_kv_prefix):
			var shard_id := key.substr(_kv_prefix.length())
			var data: Dictionary = ds.get(key)
			if not data.is_empty():
				_shard_info[shard_id] = data
				if not _connected_shards.has(shard_id):
					_connected_shards.append(shard_id)
	GameLog.info("ShardManager: Loaded %d shards from persistence" % _shard_info.size())

func _persist_shard(shard_id: String) -> void:
	var ds := DictStore.new()
	var key := _kv_prefix + shard_id
	if _shard_info.has(shard_id) and not _shard_info[shard_id].is_empty():
		ds.set(key, _shard_info[shard_id])
	else:
		ds.erase(key)
