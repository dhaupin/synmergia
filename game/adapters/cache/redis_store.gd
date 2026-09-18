extends "res://adapters/cache/cache_store.gd"
class_name RedisStore

# HTTP-backed Redis implementation.
#
# Talks to a small sidecar (redis-bridge) that exposes a Redis
# HTTP API. Pub/sub uses a long-lived SSE or WebSocket connection
# (handled by the sidecar; the adapter just publishes).
#
# Wire protocol (one HTTP call per op):
#   GET  /get?key=...                  -> { value: <any> } | { value: null }
#   POST /set                          { key, value, ttl_sec }
#   POST /set_nx                       { key, value, ttl_sec } -> { ok: true|false }
#   POST /del                          { key } -> { deleted: 0|1 }
#   GET  /exists?key=...               -> { exists: true|false }
#   POST /expire                       { key, ttl_sec } -> { changed: -1|0|1 }
#   POST /incr                         { key, by }       -> { value: N }
#   POST /incr_with_ttl                { key, ttl_sec }  -> { value: N }
#   POST /hset                         { key, field, value }
#   GET  /hget?key=&field=             -> { value }
#   GET  /hget_all?key=                -> { fields: {f: v} }
#   POST /hdel                         { key, field }
#   POST /sadd                         { key, member }
#   POST /srem                         { key, member }
#   GET  /smembers?key=                -> { members: [...] }
#   GET  /sismember?key=&member=       -> { is_member: bool }
#   POST /lpush                        { key, value }
#   POST /rpush                        { key, value }
#   POST /lpop                         { key } -> { value }
#   GET  /lrange?key=&start=&stop=     -> { values: [...] }
#   GET  /llen?key=                    -> { length: N }
#   POST /publish                      { channel, message }
#   GET  /health
#
# Status: SKELETON. connect() pushes an error until the
# redis-bridge sidecar lands. Use MemoryCacheStore for
# tests / dev / offline in the meantime.
#
# Config (from .env):
#   REDIS_HOST=redis
#   REDIS_PORT=6379
#   REDIS_PASSWORD=...
#   REDIS_DB=0
#   REDIS_BRIDGE_URL=http://redis-bridge:8080
#   REDIS_BRIDGE_TIMEOUT_MS=5000


const NotImplemented = "RedisStore: redis-bridge sidecar not yet wired. Use MemoryCacheStore for tests/dev."

var _bridge_url: String = ""
var _http: HTTPRequest
var _parent: Node
var _last_response: Dictionary = {}
var _last_ok: bool = false
var _response_received: bool = false

# Retry configuration
const MAX_RETRIES: int = 3
const BASE_RETRY_DELAY_MS: int = 100
const MAX_RETRY_DELAY_MS: int = 2000

# Circuit breaker state
var _circuit_breaker_failures: int = 0
var _circuit_breaker_tripped: bool = false
var _circuit_breaker_threshold: int = 5
var _circuit_breaker_reset_timeout_ms: int = 30000
var _circuit_breaker_tripped_time: int = 0

# Metrics
var _active_connections: int = 0
var _pending_queries: int = 0


# --- Result type for clean error handling ---
class RedisResult:
	var success: bool = false
	var data: Variant = null
	var error: String = ""
	var error_code: int = 0

	static func ok(value: Variant) -> RedisResult:
		var r := RedisResult.new()
		r.success = true
		r.data = value
		return r

	static func err(msg: String, code: int = -1) -> RedisResult:
		var r := RedisResult.new()
		r.success = false
		r.error = msg
		r.error_code = code
		return r

	func unwrap() -> Variant:
		if not success:
			push_error("RedisResult.unwrap() called on error: " + error)
		return data

	func expect(msg: String) -> Variant:
		if not success:
			push_error(msg + ": " + error)
		return data


# --- Retry wrapper with exponential backoff and circuit breaker ---

func _retry_request(callable: Callable, max_attempts: int = MAX_RETRIES) -> RedisResult:
	if not _http:
		return RedisResult.err("HTTP client not initialized", -1)
	if _circuit_breaker_tripped:
		var now = Time.get_ticks_msec()
		if now - _circuit_breaker_tripped_time >= _circuit_breaker_reset_timeout_ms:
			_circuit_breaker_tripped = false
			_circuit_breaker_failures = 0
		else:
			return RedisResult.err("circuit breaker open", -2)

	var attempt := 0
	var delay_ms := BASE_RETRY_DELAY_MS
	var last_error: String = ""

	while attempt <= max_attempts:
		var result := callable.call()
		if result is RedisResult:
			if result.success:
				_record_success()
				return result
			last_error = result.error
			_record_failure()
		elif result is Dictionary:
			if result.has("ok") and result.get("ok", false):
				_record_success()
				return RedisResult.ok(result)
			last_error = str(result)
			_record_failure()
		else:
			last_error = "unexpected return type: " + str(result)
			_record_failure()
		
		attempt += 1
		if attempt <= max_attempts:
			OS.delay_msec(delay_ms)
			delay_ms = min(delay_ms * 2, MAX_RETRY_DELAY_MS)
	
	return RedisResult.err("Max retries exceeded: " + last_error, -3)


