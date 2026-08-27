## NetworkManager - Handles multiplayer networking
## Manages client/server connections using ENet
extends Node

signal connected_to_server
signal connection_failed
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal server_started
signal server_stopped

# Firewall instance
var _firewall: AppFirewall

# Network settings (using GameConfig for centralized configuration)
const DEFAULT_PORT := GameConfig.Network.DEFAULT_PORT
const MAX_PLAYERS := GameConfig.Network.MAX_PLAYERS
const SERVER_IP := "127.0.0.1"

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

# Server data
var server_ticks: int = 0
var tick_rate: int = 20  # 20 Hz
var tick_timer: Timer

func _ready() -> void:
	Logger.info("NetworkManager initialized")
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Initialize firewall with GameConfig values
	_firewall = AppFirewall.new(
		GameConfig.Security.FIREWALL_BLOCK_DURATION,
		GameConfig.Security.FIREWALL_MAX_ATTEMPTS,
		GameConfig.Security.FIREWALL_MAX_CONNECTIONS_PER_IP
	)

func _process(_delta: float) -> void:
	match connection_state:
		ConnectionState.CONNECTED:
			_check_connection_health()
		ConnectionState.SERVER:
			_process_server_ticks()

## SERVER FUNCTIONS

func start_server(port: int = DEFAULT_PORT) -> bool:
	if connection_state != ConnectionState.DISCONNECTED:
		Logger.warn("Cannot start server: already connected")
		return false
	
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS)
	
	if error != OK:
		Logger.error("Failed to start server on port %d: %s" % [port, error])
		return false
	
	multiplayer.multiplayer_peer = peer
	connection_state = ConnectionState.SERVER
	is_server = true
	
	peer.peer_connected.connect(_on_server_peer_connected)
	peer.peer_disconnected.connect(_on_server_peer_disconnected)
	peer.connection_succeeded.connect(_on_server_peer_connected)
	
	_start_server_loop()
	
	Logger.info("Server started on port %d" % port)
	server_started.emit()
	return true

func _start_server_loop() -> void:
	tick_timer = Timer.new()
	tick_timer.wait_time = 1.0 / tick_rate
	tick_timer.timeout.connect(_on_server_tick)
	add_child(tick_timer)
	tick_timer.start()

func _on_server_tick() -> void:
	server_ticks += 1
	_process_world_update()
	_broadcast_world_state()

func _process_world_update() -> void:
	# Update all entities, physics, AI
	# This is where server-side game logic happens
	pass

func _broadcast_world_state() -> void:
	# Send world state to all clients
	var state := _get_world_state()
	for peer_id in connected_peers:
		rpc_id(peer_id, "_receive_world_state", state)

func _get_world_state() -> Dictionary:
	return {
		"tick": server_ticks,
		"timestamp": Time.get_ticks_msec()
	}

@rpc("reliable")
func _receive_world_state(state: Dictionary) -> void:
	# Client receives world state
	pass

func _on_server_peer_connected(id: int) -> void:
	# Get IP from peer (if available)
	var ip := "unknown"
	if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_peer(id):
		# ENet doesn't expose IP directly in Godot 4, use peer ID as identifier
		ip = "peer_%d" % id

	# Check firewall
	var fw_check := _firewall.can_connect(ip)
	if not fw_check.allowed:
		Logger.warn("Firewall blocked connection from %s: %s" % [ip, fw_check.reason])
		multiplayer.multiplayer_peer.disconnect_peer(id, true)
		return

	Logger.info("Client connected: %d" % id)
	connected_peers[id] = {"joined": Time.get_ticks_msec(), "ip": ip}
	_firewall.register_connection("peer_%d" % id, ip)
	peer_connected.emit(id)

func _on_server_peer_disconnected(id: int) -> void:
	Logger.info("Client disconnected: %d" % id)
	# Cleanup firewall tracking
	var ip = connected_peers.get(id, {}).get("ip", "unknown")
	_firewall.unregister_connection("peer_%d" % id)
	connected_peers.erase(id)
	peer_disconnected.emit(id)

## CLIENT FUNCTIONS

func connect_to_server(ip: String = SERVER_IP, port: int = DEFAULT_PORT) -> bool:
	if connection_state != ConnectionState.DISCONNECTED:
		Logger.warn("Cannot connect: already connected")
		return false
	
	connection_state = ConnectionState.CONNECTING
	
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, port)
	
	if error != OK:
		Logger.error("Failed to create client: %s" % error)
		connection_state = ConnectionState.DISCONNECTED
		return false
	
	multiplayer.multiplayer_peer = peer
	is_client = true
	
	peer.connection_succeeded.connect(_on_client_connected)
	peer.connection_failed.connect(_on_client_connection_failed)
	peer.server_disconnected.connect(_on_server_disconnected)
	
	Logger.info("Connecting to server at %s:%d..." % [ip, port])
	return true

func _on_client_connected() -> void:
	connection_state = ConnectionState.CONNECTED
	peer_id = multiplayer.get_unique_id()
	Logger.info("Connected to server! Peer ID: %d" % peer_id)
	connected_to_server.emit()

func _on_client_connection_failed() -> void:
	connection_state = ConnectionState.DISCONNECTED
	is_client = false
	Logger.error("Connection to server failed")
	connection_failed.emit()

func _on_server_disconnected() -> void:
	Logger.warn("Disconnected from server")
	disconnect_from_server()
	connection_failed.emit()

func disconnect_from_server() -> void:
	if is_client and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	connection_state = ConnectionState.DISCONNECTED
	is_client = false
	peer_id = 0
	Logger.info("Disconnected from server")

## COMMON FUNCTIONS

func _check_connection_health() -> void:
	if not multiplayer.is_network_server():
		return
	
	# Check for timed out peers
	for peer_id in connected_peers:
		var peer_data = connected_peers[peer_id]
		var timeout_ms := 30000  # 30 seconds
		if Time.get_ticks_msec() - peer_data.get("last_heartbeat", 0) > timeout_ms:
			Logger.warn("Kicking inactive peer: %d" % peer_id)
			multiplayer.multiplayer_peer.disconnect_peer(peer_id, true)

func stop_server() -> void:
	if not is_server:
		return
	
	if tick_timer:
		tick_timer.stop()
		tick_timer.queue_free()
	
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	
	connection_state = ConnectionState.DISCONNECTED
	is_server = false
	server_ticks = 0
	connected_peers.clear()
	
	Logger.info("Server stopped")
	server_stopped.emit()

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
		Logger.info("Blocked %s for %d seconds: %s" % [player_id, duration_seconds, reason])

## Issue a permanent ban (admin function)
func ban_player(player_id: String, reason: String, banned_by: String = "system") -> void:
	if _firewall:
		var ip = _player_ip_from_id(player_id)
		_firewall.issue_ban(player_id, reason, banned_by, -1)
		Logger.info("Permanently banned %s: %s" % [player_id, reason])

## Flag an IP for suspicious activity
func flag_ip(ip: String, flag_type: String, count: int = 1) -> void:
	if _firewall:
		_firewall.flag_ip(ip, flag_type, count)

## Track a failed authentication attempt
func track_failed_attempt(ip: String) -> void:
	if _firewall:
		_firewall.track_failed_attempt(ip)

func _player_ip_from_id(player_id: String) -> String:
	# Look up IP from connected peers
	for peer_id in connected_peers:
		if "peer_%d" % peer_id == player_id:
			return connected_peers[peer_id].get("ip", "unknown")
	return "unknown"
