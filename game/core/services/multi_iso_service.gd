## MultiIsoService - Bridge to the Julia multi-iso orchestrator
##
## Calls the Julia HTTP API (server.jl) to register entities and
## run multi-axis intersection queries. The Julia orchestrator lives
## in game/core/frame/srv/ and runs as a sidecar container (Docker).
##
## The HTTP bridge is the simplest way to cross the Godot <-> Julia
## boundary without a full polyglot FFI setup. When polyglot-ffi
## is mature, this service can be replaced with direct FFI calls.
##
## Usage:
##   MultiIsoService.register_entity(player_id, spatial_vertex, faction_id)
##   var nearby := await MultiIsoService.query_spatial_faction(vertex, faction_id)
extends Node
class_name MultiIsoService

## Julia server URL (docker-compose service name)
@export var julia_server_url: String = "http://julia:8080"
@export var local_server_url: String = "http://localhost:8080"
@export var use_localhost: bool = true  # Toggle for dev vs prod

## Pending HTTP request queue
var _pending_requests: Dictionary = {}  # request_id -> {resolve, reject, endpoint}
var _request_id_counter: int = 0
var _http_request: HTTPRequest
var _semaphore: bool = false  # True when a response is waiting to be consumed

## Results cache
var _last_stats: Dictionary = {}

func _ready() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	GameLog.info("MultiIsoService: Ready -- Julia server: %s" % _get_server_url())
	_check_health()

## -------------------------------------------------------------------------
## Public API
## -------------------------------------------------------------------------

## Register a player/enemy/NPC on the Julia orchestrator.
## Call this once per entity when they spawn in the world.
func register_entity(
	entity_id: String,
	spatial_vertex: int,
	faction_id: int,
	social_group: int = 0,
	game_class: int = 0,
	birth_year: int = 2026
) -> void:
	var body := {
		"id": entity_id,
		"spatial_vertex": spatial_vertex,
		"faction_id": faction_id,
		"social_group": social_group,
		"game_class": game_class,
		"birth_year": birth_year,
	}
	await _post("/register", body)

## Unregister an entity (removes from all axes).
## Currently a no-op on the Julia side; entity remains until orchestrator reset.
func unregister_entity(_entity_id: String) -> void:
	# Julia orchestrator does not yet support per-entity removal.
	# For now, entities persist for the lifetime of the orchestrator.
	pass

## Query all entities at a given icosahedral vertex.
func query_spatial(vertex: int) -> Array:
	var result := await _get("/spatial/%d" % vertex)
	return result.get("entity_ids", [])

## Query all entities in a given faction.
func query_faction(faction_id: int) -> Array:
	var result := await _get("/faction/%d" % faction_id)
	return result.get("entity_ids", [])

## Query all entities in a given social group.
func query_social(group: int) -> Array:
	var result := await _get("/social/%d" % group)
	return result.get("entity_ids", [])

## Multi-axis intersection: entities that match ALL specified criteria.
## Returns Array of entity_ids.
func query_intersect(
	spatial_vertex: int = -1,
	faction_id: int = -1,
	social_group: int = -1
) -> Array:
	var body := {}
	if spatial_vertex >= 0:
		body["spatial_vertex"] = spatial_vertex
	if faction_id >= 0:
		body["faction_id"] = faction_id
	if social_group >= 0:
		body["social_group"] = social_group
	var result := await _post("/intersect", body)
	return result.get("entity_ids", [])

## Get orchestrator statistics.
func get_stats() -> Dictionary:
	if _last_stats.is_empty():
		_last_stats = await _get("/stats")
	return _last_stats

## Check if the Julia server is healthy.
func is_healthy() -> bool:
	var result: Dictionary = await _get("/health")
	return result.get("status") == "ok"

## -------------------------------------------------------------------------
## Internal HTTP helpers
## -------------------------------------------------------------------------

func _get_server_url() -> String:
	return local_server_url if use_localhost else julia_server_url

func _get(endpoint: String) -> Dictionary:
	var server := _get_server_url()
	var url := server + endpoint
	var headers := PackedStringArray(["Accept: application/json"])
	var err := _http_request.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		GameLog.error("MultiIsoService: GET %s failed -- %d" % [url, err])
		return {}
	return await _wait_for_response()

func _post(endpoint: String, body: Dictionary) -> Dictionary:
	var server := _get_server_url()
	var url := server + endpoint
	var json := JSON.stringify(body)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	])
	var err := _http_request.request(url, headers, HTTPClient.METHOD_POST, json)
	if err != OK:
		GameLog.error("MultiIsoService: POST %s failed -- %d" % [url, err])
		return {}
	return await _wait_for_response()

func _wait_for_response() -> Dictionary:
	_semaphore = false
	_pending_requests.clear()
	while not _semaphore:
		await get_tree().process_frame
	var req = _pending_requests.values()[0]
	_pending_requests.clear()
	if req.get("error"):
		GameLog.error("MultiIsoService: request error -- %s" % str(req.get("error")))
		return {}
	return req.get("result", {})

func _check_health() -> void:
	var healthy := await is_healthy()
	if healthy:
		GameLog.info("MultiIsoService: Julia server is healthy")
	else:
		GameLog.warn("MultiIsoService: Julia server not reachable at %s" % _get_server_url())

func _on_request_completed(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if response_code == 0:
		# Connection failed -- still wake the waiter with an error
		_pending_requests[0] = {"error": "connection_failed"}
		_semaphore = true
		return
	var json_str := body.get_string_from_utf8()
	if json_str.is_empty():
		return
	var json := JSON.new()
	var parse_result := json.parse(json_str)
	if parse_result != OK:
		return
	var data: Dictionary = json.get_data()
	_pending_requests[0] = {"result": data}
	_semaphore = true
