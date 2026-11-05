## RedisShardBus - the cross-process transport (Phase 1 of the mesh).
##
## Backed by a RedisStore talking to the redis-bridge sidecar, so its
## mailboxes live in Redis and survive process boundaries: two shard
## containers pointed at the same REDIS_BRIDGE_URL exchange events. The
## mailbox protocol is the base class's -- only the store differs, which
## is the whole point of the seam.
##
## Env: SHARD_BUS_BACKEND=redis selects this; REDIS_BRIDGE_URL points at
## the sidecar (defaults to the redis_store default when unset).
extends "res://core/mesh/shard_bus.gd"

const RedisStore = preload("res://adapters/cache/redis_store.gd")

var _store_ref = null

func get_id() -> String:
	return "redis"

func get_display_name() -> String:
	return "Redis pub/sub bus"

func open(config: Dictionary) -> int:
	var url := str(config.get("bridge_url", ""))
	if url.is_empty():
		url = OS.get_environment("REDIS_BRIDGE_URL")
	if url.is_empty():
		url = "http://localhost:8081"
	_store_ref = RedisStore.new()
	var rc: int = _store_ref.open({"bridge_url": url})
	if rc != 0:
		_store_ref = null
		return rc
	return 0

func close() -> void:
	if _store_ref != null:
		_store_ref.close()
		_store_ref = null

func _store():
	return _store_ref
