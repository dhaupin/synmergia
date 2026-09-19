extends "res://adapters/persistence/persistence_store.gd"
class_name PostgresStore

# HTTP-backed Postgres implementation.
#
# Talks to a small sidecar service (pg-bridge) that exposes a
# minimal Postgres HTTP API. The sidecar can be a thin Go or
# Rust service -- the wire protocol is below.
#
# Wire protocol (POST /query, etc.):
#   POST /query        { sql, params }    -> { rows: [...] }
#   POST /execute      { sql, params }    -> { affected: N }
#   POST /tx/begin                       -> { tx_id: N }
#   POST /tx/commit    { tx_id }          -> { ok: true }
#   POST /tx/rollback  { tx_id }          -> { ok: true }
#   POST /insert_many  { table, rows, columns } -> { affected: N }
#   POST /batch        { statements: [...] } -> { ok: true }
#   GET  /health                         -> { ok: true, version: "..." }
#
# Status: SKELETON. connect() and all methods push errors until
# the pg-bridge sidecar lands. Use MemoryPersistenceStore for
# tests / dev / offline in the meantime.
#
# Config (from .env):
#   POSTGRES_HOST=postgres
#   POSTGRES_PORT=5432
#   POSTGRES_DB=synmergia
#   POSTGRES_USER=synmergia
#   POSTGRES_PASSWORD=...
#   PG_BRIDGE_URL=http://pg-bridge:8080
#   PG_BRIDGE_TIMEOUT_MS=5000


const NotImplemented = "PostgresStore: pg-bridge sidecar not yet wired. Use MemoryPersistenceStore for tests/dev."

var _bridge_url: String = ""
var _http: HTTPRequest
var _parent: Node
var _pending: Dictionary = {}
var _request_counter: int = 0

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

class PostgresResult:
	var success: bool = false
	var data: Variant = null
	var error: String = ""
	var error_code: int = 0

	static func ok(value: Variant) -> PostgresResult:
		var r := PostgresResult.new()
		r.success = true
		r.data = value
		return r

	static func err(msg: String, code: int = -1) -> PostgresResult:
		var r := PostgresResult.new()
		r.success = false
		r.error = msg
		r.error_code = code
		return r

	func unwrap() -> Variant:
		if not success:
			push_error("PostgresResult.unwrap() called on error: " + error)
		return data

	func expect(msg: String) -> Variant:
		if not success:
			push_error(msg + ": " + error)
		return data


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
		push_error("PostgresStore: no parent Node for HTTPRequest")
		return -1
	_http = HTTPRequest.new()
	_parent.add_child(_http)
	_http.request_completed.connect(_on_response)
	var ok: bool = _blocking_get("/health")
	if not ok:
		push_error("PostgresStore: bridge %s not reachable" % _bridge_url)
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
	if _circuit_breaker_tripped:
		var now: int = Time.get_ticks_msec()
		if now - _circuit_breaker_tripped_time >= _circuit_breaker_reset_timeout_ms:
			_circuit_breaker_tripped = false
			_circuit_breaker_failures = 0
		else:
			return false
	return _blocking_get("/health")


# --- Public API returning types matching PersistenceStore ---

func query(sql: String, params: Array = []) -> Array:
	var body: Dictionary = {"sql": sql, "params": params}
	var resp: PostgresResult = _request_with_retry("/query", body)
	if not resp.success:
		push_error("query failed: " + resp.error)
		return []
	if not resp.data.has("rows"):
		return []
	return resp.data.get("rows", [])


func execute(sql: String, params: Array = []) -> int:
	var body: Dictionary = {"sql": sql, "params": params}
	var resp: PostgresResult = _request_with_retry("/execute", body)
	if not resp.success:
		push_error("execute failed: " + resp.error)
		return -1
	if resp.data.is_empty():
		push_error("execute: empty response")
		return -1
	return int(resp.data.get("affected", -1))


func begin() -> int:
	var resp: PostgresResult = _request_with_retry("/tx/begin", {})
	if not resp.success:
		push_error("begin failed: " + resp.error)
		return -1
	if resp.data.is_empty():
		push_error("begin: empty response")
		return -1
	return int(resp.data.get("tx_id", -1))


