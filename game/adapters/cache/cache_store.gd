extends RefCounted
class_name CacheStore

# Base interface for any KV cache backend (Redis, Memcached, in-memory).
# Mirrors the subset of Redis operations the game actually uses.
#
# Methods return:
#   - int count (rows affected, list length, etc.) for mutators
#   - bool for tests
#   - Variant for reads (null = missing key)


func open(config: Dictionary) -> int:
	push_error("CacheStore.connect: not implemented")
	return -1


func close() -> void:
	pass


func healthy() -> bool:
	return false


# --- Basic KV ---

# Returns the value or null if missing.
func fetch(key: String) -> Variant:
	push_error("CacheStore.get: not implemented")
	return null


# ttl_sec = 0 means no expiry. Returns 1 if set, 0 on error.
func store(key: String, value: Variant, ttl_sec: int = 0) -> int:
	push_error("CacheStore.set: not implemented")
	return 0


# Set only if key does not exist. Returns true on success.
func set_nx(key: String, value: Variant, ttl_sec: int = 0) -> bool:
	push_error("CacheStore.set_nx: not implemented")
	return false


# Returns 1 if deleted, 0 if absent.
func delete(key: String) -> int:
	push_error("CacheStore.delete: not implemented")
	return 0


func exists(key: String) -> bool:
	push_error("CacheStore.exists: not implemented")
	return false


# Returns 1 if expiry set, 0 if no change, -1 if key missing.
func expire(key: String, ttl_sec: int) -> int:
	push_error("CacheStore.expire: not implemented")
	return -1


# --- Counters / rate limits ---

# Creates at 0 if missing. Returns new value.
func incr(key: String) -> int:
	push_error("CacheStore.incr: not implemented")
	return 0


func incr_by(key: String, by: int) -> int:
	push_error("CacheStore.incr_by: not implemented")
	return 0


# Create + TTL atomically (for rate-limit windows). Returns new value.
func incr_with_ttl(key: String, ttl_sec: int) -> int:
	push_error("CacheStore.incr_with_ttl: not implemented")
	return 0


# --- Hashes ---

func hset(key: String, field: String, value: Variant) -> int:
	push_error("CacheStore.hset: not implemented")
	return 0


func hget(key: String, field: String) -> Variant:
	push_error("CacheStore.hget: not implemented")
	return null


func hget_all(key: String) -> Dictionary:
	push_error("CacheStore.hget_all: not implemented")
	return {}


func hdel(key: String, field: String) -> int:
	push_error("CacheStore.hdel: not implemented")
	return 0


# --- Sets ---

func sadd(key: String, member: String) -> int:
	push_error("CacheStore.sadd: not implemented")
	return 0


func srem(key: String, member: String) -> int:
	push_error("CacheStore.srem: not implemented")
	return 0


func smembers(key: String) -> Array:
	push_error("CacheStore.smembers: not implemented")
	return []


func sismember(key: String, member: String) -> bool:
	push_error("CacheStore.sismember: not implemented")
	return false


# --- Lists (queues, recent-N) ---

func lpush(key: String, value: Variant) -> int:
	push_error("CacheStore.lpush: not implemented")
	return 0


func rpush(key: String, value: Variant) -> int:
	push_error("CacheStore.rpush: not implemented")
	return 0


func lpop(key: String) -> Variant:
	push_error("CacheStore.lpop: not implemented")
	return null


func lrange(key: String, start: int, stop: int) -> Array:
	push_error("CacheStore.lrange: not implemented")
	return []


func llen(key: String) -> int:
	push_error("CacheStore.llen: not implemented")
	return 0


# --- Pub/sub (best-effort; not all backends support) ---

func publish(channel: String, message: Variant) -> int:
	push_error("CacheStore.publish: not implemented")
	return 0


# --- Bulk KV Operations ---

# Set multiple key-value pairs in one call. `entries` is a Dictionary
# mapping keys to values. `ttl_sec` applies to all entries.
# Returns count of keys set.
func set_many(entries: Dictionary, ttl_sec: int = 0) -> int:
	push_error("CacheStore.set_many: not implemented")
	return 0


# Get multiple values by keys in one call. Returns a Dictionary
# mapping keys to their values (missing keys map to null).
func get_many(keys: Array) -> Dictionary:
	push_error("CacheStore.get_many: not implemented")
	return {}


# Delete multiple keys in one call. Returns count of deleted keys.
func delete_many(keys: Array) -> int:
	push_error("CacheStore.delete_many: not implemented")
	return 0


# --- Observability ---

# Returns connection pool and circuit breaker metrics.
# Keys: active_connections (int), pending_queries (int), circuit_breaker_tripped (bool)
func get_metrics() -> Dictionary:
	return {
		"active_connections": 0,
		"pending_queries": 0,
		"circuit_breaker_tripped": false
	}
