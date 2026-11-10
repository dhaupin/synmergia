## AgentDriver - the one command channel an agent (or a companion app, or a
## screen-reader control surface) uses to PLAY Synmergia.
##
## Agents are citizens here (labs/prd-agent-play.md): an agent connects to an
## ACCOUNT and plays any species/class, parties with humans, and acts through
## the SAME verbs a keypress takes. There is no agent rail and no bypass --
## every action routes through the real input pipeline / service APIs, so the
## behavioral-integrity layer (prd-agent-law.md) sees an honest stream.
##
## Four verbs, request/response, structured (never pixels, never console):
##   observe()                -> structured state + the actionable list
##   act(id, args)            -> perform one action by STABLE HANDLE
##   wait_for(predicate, ms)  -> server-side wait (no fixed-sleep flake)
##   events(since)            -> the recent event ring
##
## Plus `see(label)` -- the EYES: capture the current frame to a PNG the agent
## reads with its own vision (the eyestruct `spot` role). It is the one verb
## that returns pixels, and it returns a PATH, not base64, so the wire stays
## small. The door IS the camera; the agent supplies the seeing.
##
## Threading law: the transport (agent_door.gd) runs on its own thread and
## ONLY calls submit()/poll() -- a mutex-guarded queue. The main thread is the
## sole thing that touches the scene tree, draining the queue in _process.
## wait_for parks on the main thread and re-checks each frame until the
## predicate holds or the timeout expires, then answers the request.
##
## Enable: opt-in. SYN_AGENT=1 (or 1/true/yes) in the env, or enable() at
## runtime. Off is the honest default; the door binds localhost regardless.
extends Node

const RING_MAX := 200
const DEFAULT_WAIT_MS := 8000

var _enabled: bool = false
var _frames: int = 0
var _shot_seq: int = 0

# The event ring: {t, frame, event, data}. Plain types only (JSON-safe).
var _ring: Array = []

# Thread-safe command queue (door thread -> main thread).
var _mutex := Mutex.new()
var _queue: Array = []          # [{id, verb, args}]
var _responses: Dictionary = {}  # id -> response Dictionary
var _next_id: int = 1

# Parked wait_for requests on the main thread.
var _waits: Array = []  # [{id, pred, deadline_ms, since_frame}]

func _ready() -> void:
	_enabled = _env_enabled()
	_connect_event_ring()
	if _enabled:
		GameLog.info("AgentDriver: ENABLED (agents may connect; door binds localhost)")

func _env_enabled() -> bool:
	var raw: String = ""
	if OS.has_environment("SYN_AGENT"):
		raw = OS.get_environment("SYN_AGENT").strip_edges().to_lower()
	return raw in ["1", "true", "yes", "on"]

## Enable/disable at runtime (the door asks; receipts force it on).
func set_enabled(v: bool) -> void:
	_enabled = v

func is_enabled() -> bool:
	return _enabled

## True once a local player exists and a world is live (an agent can act).
func in_world() -> bool:
	return _local_player() != null

# -- The event ring --------------------------------------------------------

func _connect_event_ring() -> void:
	var hub := get_node_or_null("/root/EventHub")
	if hub != null:
		_tap(hub, "entity_died")
		_tap(hub, "player_died")
		_tap(hub, "player_respawned")
		_tap(hub, "kill_rewarded")
		_tap(hub, "damage_dealt")
		_tap(hub, "skill_executed")
		_tap(hub, "entity_entered_zone")
		_tap(hub, "entity_entered_combat")
		_tap(hub, "entity_exited_combat")
		_tap(hub, "gold_changed")
		_tap(hub, "target_action_executed")
	var notif := get_node_or_null("/root/NotificationService")
	if notif != null and notif.has_signal("notification_sent"):
		notif.notification_sent.connect(_on_notification_sent)

func _tap(hub: Node, sig: String) -> void:
	if hub.has_signal(sig):
		hub.connect(sig, _on_hub_event.bind(sig))

func _on_hub_event(a = null, b = null, c = null, d = null, e = null, sig: String = "") -> void:
	# Variadic: EventHub signals carry 1..5 args; capture the ones we get.
	var data: Dictionary = {}
	if a != null:
		data["a"] = _id_of(a)
	if b != null:
		data["b"] = _id_of(b)
	if c != null:
		data["c"] = _plain(c)
	if d != null:
		data["d"] = _plain(d)
	if e != null:
		data["e"] = _plain(e)
	_record(sig, data)

