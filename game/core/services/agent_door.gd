## AgentDoor - the one local door agents and companion apps knock on.
##
## The vant "door" pattern (one listener that is simultaneously the MCP
## surface, the headless API, and the companion-app API), applied to
## Synmergia. It binds 127.0.0.1 only and is OFF unless AgentDriver is
## enabled (SYN_AGENT=1), so a shipped server never exposes it by default.
##
## Routes (JSON in, JSON out) -- the gamestruct four-primitive wire:
##   GET  /health          -> {ok, frame, in_world, enabled}
##   GET  /observe         -> AgentDriver.observe()
##   POST /act             -> {"id": "...", "verb": "...", "value": {...}}
##                            -> AgentDriver.act(id, args)
##   POST /wait_for        -> {"predicate": {...}, "timeoutMs": N}
##   GET  /events?since=N  -> the event ring
##   POST /coord           -> {"op": "...", ...} (Synmergia's multi-agent
##                            extension, beyond the four primitives)
##
## The generic projections (MCP JSON-RPC, the tool catalog) are NOT here:
## they live in gamestruct (bindings/mcp.mjs + profiles/agent.mjs), so the
## door stays primitive-transport and the protocol layer has ONE owner.
##
## Threading law: this runs on its OWN thread and never touches the scene
## tree. Every request is submit()'d to AgentDriver and the response is
## poll()'d here -- the main thread stays the only mutator. That is also
## why a companion app (2D helper on the website) and an LLM agent speak the
## exact same protocol at different distances.
extends Node

const DEFAULT_PORT := 3789
const POLL_MS := 2

var _server: TCPServer = null
var _thread: Thread = null
var _port: int = 0
var _stop: bool = false
var _running: bool = false
var _driver_ref: Node = null  # resolved on the MAIN thread only

func _ready() -> void:
	_driver_ref = get_node_or_null("/root/AgentDriver")
	if _driver_ref == null:
		return
	if not _driver_ref.is_enabled():
		GameLog.info("AgentDoor: agent driver disabled (SYN_AGENT unset); door stays closed.")
		return
	var want: String = ""
	if OS.has_environment("SYN_AGENT_DOOR_PORT"):
		want = OS.get_environment("SYN_AGENT_DOOR_PORT").strip_edges()
	var port: int = int(want) if want != "" else DEFAULT_PORT
	start(port)

## The driver node, cached on the main thread. The transport thread must NEVER
## call get_node_or_null() (Godot forbids scene-tree reads off the main thread);
## it reads this reference instead. submit()/poll() are the only thread-safe legs.
func _driver() -> Node:
	return _driver_ref

## Bind and serve (idempotent). Returns the bound port, or 0 on failure.
## Binds loopback by default. A non-loopback bind (SYN_AGENT_DOOR_BIND) is
## REFUSED unless SYN_AGENT_TOKEN is set -- fail closed, no open remote door.
func start(port: int = DEFAULT_PORT) -> int:
	if _running:
		return _port
	var bind_addr: String = "127.0.0.1"
	if OS.has_environment("SYN_AGENT_DOOR_BIND"):
		bind_addr = OS.get_environment("SYN_AGENT_DOOR_BIND").strip_edges()
	if bind_addr == "":
		bind_addr = "127.0.0.1"
	var loopback: bool = bind_addr == "127.0.0.1" or bind_addr == "localhost" or bind_addr == "::1"
	if not loopback and not _has_token():
		GameLog.error("AgentDoor: refusing non-loopback bind '%s' without SYN_AGENT_TOKEN (fail closed)." % bind_addr)
		return 0
	_server = TCPServer.new()
	var err: int = _server.listen(port, bind_addr)
	if err != OK:
		GameLog.error("AgentDoor: could not bind %s:%d (err %d)" % [bind_addr, port, err])
		_server = null
		return 0
	_port = _server.get_local_port()
	_stop = false
	_running = true
	_thread = Thread.new()
	_thread.start(_serve_loop)
	GameLog.info("AgentDoor: listening on %s:%d (agent + companion door)" % [bind_addr, _port])
	return _port

func get_port() -> int:
	return _port

func is_running() -> bool:
	return _running

func stop() -> void:
	if not _running:
		return
	_stop = true
	# Nudge the accept loop so it notices _stop promptly.
	var wake := StreamPeerTCP.new()
	wake.connect_to_host("127.0.0.1", _port)
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	if _server != null:
		_server.stop()
		_server = null
	_running = false

func _exit_tree() -> void:
	stop()

# -- The door thread -------------------------------------------------------

func _serve_loop() -> void:
	while not _stop:
		if _server == null or not _server.is_connection_available():
			OS.delay_msec(POLL_MS)
			continue
		var conn: StreamPeerTCP = _server.take_connection()
		if conn == null:
			continue
		_serve_connection(conn)

func _serve_connection(conn: StreamPeerTCP) -> void:
	var buffer := PackedByteArray()
	while not _stop:
		conn.poll()
		if conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return
		var avail: int = conn.get_available_bytes()
		if avail <= 0:
			OS.delay_msec(POLL_MS)
			continue
		var chunk: Array = conn.get_partial_data(avail)
		if chunk[0] != OK:
			return
		buffer.append_array(chunk[1])
		var parsed: Dictionary = _try_parse(buffer)
		if parsed.is_empty():
			continue
		buffer = parsed["rest"]
		_send(conn, parsed["method"], parsed["path"], parsed["body"], parsed.get("headers", {}))

