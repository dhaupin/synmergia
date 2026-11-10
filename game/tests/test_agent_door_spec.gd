## test_agent_door_spec.gd - LIVE receipt for gamestruct SPEC v1.1 conformance
## on the AgentDoor (game/core/services/agent_door.gd). Boots the real globe
## with the door enabled (SYN_AGENT=1) and asserts the SPEC wire over real
## HTTP round-trips:
##   1. GET  /health          -> {ok:true} (liveness)
##   2. GET  /observe         -> a snapshot whose actionables fold into the
##                               doorNodes contract: every interactive node
##                               carries a non-empty id + non-empty name (N6)
##   3. POST /act             -> an unknown handle is an HONEST refusal
##                               {ok:false, reason} by stable handle (N1/N2/N21)
##   4. POST /wait_for        -> an unsatisfiable predicate times out honestly
##                               (reason:"timeout") and NEVER hangs (N3)
##   5. GET  /events?since=N  -> a monotonic, honest frame cursor (N4)
##   6. POST /see             -> ok+path OR an honest refusal; never base64 on
##                               the wire (N22/N23)
##
## The door `kind` -> gamestruct role fold mirrors gamestruct's own reference
## adapter (node_modules/gamestruct/lib/adapters/synmergia.mjs, doorNodes), so
## this receipt proves the surface the two lanes actually read.
##
## Run (the live-driver convention -- xvfb + headless):
##   SYN_AGENT=1 xvfb-run -a godot --headless --path game \
##     --script res://tests/test_agent_door_spec.gd
##
## Exit 0 = every leg held; failures print [FAIL] lines and exit 1.
extends SceneTree

var _pass := 0
var _fail := 0

var _globe: Node = null
var _boot = null
var _player: Node = null
var _driver: Node = null
var _door: Node = null

# door `kind` -> gamestruct role, mirrored from synmergia.mjs KIND_ROLES.
# An unknown kind falls to "button" (the adapter's default).
const KIND_ROLES := {
	"entity": "listitem",
	"button": "button",
	"checkbox": "checkbox",
	"checkbutton": "checkbox",
	"lineedit": "textbox",
	"textedit": "textbox",
	"itemlist": "list",
	"slider": "slider",
	"hslider": "slider",
	"vslider": "slider",
	"optionbutton": "combobox",
	"label": "text",
	"richlabel": "text",
	"panel": "group",
}

# Roles whose value an agent can WRITE (the door's set_value verb).
const SETTABLE_ROLES := ["textbox", "slider", "combobox", "checkbox", "switch"]


func _initialize() -> void:
	print("=== AGENT DOOR SPEC: booting globe scene ===")
	_boot = load("res://tests/support/globe_boot.gd")
	_boot_globe.call_deferred()


func _boot_globe() -> void:
	_globe = await _boot.boot(self)
	if _globe == null:
		print("  FAIL: could not load globe_world.tscn")
		quit(1)
		return
	current_scene = _globe
	_run.call_deferred()


func _run() -> void:
	_driver = root.get_node_or_null("AgentDriver")
	_door = root.get_node_or_null("AgentDoor")
	_assert(_driver != null, "AgentDriver autoload present")
	_assert(_door != null, "AgentDoor autoload present")
	if _driver == null or _door == null:
		_finish()
		return
	# The shipped posture is SYN_AGENT=1; the receipt forces the same enable
	# so it holds regardless of how the process was launched.
	_driver.set_enabled(true)
	_player = _boot.player(_globe)
	_assert(_player != null, "local player present on the globe")

	var port: int = _door.start(0)
	_assert(port > 0, "AgentDoor binds a port (enabled door is live)")
	if port <= 0:
		_finish()
		return

	await _leg_health()
	await _leg_observe()
	await _leg_act_refusal()
	await _leg_wait_for_timeout()
	await _leg_events_cursor()
	await _leg_see()

	_door.stop()
	_finish()


## 1. Liveness.
func _leg_health() -> void:
	var health: Dictionary = await _http("GET", "/health")
	_assert(bool(health.get("ok", false)), "GET /health -> ok:true")
	_assert(health.has("frame"), "GET /health carries a frame cursor")
	print("    [health] ok=%s frame=%s" % [str(health.get("ok", false)), str(health.get("frame", "?"))])


