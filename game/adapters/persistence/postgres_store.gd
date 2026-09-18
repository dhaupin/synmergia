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
var _pending: Dictionary = {}  # request_id -> Promise-ish dict
var _request_counter: int = 0

# Circuit breaker state
var _circuit_breaker_failures: int = 0
var _circuit_breaker_tripped: bool = false
var _circuit_breaker_threshold: int = 5
var _circuit_breaker_reset_timeout_ms: int = 30000
var _circuit_breaker_tripped_time: int = 0

# Metrics
var _active_connections: int = 0
var _pending_queries: int = 0


func _init(parent: Node = null) -> void:
	_parent = parent


func open(config: Dictionary) -> int:
	_bridge_url = config.get("bridge_url", "")
	if _bridge_url == "":
		push_error(NotImplemented)
		return -1
	# Health check before declaring success.
	if not _parent:
		_parent = Engine.get_main_loop().root if Engine.get_main_loop() else null
	if not _parent:
		push_error("PostgresStore: no parent Node for HTTPRequest")
		return -1
	_http = HTTPRequest.new()
	_parent.add_child(_http)
	_http.request_completed.connect(_on_response)
	# Synchronous health check via polling.
	var ok := _blocking_get("/health")
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


func query(sql: String, params: Array = []) -> Array:
	var body := {"sql": sql, "params": params}
	var resp := _blocking_post("/query", body)
	if resp.is_empty() or not resp.has("rows"):
		return []
	return resp.get("rows", [])


func execute(sql: String, params: Array = []) -> int:
	var body := {"sql": sql, "params": params}
	var resp := _blocking_post("/execute", body)
	if resp.is_empty():
		return -1
	return int(resp.get("affected", -1))


func begin() -> int:
	var resp := _blocking_post("/tx/begin", {})
	if resp.is_empty():
		return -1
	return int(resp.get("tx_id", -1))


func commit(tx_id: int) -> int:
	return _ok_or_err(_blocking_post("/tx/commit", {"tx_id": tx_id}))


func rollback(tx_id: int) -> int:
	return _ok_or_err(_blocking_post("/tx/rollback", {"tx_id": tx_id}))


func insert_many(table: String, rows: Array, columns: Array) -> int:
	var body := {"table": table, "rows": rows, "columns": columns}
	var resp := _blocking_post("/insert_many", body)
	if resp.is_empty():
		return -1
	return int(resp.get("affected", -1))


func execute_batch(statements: Array) -> int:
	return _ok_or_err(_blocking_post("/batch", {"statements": statements}))


# --- HTTP plumbing ---

