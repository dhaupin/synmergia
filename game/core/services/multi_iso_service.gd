## MultiIsoService - Bridge to the Julia multi-iso orchestrator
##
## Calls the Julia HTTP API (server.jl) to register entities and
## run multi-axis intersection queries. The Julia orchestrator lives
## in srv/julia-bridge/ (relocated 2026-09-30 -- it is an HTTP
## bridge sidecar, sibling of pg-bridge/redis-bridge, NOT a Godot
## frame primitive) and runs as a sidecar container (Docker).
##
## The HTTP bridge is the simplest way to cross the Godot <-> Julia
## boundary without a full polyglot FFI setup. When polyglot-ffi
## is mature, this service can be replaced with direct FFI calls.
##
## STATUS (2026-11-04): LIVE. Registered as an autoload. When enabled
## it binds EntityService.entity_registered / entity_unregistered and
## mirrors the entity roster into the Julia orchestrator's axes, so
## multi-axis queries (spatial x faction x social) resolve against a
## real, current index. The bridge is best-effort: if the sidecar is
## down every call degrades to an empty result and logs once -- it is
## never on the critical path for gameplay.
##
## The autoload name is MultiIsoService; this script deliberately has
## NO class_name (autoload + same-name class_name is the documented
## shadow trap -- see AGENTS.md). Use the autoload directly, or
## load("res://core/services/multi_iso_service.gd").new() for a fresh
## instance in tests.
##
## Usage:
##   MultiIsoService.register_entity(player_id, spatial_vertex, faction_id)
##   var nearby := await MultiIsoService.query_spatial_faction(vertex, faction_id)
extends Node

## Julia server URL (docker-compose service name)
@export var julia_server_url: String = "http://julia:8080"
@export var local_server_url: String = "http://localhost:8080"
@export var use_localhost: bool = true  # Toggle for dev vs prod
## Master switch: when false the service never touches the network and
## every query returns empty. Set false in tests that must not egress.
@export var enabled: bool = true

## HTTPRequest nodes (work + health)
var _http_request: HTTPRequest
var _health_request: HTTPRequest

## Results cache
var _last_stats: Dictionary = {}

## Serial outbound queue (one in-flight request at a time -- the single
## HTTPRequest node cannot serve overlapping requests).
var _queue: Array = []
var _busy: bool = false
var _bound: bool = false
var _warned_unreachable: bool = false

func _ready() -> void:
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	# Dedicated node for the boot health probe so it can never race the
	# serial work queue.
	_health_request = HTTPRequest.new()
	add_child(_health_request)
	_health_request.request_completed.connect(_on_health_completed)
	GameLog.info("MultiIsoService: Ready -- Julia server: %s" % _get_server_url())
	call_deferred("_boot")

func _boot() -> void:
	_bind_entity_service()
	if enabled:
		_check_health()

## Mirror EntityService's roster into the orchestrator. Deferred so the
## autoload order never matters; idempotent.
func _bind_entity_service() -> void:
	if _bound or not enabled:
		return
	if EntityService == null:
		return
	EntityService.entity_registered.connect(_on_entity_registered)
	EntityService.entity_unregistered.connect(_on_entity_unregistered)
	_bound = true
	GameLog.info("MultiIsoService: bound to EntityService (entity roster mirrored)")

## Static accessor for the running autoload (null when not registered).
static func instance() -> Node:
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		return (tree as SceneTree).root.get_node_or_null("MultiIsoService")
	return null

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
	await _http_post("/register", body)

## Unregister an entity (removes it from every axis bucket).
func unregister_entity(entity_id: String) -> void:
	if not enabled:
		return
	await _http_post("/unregister", {"id": entity_id})

## Query all entities at a given icosahedral vertex.
func query_spatial(vertex: int) -> Array:
	var result := await _http_get("/spatial/%d" % vertex)
	return result.get("entity_ids", [])

## Query all entities in a given faction.
func query_faction(faction_id: int) -> Array:
	var result := await _http_get("/faction/%d" % faction_id)
	return result.get("entity_ids", [])

