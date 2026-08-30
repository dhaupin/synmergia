## VantConnector - Connect to Vant AI OS/runtime
## Vant is a custom agent runtime - https://github.com/dhaupin/vant (axolotl branch)
## Synmergia agents can connect via Vant to play the game alongside humans
class_name VantConnector
extends AgentConnector

# Vant API configuration
# Vant endpoint: http://localhost:8080/api/agent/connect
@export var vant_api_url: String = "http://localhost:8080"
@export var api_key: String = ""
@export var agent_session_id: String = ""  # Vant agent session to connect
@export var poll_interval: float = 0.1  # Seconds between observations

var _poll_timer: Timer
var _session_id: String = ""
var _http_request: HTTPRequest

func _init() -> void:
	connector_name = "Vant"
	agent_type = AgentType.VANT

func _ready() -> void:
	super._ready()
	
	# Setup polling
	_poll_timer = Timer.new()
	_poll_timer.wait_time = poll_interval
	_poll_timer.timeout.connect(_on_poll)
	add_child(_poll_timer)
	
	# Setup HTTP for API calls
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_http_request_completed)

## Connect to Vant runtime
func connect(config: Dictionary) -> bool:
	vant_api_url = config.get("api_url", vant_api_url)
	api_key = config.get("api_key", api_key)
	agent_session_id = config.get("agent_session_id", agent_session_id)
	
	# Start Vant agent session
	var session_result = await _create_session()
	if not session_result:
		_set_status(ConnectorStatus.ERROR)
		error_occurred.emit("Failed to create Vant session")
		return false
	
	_set_status(ConnectorStatus.CONNECTED)
	_poll_timer.start()
	
	GameLog.info("VantConnector: Connected to Vant at %s (agent: %s)" % [vant_api_url, agent_session_id])
	return true

## Disconnect from Vant
func disconnect() -> void:
	_poll_timer.stop()
	
	if _session_id != "":
		_close_session()
	
	_set_status(ConnectorStatus.DISCONNECTED)
	GameLog.info("VantConnector: Disconnected from Vant")

## Send observation to Vant
func send_observation(observation: Dictionary) -> void:
	if not is_connected():
		return
	
	var payload := {
		"session_id": _session_id,
		"agent_id": agent_session_id,
		"observation": observation,
		"action_space": get_action_space(),
		"observation_space": get_observation_space(),
		"timestamp": Time.get_ticks_msec()
	}
	
	var headers := ["Content-Type: application/json"]
	if api_key != "":
		headers.append("Authorization: Bearer " + api_key)
	
	_http_request.request(
		vant_api_url + "/api/agent/state",
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)

## Parse action from Vant response
func _parse_vant_response(response: Dictionary) -> void:
	var action_data := response.get("action", {})
	if action_data.is_empty():
		return
	
	var action := AgentAction.from_dict(action_data)
	action_received.emit(action)

## Create Vant agent session
func _create_session() -> bool:
	# POST /api/agent/connect with agent_session_id
	# Expected response: {"session_id": "...", "status": "connected"}
	
	var payload := {
		"agent_id": agent_session_id,
		"capabilities": get_capabilities(),
		"connector": "synmergia"
	}
	
	var headers := ["Content-Type: application/json"]
	if api_key != "":
		headers.append("Authorization: Bearer " + api_key)
	
	# Sync call for simplicity (would be async in real impl)
	_session_id = "ws_%s_%d" % [agent_session_id, Time.get_ticks_msec()]
	
	GameLog.info("VantConnector: Created session %s for agent %s" % [_session_id, agent_session_id])
	return true

func _close_session() -> void:
	if _session_id != "":
		GameLog.info("VantConnector: Closing session %s" % _session_id)
	_session_id = ""

func _on_poll() -> void:
	# Poll for actions
	if not is_connected():
		return
	
	# TODO: GET request to /api/action endpoint
	# var response = await _get_actions()
	pass

func _on_http_request_completed(result: int, response_code: int, headers: Array, body: PackedByteArray) -> void:
	if response_code != 200:
		return
	
	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result == OK:
		var response := json.get_data() as Dictionary
		_parse_vant_response(response)

## Get Vant-specific capabilities
func get_capabilities() -> Dictionary:
	return {
		"connector": "synmergia",
		"version": "1.0",
		"supports_streaming": true,
		"supports_memory": true,
		"supports_tools": true,
		"supports_vision": true,
		"max_observation_rate_hz": 10,
		"native_vision": true,
		"native_voice": false,
		"game_endpoint": vant_api_url + "/api/agent",
		"vant_repo": "https://github.com/dhaupin/vant (axolotl branch)"
	}
