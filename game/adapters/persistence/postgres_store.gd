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
var _client: HTTPClient = null
var _host: String = ""
var _port: int = 80
var _use_ssl: bool = false
var _pending: Dictionary = {}
var _request_counter: int = 0

## Synchronous request budget and poll cadence. This store is called at
## boot and from service legs that cannot yield frames, so the transport
## polls the socket directly instead of waiting on an HTTPRequest signal
## (which only fires on a processed frame -- a busy-wait never delivers it).
const SYNC_TIMEOUT_MS: int = 5000
const SYNC_POLL_STEP_MS: int = 2

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


func _init(_parent: Node = null) -> void:
	# `parent` is retained for call-site compatibility; the synchronous
	# HTTPClient transport needs no scene-tree node.
	pass


func open(config: Dictionary) -> int:
	_bridge_url = config.get("bridge_url", "")
	if _bridge_url == "":
		push_error(NotImplemented)
		return -1
	if not _parse_url(_bridge_url):
		push_error("PostgresStore: malformed bridge_url %s" % _bridge_url)
		return -1
	var ok: bool = _blocking_get("/health")
	if not ok:
		push_error("PostgresStore: bridge %s not reachable" % _bridge_url)
		return -1
	_active_connections = 1
	return 0


func close() -> void:
	if _client:
		_client.close()
		_client = null
	_active_connections = 0
	_pending_queries = 0
	_circuit_breaker_failures = 0
	_circuit_breaker_tripped = false
	_circuit_breaker_tripped_time = 0


func healthy() -> bool:
	if _client == null:
		return false
	if _circuit_breaker_tripped:
		var now: int = Time.get_ticks_msec()
		if now - _circuit_breaker_tripped_time >= _circuit_breaker_reset_timeout_ms:
			_circuit_breaker_tripped = false
			_circuit_breaker_failures = 0
		else:
			return false
	return _blocking_get("/health")


## Parse "http://host:port" (or https) into connection fields.
func _parse_url(url: String) -> bool:
	var rest: String = url
	_use_ssl = false
	if rest.begins_with("https://"):
		_use_ssl = true
		rest = rest.substr(8)
	elif rest.begins_with("http://"):
		rest = rest.substr(7)
	# Strip any trailing path; the bridge API is rooted at "/".
	var slash: int = rest.find("/")
	if slash >= 0:
		rest = rest.substr(0, slash)
	var colon: int = rest.rfind(":")
	if colon >= 0:
		_host = rest.substr(0, colon)
		_port = int(rest.substr(colon + 1))
	else:
		_host = rest
		_port = 443 if _use_ssl else 80
	return _host != "" and _port > 0


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
		var json: String = JSON.stringify(body)
		var headers: PackedStringArray = PackedStringArray([
			"Content-Type: application/json",
			"Accept: application/json",
		])
		var resp: Dictionary = _sync_request(HTTPClient.METHOD_POST, path, headers, json)
		_pending_queries -= 1
		if resp.get("_transport_error", false):
			return PostgresResult.err(str(resp.get("error", "transport error")), -3)
		return PostgresResult.ok(resp)
	)


func _blocking_get(path: String) -> bool:
	var res: PostgresResult = _retry_request(func() -> PostgresResult:
		_pending_queries += 1
		var r: Dictionary = _sync_request(
			HTTPClient.METHOD_GET, path, PackedStringArray(["Accept: application/json"]), ""
		)
		_pending_queries -= 1
		if r.get("_transport_error", false):
			return PostgresResult.err(str(r.get("error", "transport error")), -3)
		return PostgresResult.ok(r)
	)
	if not res.success or not (res.data is Dictionary):
		return false
	return res.data.get("ok", false)


## One synchronous request: connect (if needed), send, poll until the
## response arrives or the budget expires. No frame pumping required --
## this is what lets the store connect during boot and from any service leg.
## A dropped keep-alive is retried once on a fresh socket.
func _sync_request(method: int, path: String, headers: PackedStringArray, body: String) -> Dictionary:
	for attempt in range(2):
		if _client == null or _client.get_status() == HTTPClient.STATUS_DISCONNECTED:
			if not _connect():
				return {"_transport_error": true, "error": "connection timed out"}
		if _client.get_status() != HTTPClient.STATUS_CONNECTED:
			_client.close()
			_client = null
			continue
		var rerr: int = _client.request(method, path, headers, body)
		if rerr != OK:
			# The socket was stale despite a CONNECTED read; drop it and retry.
			_client.close()
			_client = null
			continue
		if not _pump_until([HTTPClient.STATUS_BODY, HTTPClient.STATUS_CONNECTED], [HTTPClient.STATUS_REQUESTING]):
			return {"_transport_error": true, "error": "request timed out"}
		if _client.get_status() == HTTPClient.STATUS_DISCONNECTED:
			_client = null
			continue
		var code: int = _client.get_response_code()
		var payload: String = ""
		if _client.has_response():
			var buf: PackedByteArray = PackedByteArray()
			while _client.get_status() == HTTPClient.STATUS_BODY:
				_client.poll()
				var chunk: PackedByteArray = _client.read_response_body_chunk()
				if chunk.size() == 0:
					OS.delay_msec(SYNC_POLL_STEP_MS)
				else:
					buf.append_array(chunk)
			payload = buf.get_string_from_utf8()
		if code != 200:
			return {"_transport_error": true, "error": "http %d: %s" % [code, payload]}
		var parsed: Variant = JSON.parse_string(payload)
		if parsed is Dictionary:
			return parsed
		if parsed != null:
			return {"value": parsed}
		return {}
	return {"_transport_error": true, "error": "connection reset"}


## Open a fresh connection to the bridge. Returns false on timeout.
func _connect() -> bool:
	if _client:
		_client.close()
	_client = HTTPClient.new()
	var cerr: int = _client.connect_to_host(_host, _port, TLSOptions.client() if _use_ssl else null)
	if cerr != OK:
		return false
	return _pump_until([HTTPClient.STATUS_CONNECTED], [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING])


## Poll the socket until the status leaves `from_states` (lands in a
## terminal set) or the timeout budget is spent. Returns true if it left.
func _pump_until(accept: Array, from_states: Array) -> bool:
	var elapsed: int = 0
	while _client.get_status() in from_states and elapsed < SYNC_TIMEOUT_MS:
		_client.poll()
		OS.delay_msec(SYNC_POLL_STEP_MS)
		elapsed += SYNC_POLL_STEP_MS
	return _client.get_status() in accept or not (_client.get_status() in from_states)


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
	var tx_id: int = begin()
	if tx_id < 0:
		push_error("with_transaction: begin failed")
		return -1
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
