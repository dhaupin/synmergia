## NetworkManager - Handles multiplayer networking
## Manages client/server connections using ENet
extends Node
const CacheWrapper = preload("res://adapters/cache/cache_wrapper.gd")
const StateTreeScript = preload("res://core/frame/kv/state_tree.gd")

signal connected_to_server
signal connection_failed
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal server_started
signal server_stopped
signal world_state_received(tick: int, diff: Array)
signal full_state_sync_requested  # Client requested full resync due to hash divergence
signal full_state_sync_received(tick: int, scope_size: int)  # Client received full resync

# Firewall instance
var _firewall: AppFirewall

var DEFAULT_PORT: int = 10555
var MAX_PLAYERS: int = 100
const SERVER_IP: String = "127.0.0.1"

## WASM-SAFE NETWORKING CONSTANTS
## Maximum packet size: 64KB (65536 bytes) to prevent heap spikes in browser WASM
const MAX_PACKET_SIZE: int = 65536
## Chunk header size overhead (type, chunk_id, total_chunks, sequence, flags)
const CHUNK_HEADER_SIZE: int = 32
## Maximum payload per chunk after header overhead
const MAX_CHUNK_PAYLOAD: int = MAX_PACKET_SIZE - CHUNK_HEADER_SIZE

## Chunked message types for reassembly
const CHUNK_TYPE_FULL_STATE = 0
const CHUNK_TYPE_DIFF = 1
const CHUNK_TYPE_CONTINUATION = 2
const CHUNK_TYPE_FINAL = 3

## Client-side reassembly buffer (pre-allocated to avoid unbounded growth)
const REASSEMBLY_BUFFER_SIZE: int = 1024 * 1024  # 1MB max per message

## Client-side outbound send buffer (pre-allocated ring buffer for WASM safety)
## Prevents unbounded queue growth when sending many messages (e.g., input updates)
const SEND_BUFFER_CAPACITY: int = 256  # Max queued messages
const SEND_BUFFER_MAX_BYTES: int = 1024 * 1024  # 1MB total buffer

enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	SERVER
}

var connection_state: ConnectionState = ConnectionState.DISCONNECTED
var is_server: bool = false
var is_client: bool = false
var peer_id: int = 0
var connected_peers: Dictionary = {}

var _cache: CacheWrapper = CacheWrapper.new()
const _kv_prefix := "peer:"
const _kv_index := "peer:index"

# Client-side state tree for applying server diffs
var _client_state_tree: StateTreeScript = null
var _client_root_hash: PackedByteArray = PackedByteArray()

## CLIENT-SIDE REASSEMBLY STATE (WASM-safe: fixed-size, pre-allocated)
## Inbound chunk reassembly buffer - pre-allocated to prevent unbounded array growth
var _reassembly_buffer: Dictionary = {}
## Expected total chunks for current reassembly
var _reassembly_expected_chunks: int = 0
## Received chunk count
var _reassembly_received_count: int = 0
## Reassembly message ID (to handle out-of-order/overlapping messages)
var _reassembly_message_id: int = 0
## Accumulated payload bytes for reassembly
var _reassembly_accumulated: PackedByteArray = PackedByteArray()

## CLIENT-SIDE OUTBOUND SEND BUFFER (WASM-safe: fixed-size ring buffer)
## Pre-allocated array to prevent unbounded growth when queueing sends
var _send_buffer: Array = []
var _send_buffer_head: int = 0
var _send_buffer_tail: int = 0
var _send_buffer_size: int = 0
var _send_buffer_bytes: int = 0

func _log(level: String, message: String) -> void:
	var gl = get_node_or_null("/root/GameLog")
	if gl:
		gl.call(level, message)

