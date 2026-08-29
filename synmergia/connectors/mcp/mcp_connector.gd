## MCPConnector - Model Context Protocol connector
## Standard MCP interface for AI agents
class_name MCPConnector
extends AgentConnector

# MCP server configuration
@export var mcp_server_url: String = "http://localhost:3000"
@export var access_token: String = ""
@export var model: String = "claude-3-sonnet"

var _ws_client: WebSocketClient
var _message_queue: Array[Dictionary] = []
var _pending_requests: Dictionary = {}

func _init() -> void:
	connector_name = "MCP"
	agent_type = AgentType.CUSTOM

func _ready() -> void:
	super._ready()
	_ws_client = WebSocketClient.new()
	_ws_client.message_received.connect(_on_ws_message)
	_ws_client.connected.connect(_on_ws_connected)
	_ws_client.disconnected.connect(_on_ws_disconnected)

## Connect to MCP server
func connect(config: Dictionary) -> bool:
	mcp_server_url = config.get("server_url", mcp_server_url)
	access_token = config.get("access_token", access_token)
	model = config.get("model", model)
	
	# Connect WebSocket
	var url := "ws://%s/mcp" % mcp_server_url.replace("http://", "").replace("https://", "")
	var result := await _ws_client.connect_to_url(url)
	
	if result != OK:
		_set_status(ConnectorStatus.ERROR)
		error_occurred.emit("Failed to connect to MCP server")
		return false
	
	# Initialize MCP session
	await _send_initialize()
	
	_set_status(ConnectorStatus.CONNECTED)
	GameLogger.info("MCPConnector: Connected to %s" % mcp_server_url)
	return true

## Disconnect from MCP
func disconnect() -> void:
	_ws_client.close()
	_set_status(ConnectorStatus.DISCONNECTED)
	GameLogger.info("MCPConnector: Disconnected")

## Send observation via MCP
func send_observation(observation: Dictionary) -> void:
	if not is_connected():
		return
	
	var message: Dictionary = {
		"jsonrpc": "2.0",
		"method": "observation",
		"params": {
			"observation": observation,
			"action_space": get_action_space(),
			"observation_space": get_observation_space()
		}
	}
	
	_ws_client.send_text(JSON.stringify(message))

## Request action from MCP agent
func request_action(prompt: String = "") -> void:
	if not is_connected():
		return
	
	var request_id := "req_%d" % Time.get_ticks_msec()
	
	var message: Dictionary = {
		"jsonrpc": "2.0",
		"id": request_id,
		"method": "game/action",
		"params": {
			"prompt": prompt if prompt != "" else "What action should the agent take?",
			"observation_space": get_observation_space(),
			"action_space": get_action_space()
		}
	}
	
	_pending_requests[request_id] = Time.get_ticks_msec()
	_ws_client.send_text(JSON.stringify(message))

func _send_initialize() -> void:
	var message: Dictionary = {
		"jsonrpc": "2.0",
		"id": "init",
		"method": "initialize",
		"params": {
			"protocolVersion": "1.0",
			"capabilities": {
				"game": true,
				"streaming": false
			},
			"clientInfo": {
				"name": "Synmergia",
				"version": "1.0"
			}
		}
	}
	
	_ws_client.send_text(JSON.stringify(message))

func _on_ws_message(message: String) -> void:
	var json := JSON.new()
	var parse_result := json.parse(message)
	if parse_result != OK:
		return
	
	var data: Dictionary = json.get_data()
	
	# Handle response
	if data.has("id"):
		var req_id := str(data["id"])
		if _pending_requests.has(req_id):
			_pending_requests.erase(req_id)
			
			if data.has("result"):
				var result: Dictionary = data["result"]
				if result.has("action"):
					var action := AgentAction.from_dict(result["action"])
					action_received.emit(action)
	elif data.has("method"):
		match data["method"]:
			"observation/ack":
				# Observation acknowledged
				pass
			"game/state":
				# Full state update
				var state: Dictionary = data["params"]["state"]
				# Process state...
				pass

func _on_ws_connected() -> void:
	GameLogger.debug("MCPConnector: WebSocket connected")

func _on_ws_disconnected() -> void:
	_set_status(ConnectorStatus.DISCONNECTED)
	GameLogger.info("MCPConnector: WebSocket disconnected")

## Get MCP capabilities
func get_capabilities() -> Dictionary:
	return {
		"supports_streaming": false,
		"supports_memory": true,
		"supports_tools": true,
		"max_observation_rate_hz": 10,
		"native_vision": false,
		"native_voice": false,
		"protocol": "MCP 1.0"
	}