func _blocking_get(path: String) -> bool:
	if not _http:
		return false
	_pending_queries += 1
	var url := _bridge_url + path
	var err := _http.request(url, PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
	if err != OK:
		_pending_queries -= 1
		_record_failure()
		return false
	var ok := _await_response()
	_pending_queries -= 1
	if not ok:
		_record_failure()
	else:
		_record_success()
	return ok


func _blocking_post(path: String, body: Dictionary) -> Dictionary:
	if not _http:
		return {}
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
		_record_failure()
		return {}
	var ok := _await_response()
	_pending_queries -= 1
	if not ok:
		_record_failure()
		return {}
	# Pull the stored body from the signal handler
	_record_success()
	return _last_response


var _last_response: Dictionary = {}
var _last_ok: bool = false
var _response_received: bool = false


func _on_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_last_response = {}
	_last_ok = (result == HTTPRequest.RESULT_SUCCESS and response_code == 200)
	if _last_ok and body.size() > 0:
		var text := body.get_string_from_utf8()
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			_last_response = parsed
	_response_received = true


func _await_response() -> bool:
	_response_received = false
	_last_response = {}
	_last_ok = false
	# Block until the signal fires. Godot polls _process on the
	# main thread, so this works as long as we're not in a worker thread.
	var timeout_ms := 5000
	var elapsed := 0
	while not _response_received and elapsed < timeout_ms:
		# Yield to the engine so the HTTPRequest can complete.
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


# --- Transaction context manager ---

# Execute a callable inside a Postgres transaction.
# Usage:
#   var ok := store.with_transaction(func(tx_id: int) -> int:
#       var r1 := store.query("SELECT ...", [], tx_id)
#       var r2 := store.execute("INSERT ...", [], tx_id)
#       return 0
#   )
# Returns 0 on success (commit), -1 on failure (rollback).
func with_transaction(callable: Callable) -> int:
	var tx_id := begin()
	if tx_id < 0:
		return -1
	var result: int = -1
	var success: bool = false
	try:
		result = callable.call(tx_id)
		if result == 0:
			success = true
	else:
		pass
	if success:
		return commit(tx_id)
	else:
		rollback(tx_id)
		return -1


# Low-level transaction query/execute that accept tx_id.
# These are used inside the callable passed to with_transaction.
func query_tx(sql: String, params: Array, tx_id: int) -> Array:
	var body := {"sql": sql, "params": params, "tx_id": tx_id}
	var resp := _blocking_post("/query", body)
	if resp.is_empty() or not resp.has("rows"):
		return []
	return resp.get("rows", [])


func execute_tx(sql: String, params: Array, tx_id: int) -> int:
	var body := {"sql": sql, "params": params, "tx_id": tx_id}
	var resp := _blocking_post("/execute", body)
	if resp.is_empty():
		return -1
	return int(resp.get("affected", -1))


func insert_many_tx(table: String, rows: Array, columns: Array, tx_id: int) -> int:
	var body := {"table": table, "rows": rows, "columns": columns, "tx_id": tx_id}
	var resp := _blocking_post("/insert_many", body)
	if resp.is_empty():
		return -1
	return int(resp.get("affected", -1))


# --- Shard state atomic commit (Edge Case B) ---

# Atomically commit shard state snapshot + locked seeds + parameter flushes.
# Prevents partial state on crash during finalization.
# Args:
#   shard_id: String identifier for the shard
#   snapshot_data: Dictionary with keys:
#     - "state_tree": content-hash state tree data
#     - "locked_seeds": Array of seed IDs that are locked for reconnect window
#     - "parameters": Dictionary of shard parameters to flush
# Returns 0 on success, -1 on failure (full rollback).
func commit_shard_state_atomic(shard_id: String, snapshot_data: Dictionary) -> int:
	return with_transaction(func(tx_id: int) -> int:
		# 1. Insert/replace shard state snapshot
		var state_tree := snapshot_data.get("state_tree", {})
		var ok := execute_tx(
			"INSERT INTO shard_snapshots (shard_id, state_tree, created_at) VALUES ($1, $2, NOW()) ON CONFLICT (shard_id) DO UPDATE SET state_tree = EXCLUDED.state_tree, created_at = NOW()",
			[shard_id, JSON.stringify(state_tree)],
			tx_id
		)
		if ok < 0:
			return -1

		# 2. Commit locked seeds (reconnect window TTL tracking)
		var locked_seeds := snapshot_data.get("locked_seeds", [])
		if locked_seeds.size() > 0:
			var seed_rows := []
			for seed_id in locked_seeds:
				seed_rows.append([shard_id, seed_id, Time.get_unix_time_from_system() + 300])  # 5 min TTL
			ok = insert_many_tx("locked_seeds", seed_rows, ["shard_id", "seed_id", "expires_at"], tx_id)
			if ok < 0:
				return -1

		# 3. Flush shard parameters (immediate or coalesced)
		var parameters := snapshot_data.get("parameters", {})
		if parameters.size() > 0:
			var param_rows := []
			for key in parameters:
				var val := parameters[key]
				param_rows.append([shard_id, key, JSON.stringify(val), Time.get_unix_time_from_system()])
			ok = insert_many_tx("shard_parameters", param_rows, ["shard_id", "param_key", "param_value", "updated_at"], tx_id)
			if ok < 0:
				return -1

		return 0
	))


func get_metrics() -> Dictionary:
	return {
		"active_connections": _active_connections,
		"pending_queries": _pending_queries,
		"circuit_breaker_tripped": _circuit_breaker_tripped,
		"circuit_breaker_failures": _circuit_breaker_failures,
		"circuit_breaker_threshold": _circuit_breaker_threshold
	}