func _ready() -> void:
	_log("info", "NetworkManager initialized")
	DEFAULT_PORT = GameConfig.Network.DEFAULT_PORT
	MAX_PLAYERS = GameConfig.Network.MAX_PLAYERS
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Defer firewall initialization to avoid forward reference (AppFirewall is autoload #69, NetworkManager is #46)
	call_deferred("_init_firewall")

	_load_peer_mappings()

	# Initialize client-side state tree
	_client_state_tree = StateTreeScript.new()
	_client_root_hash = _client_state_tree.root_hash()

	# Auto-start server in headless/production mode
	var godot_port := int(OS.get_environment("GODOT_PORT")) if OS.has_environment("GODOT_PORT") else DEFAULT_PORT
	if OS.has_environment("START_MODE"):
		var mode := OS.get_environment("START_MODE")
		if mode in ["prod", "headless", "server"]:
			_auto_start_server(godot_port)


func _init_firewall() -> void:
	# Late binding: resolve AppFirewall at runtime via scene tree
	var fw = get_node_or_null("/root/AppFirewall")
	if fw:
		# AppFirewall._init() takes no args; configure via its public API.
		if fw.has_method("configure"):
			fw.configure(
				GameConfig.Security.FIREWALL_BLOCK_DURATION,
				GameConfig.Security.FIREWALL_MAX_ATTEMPTS,
				GameConfig.Security.FIREWALL_MAX_CONNECTIONS_PER_IP
			)
		_firewall = fw
		_log("info", "NetworkManager: AppFirewall initialized via deferred call")
	else:
		_log("warn", "NetworkManager: AppFirewall not available (autoload order)")


func _auto_start_server(port: int) -> void:
	# Small delay to let other autoloads initialize
	await get_tree().create_timer(0.5).timeout
	if start_server(port):
		_log("info", "Auto-started server on port %d (START_MODE=%s)" % [port, OS.get_environment("START_MODE")])
	else:
		_log("error", "Failed to auto-start server on port %d" % port)

func _process(_delta: float) -> void:
	match connection_state:
		ConnectionState.CONNECTED:
			_check_connection_health()
			_flush_send_buffer()
		ConnectionState.SERVER:
			# TickService drives the authoritative tick loop
			# NetworkManager only handles transport
			pass


## ============================================================================
## WASM-SAFE CHUNKING & REASSEMBLY HELPERS
## ============================================================================

## Serializes a diff payload to bytes for size checking and chunking.
## Returns PackedByteArray of the serialized payload.
func _serialize_payload(payload: Dictionary) -> PackedByteArray:
	var bytes: PackedByteArray = JSON.stringify(payload).to_utf8_buffer()
	return bytes

## Estimates the network packet size for a payload (includes RPC overhead).
func _estimate_packet_size(payload: Dictionary) -> int:
	var serialized := _serialize_payload(payload)
	return serialized.size() + 64  # RPC framing overhead estimate

## Splits a large payload into chunks that fit within MAX_PACKET_SIZE.
## Returns an array of chunk payloads (each a Dictionary with chunk metadata).
func _chunk_payload(payload: Dictionary, chunk_type: int) -> Array:
	var serialized: PackedByteArray = _serialize_payload(payload)
	var total_size: int = serialized.size()
	
	if total_size <= MAX_CHUNK_PAYLOAD:
		# Fits in single packet - no chunking needed
		var single_chunk = {
			"type": chunk_type,
			"message_id": 0,
			"chunk_id": 0,
			"total_chunks": 1,
			"is_final": true,
			"payload": payload
		}
		return [single_chunk]
	
	# Need to chunk
	var chunks: Array = []
	var message_id: int = _generate_message_id()
	var offset: int = 0
	var chunk_id: int = 0
	var total_chunks: int = ceil(total_size / MAX_CHUNK_PAYLOAD)
	
	while offset < total_size:
		var chunk_size: int = min(MAX_CHUNK_PAYLOAD, total_size - offset)
		var chunk_data: PackedByteArray = serialized.slice(offset, offset + chunk_size)
		
		var is_final: bool = (chunk_id == total_chunks - 1)
		var chunk_type_actual: int = CHUNK_TYPE_FULL_STATE if chunk_type == CHUNK_TYPE_FULL_STATE else CHUNK_TYPE_DIFF
		if chunk_id > 0:
			chunk_type_actual = CHUNK_TYPE_CONTINUATION
		if is_final:
			chunk_type_actual = CHUNK_TYPE_FINAL
		
		var chunk = {
			"type": chunk_type_actual,
			"message_id": message_id,
			"chunk_id": chunk_id,
			"total_chunks": total_chunks,
			"is_final": is_final,
			"payload_bytes": chunk_data
		}
		chunks.append(chunk)
		
		offset += chunk_size
		chunk_id += 1
	
	return chunks

## Generates a unique message ID for chunking tracking.
var _message_id_counter: int = 0
func _generate_message_id() -> int:
	_message_id_counter += 1
	if _message_id_counter > 2147483647:
		_message_id_counter = 1
	return _message_id_counter

## Reassembles chunks into the original payload.
## Returns the reassembled payload Dictionary or null if incomplete.
func _reassemble_chunks(chunk: Dictionary) -> Dictionary:
	var msg_id: int = chunk.get("message_id", 0)
	var chunk_id: int = chunk.get("chunk_id", 0)
	var total_chunks: int = chunk.get("total_chunks", 1)
	var is_final: bool = chunk.get("is_final", true)
	var payload_bytes: PackedByteArray = chunk.get("payload_bytes", PackedByteArray())
	
	# Handle single-chunk messages (no chunking)
	if total_chunks == 1:
		if payload_bytes.size() > 0:
			return _deserialize_payload(payload_bytes)
		return chunk.get("payload", {})
	
	# Multi-chunk reassembly
	if msg_id != _reassembly_message_id:
		# New message - reset reassembly state
		_reassembly_message_id = msg_id
		_reassembly_expected_chunks = total_chunks
		_reassembly_received_count = 0
		_reassembly_accumulated = PackedByteArray()
		_reassembly_buffer.clear()
	
	# Bounds check: prevent buffer overflow
	if _reassembly_accumulated.size() + payload_bytes.size() > REASSEMBLY_BUFFER_SIZE:
		_log("warn", "Reassembly buffer overflow, discarding message %d" % msg_id)
		_reassembly_buffer.clear()
		_reassembly_message_id = 0
		return {}
	
	# Store chunk
	_reassembly_buffer[chunk_id] = payload_bytes
	_reassembly_received_count += 1
	
	# Check if complete
	if _reassembly_received_count >= _reassembly_expected_chunks or is_final:
		# Reassemble in order
		var complete: PackedByteArray = PackedByteArray()
		for i in range(_reassembly_expected_chunks):
			if _reassembly_buffer.has(i):
				complete.append_array(_reassembly_buffer[i])
			else:
				_log("warn", "Missing chunk %d for message %d" % [i, msg_id])
				_reassembly_buffer.clear()
				_reassembly_message_id = 0
				return {}
		
		# Reset for next message
		_reassembly_buffer.clear()
		_reassembly_message_id = 0
		_reassembly_expected_chunks = 0
		_reassembly_received_count = 0
		_reassembly_accumulated = PackedByteArray()
		
		return _deserialize_payload(complete)
	
	return {}  # Still waiting for more chunks

## Deserializes payload bytes back to Dictionary.
func _deserialize_payload(bytes: PackedByteArray) -> Dictionary:
	var json_str: String = bytes.get_string_from_utf8()
	return JSON.parse_string(json_str)

## ============================================================================
## CLIENT-SIDE OUTBOUND SEND BUFFER HELPERS (WASM-safe)
## ============================================================================

## Initializes the send buffer (call on client connect).
func _init_send_buffer() -> void:
	_send_buffer = []
	_send_buffer.resize(SEND_BUFFER_CAPACITY)
	_send_buffer_head = 0
	_send_buffer_tail = 0
	_send_buffer_size = 0
	_send_buffer_bytes = 0

## Clears the send buffer (call on client disconnect).
func _clear_send_buffer() -> void:
	_send_buffer.clear()
	_send_buffer_head = 0
	_send_buffer_tail = 0
	_send_buffer_size = 0
	_send_buffer_bytes = 0

## Queues a message for sending (client-side).
## Returns true if queued, false if buffer full (backpressure).
func _queue_send(message: Dictionary) -> bool:
	if _send_buffer_size >= SEND_BUFFER_CAPACITY:
		_log("warn", "Send buffer full, dropping message (backpressure)")
		return false
	
	var msg_bytes: int = _estimate_packet_size(message)
	if _send_buffer_bytes + msg_bytes > SEND_BUFFER_MAX_BYTES:
		_log("warn", "Send buffer byte limit reached, dropping message")
		return false
	
	_send_buffer[_send_buffer_tail] = message
	_send_buffer_tail = (_send_buffer_tail + 1) % SEND_BUFFER_CAPACITY
	_send_buffer_size += 1
	_send_buffer_bytes += msg_bytes
	return true

## Flushes the send buffer by sending all queued messages.
## Call this periodically (e.g., in _process when connected).
func _flush_send_buffer() -> void:
	if not is_client or _send_buffer_size == 0:
		return
	
	while _send_buffer_size > 0:
		var message: Dictionary = _send_buffer[_send_buffer_head]
		_send_buffer[_send_buffer_head] = null
		_send_buffer_head = (_send_buffer_head + 1) % SEND_BUFFER_CAPACITY
		_send_buffer_size -= 1
		_send_buffer_bytes -= _estimate_packet_size(message)
		
		# Send via RPC to server (server is peer 1 in Godot multiplayer)
		if multiplayer.is_network_connected() and multiplayer.multiplayer_peer:
			# Use rpc for client->server messages
			rpc("_receive_client_message", message)

## Client-side RPC to send messages to server (input, actions, etc.)
## This is the client-facing API - queues message for batched sending.
func send_to_server(message: Dictionary) -> bool:
	if not is_client:
		return false
	return _queue_send(message)

## Server-side RPC to receive client messages.
@rpc("any_peer", "call_local")
func _receive_client_message(message: Dictionary) -> void:
	if not is_server:
		return
	# Handle client message (input, actions, etc.)
	# Forward to appropriate service based on message type
	if message.has("type"):
		var msg_type: String = message["type"]
		match msg_type:
			"input":
				if InputManager:
					InputManager.handle_client_input(message.get("peer_id", 1), message.get("data", {}))
			"action":
				if InteractionLayer:
					InteractionLayer.handle_client_action(message.get("peer_id", 1), message.get("data", {}))
			"chat":
				if ChatService:
					ChatService.handle_client_chat(message.get("peer_id", 1), message.get("data", {}))
			"character_select":
				_handle_character_select(message.get("peer_id", 1), message.get("data", {}))

## Handles character selection from client.
## Kicks any existing session for the character (Edge Case B),
## builds seed receipt, and sends it to the client.
func _handle_character_select(peer_id: int, data: Dictionary) -> void:
	var character_id: String = data.get("character_id", "")
	if character_id == "":
		_log("warn", "Character select: missing character_id from peer %d" % peer_id)
		return
	
	_log("info", "Character select: peer %d selected character %s" % [peer_id, character_id])
	
	if LoginService:
		var receipt: Resource = LoginService.on_character_selected(character_id, peer_id)
		if receipt:
			_send_seed_receipt(peer_id, character_id, receipt)
		else:
			_log("error", "Character select: failed to build seed receipt for %s" % character_id)
			rpc_id(peer_id, "_receive_seed_receipt_failed", "Failed to build seed receipt")

## SERVER: Send chunked world state to a specific peer.
func _send_chunked_to_peer(peer_id: int, diff_payload: Dictionary, chunk_type: int) -> void:
	if not is_server:
		return
	if not connected_peers.has(peer_id):
		return
	
	var chunks: Array = _chunk_payload(diff_payload, chunk_type)
	for chunk in chunks:
		rpc_id(peer_id, "_receive_chunked_world_state", chunk)

## CLIENT: RPC to receive a chunked world state piece.
@rpc("reliable", "call_local")
func _receive_chunked_world_state(chunk: Dictionary) -> void:
	if not is_client:
		return
	
	var reassembled: Dictionary = _reassemble_chunks(chunk)
	if reassembled == null:
		return  # Still waiting for more chunks
	
	# Process the fully reassembled payload
	_process_reassembled_world_state(reassembled)


## SERVER FUNCTIONS

func start_server(port: int = DEFAULT_PORT) -> bool:
	if OS.has_feature("web"):
		_log("warn", "Cannot start server in web browser")
		return false
	if connection_state != ConnectionState.DISCONNECTED:
		_log("warn", "Cannot start server: already connected")
		return false

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS)

	if error != OK:
		_log("error", "Failed to start server on port %d: %s" % [port, error])
		return false

	multiplayer.multiplayer_peer = peer
	connection_state = ConnectionState.SERVER
	is_server = true

	peer.peer_connected.connect(_on_server_peer_connected)
	peer.peer_disconnected.connect(_on_server_peer_disconnected)

	# Connect seed receipt signal for server
	_connect_seed_receipt_signal()

	# TickService drives the authoritative tick loop via its own timer
	# NetworkManager only handles transport

	_log("info", "Server started on port %d" % port)
	server_started.emit()
	return true