func commit(tx_id: int) -> int:
	var resp: PostgresResult = _request_with_retry("/tx/commit", {"tx_id": tx_id})
	if not resp.success:
		push_error("commit failed: " + resp.error)
		return -1
	var data: Dictionary = resp.data
	if data.is_empty():
		push_error("commit: empty response")
		return -1
	if data.get("ok", false):
		return 0
	push_error("commit failed: " + str(data))
	return -1


func rollback(tx_id: int) -> int:
	var resp: PostgresResult = _request_with_retry("/tx/rollback", {"tx_id": tx_id})
	if not resp.success:
		push_error("rollback failed: " + resp.error)
		return -1
	var data: Dictionary = resp.data
	if data.is_empty():
		push_error("rollback: empty response")
		return -1
	if data.get("ok", false):
		return 0
	push_error("rollback failed: " + str(data))
	return -1


func insert_many(table: String, rows: Array, columns: Array) -> int:
	var body: Dictionary = {"table": table, "rows": rows, "columns": columns}
	var resp: PostgresResult = _request_with_retry("/insert_many", body)
	if not resp.success:
		push_error("insert_many failed: " + resp.error)
		return -1
	if resp.data.is_empty():
		push_error("insert_many: empty response")
		return -1
	return int(resp.data.get("affected", -1))


func execute_batch(statements: Array) -> int:
	var batch_body: Dictionary = {"statements": []}
	for stmt in statements:
		if stmt is String:
			batch_body["statements"].append({"sql": stmt, "params": []})
		elif stmt is Dictionary and stmt.has("sql"):
			batch_body["statements"].append(stmt)
		else:
			push_error("execute_batch: invalid statement format: " + str(stmt))
			return -1
	var resp: PostgresResult = _request_with_retry("/batch", batch_body)
	if not resp.success:
		push_error("execute_batch failed: " + resp.error)
		return -1
	var data: Dictionary = resp.data
	if data.is_empty():
		push_error("execute_batch: empty response")
		return -1
	if data.get("ok", false):
		return 0
	push_error("execute_batch failed: " + str(data))
	return -1


# --- KV Bulk Operations ---

func set_many(entries: Dictionary) -> int:
	if entries.is_empty():
		return 0
	var statements: Array = []
	for key in entries.keys():
		var value: Variant = entries[key]
		var json_value: String = JSON.stringify(value)
		statements.append(
			"INSERT INTO kv (key, value) VALUES ($1, $2) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value"
		)
	return execute_batch_with_params(statements, entries)


func get_many(keys: Array) -> Dictionary:
	if keys.is_empty():
		return {}
	var placeholders: Array = []
	var params: Array = []
	for i in range(keys.size()):
		placeholders.append("$%d" % (i + 1))
		params.append(keys[i])
	var sql: String = "SELECT key, value FROM kv WHERE key IN (%s)" % [",".join(placeholders)]
	var resp: PostgresResult = _request_with_retry("/query", {"sql": sql, "params": params})
	if not resp.success:
		push_error("get_many failed: " + resp.error)
		return {}
	if resp.data.is_empty() or not resp.data.has("rows"):
		return {}
	var result: Dictionary = {}
	for row in resp.data.get("rows", []):
		var k: String = row.get("key", "")
		var raw: String = row.get("value", "")
		if raw != "":
			var parsed: Variant = JSON.parse_string(raw)
			result[k] = parsed
		else:
			result[k] = null
	return result


func delete_many(keys: Array) -> int:
	if keys.is_empty():
		return 0
	var placeholders: Array = []
	var params: Array = []
	for i in range(keys.size()):
		placeholders.append("$%d" % (i + 1))
		params.append(keys[i])
	var sql: String = "DELETE FROM kv WHERE key IN (%s)" % [",".join(placeholders)]
	var resp: PostgresResult = _request_with_retry("/execute", {"sql": sql, "params": params})
	if not resp.success:
		push_error("delete_many failed: " + resp.error)
		return -1
	if resp.data.is_empty():
		push_error("delete_many: empty response")
		return -1
	return int(resp.data.get("affected", -1))


func execute_batch_with_params(statements: Array, entries: Dictionary) -> int:
	var keys: Array = entries.keys()
	var batch_body: Dictionary = {"statements": []}
	for i in range(statements.size()):
		var key: String = keys[i]
		var value: Variant = entries[key]
		var json_value: String = JSON.stringify(value)
		batch_body["statements"].append({
			"sql": statements[i],
			"params": [key, json_value]
		})
	var resp: PostgresResult = _request_with_retry("/batch", batch_body)
	if not resp.success:
		push_error("execute_batch_with_params failed: " + resp.error)
		return -1
	var data: Dictionary = resp.data
	if data.is_empty():
		push_error("execute_batch_with_params: empty response")
		return -1
	if data.get("ok", false):
		return 0
	push_error("execute_batch_with_params failed: " + str(data))
	return -1


