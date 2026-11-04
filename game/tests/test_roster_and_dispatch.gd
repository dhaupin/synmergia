# test_roster_and_dispatch.gd - issues #34 + #35: the phantom-call seams.
#
# Two server surfaces used to call methods that never existed. Both are
# pinned here so a future edit cannot quietly restore the ghosts:
#
#   A. THE ROSTER API (issue #34): PlayerManager gains the delegating
#      helpers the admin/targeting surfaces always asked for --
#      get_player_info / get_all_players / get_online_player_ids /
#      is_player_online -- backed by EntityService's live registration.
#      "Online" means a live player node is registered, never an
#      invented character id.
#   B. THE DISPATCH IS HONEST (issue #35): NetworkManager routes client
#      chat through the REAL ChatService.send_message using the
#      peer->character mapping for identity (the payload cannot name its
#      own sender), drops messages from peers with no character, and
#      warns ONCE for message types with no live handler instead of
#      calling handle_client_input/action/chat into the void.
#
# Script mode law: autoloads at runtime (PlayerManager, EntityService,
# NetworkManager, ChatService); Entity loads in the body, never preloaded.
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)

func _count_sender(rows: Array, sender: String) -> int:
	var n: int = 0
	for row in rows:
		if str((row as Dictionary).get("sender", "")) == sender:
			n += 1
	return n

func _last_from(rows: Array, sender: String) -> Dictionary:
	for i in range(rows.size() - 1, -1, -1):
		var row: Dictionary = rows[i]
		if str(row.get("sender", "")) == sender:
			return row
	return {}


## A live player-shaped body: entity_id + display_name + level +
## entity_type, the four fields EntityService registration reads.
func _make_player_body(id: String, display_name: String, level: int, player_type: int) -> Node3D:
	var script := GDScript.new()
	script.source_code = "extends Node3D\n" \
		+ "var entity_id: String = \"%s\"\n" % id \
		+ "var display_name: String = \"%s\"\n" % display_name \
		+ "var level: int = %d\n" % level \
		+ "var entity_type: int = %d\n" % player_type \
		+ "var seed: int = 0\n"
	script.reload()
	var body := Node3D.new()
	body.set_script(script)
	return body