func _on_server_peer_connected(id: int) -> void:
	# Get IP from peer (if available)
	var ip := "unknown"
	if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_peer(id):
		# ENet doesn't expose IP directly in Godot 4, use peer ID as identifier
		ip = "peer_%d" % id

	# Check firewall
	var fw_check := _firewall.can_connect(ip)
	if not fw_check.allowed:
		_log("warn", "Firewall blocked connection from %s: %s" % [ip, fw_check.reason])
		multiplayer.multiplayer_peer.disconnect_peer(id, true)
		return

	_log("info", "Client connected: %d" % id)
	connected_peers[id] = {"joined": Time.get_ticks_msec(), "ip": ip}
	_firewall.register_connection("peer_%d" % id, ip)
	_persist_peer_mapping(id, "")
	peer_connected.emit(id)

	# Register client with TickService for diff emission
	if TickService:
		TickService.register_client(id)

func _on_server_peer_disconnected(id: int) -> void:
	_log("info", "Client disconnected: %d" % id)
	# Cleanup firewall tracking
	var ip = connected_peers.get(id, {}).get("ip", "unknown")
	_firewall.unregister_connection("peer_%d" % id)
	_persist_peer_mapping(id, "")
	connected_peers.erase(id)
	peer_disconnected.emit(id)

	# Unregister client from TickService
	if TickService:
		TickService.unregister_client(id)