# --- HTTP plumbing with retry wrapper ---

func _retry_request(callable: Callable, max_attempts: int = MAX_RETRIES) -> PostgresResult:
	if not _http:
		return PostgresResult.err("HTTP client not initialized", -1)
	if _circuit_breaker_tripped:
		var now: int = Time.get_ticks_msec()
		if now - _circuit_breaker_tripped_time >= _circuit_breaker_reset_timeout_ms:
			_circuit_breaker_tripped = false
			_circuit_breaker_failures = 0
		else:
			return PostgresResult.err("circuit breaker open", -2)

	var attempt: int = 0
	var delay_ms: int = BASE_RETRY_DELAY_MS
	var last_error: String = ""

	while attempt <= max_attempts:
		var result: Variant = callable.call()
		if result is PostgresResult:
			if result.success:
				_record_success()
				return result
			last_error = result.error
			_record_failure()
		elif result is Dictionary:
			if result.has("ok") and result.get("ok", false):
				_record_success()
				return PostgresResult.ok(result)
			last_error = str(result)
			_record_failure()
		else:
			last_error = "unexpected return type: " + str(result)
			_record_failure()
		
		attempt += 1
		if attempt <= max_attempts:
			OS.delay_msec(delay_ms)
			delay_ms = min(delay_ms * 2, MAX_RETRY_DELAY_MS)
	
	return PostgresResult.err("Max retries exceeded: " + last_error, -3)


func _request_with_retry(path: String, body: Dictionary) -> PostgresResult:
	return _retry_request(func() -> PostgresResult:
		_pending_queries += 1
		var url: String = _bridge_url + path
		var json: String = JSON.stringify(body)
		var headers: PackedStringArray = PackedStringArray([
			"Content-Type: application/json",
			"Accept: application/json",
		])
		var err: int = _http.request(url, headers, HTTPClient.METHOD_POST, json)
		if err != OK:
			_pending_queries -= 1
			return PostgresResult.err("HTTP request error: " + str(err), err)
		var ok: bool = _await_response()
		_pending_queries -= 1
		if not ok:
			return PostgresResult.err("Request timeout or failed", -3)
		return PostgresResult.ok(_last_response)
	)