## Query all entities in a given social group.
func query_social(group: int) -> Array:
	var result := await _http_get("/social/%d" % group)
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
	var result := await _http_post("/intersect", body)
	return result.get("entity_ids", [])

## Get orchestrator statistics.
func get_stats() -> Dictionary:
	if _last_stats.is_empty():
		_last_stats = await _http_get("/stats")
	return _last_stats

## Check if the Julia server is healthy.
func is_healthy() -> bool:
	var result: Dictionary = await _http_get("/health")
	return result.get("status") == "ok"

## -------------------------------------------------------------------------
## Internal HTTP helpers
##
## All outbound traffic rides ONE serial queue: a single HTTPRequest node
## cannot serve overlapping requests, and entity registration (bursty at
## spawn) must never clobber a query's reply. Each caller awaits its own
## entry's completion.
## -------------------------------------------------------------------------

func _get_server_url() -> String:
	return local_server_url if use_localhost else julia_server_url

func _http_get(endpoint: String) -> Dictionary:
	return await _enqueue(endpoint, HTTPClient.METHOD_GET, "")

func _http_post(endpoint: String, body: Dictionary) -> Dictionary:
	return await _enqueue(endpoint, HTTPClient.METHOD_POST, JSON.stringify(body))

## Enqueue one request and await its parsed JSON reply ({} on any failure).
func _enqueue(endpoint: String, method: int, body: String) -> Dictionary:
	if not enabled:
		return {}
	var entry := {"endpoint": endpoint, "method": method, "body": body,
		"done": false, "result": {}}
	_queue.append(entry)
	_pump()
	while not entry["done"]:
		await get_tree().process_frame
	return entry["result"]

## Start the next queued request if nothing is in flight.
func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	var entry: Dictionary = _queue[0]
	var url: String = _get_server_url() + str(entry["endpoint"])
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
	])
	var err: int
	if entry["method"] == HTTPClient.METHOD_GET:
		err = _http_request.request(url, headers, HTTPClient.METHOD_GET)
	else:
		err = _http_request.request(url, headers, HTTPClient.METHOD_POST, entry["body"])
	if err != OK:
		GameLog.error("MultiIsoService: request to %s failed -- %d" % [url, err])
		_queue.pop_front()
		entry["done"] = true
		entry["result"] = {}
		_pump()
		return
	_busy = true

func _check_health() -> void:
	if not enabled:
		return
	_health_request.request(_get_server_url() + "/health",
		PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)

func _on_health_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200 and not body.is_empty():
		_warned_unreachable = false
		GameLog.info("MultiIsoService: Julia server is healthy")
	elif not _warned_unreachable:
		_warned_unreachable = true
		GameLog.warn("MultiIsoService: Julia server not reachable at %s (bridge degrades to empty)" % _get_server_url())

## ---- EntityService hooks (the real consumer) ----

func _on_entity_registered(entity, _metadata) -> void:
	if not enabled or entity == null or not ("entity_id" in entity):
		return
	var vertex := 0
	var faction := 0
	if "team_id" in entity and entity.team_id != 0:
		vertex = abs(entity.team_id) % 12
	if "faction_id" in entity and str(entity.faction_id) != "":
		faction = abs(hash(str(entity.faction_id))) % 100
		vertex = abs(hash(str(entity.faction_id))) % 12
	register_entity(str(entity.entity_id), vertex, faction)

func _on_entity_unregistered(entity, _metadata) -> void:
	if not enabled or entity == null or not ("entity_id" in entity):
		return
	unregister_entity(str(entity.entity_id))

func _on_request_completed(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if _queue.is_empty():
		_busy = false
		return
	var entry: Dictionary = _queue.pop_front()
	_busy = false
	if response_code != 0 and not body.is_empty():
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK and json.get_data() is Dictionary:
			entry["result"] = json.get_data()
	entry["done"] = true
	_pump()
