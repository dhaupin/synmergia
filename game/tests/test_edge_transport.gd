## Edge transport receipt: shard mesh Phase 2 (labs/prd-shard-mesh.md).
##
## The shard mesh Phase 1 gave the coordinator a cross-shard bus; the
## edge (how a client reaches a shard behind an L7 proxy) is Phase 2.
## This receipt proves the transport seam on the SERVER boot path:
## EDGE_TRANSPORT selects enet (default, byte-identical) or websocket,
## and _make_server_peer builds the matching MultiplayerPeer.
##
## Legs:
##   1. No EDGE_TRANSPORT -> enet (dev/CI unchanged).
##   2. EDGE_TRANSPORT=websocket -> websocket.
##   3. ws / wss aliases -> websocket.
##   4. Empty EDGE_TRANSPORT -> enet.
##   5. Unknown EDGE_TRANSPORT -> enet (honest fallback, never a crash).
##   6. _make_server_peer(enet) builds an ENetMultiplayerPeer.
##   7. _make_server_peer(websocket) builds a WebSocketMultiplayerPeer
##      that actually BINDS (reaches CONNECTED) -- the Phase 2 capability
##      the note's Option B depends on.
##   8. get_connection_info() reports the selected transport.
##
## Run with:
##   godot --headless --path game/ --script res://tests/test_edge_transport.gd
extends SceneTree

var _passed: int = 0
var _failed: int = 0

const NM_NODE := "NetworkManager"


func _initialize() -> void:
	print("--- EDGE TRANSPORT ---")
	await process_frame
	var nm = root.get_node_or_null(NM_NODE)
	if nm == null:
		_fail("NetworkManager autoload present")
		_finish()
		return
	_test_default_is_enet(nm)
	_test_websocket_resolves(nm)
	_test_aliases(nm)
	_test_empty_is_enet(nm)
	_test_unknown_falls_back(nm)
	_test_make_enet_peer(nm)
	await _test_make_websocket_peer(nm)
	_test_connection_info(nm)
	_clear_env()
	_finish()


func _test_default_is_enet(nm) -> void:
	OS.unset_environment("EDGE_TRANSPORT")
	_assert(nm._resolve_edge_transport() == "enet", "no EDGE_TRANSPORT resolves to enet")


func _test_websocket_resolves(nm) -> void:
	OS.set_environment("EDGE_TRANSPORT", "websocket")
	_assert(nm._resolve_edge_transport() == "websocket", "EDGE_TRANSPORT=websocket resolves to websocket")


func _test_aliases(nm) -> void:
	OS.set_environment("EDGE_TRANSPORT", "ws")
	_assert(nm._resolve_edge_transport() == "websocket", "EDGE_TRANSPORT=ws is a websocket alias")
	OS.set_environment("EDGE_TRANSPORT", "wss")
	_assert(nm._resolve_edge_transport() == "websocket", "EDGE_TRANSPORT=wss is a websocket alias")
	OS.set_environment("EDGE_TRANSPORT", "WEBSOCKET")
	_assert(nm._resolve_edge_transport() == "websocket", "EDGE_TRANSPORT is case-insensitive")


func _test_empty_is_enet(nm) -> void:
	OS.set_environment("EDGE_TRANSPORT", "")
	_assert(nm._resolve_edge_transport() == "enet", "empty EDGE_TRANSPORT resolves to enet")


func _test_unknown_falls_back(nm) -> void:
	OS.set_environment("EDGE_TRANSPORT", "carrier-pigeon")
	_assert(nm._resolve_edge_transport() == "enet", "unknown EDGE_TRANSPORT falls back to enet")


func _test_make_enet_peer(nm) -> void:
	nm.edge_transport = "enet"
	var peer = nm._make_server_peer(19410)
	_assert(peer != null, "_make_server_peer(enet) returns a peer")
	_assert(peer is ENetMultiplayerPeer, "the enet peer is an ENetMultiplayerPeer")
	if peer != null:
		peer.close()


func _test_make_websocket_peer(nm) -> void:
	nm.edge_transport = "websocket"
	var peer = nm._make_server_peer(19411)
	_assert(peer != null, "_make_server_peer(websocket) returns a peer")
	_assert(peer is WebSocketMultiplayerPeer, "the websocket peer is a WebSocketMultiplayerPeer")
	if peer == null:
		return
	# The ws server must actually BIND: poll until it reports CONNECTED.
	var api := MultiplayerAPI.create_default_interface()
	api.multiplayer_peer = peer
	var connected := false
	for i in range(120):
		api.poll()
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			connected = true
			break
		OS.delay_msec(10)
	_assert(connected, "the websocket server peer binds (reaches CONNECTED)")
	peer.close()


func _test_connection_info(nm) -> void:
	nm.edge_transport = "websocket"
	var info: Dictionary = nm.get_connection_info()
	_assert(info.has("edge_transport"), "connection info reports edge_transport")
	_assert(info.get("edge_transport") == "websocket", "connection info reflects the selected transport")


func _clear_env() -> void:
	OS.unset_environment("EDGE_TRANSPORT")


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("PASS: %s" % label)
	else:
		_failed += 1
		print("FAIL: %s" % label)


func _fail(label: String) -> void:
	_failed += 1
	print("FAIL: %s" % label)


func _finish() -> void:
	print("--- RESULT: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