func _blocking_get(path: String) -> bool:
	if not _http:
		return false
	if _circuit_breaker_tripped:
		var now: int = Time.get_ticks_msec()
		if now - _circuit_breaker_tripped_time >= _circuit_breaker_reset_timeout_ms:
			_circuit_breaker_tripped = false
			_circuit_breaker_failures = 0
		else:
			return false
	
	var attempt: int = 0
	var delay_ms: int = BASE_RETRY_DELAY_MS
	
	while attempt <= MAX_RETRIES:
		_pending_queries += 1
		var url: String = _bridge_url + path
		var err: int = _http.request(url, PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
		if err != OK:
			_pending_queries -= 1
			_record_failure()
		else:
			var ok: bool = _await_response()
			_pending_queries -= 1
			if not ok:
				_record_failure()
			else:
				_record_success()
				return true
		
		attempt += 1
		if attempt <= MAX_RETRIES:
			OS.delay_msec(delay_ms)
			delay_ms = min(delay_ms * 2, MAX_RETRY_DELAY_MS)
	
	return false


var _last_response: Dictionary = {}
var _last_ok: bool = false
var _response_received: bool = false


func _on_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_last_response = {}
	_last_ok = (result == HTTPRequest.RESULT_SUCCESS and response_code == 200)
	if _last_ok and body.size() > 0:
		var text: String = body.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_last_response = parsed
		elif parsed != null:
			_last_response = {"value": parsed}
	_response_received = true


func _await_response() -> bool:
	_response_received = false
	_last_response = {}
	_last_ok = false
	var timeout_ms: int = 5000
	var elapsed: int = 0
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


func _ok_or_err_result(resp: PostgresResult) -> PostgresResult:
	if not resp.success:
		return resp
	var data: Dictionary = resp.data
	if data.is_empty():
		return PostgresResult.err("empty response", -1)
	if data.get("ok", false):
		return PostgresResult.ok(0)
	return PostgresResult.err("operation failed: " + str(data), -1)


func _ok_or_err(resp: Dictionary) -> int:
	if resp.is_empty():
		return -1
	if resp.get("ok", false):
		return 0
	return -1


# --- Transaction context manager ---

func with_transaction(callable: Callable) -> int:
	var tx_result: PostgresResult = begin()
	if not tx_result.success or tx_result.data < 0:
		push_error("with_transaction: begin failed: " + tx_result.error)
		return -1
	var tx_id: int = tx_result.data
	var result: int = -1
	var success: bool = false
	
	result = callable.call(tx_id)
	if result == 0:
		success = true
	
	if success:
		return commit(tx_id)
	else:
		rollback(tx_id)
		return -1


# Low-level transaction query/execute that accept tx_id.
# These are used inside the callable passed to with_transaction.
func query_tx(sql: String, params: Array, tx_id: int) -> Array:
	var body: Dictionary = {"sql": sql, "params": params, "tx_id": tx_id}
	var resp: PostgresResult = _request_with_retry("/query", body)
	if not resp.success:
		push_error("query_tx failed: " + resp.error)
		return []
	if resp.data.is_empty() or not resp.data.has("rows"):
		return []
	return resp.data.get("rows", [])


func execute_tx(sql: String, params: Array, tx_id: int) -> int:
	var body: Dictionary = {"sql": sql, "params": params, "tx_id": tx_id}
	var resp: PostgresResult = _request_with_retry("/execute", body)
	if not resp.success:
		push_error("execute_tx failed: " + resp.error)
		return -1
	if resp.data.is_empty():
		push_error("execute_tx: empty response")
		return -1
	return int(resp.data.get("affected", -1))


func insert_many_tx(table: String, rows: Array, columns: Array, tx_id: int) -> int:
	var body: Dictionary = {"table": table, "rows": rows, "columns": columns, "tx_id": tx_id}
	var resp: PostgresResult = _request_with_retry("/insert_many", body)
	if not resp.success:
		push_error("insert_many_tx failed: " + resp.error)
		return -1
	if resp.data.is_empty():
		push_error("insert_many_tx: empty response")
		return -1
	return int(resp.data.get("affected", -1))


# --- Shard state atomic commit (Edge Case B) ---

func commit_shard_state_atomic(shard_id: String, snapshot_data: Dictionary) -> int:
	return with_transaction(func(tx_id: int) -> int:
		var state_tree: Dictionary = snapshot_data.get("state_tree", {})
		var ok_result: int = execute_tx(
			"INSERT INTO shard_snapshots (shard_id, state_tree, created_at) VALUES ($1, $2, NOW()) ON CONFLICT (shard_id) DO UPDATE SET state_tree = EXCLUDED.state_tree, created_at = NOW()",
			[shard_id, JSON.stringify(state_tree)],
			tx_id
		)
		if ok_result < 0:
			return -1

		var locked_seeds: Array = snapshot_data.get("locked_seeds", [])
		if locked_seeds.size() > 0:
			var seed_rows: Array = []
			for seed_id in locked_seeds:
				seed_rows.append([shard_id, seed_id, Time.get_unix_time_from_system() + 300])
			ok_result = insert_many_tx("locked_seeds", seed_rows, ["shard_id", "seed_id", "expires_at"], tx_id)
			if ok_result < 0:
				return -1

		var parameters: Dictionary = snapshot_data.get("parameters", {})
		if parameters.size() > 0:
			var param_rows: Array = []
			for key in parameters:
				var val: Variant = parameters[key]
				param_rows.append([shard_id, key, JSON.stringify(val), Time.get_unix_time_from_system()])
			ok_result = insert_many_tx("shard_parameters", param_rows, ["shard_id", "param_key", "param_value", "updated_at"], tx_id)
			if ok_result < 0:
				return -1

		return 0
	)


func get_metrics() -> Dictionary:
	return {
		"active_connections": _active_connections,
		"pending_queries": _pending_queries,
		"circuit_breaker_tripped": _circuit_breaker_tripped,
		"circuit_breaker_failures": _circuit_breaker_failures,
		"circuit_breaker_threshold": _circuit_breaker_threshold
	}