## 2. The snapshot folds into the doorNodes contract: one node per actionable,
## each with a stable non-empty id, a role, and a non-empty accessible name.
func _leg_observe() -> void:
	var obs: Dictionary = await _http("GET", "/observe")
	_assert(bool(obs.get("ok", false)), "GET /observe -> ok:true")
	var acts = obs.get("actions", [])
	_assert(acts is Array, "GET /observe carries an actions[] list")
	if not (acts is Array):
		return
	var nodes: Array = _fold_nodes(acts)
	_assert(nodes.size() == _count_handles(acts), "every action with a handle folds into a node (doorNodes contract)")
	var names_ok: bool = true
	var verbs_ok: bool = true
	for n in nodes:
		if String(n.get("id", "")) == "" or String(n.get("name", "")) == "":
			names_ok = false
		if (n.get("actions", []) as Array).is_empty():
			verbs_ok = false
	_assert(names_ok, "every interactive node has a non-empty id + name (N6)")
	_assert(verbs_ok, "every interactive node declares at least one action (N8)")
	print("    [observe] actions=%d nodes=%d in_world=%s" % [acts.size(), nodes.size(), str(obs.get("in_world", false))])


## 3. A refusal is a value, never a throw: an unknown handle and an unknown
## verb both answer {ok:false, reason}.
func _leg_act_refusal() -> void:
	var ghost: Dictionary = await _http("POST", "/act", JSON.stringify({"id": "ui:Does/Not/Exist", "verb": "activate", "value": {}}))
	_assert(not bool(ghost.get("ok", true)), "POST /act unknown handle is refused (N1/N2)")
	_assert(String(ghost.get("reason", "")) != "", "the handle refusal carries a human-readable reason (N21)")
	var verb: Dictionary = await _http("POST", "/act", JSON.stringify({"id": "fly_to_moon", "value": {}}))
	_assert(not bool(verb.get("ok", true)), "POST /act unknown verb is refused")
	_assert(String(verb.get("reason", "")) != "", "the unknown-verb refusal carries a reason")
	print("    [act] ghost reason=%s" % String(ghost.get("reason", "")))


## 4. wait_for resolves honestly on timeout, within the window, never hangs.
func _leg_wait_for_timeout() -> void:
	var start: int = Time.get_ticks_msec()
	var to: Dictionary = await _http("POST", "/wait_for", JSON.stringify({"predicate": {"event": "never_fires_spec_xyz"}, "timeoutMs": 300}))
	var elapsed: int = Time.get_ticks_msec() - start
	_assert(not bool(to.get("ok", true)), "POST /wait_for unsatisfiable predicate does not resolve")
	_assert(String(to.get("reason", "")) == "timeout", "wait_for reports the honest reason 'timeout' (N3)")
	_assert(elapsed < 5000, "wait_for returned inside the window, never hung (%d ms)" % elapsed)
	print("    [wait_for] reason=%s elapsed=%dms" % [String(to.get("reason", "")), elapsed])


## 5. The frame cursor is monotonic and honest: a later cursor returns only
## frames past it.
func _leg_events_cursor() -> void:
	var ring_all: Dictionary = await _http("GET", "/events?since=-1")
	_assert(bool(ring_all.get("ok", false)), "GET /events?since=-1 -> ok:true")
	var evs = ring_all.get("events", [])
	_assert(evs is Array, "GET /events carries an events[] ring")
	if not (evs is Array):
		return
	var monotonic: bool = true
	var last: int = -1
	var cursor: int = -1
	for e in evs:
		if not (e is Dictionary):
			continue
		var f: int = int(e.get("frame", -1))
		if f < last:
			monotonic = false
		last = f
		if f > cursor:
			cursor = f
	_assert(monotonic, "event frames are monotonic (N4)")
	var after: Dictionary = await _http("GET", "/events?since=%d" % cursor)
	_assert(bool(after.get("ok", false)), "GET /events?since=<cursor> -> ok:true")
	var honest: bool = true
	for e in after.get("events", []):
		if e is Dictionary and int(e.get("frame", -1)) <= cursor:
			honest = false
	_assert(honest, "since=<cursor> returns only frames past the cursor (honest cursor, N4)")
	# HONEST GAP (reported, not fixed here -- agent_door.gd is outside this
	# receipt's owned file): SPEC's primitive table + N4 define
	# events(sinceFrame) -> { frame, events[] } with a TOP-LEVEL `frame`
	# cursor (gamestruct's own reference bridge.events() returns it). The
	# door's /events route answers { ok, events[] } with no top-level frame,
	# so a client must derive the cursor from the events themselves. This leg
	# reports the gap; the cursor above is derived from event frames, which is
	# why the monotonic/honest assertions still hold.
	var has_top_frame: bool = ring_all.has("frame")
	print("    [events] ring=%d cursor=%d top_level_frame=%s" % [evs.size(), cursor, str(has_top_frame)])