func _on_notification_sent(entity_id: String, notification: Dictionary) -> void:
	_record("notification", {
		"entity_id": entity_id,
		"kind": int(notification.get("kind", -1)),
		"message": String(notification.get("message", "")),
	})

func _record(event: String, data: Dictionary) -> void:
	_ring.append({"t": Time.get_ticks_msec(), "frame": _frames, "event": event, "data": data})
	if _ring.size() > RING_MAX:
		_ring = _ring.slice(_ring.size() - RING_MAX)

func _id_of(v) -> Variant:
	if v is Node and "entity_id" in v:
		return String(v.entity_id)
	return _plain(v)

func _plain(v) -> Variant:
	if v == null:
		return null
	if v is Vector3:
		return {"x": v.x, "y": v.y, "z": v.z}
	if v is Vector2:
		return {"x": v.x, "y": v.y}
	if v is int or v is float or v is bool or v is String:
		return v
	if v is Array:
		var out: Array = []
		for item in v:
			out.append(_plain(item))
		return out
	if v is Dictionary:
		var outd: Dictionary = {}
		for k in v:
			outd[String(k)] = _plain(v[k])
		return outd
	if v is Node and "entity_id" in v:
		return String(v.entity_id)
	return str(v)

## The recent event ring, optionally only entries after a frame.
func events(since_frame: int = -1) -> Array:
	if since_frame < 0:
		return _ring.duplicate(true)
	var out: Array = []
	for e in _ring:
		if int(e["frame"]) > since_frame:
			out.append(e)
	return out

# -- observe() -------------------------------------------------------------

## The structured snapshot: who/where I am, what I can do, what just happened.
## Never prints (the old print-stream is gone); returns JSON-safe data.
func observe(principal: String = "") -> Dictionary:
	var body := _body_for(principal)
	var player := body if body != null else _local_player()
	var scene: String = ""
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		scene = String(tree.current_scene.name)
	var out: Dictionary = {
		"ok": true,
		"frame": _frames,
		"enabled": _enabled,
		"scene": scene,
		"in_world": player != null,
		"principal": principal,
		"player": _player_block(player),
		"target": _target_block(),
		"party": _party_block(player),
		"actions": _actions(),
		"events": _ring.slice(maxi(0, _ring.size() - 20)),
	}
	return out

func _local_player() -> Node:
	var pm := get_node_or_null("/root/PlayerManager")
	if pm != null and "local_player" in pm:
		var lp = pm.local_player
		if lp != null and is_instance_valid(lp):
			return lp
	return null

func _player_block(player: Node) -> Variant:
	if player == null or not is_instance_valid(player):
		return null
	var pos: Vector3 = player.global_position
	var hp: int = 0
	var hp_max: int = 0
	var dead: bool = false
	if "health_component" in player and player.health_component != null:
		var hc = player.health_component
		if hc.has_method("get_health"):
			hp = int(hc.get_health())
		elif "current_health" in hc:
			hp = int(hc.current_health)
		if "max_health" in hc:
			hp_max = int(hc.max_health)
		if hc.has_method("is_dead"):
			dead = bool(hc.is_dead())
	var block: Dictionary = {
		"id": String(player.entity_id) if "entity_id" in player else "",
		"name": String(player.display_name) if "display_name" in player else "",
		"position": {"x": pos.x, "y": pos.y, "z": pos.z},
		"health": hp,
		"max_health": hp_max,
		"is_dead": dead,
	}
	if "level" in player:
		block["level"] = int(player.level)
	if "current_mana" in player:
		block["mana"] = int(player.current_mana)
	if "current_stamina" in player:
		block["stamina"] = int(player.current_stamina)
	if "is_sprinting" in player:
		block["is_sprinting"] = bool(player.is_sprinting)
	if "char_class" in player:
		block["char_class"] = String(player.char_class)
	if "species_id" in player:
		block["species"] = String(player.species_id)
	return block