## SERVER TRANSPORT METHODS (called by TickService)

## Send a world state diff to a specific peer.
## Called by TickService._phase4_diff_emit() for each client in their AOI.
## Uses chunking to enforce MAX_PACKET_SIZE (64KB) for WASM safety.
func send_to_peer(peer_id: int, diff_payload: Dictionary) -> void:
	if not is_server:
		return
	if not connected_peers.has(peer_id):
		return
	# diff_payload contains: {"tick": int, "root_hash": PackedByteArray, "diff": Array, "lod_level": int}
	# Determine chunk type: full state (empty diff) or differential
	var chunk_type: int = CHUNK_TYPE_DIFF
	if diff_payload.get("diff", []).is_empty():
		chunk_type = CHUNK_TYPE_FULL_STATE
	_send_chunked_to_peer(peer_id, diff_payload, chunk_type)

## Broadcast a world state diff to all connected peers.
## Used for full-state sync on join or critical updates.
## Uses chunking to enforce MAX_PACKET_SIZE (64KB) for WASM safety.
func _broadcast_world_state(diff_payload: Dictionary) -> void:
	if not is_server:
		return
	var chunk_type: int = CHUNK_TYPE_DIFF
	if diff_payload.get("diff", []).is_empty():
		chunk_type = CHUNK_TYPE_FULL_STATE
	for peer_id in connected_peers:
		_send_chunked_to_peer(peer_id, diff_payload, chunk_type)

