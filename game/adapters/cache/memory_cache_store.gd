extends "res://adapters/cache/cache_store.gd"
class_name MemoryCacheStore

# In-memory implementation of CacheStore.
# Real TTL enforcement via a deadline timestamp. Sweep happens
# lazily on access, plus an explicit sweep_expired() for callers
# that want to bound memory.


var _kv: Dictionary = {}        # key -> value
var _expires: Dictionary = {}   # key -> unix timestamp (0 = no expiry)
var _hashes: Dictionary = {}    # key -> {field: value}
var _sets: Dictionary = {}      # key -> Array[String]
var _lists: Dictionary = {}     # key -> Array


func open(config: Dictionary) -> int:
	_kv.clear()
	_expires.clear()
	_hashes.clear()
	_sets.clear()
	_lists.clear()
	return 0


func close() -> void:
	_kv.clear()
	_expires.clear()
	_hashes.clear()
	_sets.clear()
	_lists.clear()


func healthy() -> bool:
	return true


func reset() -> void:
	open({})


# Sweep all expired keys. Call from a periodic timer in services
# that hold a lot of short-TTL data.
func sweep_expired() -> int:
	var now := Time.get_unix_time_from_system()
	var removed := 0
	for k in _expires.keys():
		var exp: float = _expires[k]
		if exp > 0 and now >= exp:
			_kv.erase(k)
			_expires.erase(k)
			removed += 1
	return removed


func keys() -> Array:
	sweep_expired()
	return _kv.keys()


# --- Basic KV ---

func fetch(key: String) -> Variant:
	if _is_expired(key):
		_kv.erase(key)
		_expires.erase(key)
		return null
	return _kv.get(key, null)


func store(key: String, value: Variant, ttl_sec: int = 0) -> int:
	_kv[key] = value
	if ttl_sec > 0:
		_expires[key] = Time.get_unix_time_from_system() + ttl_sec
	else:
		_expires.erase(key)
	return 1


func set_nx(key: String, value: Variant, ttl_sec: int = 0) -> bool:
	if _kv.has(key) and not _is_expired(key):
		return false
	store(key, value, ttl_sec)
	return true


func delete(key: String) -> int:
	var had := _kv.has(key) or _hashes.has(key) or _sets.has(key) or _lists.has(key)
	_kv.erase(key)
	_expires.erase(key)
	_hashes.erase(key)
	_sets.erase(key)
	_lists.erase(key)
	return 1 if had else 0


func exists(key: String) -> bool:
	if _is_expired(key):
		return false
	return _kv.has(key) or _hashes.has(key) or _sets.has(key) or _lists.has(key)


func expire(key: String, ttl_sec: int) -> int:
	if not _kv.has(key):
		return -1
	if ttl_sec <= 0:
		_expires.erase(key)
		return 0
	_expires[key] = Time.get_unix_time_from_system() + ttl_sec
	return 1


# --- Counters ---

func incr(key: String) -> int:
	var cur = _kv.get(key, 0)
	if typeof(cur) != TYPE_INT and typeof(cur) != TYPE_FLOAT:
		cur = 0
	var v: int = int(cur) + 1
	_kv[key] = v
	return v


func incr_by(key: String, by: int) -> int:
	var cur = _kv.get(key, 0)
	if typeof(cur) != TYPE_INT and typeof(cur) != TYPE_FLOAT:
		cur = 0
	var v: int = int(cur) + by
	_kv[key] = v
	return v


func incr_with_ttl(key: String, ttl_sec: int) -> int:
	var v := incr(key)
	_expires[key] = Time.get_unix_time_from_system() + ttl_sec
	return v


# --- Hashes ---

func hset(key: String, field: String, value: Variant) -> int:
	if not _hashes.has(key):
		_hashes[key] = {}
	(_hashes[key] as Dictionary)[field] = value
	return 1


func hget(key: String, field: String) -> Variant:
	if not _hashes.has(key):
		return null
	return (_hashes[key] as Dictionary).get(field, null)


func hget_all(key: String) -> Dictionary:
	if not _hashes.has(key):
		return {}
	return (_hashes[key] as Dictionary).duplicate()


func hdel(key: String, field: String) -> int:
	if not _hashes.has(key):
		return 0
	var h: Dictionary = _hashes[key]
	if h.has(field):
		h.erase(field)
		return 1
	return 0


# --- Sets ---

func sadd(key: String, member: String) -> int:
	if not _sets.has(key):
		_sets[key] = []
	var s: Array = _sets[key]
	if not s.has(member):
		s.append(member)
		return 1
	return 0


func srem(key: String, member: String) -> int:
	if not _sets.has(key):
		return 0
	var s: Array = _sets[key]
	var idx := s.find(member)
	if idx >= 0:
		s.remove_at(idx)
		return 1
	return 0


func smembers(key: String) -> Array:
	if not _sets.has(key):
		return []
	return (_sets[key] as Array).duplicate()


func sismember(key: String, member: String) -> bool:
	if not _sets.has(key):
		return false
	return (_sets[key] as Array).has(member)


# --- Lists ---

func lpush(key: String, value: Variant) -> int:
	if not _lists.has(key):
		_lists[key] = []
	(_lists[key] as Array).push_front(value)
	return (_lists[key] as Array).size()


func rpush(key: String, value: Variant) -> int:
	if not _lists.has(key):
		_lists[key] = []
	(_lists[key] as Array).append(value)
	return (_lists[key] as Array).size()


func lpop(key: String) -> Variant:
	if not _lists.has(key):
		return null
	var l: Array = _lists[key]
	if l.is_empty():
		return null
	return l.pop_front()


func lrange(key: String, start: int, stop: int) -> Array:
	if not _lists.has(key):
		return []
	var l: Array = _lists[key]
	var lo := maxi(start, 0)
	var hi: int
	if stop < 0:
		hi = l.size() - 1
	else:
		hi = mini(stop, l.size() - 1)
	if lo > hi:
		return []
	return l.slice(lo, hi + 1)


func llen(key: String) -> int:
	if not _lists.has(key):
		return 0
	return (_lists[key] as Array).size()


# --- Pub/sub (no-op for in-memory) ---

func publish(channel: String, message: Variant) -> int:
	# No subscriber model in memory impl. Test/observe with the
	# capture_subscriptions() helper below.
	return 0


# --- Test/dev helpers ---

func _is_expired(key: String) -> bool:
	if not _expires.has(key):
		return false
	var exp: float = _expires[key]
	if exp <= 0:
		return false
	return Time.get_unix_time_from_system() >= exp