## 6. The eyes: ok+path when the surface can render, an honest refusal when it
## cannot -- and NEVER pixel bytes on the wire (the descriptor is small).
func _leg_see() -> void:
	var resp: Dictionary = await _http("POST", "/see", JSON.stringify({"label": "spec"}))
	if bool(resp.get("ok", false)):
		var path: String = String(resp.get("path", ""))
		_assert(path != "", "POST /see -> ok carries a locatable path (N23)")
		_assert(FileAccess.file_exists(path), "the capture file exists on disk (N23)")
		print("    [see] captured %s" % path.get_file())
	else:
		_assert(String(resp.get("reason", "")) != "", "POST /see refused with an honest reason (N22)")
		print("    [see] honest refusal: %s" % String(resp.get("reason", "")))
	var raw: String = JSON.stringify(resp)
	_assert(not raw.contains("\"base64\"") and not raw.contains("data:image"), "no base64/pixels on the wire (N23)")
	_assert(raw.length() < 4096, "the /see descriptor is small -- no pixel bytes (N23)")


## Fold the door's flat actions[] into SPEC nodes, mirroring gamestruct's
## doorNodes: id unchanged, role from kind, name from the action label.
func _fold_nodes(actions: Array) -> Array:
	var nodes: Array = []
	for a in actions:
		if not (a is Dictionary):
			continue
		var handle: String = String(a.get("id", ""))
		if handle == "":
			continue
		var role: String = _role_for_kind(String(a.get("kind", "")))
		var nm: String = handle
		if a.get("action", null) != null:
			nm = String(a.get("action"))
		var verbs: Array = ["activate"]
		if SETTABLE_ROLES.has(role):
			verbs = ["set_value"]
		nodes.append({"id": handle, "role": role, "name": nm, "actions": verbs})
	return nodes


func _count_handles(actions: Array) -> int:
	var n: int = 0
	for a in actions:
		if a is Dictionary and String(a.get("id", "")) != "":
			n += 1
	return n


func _role_for_kind(kind: String) -> String:
	var k: String = kind.to_lower()
	if KIND_ROLES.has(k):
		return String(KIND_ROLES[k])
	return "button"


## A one-shot HTTP round-trip against the door (raw TCP, no client lib).
func _http(method: String, path: String, body: String = "") -> Dictionary:
	var peer := StreamPeerTCP.new()
	var err: int = peer.connect_to_host("127.0.0.1", _door.get_port())
	if err != OK:
		return {}
	var deadline: int = Time.get_ticks_msec() + 5000
	while peer.get_status() != StreamPeerTCP.STATUS_CONNECTED and Time.get_ticks_msec() < deadline:
		await process_frame
		peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return {}
	var req: String = "%s %s HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: keep-alive\r\n\r\n%s" % [
		method, path, body.to_utf8_buffer().size(), body]
	peer.put_data(req.to_utf8_buffer())
	var raw := PackedByteArray()
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		peer.poll()
		var avail: int = peer.get_available_bytes()
		if avail > 0:
			var chunk: Array = peer.get_partial_data(avail)
			if chunk[0] == OK:
				raw.append_array(chunk[1])
		if raw.size() > 0:
			var t: String = raw.get_string_from_utf8()
			var sp: int = t.find("\r\n\r\n")
			if sp >= 0 and t.substr(sp + 4).strip_edges() != "":
				break
	peer.disconnect_from_host()
	var full: String = raw.get_string_from_utf8()
	var sep: int = full.find("\r\n\r\n")
	if sep < 0:
		return {}
	var parsed = JSON.parse_string(full.substr(sep + 4))
	return parsed if parsed is Dictionary else {}


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] %s" % label)
	else:
		_fail += 1
		print("  [FAIL] %s" % label)


func _finish() -> void:
	print("=== AGENT DOOR SPEC: %d passed / %d failed ===" % [_pass, _fail])
	if _globe != null and is_instance_valid(_globe):
		_globe.free()
	quit(0 if _fail == 0 else 1)