## CLIENT FUNCTIONS

func connect_to_server(ip: String = SERVER_IP, port: int = DEFAULT_PORT) -> bool:
	if connection_state != ConnectionState.DISCONNECTED:
		_log("warn", "Cannot connect: already connected")
		return false

	connection_state = ConnectionState.CONNECTING

	if OS.has_feature("web"):
		return _connect_websocket(ip, port)

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, port)

	if error != OK:
		_log("error", "Failed to create client: %s" % error)
		connection_state = ConnectionState.DISCONNECTED
		return false

	multiplayer.multiplayer_peer = peer
	is_client = true

	peer.connection_failed.connect(_on_client_connection_failed)
	peer.server_disconnected.connect(_on_server_disconnected)

	_log("info", "Connecting to server at %s:%d..." % [ip, port])
	return true

func _on_client_connected() -> void:
	connection_state = ConnectionState.CONNECTED
	peer_id = multiplayer.get_unique_id()
	_init_send_buffer()
	_log("info", "Connected to server! Peer ID: %d" % peer_id)
	connected_to_server.emit()

func _on_client_connection_failed() -> void:
	connection_state = ConnectionState.DISCONNECTED
	is_client = false
	_clear_send_buffer()
	_log("error", "Connection to server failed")
	connection_failed.emit()

func _on_server_disconnected() -> void:
	_log("warn", "Disconnected from server")
	disconnect_from_server()
	connection_failed.emit()

func disconnect_from_server() -> void:
	if is_client and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	connection_state = ConnectionState.DISCONNECTED
	is_client = false
	peer_id = 0
	_clear_send_buffer()
	_log("info", "Disconnected from server")

## WEBSOCKET CLIENT (browser only)