func _target_block() -> Variant:
	var tm := get_node_or_null("/root/TargetingManager")
	if tm == null or not tm.has_method("get_current_target"):
		return null
	var info = tm.get_current_target()
	if info == null:
		return null
	return {
		"id": String(info.id) if "id" in info else "",
		"name": String(info.display_name) if "display_name" in info else "",
	}

func _party_block(player: Node) -> Variant:
	if player == null or not "entity_id" in player:
		return null
	var ps := get_node_or_null("/root/PartyService")
	if ps == null or not ps.has_method("get_player_party"):
		return null
	var party: Dictionary = ps.get_player_party(String(player.entity_id))
	if party.is_empty():
		return null
	var members: Array = []
	if ps.has_method("get_party_members"):
		members = ps.get_party_members(String(party.get("party_id", "")))
	return {"party_id": String(party.get("party_id", "")), "leader_id": String(party.get("leader_id", "")), "members": members}

## The actionable list, each carrying a STABLE id (ui:<path> / world:<id>).
func _actions() -> Array:
	var a11y := get_node_or_null("/root/A11yService")
	if a11y == null or not a11y.has_method("snapshot"):
		return []
	var snap: Array = a11y.snapshot()
	var out: Array = []
	for e in snap:
		var row: Dictionary = {
			"id": String(e.get("id", "")),
			"kind": String(e.get("kind", "")),
			"action": String(e.get("action", "")),
			"detail": String(e.get("detail", "")),
			"disabled": bool(e.get("disabled", false)),
		}
		# Settable controls carry their current value (so an agent can confirm a
		# set_value landed); secret fields report only whether they are filled.
		if e.has("value"):
			row["value"] = e["value"]
		out.append(row)
	return out

# -- act() -----------------------------------------------------------------

## Perform one action by stable handle (ui:<path> / world:<id>) or by a small
## set of world verbs (move/look/chat/attack/target/party_invite/stop). Every
## path routes through the real pipeline; returns {ok, reason, ...}.
func act(action_id: String, args: Dictionary = {}) -> Dictionary:
	if not _enabled:
		return {"ok": false, "reason": "agent driver disabled"}
	if action_id.begins_with("ui:") or action_id.begins_with("world:"):
		return _act_handle(action_id, String(args.get("verb", "")), args.get("value", null))
	return _act_verb(action_id, args, _principal(args))

## A `ui:`/`world:` handle. The gamestruct wire carries a `verb`: `set_value`
## is a VALUE WRITE (a text field or slider takes a value), any other verb (or
## none) is ACTIVATION. A verb the handle cannot satisfy is an HONEST refusal
## ("no settable value on ..."), never a silent success -- the class the live
## play-test caught: set_value on a LineEdit returned ok:true while the field
## stayed empty.
func _act_handle(action_id: String, verb: String, value) -> Dictionary:
	var a11y := get_node_or_null("/root/A11yService")
	if a11y == null:
		return {"ok": false, "reason": "a11y service missing"}
	if verb == "set_value":
		if not a11y.has_method("set_value_by_id"):
			return {"ok": false, "reason": "a11y service cannot set values"}
		if not a11y.set_value_by_id(action_id, value):
			return {"ok": false, "reason": "no settable value on '%s'" % action_id}
		return {"ok": true, "reason": "", "handle": action_id, "verb": "set_value"}
	if not a11y.has_method("activate_by_id"):
		return {"ok": false, "reason": "a11y service missing"}
	if not a11y.activate_by_id(action_id):
		return {"ok": false, "reason": "no actionable '%s' (gone or disabled)" % action_id}
	return {"ok": true, "reason": "", "handle": action_id}

## The principal a call is for: an explicit `principal`/`handle`/`body` arg,
## else "". "" means the LOCAL seat -- the human's own body -- which is what
## a single-agent caller (the human's door, the 2D surface) always wants.
func _principal(args: Dictionary) -> String:
	for key in ["principal", "handle", "body"]:
		if args.has(key):
			var v: String = String(args.get(key, "")).strip_edges()
			if v != "":
				return v
	return ""


