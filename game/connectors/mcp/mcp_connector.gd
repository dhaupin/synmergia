## MCPConnector - Model Context Protocol connector
## Standard MCP interface for AI agents
extends AgentConnector

const AgentConnector = preload("res://core/schemas/agent_connector.gd")
class_name MCPConnector
# QoSService uses static shim methods (AGENTS.md allowlist); the const is required.
const QoSService = preload("res://core/autoload/qos_service.gd")

# MCP server configuration
@export var mcp_server_url: String = "http://localhost:3000"
@export var access_token: String = ""
@export var model: String = "claude-3-sonnet"

# Rate limiting: max actions per agent per server tick
@export var max_actions_per_tick: int = 10

var _ws_client: WebSocketClient
var _message_queue: Array[Dictionary] = []
var _pending_requests: Dictionary = {}

# Per-agent action tracking for per-tick limiting
var _agent_action_counts: Dictionary = {}
var _last_tick: int = 0

func _init() -> void:
	connector_name = "MCP"
	agent_type = AgentType.CUSTOM
	_agent_action_counts = {}
	_last_tick = 0

func _ready() -> void:
	super._ready()
	_ws_client = WebSocketClient.new()
	_ws_client.message_received.connect(_on_ws_message)
	_ws_client.connected.connect(_on_ws_connected)
	_ws_client.disconnected.connect(_on_ws_disconnected)

## Connect to MCP server
func connect_agent(config: Dictionary) -> bool:
	mcp_server_url = config.get("server_url", mcp_server_url)
	access_token = config.get("access_token", access_token)
	model = config.get("model", model)

	# Set agent ID for rate limiting
	_agent_id = config.get("agent_id", "mcp_agent_%d" % Time.get_ticks_msec())

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
	GameLog.info("MCPConnector: Connected to %s" % mcp_server_url)
	return true

## Disconnect from MCP
func disconnect_agent() -> void:
	_ws_client.close()
	_set_status(ConnectorStatus.DISCONNECTED)
	GameLog.info("MCPConnector: Disconnected")

## Send observation via MCP
func send_observation(observation: Dictionary) -> void:
	if not is_agent_connected():
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
	if not is_agent_connected():
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
					# Rate limit check before emitting action
					if _check_agent_rate_limit(action):
						action_received.emit(action)
					else:
						GameLog.warn("MCPConnector: Rate limited action from agent %s" % _agent_id)
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

## Check agent rate limits (QoS + per-tick)
func _check_agent_rate_limit(action: AgentAction) -> bool:
	var agent_id := _agent_id if _agent_id != "" else "mcp_agent"

	# Per-tick action limit
	var current_tick := Time.get_ticks_msec() / 16  # ~60 ticks/sec
	if current_tick != _last_tick:
		_last_tick = current_tick
		_agent_action_counts.erase(agent_id)

	var count := _agent_action_counts.get(agent_id, 0)
	if count >= max_actions_per_tick:
		# Exceeded per-tick limit
		if QoSService:
			QoSService.rate_limit(agent_id, "agent_action_burst")
		return false

	_agent_action_counts[agent_id] = count + 1

	# QoS rate limit (token bucket per action type)
	var action_type_str := AgentAction.ActionType.keys()[action.action_type].lower()
	if QoSService and not QoSService.rate_limit(agent_id, "agent_" + action_type_str):
		return false

	return true

func _on_ws_connected() -> void:
	GameLog.debug("MCPConnector: WebSocket connected")

func _on_ws_disconnected() -> void:
	_set_status(ConnectorStatus.DISCONNECTED)
	GameLog.info("MCPConnector: WebSocket disconnected")

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