func _send(conn: StreamPeerTCP, method: String, path: String, body: String, headers: Dictionary) -> void:
	var payload: Dictionary = _route(method, path, body, headers)
	var data: PackedByteArray = JSON.stringify(payload).to_utf8_buffer()
	var head: String = (
		"HTTP/1.1 200 OK\r\n"
		+ "Content-Type: application/json\r\n"
		+ "Access-Control-Allow-Origin: *\r\n"
		+ "Access-Control-Allow-Headers: Content-Type\r\n"
		+ "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
		+ "Content-Length: %d\r\n"
		+ "Connection: keep-alive\r\n\r\n"
	) % data.size()
	conn.put_data(head.to_utf8_buffer())
	conn.put_data(data)

## Return {method, path, body, rest} once a full request is buffered, else {}.
func _try_parse(buffer: PackedByteArray) -> Dictionary:
	var text: String = buffer.get_string_from_utf8()
	var header_end: int = text.find("\r\n\r\n")
	if header_end < 0:
		return {}
	var head: String = text.substr(0, header_end)
	var lines: Array = head.split("\r\n")
	if lines.is_empty():
		return {}
	var parts: Array = String(lines[0]).split(" ")
	if parts.size() < 2:
		return {}
	var method: String = String(parts[0]).to_upper()
	var path: String = String(parts[1])
	var content_length: int = 0
	var headers: Dictionary = {}
	for i in range(1, lines.size()):
		var ln: String = String(lines[i])
		var idx: int = ln.find(":")
		if idx <= 0:
			continue
		var hname: String = ln.substr(0, idx).strip_edges().to_lower()
		var hval: String = ln.substr(idx + 1).strip_edges()
		headers[hname] = hval
		if hname == "content-length":
			content_length = int(hval)
	var body_start: int = header_end + 4
	var total: int = buffer.size()
	if total - body_start < content_length:
		return {}  # body not fully arrived yet
	var body: String = buffer.slice(body_start, body_start + content_length).get_string_from_utf8()
	var rest: PackedByteArray = buffer.slice(body_start + content_length, total)
	return {"method": method, "path": path, "body": body, "headers": headers, "rest": rest}

# -- Routing (all agent work goes through AgentDriver.submit/poll) ---------

func _route(method: String, path: String, body: String, headers: Dictionary = {}) -> Dictionary:
	var path_only: String = path
	var query: Dictionary = {}
	var qidx: int = path.find("?")
	if qidx >= 0:
		path_only = path.substr(0, qidx)
		query = _parse_query(path.substr(qidx + 1))
	if method == "OPTIONS":
		return {"ok": true}
	if not _authorized(headers):
		return {"ok": false, "error": "unauthorized"}
	var driver := _driver()
	if driver == null:
		return {"ok": false, "error": "agent driver unavailable"}
	match path_only:
		"/health":
			return _call(driver, "ping", {})
		"/observe":
			return _call(driver, "observe", {})
		"/events":
			return _call(driver, "events", {"since": int(query.get("since", -1))})
		"/act":
			return _call(driver, "act", _act_args(_parse_body(body)))
		"/wait_for":
			var w: Dictionary = _parse_body(body)
			return _call(driver, "wait_for", {
				"predicate": w.get("predicate", {}),
				"timeout_ms": int(w.get("timeout_ms", w.get("timeoutMs", 8000))),
			})
		"/coord":
			return _call(driver, "coord", _parse_body(body))
	return {"ok": false, "error": "unknown route '%s'" % path_only}

## The gamestruct /act body is {id, verb, value}. The driver's act(id, args)
## takes an id plus a verb-specific args object, so fold `value` in (tolerating
## the legacy {id, args} shape a vant/companion client may still send).
func _act_args(body: Dictionary) -> Dictionary:
	var args: Dictionary = body.get("args", {}) if body.get("args", {}) is Dictionary else {}
	var value = body.get("value", null)
	if value is Dictionary:
		args = args.duplicate(true)
		for k in value:
			args[k] = value[k]
	return {"id": String(body.get("id", "")), "args": args}

## Submit to AgentDriver (main thread does the work), then poll this thread
## until the response lands. Never touches the scene tree here.
func _call(driver: Node, verb: String, args: Dictionary) -> Dictionary:
	var rid: int = driver.submit(verb, args)
	var deadline: int = Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		var resp: Dictionary = driver.poll(rid)
		if not resp.is_empty():
			return resp
		OS.delay_msec(POLL_MS)
	return {"ok": false, "error": "driver timeout"}

## Bearer auth, fail-closed when a token is configured. Loopback-only by
## default (no token) is the dev posture; a non-loopback bind without a token
## is refused by start(). See labs/prd-agent-play.md sec 9.
func _expected_token() -> String:
	if OS.has_environment("SYN_AGENT_TOKEN"):
		return OS.get_environment("SYN_AGENT_TOKEN").strip_edges()
	return ""

func _has_token() -> bool:
	return _expected_token() != ""

func _authorized(headers: Dictionary) -> bool:
	var want: String = _expected_token()
	if want == "":
		return true
	var auth: String = String(headers.get("authorization", ""))
	if auth.begins_with("Bearer "):
		return auth.substr(7).strip_edges() == want
	if auth.begins_with("bearer "):
		return auth.substr(7).strip_edges() == want
	if String(headers.get("x-api-key", "")) == want:
		return true
	return false

func _parse_body(body: String) -> Dictionary:
	if body.strip_edges() == "":
		return {}
	var parsed = JSON.parse_string(body)
	return parsed if parsed is Dictionary else {}

func _parse_query(qs: String) -> Dictionary:
	var out: Dictionary = {}
	for pair in qs.split("&"):
		if pair == "":
			continue
		var kv: Array = pair.split("=")
		out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out