func _connect_websocket(ip: String, port: int) -> bool:
	var ws_url := "ws://%s:%d" % [ip, port]
	if OS.has_feature("web"):
		ws_url = JavaScriptBridge.eval("window.SynmergiaConfig.serverUrl", true) or ws_url

	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_client(ws_url)
	if error != OK:
		_log("error", "Failed to create WebSocket client: %s" % error)
		connection_state = ConnectionState.DISCONNECTED
		return false

	multiplayer.multiplayer_peer = peer
	is_client = true

	# WebSocketMultiplayerPeer uses Godot's high-level multiplayer API
	# Signals are handled by the multiplayer node itself
	multiplayer.connected_to_server.connect(_on_client_connected)
	multiplayer.connection_failed.connect(_on_client_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	_log("info", "Connecting via WebSocket to %s..." % ws_url)
	return true

## COMMON FUNCTIONS

func _check_connection_health() -> void:
	if not multiplayer.is_network_server():
		return

	# Check for timed out peers
	for peer_id in connected_peers:
		var peer_data = connected_peers[peer_id]
		var timeout_ms := 30000  # 30 seconds
		if Time.get_ticks_msec() - peer_data.get("last_heartbeat", 0) > timeout_ms:
			_log("warn", "Kicking inactive peer: %d" % peer_id)
			multiplayer.multiplayer_peer.disconnect_peer(peer_id, true)

func stop_server() -> void:
	if not is_server:
		return

	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

	connection_state = ConnectionState.DISCONNECTED
	is_server = false
	connected_peers.clear()

	_log("info", "Server stopped")
	server_stopped.emit()

## Disconnect all connected peers with a maintenance/reason message
## Called by ServerManager.invalidate_all_sessions() on manifest restore
func disconnect_all_peers(reason: String = "Server maintenance: world state restored") -> void:
	if not is_server:
		_log("warn", "disconnect_all_peers called but not running as server")
		return

	_log("info", "NetworkManager: Disconnecting all peers: %s" % reason)

	# Send maintenance disconnect RPC to all peers before closing
	for peer_id in connected_peers:
		if connected_peers.has(peer_id):
			rpc_id(peer_id, "_receive_maintenance_disconnect", reason)

	# Brief delay to let RPCs deliver, then force close
	var t = Timer.new()
	t.timeout.connect(_force_close_all_peers)
	t.one_shot = true
	t.wait_time = 0.5
	add_child(t)
	t.start()

@rpc("reliable", "call_local")
func _receive_maintenance_disconnect(reason: String) -> void:
	# Client receives this and should handle graceful disconnect
	_log("info", "Received maintenance disconnect: %s" % reason)
	if is_client:
		disconnect_from_server()

func _force_close_all_peers() -> void:
	if not is_server:
		return
	for peer_id in connected_peers:
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.disconnect_peer(peer_id, true)
	connected_peers.clear()
	_log("info", "NetworkManager: All peers force-disconnected")

func is_multiplayer_active() -> bool:
	return connection_state == ConnectionState.CONNECTED or connection_state == ConnectionState.SERVER

func get_connection_info() -> Dictionary:
	return {
		"state": ConnectionState.keys()[connection_state],
		"is_server": is_server,
		"is_client": is_client,
		"peer_id": peer_id,
		"connected_peers": connected_peers.size()
	}

## ============================================================================
## FIREWALL HELPERS
## ============================================================================

## Get the firewall instance for external use
func get_firewall() -> AppFirewall:
	return _firewall

## Block a player/IP (admin function)
func block_player(player_id: String, reason: String, duration_seconds: int) -> void:
	if _firewall:
		var ip = _player_ip_from_id(player_id)
		_firewall.block_ip(ip, reason, duration_seconds)
		_log("info", "Blocked %s for %d seconds: %s" % [player_id, duration_seconds, reason])

## Issue a permanent ban (admin function)
func ban_player(player_id: String, reason: String, banned_by: String = "system") -> void:
	if _firewall:
		var ip = _player_ip_from_id(player_id)
		_firewall.issue_ban(player_id, reason, banned_by, -1)
		_log("info", "Permanently banned %s: %s" % [player_id, reason])

## Flag an IP for suspicious activity
func flag_ip(ip: String, flag_type: String, count: int = 1) -> void:
	if _firewall:
		_firewall.flag_ip(ip, flag_type, count)

## Track a failed authentication attempt
func track_failed_attempt(ip: String) -> void:
	if _firewall:
		_firewall.track_failed_attempt(ip)

## Kick an existing session for a character (prevents double-join/hijacking)
## Returns true if a peer was found and disconnected
func kick_player_by_character_id(character_id: String, reason: String = "New session started") -> bool:
	if not is_server:
		_log("warn", "kick_player_by_character_id called but not running as server")
		return false
	
	var peer_id := _find_peer_for_character(character_id)
	if peer_id > 0:
		_log("info", "Kicking existing session for character %s (peer %d): %s" % [character_id, peer_id, reason])
		if multiplayer.multiplayer_peer:
			rpc_id(peer_id, "_receive_maintenance_disconnect", reason)
			# Brief delay to let RPC deliver, then force close
			var t = Timer.new()
			t.timeout.connect(func(): multiplayer.multiplayer_peer.disconnect_peer(peer_id, true))
			t.one_shot = true
			t.wait_time = 0.2
			add_child(t)
			t.start()
		return true
	return false

func _player_ip_from_id(player_id: String) -> String:
	# Look up IP from connected peers
	for peer_id in connected_peers:
		if "peer_%d" % peer_id == player_id:
			return connected_peers[peer_id].get("ip", "unknown")
	return "unknown"

func _load_peer_mappings() -> void:
	var peer_ids: Array = _cache.smembers(_kv_index)
	for pid in peer_ids:
		var key := _kv_prefix + str(pid)
		var player_id: String = _cache.get_kv(key)
		if player_id != null and player_id != "":
			connected_peers[pid] = {"player_id": player_id}

func _persist_peer_mapping(peer_id: int, player_id: String) -> void:
	var key := _kv_prefix + str(peer_id)
	if player_id == null or player_id == "":
		_cache.delete(key)
		_cache.srem(_kv_index, str(peer_id))
	else:
		_cache.set_kv(key, player_id)
		_cache.sadd(_kv_index, str(peer_id))

## CLIENT-SIDE STATE SYNC

## RPC called by server to send world state diff to client (legacy, non-chunked).
## Kept for backward compatibility with non-chunked peers.
## Applies the diff to the client's local state tree.
@rpc("reliable", "call_local")
func _receive_world_state(payload: Dictionary) -> void:
	if not is_client:
		return
	
	# Check if this is a chunked message (has chunk metadata)
	if payload.has("type") and payload.has("message_id"):
		# This is a chunk - delegate to chunked receiver
		_receive_chunked_world_state(payload)
		return
	
	_process_reassembled_world_state(payload)

## Processes a fully reassembled world state payload (chunked or legacy).
func _process_reassembled_world_state(payload: Dictionary) -> void:
	var tick: int = payload.get("tick", 0)
	var root_hash: PackedByteArray = payload.get("root_hash", PackedByteArray())
	var diff: Array = payload.get("diff", [])
	var lod_level: int = payload.get("lod_level", 0)
	var is_full_sync: bool = payload.get("is_full_sync", false)
	
	if diff.is_empty():
		# Full state sync - reset client tree to server root
		_client_root_hash = root_hash
		_client_state_tree = StateTreeScript.new()
		_log("debug", "Client full state sync at tick %d" % tick)
	elif is_full_sync:
		# Server sent full scope snapshot (resync after hash divergence)
		# Rebuild local state tree from the full snapshot
		_client_state_tree.apply_full_snapshot(diff, root_hash)
		_client_root_hash = root_hash
		_log("info", "Client received full scope resync at tick %d (%d entries)" % [tick, diff.size()])
		full_state_sync_received.emit(tick, diff.size())
	else:
		# Apply differential update
		if _client_root_hash.size() > 0 and root_hash.size() > 0:
			var new_root = _client_state_tree.apply_diff(_client_root_hash, diff)
			if new_root.size() > 0:
				_client_root_hash = new_root
				_log("debug", "Client applied diff at tick %d, new root: %s" % [tick, new_root.hex_encode()])
			else:
				# Hash divergence detected - client root doesn't match server's expected old_root
				_log("error", "Client hash divergence at tick %d: local root %s != server expected %s" % [
					tick, _client_root_hash.hex_encode(), root_hash.hex_encode()])
				_request_full_state_sync()
		else:
			_log("warn", "Client missing root hash for diff at tick %d" % tick)
	
	world_state_received.emit(tick, diff)


## Client requests full state sync from server due to hash divergence.
func _request_full_state_sync() -> void:
	if not is_client:
		return
	
	_log("info", "Requesting full state sync from server due to hash divergence")
	full_state_sync_requested.emit()
	
	# Send request to server via RPC
	if multiplayer.is_network_connected() and multiplayer.multiplayer_peer:
		rpc_id(1, "_receive_full_sync_request", peer_id)


## Server RPC: receives client's full sync request.
@rpc("any_peer", "call_local")
func _receive_full_sync_request(requesting_peer_id: int) -> void:
	if not is_server:
		return
	if not connected_peers.has(requesting_peer_id):
		return
	
	_log("info", "Server received full sync request from peer %d" % requesting_peer_id)
	
	# Delegate to TickService to send full scope snapshot
	if TickService:
		TickService.send_full_scope_sync(requesting_peer_id)

## Get the client's local state tree (for reading predicted state)
func get_client_state_tree() -> StateTreeScript:
	return _client_state_tree

## Get the client's current root hash
func get_client_root_hash() -> PackedByteArray:
	return _client_root_hash

## Force full state resync (call after reconnection or manually)
func request_full_state_sync() -> void:
	if is_client:
		_request_full_state_sync()
	elif is_server:
		# Server can push full state to all clients
		if _client_state_tree:
			var full_root = _client_state_tree.root_hash()
			var payload = {
				"tick": 0,
				"root_hash": full_root,
				"diff": [],
				"lod_level": 0
			}
			_broadcast_world_state(payload)


## ============================================================================
## SEED RECEIPT NETWORK HANDLING
## ============================================================================

## Signal emitted when client receives and verifies a SeedReceipt
signal seed_receipt_received(character_id: String, receipt: Resource)

## Signal emitted when client fails to verify a SeedReceipt
signal seed_receipt_failed(reason: String)

## Server: sends the SeedReceipt to a specific peer after character select
func _send_seed_receipt(peer_id: int, character_id: String, receipt: Resource) -> void:
	if not is_server:
		return
	if not connected_peers.has(peer_id):
		return
	var bytes: PackedByteArray = receipt.to_bytes()
	rpc_id(peer_id, "_receive_seed_receipt", character_id, bytes)

## Client: RPC to receive the SeedReceipt from server
@rpc("reliable", "call_local")
func _receive_seed_receipt(character_id: String, receipt_bytes: PackedByteArray) -> void:
	if not is_client:
		return
	
	var SeedReceiptScript = preload("res://core/schemas/seed_receipt.gd")
	var receipt: Resource = SeedReceiptScript.from_bytes(receipt_bytes)
	
	# Get the server HMAC key (embedded in client at build time)
	var server_key := _get_client_server_key()
	if server_key.is_empty():
		_log("error", "SeedReceipt: Client server key not configured")
		seed_receipt_failed.emit("Client server key not configured")
		return
	
	# Verify the receipt
	if not receipt.verify(server_key):
		_log("error", "SeedReceipt: Verification failed for %s" % character_id)
		seed_receipt_failed.emit("Signature verification failed")
		return
	
	# Store the seeds for later state verification
	_store_client_seeds(character_id, receipt)
	
	_log("info", "SeedReceipt: Verified and stored for %s" % character_id)
	seed_receipt_received.emit(character_id, receipt)

## Client: RPC to receive seed receipt failure from server
@rpc("reliable", "call_local")
func _receive_seed_receipt_failed(reason: String) -> void:
	if not is_client:
		return
	_log("error", "SeedReceipt failed: %s" % reason)
	seed_receipt_failed.emit(reason)

## Gets the server HMAC key embedded in the client.
## In production, this would be a binary key shipped with the client.
func _get_client_server_key() -> PackedByteArray:
	# Try to load from GameConfig
	if GameConfig and GameConfig.has_method("get_server_hmac_key"):
		var key_str: String = GameConfig.get_server_hmac_key()
		if key_str != "":
			return key_str.hex_decode()
	
	# Fallback: derive from known constant (dev only, must match server)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("synmergia_dev_hmac_key".to_utf8_buffer())
	return ctx.finish()

## Stores the verified seeds in client-side config for later use.
func _store_client_seeds(character_id: String, receipt: Resource) -> void:
	var config := ConfigFile.new()
	var err := config.load("user://client_seeds.cfg")
	if err != OK:
		config = ConfigFile.new()
	
	var section := "seeds_%s" % character_id
	config.set_value(section, "world_seed", receipt.world_seed.hex_encode())
	config.set_value(section, "shard_seed", receipt.shard_seed.hex_encode())
	config.set_value(section, "instance_seed", receipt.instance_seed.hex_encode())
	config.set_value(section, "player_seed", receipt.player_seed.hex_encode())
	config.set_value(section, "manifest_hash", receipt.manifest_hash.hex_encode())
	config.set_value(section, "issued_at", receipt.issued_at)
	config.save("user://client_seeds.cfg")

## Server: connects to LoginService seed_receipt_ready signal
func _connect_seed_receipt_signal() -> void:
	if not is_server:
		return
	if LoginService:
		LoginService.seed_receipt_ready.connect(_on_seed_receipt_ready)

func _on_seed_receipt_ready(character_id: String, receipt: Resource) -> void:
	# Find the peer for this character
	var peer_id := _find_peer_for_character(character_id)
	if peer_id > 0:
		_send_seed_receipt(peer_id, character_id, receipt)
	else:
		_log("warn", "SeedReceipt: No peer found for character %s" % character_id)

## Finds the peer ID associated with a character
func _find_peer_for_character(character_id: String) -> int:
	for peer_id in connected_peers:
		var peer_data: Dictionary = connected_peers[peer_id]
		if peer_data.has("player_id") and peer_data["player_id"] == character_id:
			return peer_id
	return -1

## Call this when a player's character is fully loaded to associate peer with character
func associate_peer_with_character(peer_id: int, character_id: String) -> void:
	if connected_peers.has(peer_id):
		connected_peers[peer_id]["player_id"] = character_id
		_persist_peer_mapping(peer_id, character_id)

## Loads stored client seeds for a character (for state verification).
## Returns a Dictionary with seed data or empty dict if not found.
func get_client_seeds(character_id: String) -> Dictionary:
	var config := ConfigFile.new()
	var err := config.load("user://client_seeds.cfg")
	if err != OK:
		return {}
	
	var section := "seeds_%s" % character_id
	if not config.has_section(section):
		return {}
	
	return {
		"world_seed": config.get_value(section, "world_seed", "").hex_decode(),
		"shard_seed": config.get_value(section, "shard_seed", "").hex_decode(),
		"instance_seed": config.get_value(section, "instance_seed", "").hex_decode(),
		"player_seed": config.get_value(section, "player_seed", "").hex_decode(),
		"manifest_hash": config.get_value(section, "manifest_hash", "").hex_decode(),
		"issued_at": config.get_value(section, "issued_at", 0)
	}

## Verifies a state tree root hash against the stored world seed.
## Returns true if the hash matches the expected seed.
func verify_state_hash(root_hash: PackedByteArray, character_id: String) -> bool:
	var seeds := get_client_seeds(character_id)
	if seeds.is_empty():
		return false
	
	var expected_seed: PackedByteArray = seeds.get("world_seed", PackedByteArray())
	if expected_seed.is_empty():
		return false
	
	# The root hash should match the world seed (or be derived from it)
	# For now, direct comparison; can be extended with derivation logic
	return root_hash == expected_seed