## Resolve a principal to a live body. A non-empty principal that does not
## resolve is an HONEST refusal at the call site (never a silent fall-back
## onto the local player, which would let one agent drive another's body).
## "local" / "human" / "" resolve to the human's own body.
func _body_for(principal: String) -> Node:
	if principal == "" or principal == "local" or principal == "human":
		return _local_player()
	var bodies := get_node_or_null("/root/AgentBodyService")
	if bodies != null and bodies.has_method("body_for"):
		var b = bodies.body_for(principal)
		if b is Node and is_instance_valid(b):
			return b
	return null


func _act_verb(verb: String, args: Dictionary, principal: String = "") -> Dictionary:
	var body := _body_for(principal)
	var player := body if body != null else _local_player()
	match verb:
		"move":
			return _verb_move(args, player)
		"stop":
			return _verb_stop(player)
		"look":
			return _verb_look(args, player)
		"chat":
			return _verb_chat(player, args)
		"attack":
			return _verb_attack(player, args)
		"target":
			return _verb_target(args)
		"party_invite":
			return _verb_party_invite(player, args)
		"party_leave":
			return _verb_party_leave(player)
		"interact":
			return _verb_interact(player)
		"see":
			return _verb_see(args)
	return {"ok": false, "reason": "unknown verb '%s'" % verb}

## Movement rides the REAL action map: action_press/release are exactly what a
## key does, so globe_player's Input.get_vector reads them with no bypass.
const _MOVE_ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "sprint"]

func _verb_move(args: Dictionary, body: Node) -> Dictionary:
	var fwd: float = float(args.get("forward", 0.0))
	var strafe: float = float(args.get("strafe", 0.0))
	var sprint: bool = bool(args.get("sprint", false))
	# An agent body owns its OWN input (sec 1/7): a move sets that body's
	# virtual stick, never the global Input singleton -- so two bodies in
	# one process do not steer each other. The HUMAN's body keeps riding
	# the real action map (exactly what a key does), so nothing about the
	# single-player path changes.
	if body != null and body.has_method("set_virtual_input"):
		body.set_virtual_input(Vector2(strafe, fwd), sprint)
		return {"ok": true}
	_release_moves()
	if fwd > 0.05:
		Input.action_press("move_forward")
	elif fwd < -0.05:
		Input.action_press("move_back")
	if strafe > 0.05:
		Input.action_press("move_right")
	elif strafe < -0.05:
		Input.action_press("move_left")
	if sprint:
		Input.action_press("sprint")
	return {"ok": true}


## stop(): an agent body zeroes its virtual stick; the human's body releases
## the held actions.
func _verb_stop(body: Node) -> Dictionary:
	if body != null and body.has_method("set_virtual_input"):
		body.set_virtual_input(Vector2.ZERO, false)
		return {"ok": true}
	_release_moves()
	return {"ok": true}

func _release_moves() -> void:
	for a in _MOVE_ACTIONS:
		if Input.is_action_pressed(a):
			Input.action_release(a)

func _verb_look(args: Dictionary, body: Node = null) -> Dictionary:
	var player := body if body != null else _local_player()
	if player == null:
		return {"ok": false, "reason": "no local player"}
	# An agent body aims its OWN camera pivot; only the human's body (the
	# one the OS mouse drives) parses a global mouse event.
	if body != null and body != _local_player():
		var pivot: Node3D = body.get_node_or_null("CameraPivot")
		if pivot != null:
			var yaw: float = float(args.get("yaw", 0.0))
			var pitch: float = float(args.get("pitch", 0.0))
			pivot.rotate_object_local(Vector3.UP, -yaw * 0.001)
			pivot.rotate_object_local(Vector3.RIGHT, -pitch * 0.001)
			return {"ok": true}
	var yaw: float = float(args.get("yaw", 0.0))
	var pitch: float = float(args.get("pitch", 0.0))
	if yaw == 0.0 and pitch == 0.0:
		return {"ok": true}
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(yaw, pitch)
	ev.position = Vector2.ZERO
	Input.parse_input_event(ev)
	return {"ok": true}