func _run() -> void:
	print("=== ROSTER + DISPATCH RECEIPT (issues #34 / #35) ===")
	var entity_script = load("res://core/entities/entity.gd")
	var player_type: int = int(entity_script.EntityType.PLAYER)
	var pm = root.get_node_or_null("PlayerManager")
	var es = root.get_node_or_null("EntityService")
	var nm = root.get_node_or_null("NetworkManager")
	var chat = root.get_node_or_null("ChatService")

	# --- A. THE API EXISTS (the issue's exact gap) -------------------------
	_check("PlayerManager present", pm != null)
	_check("EntityService present", es != null)
	_check("NetworkManager present", nm != null)
	_check("ChatService present", chat != null)
	if pm == null or es == null or nm == null or chat == null:
		_finish("MISSING AUTOLOAD")
		return

	_check("PlayerManager.get_player_info exists", pm.has_method("get_player_info"))
	_check("PlayerManager.get_all_players exists", pm.has_method("get_all_players"))
	_check("PlayerManager.get_online_player_ids exists", pm.has_method("get_online_player_ids"))
	_check("PlayerManager.is_player_online exists", pm.has_method("is_player_online"))
	_check("NetworkManager._handle_client_chat exists", nm.has_method("_handle_client_chat"))
	_check("NetworkManager._warn_unrouted exists", nm.has_method("_warn_unrouted"))
	# The ghost the old dispatch called: ChatService never had it.
	_check("ChatService has no phantom handle_client_chat", not chat.has_method("handle_client_chat"))

	# --- B. EMPTY / UNKNOWN READS ARE HONEST --------------------------------
	_check("is_player_online('') is false", not pm.is_player_online(""))
	_check("is_player_online(unknown) is false", not pm.is_player_online("nobody_home_xyz"))
	_check("get_player_info('') is empty", (pm.get_player_info("") as Dictionary).is_empty())
	_check("get_player_info(unknown) is empty", (pm.get_player_info("nobody_home_xyz") as Dictionary).is_empty())
	_check("get_all_players() is an Array", pm.get_all_players() is Array)
	_check("get_online_player_ids() is an Array", pm.get_online_player_ids() is Array)

	# --- C. LIVE ROSTER TRUTH ------------------------------------------------
	var body := _make_player_body("roster_test_player", "Ro Muster", 9, player_type)
	root.add_child(body)
	es.register_entity(body, null, "roster_test_player")
	_check("registered body is online", pm.is_player_online("roster_test_player"))
	var info: Dictionary = pm.get_player_info("roster_test_player")
	_check("roster row carries entity_id", str(info.get("entity_id", "")) == "roster_test_player")
	_check("roster row carries display_name", str(info.get("name", "")) == "Ro Muster")
	_check("roster row carries live level", int(info.get("level", 0)) == 9)
	_check("roster row says online", bool(info.get("online", false)))
	_check("roster row carries a permission_level", info.has("permission_level"))
	var ids: Array = pm.get_online_player_ids()
	_check("online ids include the live player", ids.has("roster_test_player"))
	var listed := false
	for row in pm.get_all_players():
		if str((row as Dictionary).get("entity_id", "")) == "roster_test_player":
			listed = true
	_check("get_all_players lists the live player", listed)

	# --- D. ADMIN ROW -> ENTITY RESOLUTION (the old `p as Node3D` hole) ----
	var admin_cmds = load("res://core/utils/admin_commands.gd").new()
	root.add_child(admin_cmds)
	var found = admin_cmds._find_entity_by_id("roster_test_player")
	_check("admin lookup resolves the roster row to the live node", found == body)
	_check("admin lookup of an unknown id is null", admin_cmds._find_entity_by_id("nobody_home_xyz") == null)
	admin_cmds.queue_free()

	# --- E. CLIENT CHAT ROUTES THROUGH THE REAL SERVICE ---------------------
	# ChatService emits SYSTEM lines of its own (achievements), so the legs
	# count only rows whose sender is the derived character.
	var received: Array = []
	var on_received := func(sender_id, _channel, message, _targets) -> void:
		received.append({"sender": str(sender_id), "message": str(message)})
	chat.message_received.connect(on_received)
	# A peer with no associated character cannot speak (identity is derived).
	nm.connected_peers.erase(4242)
	var before: int = _count_sender(received, "roster_test_player")
	nm._handle_client_chat(4242, {"channel": "say", "message": "ghost"})
	_check("chat from an unmapped peer is dropped", _count_sender(received, "roster_test_player") == before)
	# A mapped peer speaks AS its character, never as the payload claims.
	# WHISPER resolves its own audience (targets = [target]), so the leg does
	# not need a living SAY audience; SAY/zone routing is covered by the
	# drop leg above and by the service's own receipts.
	nm.connected_peers[77] = {"player_id": "roster_test_player"}
	nm._handle_client_chat(77, {"channel": "whisper", "message": "ahoy there", "target_id": "roster_test_player", "sender_id": "somebody_else"})
	_check("chat from a mapped peer is delivered once", _count_sender(received, "roster_test_player") == before + 1)
	var first: Dictionary = _last_from(received, "roster_test_player")
	_check("chat sender is the peer's character", not first.is_empty())
	_check("chat body survives the route", str(first.get("message", "")) == "ahoy there")
	_check("the payload cannot name its own sender", _count_sender(received, "somebody_else") == 0)
	chat.message_received.disconnect(on_received)
	nm.connected_peers.erase(77)

	# --- F. UNROUTED TYPES WARN ONCE, NOT INTO THE VOID ---------------------
	nm._unrouted_warned.clear()
	nm._warn_unrouted("input")
	nm._warn_unrouted("input")
	nm._warn_unrouted("action")
	_check("unrouted book has both types", nm._unrouted_warned.size() == 2)
	_check("repeat warns do not double-log", nm._unrouted_warned.has("input") and nm._unrouted_warned.has("action"))
	nm._unrouted_warned.clear()

	# --- G. UNREGISTRATION CLEARS ONLINE -----------------------------------
	es.unregister_entity(body, "receipt_teardown")
	_check("unregistered player is offline", not pm.is_player_online("roster_test_player"))
	_check("unregistered player has no row", (pm.get_player_info("roster_test_player") as Dictionary).is_empty())
	_check("unregistered player leaves the online ids", not pm.get_online_player_ids().has("roster_test_player"))
	body.queue_free()

	_finish("ROSTER + DISPATCH RECEIPT")


func _finish(label: String) -> void:
	print("=== %s: %d checks, %d failed ===" % [label, _checks, _fails])
	if _fails == 0:
		print("ROSTER + DISPATCH RECEIPT PASSED")
		quit(0)
	else:
		print("ROSTER + DISPATCH RECEIPT FAILED")
		quit(1)
