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
	return 0


func close() -> void:
	if _http and is_instance_valid(_http):
		_http.queue_free()
		_http = null


func healthy() -> bool:
	if not _http:
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
	var url := _bridge_url + path
	var err := _http.request(url, PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
	if err != OK:
		return false
	return _await_response()


func _blocking_post(path: String, body: Dictionary) -> Dictionary:
	if not _http:
		return {}
	var url := _bridge_url + path
	var json := JSON.stringify(body)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
	])
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, json)
	if err != OK:
		return {}
	var ok := _await_response()
	if not ok:
		return {}
	# Pull the stored body from the signal handler
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


func _ok_or_err(resp: Dictionary) -> int:
	if resp.is_empty():
		return -1
	if resp.get("ok", false):
		return 0
	return -1