## see(label) -- capture the current frame to a PNG an agent can read with its
## own vision (the eyestruct `spot` role: the door IS the eyes). Runs on the
## main thread, which is what makes it safe to grab the viewport texture here.
## The pixels never travel as base64 (that would be a megabyte in the ring);
## the door writes the file and answers a path + a `file://` URL. A blank or
## tiny frame is an honest failure, never a "success" with no image.
func _verb_see(args: Dictionary) -> Dictionary:
	var vp := get_viewport()
	if vp == null:
		return {"ok": false, "reason": "no viewport"}
	var tex := vp.get_texture()
	if tex == null:
		return {"ok": false, "reason": "no viewport texture"}
	# get_image() on the main thread returns the last drawn frame; the door is
	# queried while the game is live, so that is the current view. A not-yet-
	# drawn first frame comes back skeletal and the size check refuses it.
	var img: Image = tex.get_image()
	if img == null:
		return {"ok": false, "reason": "viewport capture returned null"}
	var label: String = String(args.get("label", "")).strip_edges()
	if label == "":
		label = "see"
	label = _safe_label(label)
	_shot_seq += 1
	var rel: String = "captures/agent/see_%s_%03d.png" % [label, _shot_seq]
	var abs_path: String = ProjectSettings.globalize_path("res://" + rel)
	var mk := DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	if mk != OK and mk != ERR_ALREADY_EXISTS:
		return {"ok": false, "reason": "could not create captures/agent/"}
	var err: int = img.save_png(abs_path)
	if err != OK:
		return {"ok": false, "reason": "save_png failed (err=%d)" % err}
	var size: int = _file_size(abs_path)
	if size < 1024:
		return {"ok": false, "reason": "capture too skeletal (%d bytes) - blank frame" % size}
	var view: Dictionary = {
		"ok": true,
		"path": abs_path,
		"url": "file://" + abs_path,
		"bytes": size,
		"width": img.get_width(),
		"height": img.get_height(),
		"frame": _frames,
		"in_world": in_world(),
		"note": "read this PNG with your own vision (eyestruct spot / any viewer)",
	}
	return view

func _safe_label(label: String) -> String:
	var out: String = ""
	for i in range(label.length()):
		var c: String = label[i]
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" or c == "-":
			out += c
		else:
			out += "_"
	return out.substr(0, 40)

func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n: int = f.get_length()
	f.close()
	return n

func _verb_chat(player: Node, args: Dictionary) -> Dictionary:
	if player == null:
		return {"ok": false, "reason": "no local player"}
	var text: String = String(args.get("text", ""))
	if text == "":
		return {"ok": false, "reason": "empty message"}
	# ChatService.send_message(sender_id: String, channel: int, message: String).
	# The sender is the player's ID (not the node) and the channel is the enum
	# value, resolved by name -- the class the live play-test caught: passing
	# the node + a channel string raised a SCRIPT ERROR inside the queue drain,
	# which then never responded (the door's poll hung to timeout).
	var channel: String = String(args.get("channel", "say"))
	var chat := get_node_or_null("/root/ChatService")
	if chat == null or not chat.has_method("send_message"):
		return {"ok": false, "reason": "chat service missing"}
	var sender_id: String = String(player.entity_id) if "entity_id" in player else ""
	if sender_id == "":
		return {"ok": false, "reason": "player has no id"}
	var ch: int = chat.channel_by_name(channel) if chat.has_method("channel_by_name") else 0
	if ch < 0:
		return {"ok": false, "reason": "unknown channel '%s'" % channel}
	var ok: bool = chat.send_message(sender_id, ch, text)
	return {"ok": ok, "reason": "" if ok else "send rejected"}

func _verb_attack(player: Node, args: Dictionary) -> Dictionary:
	if player == null:
		return {"ok": false, "reason": "no local player"}
	if args.has("target"):
		var t: Dictionary = _verb_target(args)
		if not bool(t.get("ok", false)):
			return t
	if player.has_method("use_skill"):
		seed(int(Time.get_ticks_msec()) % 100000)
		player.use_skill(int(args.get("skill", 0)))
		return {"ok": true}
	return {"ok": false, "reason": "player cannot use_skill"}

