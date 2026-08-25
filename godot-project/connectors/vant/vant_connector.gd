## VantConnector - Connect to Vant AI OS/runtime
## Vant is a custom agent runtime - https://github.com/vant-project/vant
class_name VantConnector
extends AgentConnector

# Vant API configuration
@export var vant_api_url: String = "http://localhost:8080"
@export var api_key: String = ""
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
	
	# Start session
	var session_result = await _create_session()
	if not session_result:
		_set_status(ConnectorStatus.ERROR)
		error_occurred.emit("Failed to create Vant session")
		return false
	
	_set_status(ConnectorStatus.CONNECTED)
	_poll_timer.start()
	
	Logger.info("VantConnector: Connected to %s" % vant_api_url)
	return true

## Disconnect from Vant
func disconnect() -> void:
	_poll_timer.stop()
	
	if _session_id != "":
		_close_session()
	
	_set_status(ConnectorStatus.DISCONNECTED)
	Logger.info("VantConnector: Disconnected")

## Send observation to Vant
func send_observation(observation: Dictionary) -> void:
	if not is_connected():
		return
	
	var payload := {
		"session_id": _session_id,
		"observation": observation,
		"timestamp": Time.get_ticks_msec()
	}
	
	# Send via HTTP POST
	var headers := ["Content-Type: application/json"]
	if api_key != "":
		headers.append("Authorization: Bearer " + api_key)
	
	_http_request.request(
		vant_api_url + "/api/observation",
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

func _create_session() -> bool:
	# TODO: Implement actual API call
	_session_id = "session_%d" % Time.get_ticks_msec()
	return true

func _close_session() -> void:
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
		"supports_streaming": true,
		"supports_memory": true,
		"supports_tools": true,
		"max_observation_rate_hz": 10,
		"native_vision": true,
		"native_voice": false
	}
