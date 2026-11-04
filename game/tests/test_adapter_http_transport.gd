## Adapter HTTP transport receipt: the stores that talk to the pg/redis
## bridges must work WITHOUT the scene tree pumping frames.
##
## The bug this guards: both stores used HTTPRequest, whose
## request_completed signal only fires on a processed frame. They opened
## with a busy-wait (OS.delay_msec) that never pumps, so the bridge always
## read as "not reachable" and postgres/redis shared state was dead on
## arrival -- while every memory-backed test stayed green.
##
## Legs (no docker, no bridge: a throwaway in-process HTTP/1.1 server):
##   1. PostgresStore.open() reaches the server (no frame pumping).
##   2. A PostgresStore query round-trips a row.
##   3. RedisStore.open() reaches the server.
##   4. A RedisStore fetch reads the value (the {"value": ...} envelope).
##   5. Repeated calls reuse the socket / recover from a dropped keep-alive.
##
## Run with:
##   godot --headless --path game/ --script res://tests/test_adapter_http_transport.gd
extends SceneTree

var _passed: int = 0
var _failed: int = 0

var _server: TCPServer = null
var _thread: Thread = null
var _port: int = 0
var _stop: bool = false


func _initialize() -> void:
	print("--- ADAPTER HTTP TRANSPORT ---")
	await process_frame
	if not _start_server():
		_fail("could not start the local test HTTP server")
		_finish()
		return
	_test_postgres_open_and_query()
	_test_redis_open_and_fetch()
	_test_repeated_requests()
	_stop_server()
	_finish()


# ── A tiny HTTP/1.1 keep-alive server on a background thread ──────────────

func _start_server() -> bool:
	_server = TCPServer.new()
	var err: int = _server.listen(0, "127.0.0.1")
	if err != OK:
		return false
	_port = _server.get_local_port()
	_thread = Thread.new()
	_thread.start(_serve_loop)
	# Wait until the listener is actually accepting (listen() already bound).
	return _port > 0


func _stop_server() -> void:
	_stop = true
	# Nudge the accept loop so it notices _stop promptly.
	var wake := StreamPeerTCP.new()
	wake.connect_to_host("127.0.0.1", _port)
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	if _server:
		_server.stop()
		_server = null


func _serve_loop() -> void:
	while not _stop:
		if not _server.is_connection_available():
			OS.delay_msec(2)
			continue
		var conn: StreamPeerTCP = _server.take_connection()
		if conn == null:
			continue
		_serve_connection(conn)


## Serve one keep-alive connection until the peer closes or we stop.
func _serve_connection(conn: StreamPeerTCP) -> void:
	var buffer := PackedByteArray()
	while not _stop:
		conn.poll()
		var status: int = conn.get_status()
		if status != StreamPeerTCP.STATUS_CONNECTED:
			return
		var avail: int = conn.get_available_bytes()
		if avail <= 0:
			OS.delay_msec(1)
			continue
		var chunk: Array = conn.get_partial_data(avail)
		if chunk[0] != OK:
			return
		buffer.append_array(chunk[1])
		# Try to parse one full request (headers + optional body).
		var parsed: Dictionary = _try_parse(buffer)
		if parsed.is_empty():
			continue
		buffer = parsed["rest"]
		var response: String = _route(parsed["method"], parsed["path"])
		var payload: PackedByteArray = response.to_utf8_buffer()
		var head: String = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: keep-alive\r\n\r\n" % payload.size()
		conn.put_data(head.to_utf8_buffer())
		conn.put_data(payload)


## Return {method, path, rest} once a full request is buffered, else {}.
func _try_parse(buffer: PackedByteArray) -> Dictionary:
	var text: String = buffer.get_string_from_utf8()
	var header_end: int = text.find("\r\n\r\n")
	if header_end < 0:
		return {}
	var head: String = text.substr(0, header_end)
	var lines: Array = head.split("\r\n")
	if lines.size() == 0:
		return {}
	var parts: Array = String(lines[0]).split(" ")
	if parts.size() < 2:
		return {}
	var content_length: int = 0
	for i in range(1, lines.size()):
		var line: String = String(lines[i])
		if line.to_lower().begins_with("content-length:"):
			content_length = int(line.split(":")[1].strip_edges())
	var body_start: int = header_end + 4
	var body_bytes: int = buffer.size() - body_start
	if body_bytes < content_length:
		return {}
	var rest: PackedByteArray = buffer.slice(body_start + content_length)
	return {"method": String(parts[0]), "path": String(parts[1]), "rest": rest}


func _route(method: String, path: String) -> String:
	if path.begins_with("/health"):
		return '{"ok": true, "version": "test-bridge"}'
	if path.begins_with("/query"):
		return '{"ok": true, "rows": [{"key": "probe", "value": "{\\"n\\": 1}"}]}'
	if path.begins_with("/batch"):
		return '{"ok": true}'
	if path.begins_with("/execute"):
		return '{"ok": true, "affected": 1}'
	if path.begins_with("/get"):
		return '{"value": {"n": 9}}'
	if path.begins_with("/exists"):
		return '{"exists": true}'
	return '{"ok": true}'


# ── Legs ──────────────────────────────────────────────────────────────────

func _test_postgres_open_and_query() -> void:
	var Store = load("res://adapters/persistence/postgres_store.gd")
	var s = Store.new()
	var rc: int = s.open({"bridge_url": "http://127.0.0.1:%d" % _port})
	_assert(rc == 0, "PostgresStore.open() reaches the bridge with no frame pumping")
	if rc == 0:
		var rows: Array = s.query("SELECT key, value FROM kv", [])
		_assert(rows.size() == 1 and rows[0].get("key", "") == "probe",
			"PostgresStore.query() round-trips a row")
	s.close()


func _test_redis_open_and_fetch() -> void:
	var Store = load("res://adapters/cache/redis_store.gd")
	var s = Store.new()
	var rc: int = s.open({"bridge_url": "http://127.0.0.1:%d" % _port})
	_assert(rc == 0, "RedisStore.open() reaches the bridge with no frame pumping")
	if rc == 0:
		var v = s.fetch("probe")
		_assert(v is Dictionary and v.get("n", 0) == 9,
			"RedisStore.fetch() reads the value envelope")
	s.close()


func _test_repeated_requests() -> void:
	var Store = load("res://adapters/persistence/postgres_store.gd")
	var s = Store.new()
	var rc: int = s.open({"bridge_url": "http://127.0.0.1:%d" % _port})
	if rc != 0:
		_fail("PostgresStore.open() failed in the repeat leg")
		return
	var ok := true
	for i in range(5):
		var rows: Array = s.query("SELECT 1", [])
		if rows.is_empty():
			ok = false
	_assert(ok, "five sequential requests all succeed (socket reuse / reconnect)")
	s.close()


# ── Harness ───────────────────────────────────────────────────────────────

func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  PASS: ", label)
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failed += 1
	print("  FAIL: ", label)


func _finish() -> void:
	print("--- RESULT: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