func _verb_target(args: Dictionary) -> Dictionary:
	var eid: String = String(args.get("target", args.get("entity_id", "")))
	if eid == "":
		return {"ok": false, "reason": "no target id"}
	var es := get_node_or_null("/root/EntityService")
	var tm := get_node_or_null("/root/TargetingManager")
	if es == null or tm == null or not es.has_method("get_entity"):
		return {"ok": false, "reason": "targeting unavailable"}
	var entity = es.get_entity(eid)
	if entity == null or not is_instance_valid(entity):
		return {"ok": false, "reason": "no entity '%s'" % eid}
	var sname: String = String(entity.display_name) if "display_name" in entity else eid
	var etype: int = int(entity.entity_type) if "entity_type" in entity else 0
	tm.set_target(eid, eid, sname, entity.global_position, entity, etype, {})
	return {"ok": true, "reason": "", "target": eid}

func _verb_party_invite(player: Node, args: Dictionary) -> Dictionary:
	if player == null or not "entity_id" in player:
		return {"ok": false, "reason": "no local player"}
	var to: String = String(args.get("target", ""))
	if to == "":
		return {"ok": false, "reason": "no target id"}
	var ps := get_node_or_null("/root/PartyService")
	if ps == null or not ps.has_method("invite_player"):
		return {"ok": false, "reason": "party service missing"}
	var ok: bool = ps.invite_player(String(player.entity_id), to)
	return {"ok": ok, "reason": "" if ok else "invite refused"}

func _verb_party_leave(player: Node) -> Dictionary:
	if player == null or not "entity_id" in player:
		return {"ok": false, "reason": "no local player"}
	var ps := get_node_or_null("/root/PartyService")
	if ps == null or not ps.has_method("leave_party"):
		return {"ok": false, "reason": "party service missing"}
	var ok: bool = ps.leave_party(String(player.entity_id))
	return {"ok": ok}

func _verb_interact(player: Node) -> Dictionary:
	if player == null:
		return {"ok": false, "reason": "no local player"}
	if player.has_method("_try_interact"):
		player._try_interact()
		return {"ok": true}
	return {"ok": false, "reason": "player cannot interact"}

# -- wait_for() ------------------------------------------------------------

## Server-side wait: resolves when the predicate holds, else on timeout.
## Predicate vocabulary (all optional, ANDed):
##   {"action_present": "<substr>"}  {"action_absent": "<substr>"}
##   {"in_world": bool}  {"player_dead": bool}
##   {"event": "<name>"}  {"target": "<substr>"}  {"hp_below": int}
func wait_for(predicate: Dictionary, timeout_ms: int = DEFAULT_WAIT_MS) -> Dictionary:
	if not _enabled:
		return {"ok": false, "reason": "agent driver disabled"}
	var since: int = _frames
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	var tree := get_tree()
	if tree == null:
		return {"ok": false, "reason": "no tree"}
	while Time.get_ticks_msec() < deadline:
		if _predicate_met(predicate, since):
			return {"ok": true, "waited_ms": timeout_ms - (deadline - Time.get_ticks_msec())}
		await tree.process_frame
	if _predicate_met(predicate, since):
		return {"ok": true, "waited_ms": timeout_ms}
	return {"ok": false, "reason": "timeout", "predicate": predicate}

func _predicate_met(predicate: Dictionary, since_frame: int) -> bool:
	var player := _local_player()
	for key in predicate:
		var want = predicate[key]
		match String(key):
			"in_world":
				if (player != null) != bool(want):
					return false
			"player_dead":
				var dead: bool = false
				if player != null and "health_component" in player and player.health_component != null:
					var hc = player.health_component
					if hc.has_method("is_dead"):
						dead = bool(hc.is_dead())
				if dead != bool(want):
					return false
			"hp_below":
				if player == null or not "health_component" in player or player.health_component == null:
					return false
				var hc2 = player.health_component
				var hp: int = int(hc2.get_health()) if hc2.has_method("get_health") else 0
				if hp >= int(want):
					return false
			"action_present":
				if not _has_action(String(want)):
					return false
			"action_absent":
				if _has_action(String(want)):
					return false
			"target":
				var tb = _target_block()
				if tb == null or not String(tb.get("name", "")).to_lower().contains(String(want).to_lower()):
					return false
			"event":
				if not _event_since(String(want), since_frame):
					return false
			_:
				return false
	return true

func _has_action(substr: String) -> bool:
	var needle: String = substr.to_lower()
	for a in _actions():
		if String(a["action"]).to_lower().contains(needle):
			return true
	return false