func _blocking_get(path: String) -> bool:
	return _retry_request(func() -> RedisResult:
		_pending_queries += 1
		var url := _bridge_url + path
		var err := _http.request(url, PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
		if err != OK:
			_pending_queries -= 1
			return RedisResult.err("HTTP request error: " + str(err), err)
		var ok := _await_response()
		_pending_queries -= 1
		if not ok:
			return RedisResult.err("Request timeout or failed", -3)
		return RedisResult.ok(_last_response)
	).success


func _blocking_get_with_body(path: String) -> Dictionary:
	return _retry_request(func() -> RedisResult:
		_pending_queries += 1
		var url := _bridge_url + path
		var err := _http.request(url, PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
		if err != OK:
			_pending_queries -= 1
			return RedisResult.err("HTTP request error: " + str(err), err)
		var ok := _await_response()
		_pending_queries -= 1
		if not ok:
			return RedisResult.err("Request timeout or failed", -3)
		return RedisResult.ok(_last_response)
	).data


func _blocking_post(path: String, body: Dictionary) -> Dictionary:
	return _retry_request(func() -> RedisResult:
		_pending_queries += 1
		var url := _bridge_url + path
		var json := JSON.stringify(body)
		var headers := PackedStringArray([
			"Content-Type: application/json",
			"Accept: application/json",
		])
		var err := _http.request(url, headers, HTTPClient.METHOD_POST, json)
		if err != OK:
			_pending_queries -= 1
			return RedisResult.err("HTTP request error: " + str(err), err)
		if not _await_response():
			_pending_queries -= 1
			return RedisResult.err("Request timeout or failed", -3)
		_pending_queries -= 1
		return RedisResult.ok(_last_response)
	).data


func _init(parent: Node = null) -> void:
	_parent = parent


func open(config: Dictionary) -> int:
	_bridge_url = config.get("bridge_url", "")
	if _bridge_url == "":
		push_error(NotImplemented)
		return -1
	if not _parent:
		_parent = Engine.get_main_loop().root if Engine.get_main_loop() else null
	if not _parent:
		push_error("RedisStore: no parent Node for HTTPRequest")
		return -1
	_http = HTTPRequest.new()
	_parent.add_child(_http)
	_http.request_completed.connect(_on_response)
	if not _blocking_get("/health"):
		push_error("RedisStore: bridge %s not reachable" % _bridge_url)
		return -1
	_active_connections = 1
	return 0


func close() -> void:
	if _http and is_instance_valid(_http):
		_http.queue_free()
		_http = null
	_active_connections = 0
	_pending_queries = 0
	_circuit_breaker_failures = 0
	_circuit_breaker_tripped = false
	_circuit_breaker_tripped_time = 0


func healthy() -> bool:
	if not _http:
		return false
	# Check circuit breaker
	if _circuit_breaker_tripped:
		# Auto-reset after timeout
		var now = Time.get_ticks_msec()
		if now - _circuit_breaker_tripped_time >= _circuit_breaker_reset_timeout_ms:
			_circuit_breaker_tripped = false
			_circuit_breaker_failures = 0
		else:
			return false
	return _blocking_get("/health")


# --- Basic KV ---

func fetch(key: String) -> Variant:
	var resp := _blocking_get_with_body("/get?key=" + _url_escape(key))
	if not resp.get("ok", false):
		return null
	return resp.get("value", null)


func store(key: String, value: Variant, ttl_sec: int = 0) -> int:
	return _ok_or_err(_blocking_post("/set", {
		"key": key, "value": value, "ttl_sec": ttl_sec,
	}))


func set_nx(key: String, value: Variant, ttl_sec: int = 0) -> bool:
	var resp := _blocking_post("/set_nx", {
		"key": key, "value": value, "ttl_sec": ttl_sec,
	})
	return bool(resp.get("ok", false))


func delete(key: String) -> int:
	var resp := _blocking_post("/del", {"key": key})
	return int(resp.get("deleted", 0))


func exists(key: String) -> bool:
	var resp := _blocking_get_with_body("/exists?key=" + _url_escape(key))
	return bool(resp.get("exists", false))


func expire(key: String, ttl_sec: int) -> int:
	var resp := _blocking_post("/expire", {"key": key, "ttl_sec": ttl_sec})
	return int(resp.get("changed", -1))


# --- Counters ---

func incr(key: String) -> int:
	var resp := _blocking_post("/incr", {"key": key, "by": 1})
	return int(resp.get("value", 0))


func incr_by(key: String, by: int) -> int:
	var resp := _blocking_post("/incr", {"key": key, "by": by})
	return int(resp.get("value", 0))


func incr_with_ttl(key: String, ttl_sec: int) -> int:
	var resp := _blocking_post("/incr_with_ttl", {"key": key, "ttl_sec": ttl_sec})
	return int(resp.get("value", 0))


# --- Hashes ---

func hset(key: String, field: String, value: Variant) -> int:
	return _ok_or_err(_blocking_post("/hset", {
		"key": key, "field": field, "value": value,
	}))


func hget(key: String, field: String) -> Variant:
	var resp := _blocking_get_with_body(
		"/hget?key=" + _url_escape(key) + "&field=" + _url_escape(field)
	)
	if not resp.get("ok", false):
		return null
	return resp.get("value", null)


func hget_all(key: String) -> Dictionary:
	var resp := _blocking_get_with_body("/hget_all?key=" + _url_escape(key))
	var fields = resp.get("fields", {})
	if fields is Dictionary:
		return fields
	return {}


func hdel(key: String, field: String) -> int:
	return _ok_or_err(_blocking_post("/hdel", {"key": key, "field": field}))


# --- Sets ---

func sadd(key: String, member: String) -> int:
	return _ok_or_err(_blocking_post("/sadd", {"key": key, "member": member}))


func srem(key: String, member: String) -> int:
	return _ok_or_err(_blocking_post("/srem", {"key": key, "member": member}))


func smembers(key: String) -> Array:
	var resp := _blocking_get_with_body("/smembers?key=" + _url_escape(key))
	var members = resp.get("members", [])
	if members is Array:
		return members
	return []


func sismember(key: String, member: String) -> bool:
	var resp := _blocking_get_with_body(
		"/sismember?key=" + _url_escape(key) + "&member=" + _url_escape(member)
	)
	return bool(resp.get("is_member", false))


# --- Lists ---

func lpush(key: String, value: Variant) -> int:
	var resp := _blocking_post("/lpush", {"key": key, "value": value})
	return int(resp.get("length", 0))


func rpush(key: String, value: Variant) -> int:
	var resp := _blocking_post("/rpush", {"key": key, "value": value})
	return int(resp.get("length", 0))


func lpop(key: String) -> Variant:
	var resp := _blocking_post("/lpop", {"key": key})
	if not resp.get("ok", false):
		return null
	return resp.get("value", null)


func lrange(key: String, start: int, stop: int) -> Array:
	var resp := _blocking_get_with_body(
		"/lrange?key=" + _url_escape(key) + "&start=%d&stop=%d" % [start, stop]
	)
	var values = resp.get("values", [])
	if values is Array:
		return values
	return []


func llen(key: String) -> int:
	var resp := _blocking_get_with_body("/llen?key=" + _url_escape(key))
	return int(resp.get("length", 0))


# --- Pub/sub ---

func publish(channel: String, message: Variant) -> int:
	return _ok_or_err(_blocking_post("/publish", {
		"channel": channel, "message": message,
	}))


# --- Bulk KV Operations ---

func set_many(entries: Dictionary, ttl_sec: int = 0) -> int:
	var statements: Array = []
	for key in entries.keys():
		statements.append({
			"op": "set",
			"key": key,
			"value": entries[key],
			"ttl_sec": ttl_sec
		})
	var resp := _blocking_post("/mset", {"operations": statements})
	if resp.is_empty() or not resp.get("ok", false):
		return -1
	return int(resp.get("count", 0))


func get_many(keys: Array) -> Dictionary:
	var resp := _blocking_post("/mget", {"keys": keys})
	if resp.is_empty() or not resp.get("ok", false):
		return {}
	return resp.get("values", {})


func delete_many(keys: Array) -> int:
	var resp := _blocking_post("/mdel", {"keys": keys})
	if resp.is_empty() or not resp.get("ok", false):
		return -1
	return int(resp.get("deleted", 0))


func _on_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_last_response = {}
	_last_ok = (result == HTTPRequest.RESULT_SUCCESS and response_code == 200)
	if _last_ok and body.size() > 0:
		var text := body.get_string_from_utf8()
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			_last_response = parsed
		elif parsed != null:
			# Some endpoints return { value: <scalar> } wrapped; the
			# caller reads resp.get(...) so this is fine as-is.
			_last_response = {"value": parsed}
	_response_received = true


func _await_response() -> bool:
	_response_received = false
	_last_response = {}
	_last_ok = false
	var timeout_ms := 5000
	var elapsed := 0
	while not _response_received and elapsed < timeout_ms:
		OS.delay_msec(10)
		elapsed += 10
	return _last_ok


func _record_success() -> void:
	_circuit_breaker_failures = 0


func _record_failure() -> void:
	_circuit_breaker_failures += 1
	if _circuit_breaker_failures >= _circuit_breaker_threshold:
		_circuit_breaker_tripped = true
		_circuit_breaker_tripped_time = Time.get_ticks_msec()


func _ok_or_err(resp: Dictionary) -> int:
	if resp.is_empty():
		return -1
	if resp.get("ok", false):
		return 0
	return -1


func _url_escape(s: String) -> String:
	return s.replace(" ", "%20").replace("&", "%26").replace("?", "%3F")


func get_metrics() -> Dictionary:
	return {
		"active_connections": _active_connections,
		"pending_queries": _pending_queries,
		"circuit_breaker_tripped": _circuit_breaker_tripped,
		"circuit_breaker_failures": _circuit_breaker_failures,
		"circuit_breaker_threshold": _circuit_breaker_threshold
	}