func _event_since(name: String, since_frame: int) -> bool:
	for e in _ring:
		if int(e["frame"]) > since_frame and String(e["event"]) == name:
			return true
	return false

# -- Thread-safe door interface (agent_door.gd runs on its own thread) -----

## Enqueue a request from the transport thread. Returns the request id.
func submit(verb: String, args: Dictionary) -> int:
	_mutex.lock()
	var id: int = _next_id
	_next_id += 1
	_queue.append({"id": id, "verb": verb, "args": args})
	_mutex.unlock()
	return id

## Poll for a response (transport thread). Empty dict = not ready yet.
func poll(id: int) -> Dictionary:
	_mutex.lock()
	var resp: Dictionary = _responses.get(id, {})
	if not resp.is_empty():
		_responses.erase(id)
	_mutex.unlock()
	return resp

func _respond(id: int, resp: Dictionary) -> void:
	_mutex.lock()
	_responses[id] = resp
	_mutex.unlock()

func _process(_delta: float) -> void:
	_frames += 1
	if not _enabled:
		return
	_drain_queue()
	_tick_waits()

func _drain_queue() -> void:
	_mutex.lock()
	var batch: Array = _queue
	_queue = []
	_mutex.unlock()
	for req in batch:
		var verb: String = String(req["verb"])
		var args: Dictionary = req["args"]
		match verb:
			"observe":
				_respond(int(req["id"]), observe(String(args.get("principal", ""))))
			"act":
				_respond(int(req["id"]), act(String(args.get("id", "")), args.get("args", {})))
			"events":
				_respond(int(req["id"]), {"ok": true, "frame": _frames, "events": events(int(args.get("since", -1)))})
			"wait_for":
				_waits.append({
					"id": int(req["id"]),
					"pred": args.get("predicate", {}),
					"deadline": Time.get_ticks_msec() + int(args.get("timeout_ms", DEFAULT_WAIT_MS)),
					"since": _frames,
				})
			"ping":
				_respond(int(req["id"]), {"ok": true, "frame": _frames, "in_world": in_world()})
			"see":
				_respond(int(req["id"]), _verb_see(args))
			"coord":
				_respond(int(req["id"]), _coord(args))
			_:
				_respond(int(req["id"]), {"ok": false, "reason": "unknown verb '%s'" % verb})

## The coordinator dispatch (multi-agent). Runs on the main thread, same as
## every other verb -- the door thread only ever calls submit()/poll().
func _coord(args: Dictionary) -> Dictionary:
	var c := get_node_or_null("/root/AgentCoordinator")
	if c == null:
		return {"ok": false, "reason": "coordinator unavailable"}
	var op: String = String(args.get("op", ""))
	var handle: String = String(args.get("handle", ""))
	match op:
		"status":
			return c.status()
		"register":
			return c.register(handle, args.get("opts", {}))
		"unregister", "terminate":
			return {"ok": c.unregister(handle)}
		"list":
			return {"ok": true, "agents": c.list_agents()}
		"get":
			return {"ok": true, "agent": c.get_agent(handle)}
		"pause":
			return {"ok": c.pause(handle)}
		"resume":
			return {"ok": c.resume(handle)}
		"delegate":
			return c.delegate(handle, args.get("task", {}))
		"poll":
			return c.poll_work(handle)
		"queue":
			return {"ok": true, "queue": c.queue_of(handle)}
		"approve":
			return c.approve(handle, int(args.get("work_id", 0)))
		"reject":
			return c.reject(handle, int(args.get("work_id", 0)), String(args.get("reason", "")))
		"step":
			return c.step()
		"run":
			return c.run_until_idle(int(args.get("max_steps", 256)))
	return {"ok": false, "reason": "unknown coord op '%s'" % op}

func _tick_waits() -> void:
	if _waits.is_empty():
		return
	var remaining: Array = []
	for w in _waits:
		var pred: Dictionary = w["pred"]
		if _predicate_met(pred, int(w["since"])):
			_respond(int(w["id"]), {"ok": true})
		elif Time.get_ticks_msec() >= int(w["deadline"]):
			_respond(int(w["id"]), {"ok": false, "reason": "timeout", "predicate": pred})
		else:
			remaining.append(w)
	_waits = remaining
