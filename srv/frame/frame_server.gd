## FrameServer - Godot headless entry point for frame primitives
## Exposes RulesEngine, Scope, ScopeEngine, ScopeHierarchy, T3, StateTree, etc. via HTTP
##
## This runs as a separate container (srv/frame) and communicates with the game
## via HTTP bridge (v1). FFI is Phase 4+.
##
## Frame conventions: NO autoload, NO class_name, NO GameManager dependency.
extends SceneTree

const RulesEngineScript = preload("res://labs/multi-iso/srv/rules_engine.gd")
const ScopeScript = preload("res://labs/multi-iso/srv/scope.gd")
const ScopeEngineScript = preload("res://labs/multi-iso/srv/scope_engine.gd")
const ScopeHierarchyScript = preload("res://labs/multi-iso/srv/scope_hierarchy.gd")
const RulesSchemaScript = preload("res://labs/multi-iso/srv/rules_schema.gd")
const T3Script = preload("res://labs/multi-iso/kv/t3.gd")
const StateTreeScript = preload("res://labs/multi-iso/kv/state_tree.gd")
const SeedChainScript = preload("res://labs/multi-iso/kv/seed_chain.gd")
const LRUCacheScript = preload("res://labs/multi-iso/kv/lru_cache.gd")
const DefinitionTreeScript = preload("res://labs/multi-iso/kv/definition_tree.gd")
const DefinitionSchemaScript = preload("res://labs/multi-iso/kv/definition_schema.gd")
const NSC9Script = preload("res://labs/multi-iso/math/nsc9.gd")
const IcosahedralScript = preload("res://labs/multi-iso/math/icosahedral.gd")
const SnapshotStoreScript = preload("res://labs/multi-iso/db/snapshot_store.gd")

signal request_received(method: String, path: String, body: String)
signal request_completed(method: String, path: String, status: int)

var _http_server: HTTPServer
var _port: int = 8080
var _rules_engines: Dictionary = {}  # engine_id -> RulesEngine
var _scopes: Dictionary = {}  # scope_id -> Scope
var _scope_engines: Dictionary = {}  # engine_id -> ScopeEngine
var _snapshot_store: Object = null

func _init() -> void:
	# Initialize the snapshot store
	_snapshot_store = SnapshotStoreScript.new()

func _initialize() -> void:
	_port = ProjectSettings.get_setting("frame_server/port", 8080)
	_setup_http_server()
	print("FrameServer: Starting on port %d" % _port)

func _setup_http_server() -> void:
	_http_server = HTTPServer.new()
	
	# Health endpoints
	_http_server.connect("request_received", _on_request_received.bind("/health"))
	_http_server.connect("request_received", _on_request_received.bind("/ready"))
	
	# RulesEngine endpoints
	_http_server.connect("request_received", _on_request_received.bind("/evaluate"))
	_http_server.connect("request_received", _on_request_received.bind("/rules/register"))
	_http_server.connect("request_received", _on_request_received.bind("/rules/get"))
	_http_server.connect("request_received", _on_request_received.bind("/rules/diff"))
	_http_server.connect("request_received", _on_request_received.bind("/rules/apply_diff"))
	
	# Scope endpoints
	_http_server.connect("request_received", _on_request_received.bind("/scope/create"))
	_http_server.connect("request_received", _on_request_received.bind("/scope/flip"))
	_http_server.connect("request_received", _on_request_received.bind("/scope/get_override"))
	_http_server.connect("request_received", _on_request_received.bind("/scope_hierarchy/load"))
	_http_server.connect("request_received", _on_request_received.bind("/scope_hierarchy/push"))
	_http_server.connect("request_received", _on_request_received.bind("/scope_hierarchy/pop"))
	_http_server.connect("request_received", _on_request_received.bind("/scope_hierarchy/get_stack"))
	_http_server.connect("request_received", _on_request_received.bind("/scope_hierarchy/resolve_rule"))
	
	# T3/StateTree endpoints
	_http_server.connect("request_received", _on_request_received.bind("/t3/insert"))
	_http_server.connect("request_received", _on_request_received.bind("/t3/get"))
	_http_server.connect("request_received", _on_request_received.bind("/t3/hash"))
	_http_server.connect("request_received", _on_request_received.bind("/state_tree/insert"))
	_http_server.connect("request_received", _on_request_received.bind("/state_tree/get"))
	
	# SeedChain endpoints
	_http_server.connect("request_received", _on_request_received.bind("/seed_chain/generate"))
	_http_server.connect("request_received", _on_request_received.bind("/seed_chain/verify"))
	
	# LRU Cache endpoints
	_http_server.connect("request_received", _on_request_received.bind("/lru/get"))
	_http_server.connect("request_received", _on_request_received.bind("/lru/put"))
	_http_server.connect("request_received", _on_request_received.bind("/lru/evict"))
	
	# Definition Tree endpoints
	_http_server.connect("request_received", _on_request_received.bind("/definition_tree/insert"))
	_http_server.connect("request_received", _on_request_received.bind("/definition_tree/get"))
	
	# Math endpoints
	_http_server.connect("request_received", _on_request_received.bind("/nsc9/encode"))
	_http_server.connect("request_received", _on_request_received.bind("/nsc9/decode"))
	_http_server.connect("request_received", _on_request_received.bind("/icosahedral/vertex_from_coords"))
	_http_server.connect("request_received", _on_request_received.bind("/icosahedral/coords_from_vertex"))
	
	# Snapshot Store endpoints
	_http_server.connect("request_received", _on_request_received.bind("/snapshot/save"))
	_http_server.connect("request_received", _on_request_received.bind("/snapshot/load"))
	_http_server.connect("request_received", _on_request_received.bind("/snapshot/list"))
	
	err = _http_server.start(_port)
	if err != OK:
		push_error("FrameServer: Failed to start HTTP server on port %d: %d" % [_port, err])
	else:
		print("FrameServer: HTTP server started on port %d" % _port)

func _on_request_received(request: HTTPRequest, path: String) -> void:
	var method = request.get_http_method()
	var body = request.get_body().get_string_from_utf8()
	request_received.emit(method, path, body)
	
	var response: Dictionary = {}
	var status: int = 200
	
	match path:
		"/health":
			response = {"status": "healthy"}
		"/ready":
			response = {"status": "ready"}
		
		# RulesEngine endpoints
		"/evaluate":
			response = _handle_evaluate(body)
		"/rules/register":
			response = _handle_rules_register(body)
		"/rules/get":
			response = _handle_rules_get(body)
		"/rules/diff":
			response = _handle_rules_diff(body)
		"/rules/apply_diff":
			response = _handle_rules_apply_diff(body)
		
		# Scope endpoints
		"/scope/create":
			response = _handle_scope_create(body)
		"/scope/flip":
			response = _handle_scope_flip(body)
		"/scope/get_override":
			response = _handle_scope_get_override(body)
		
		# ScopeEngine endpoints
		"/scope_hierarchy/load":
			response = _handle_scope_hierarchy_load(body)
		"/scope_hierarchy/push":
			response = _handle_scope_hierarchy_push(body)
		"/scope_hierarchy/pop":
			response = _handle_scope_hierarchy_pop(body)
		"/scope_hierarchy/get_stack":
			response = _handle_scope_hierarchy_get_stack(body)
		"/scope_hierarchy/resolve_rule":
			response = _handle_scope_hierarchy_resolve_rule(body)
		
		# T3 endpoints
		"/t3/insert":
			response = _handle_t3_insert(body)
		"/t3/get":
			response = _handle_t3_get(body)
		"/t3/hash":
			response = _handle_t3_hash(body)
		
		# StateTree endpoints
		"/state_tree/insert":
			response = _handle_state_tree_insert(body)
		"/state_tree/get":
			response = _handle_state_tree_get(body)
		
		# SeedChain endpoints
		"/seed_chain/generate":
			response = _handle_seed_chain_generate(body)
		"/seed_chain/verify":
			response = _handle_seed_chain_verify(body)
		
		# LRU Cache endpoints
		"/lru/get":
			response = _handle_lru_get(body)
		"/lru/put":
			response = _handle_lru_put(body)
		"/lru/evict":
			response = _handle_lru_evict(body)
		
		# Definition Tree endpoints
		"/definition_tree/insert":
			response = _handle_definition_tree_insert(body)
		"/definition_tree/get":
			response = _handle_definition_tree_get(body)
		
		# Math endpoints
		"/nsc9/encode":
			response = _handle_nsc9_encode(body)
		"/nsc9/decode":
			response = _handle_nsc9_decode(body)
		"/icosahedral/vertex_from_coords":
			response = _handle_icosahedral_vertex_from_coords(body)
		"/icosahedral/coords_from_vertex":
			response = _handle_icosahedral_coords_from_vertex(body)
		
		# Snapshot Store endpoints
		"/snapshot/save":
			response = _handle_snapshot_save(body)
		"/snapshot/load":
			response = _handle_snapshot_load(body)
		"/snapshot/list":
			response = _handle_snapshot_list(body)
		
		_:
			status = 404
			response = {"error": "Not found", "path": path}
	
	var json = JSON.stringify(response)
	request.respond(status, ["Content-Type: application/json"], json.to_utf8_buffer())
	request_completed.emit(method, path, status)

# ============================================================================
# RulesEngine Handlers
# ============================================================================

func _handle_evaluate(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var engine_id = data.get("engine_id", "default")
	var action = data.get("action", "")
	var context = data.get("context", {})
	var stack_ids = data.get("stack", [])
	
	var engine = _get_or_create_rules_engine(engine_id)
	var stack: Array = []
	for scope_id in stack_ids:
		if _scopes.has(scope_id):
			stack.append(_scopes[scope_id])
	
	var result = engine.evaluate(action, context, stack)
	return {
		"allow": result.get("allow", false),
		"reason": result.get("reason", ""),
		"modified_action": result.get("modified_action", {}),
		"applied_rules": result.get("applied_rules", [])
	}

func _handle_rules_register(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var engine_id = data.get("engine_id", "default")
	var rule_id = data.get("rule_id", "")
	var resolution = data.get("resolution", "TOP_WINS")
	var default_allow = data.get("default_allow", true)
	var predicate = data.get("predicate", "")
	
	var engine = _get_or_create_rules_engine(engine_id)
	var hash = engine.register_rule(rule_id, resolution, default_allow)
	return {"hash": hash.to_hex()}

func _handle_rules_get(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var engine_id = data.get("engine_id", "default")
	var rule_id = data.get("rule_id", "")
	
	var engine = _get_or_create_rules_engine(engine_id)
	var rule = engine.get_rule(rule_id)
	return rule

func _handle_rules_diff(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var engine_id = data.get("engine_id", "default")
	var old_root_hex = data.get("old_root", "")
	var new_root_hex = data.get("new_root", "")
	
	var engine = _get_or_create_rules_engine(engine_id)
	var old_root = PackedByteArray().hex_decode(old_root_hex)
	var new_root = PackedByteArray().hex_decode(new_root_hex)
	var diff = engine.diff_rules(old_root, new_root)
	return {"diff": diff}

func _handle_rules_apply_diff(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var engine_id = data.get("engine_id", "default")
	var root_hex = data.get("root", "")
	var diff = data.get("diff", [])
	
	var engine = _get_or_create_rules_engine(engine_id)
	var root = PackedByteArray().hex_decode(root_hex)
	var new_root = engine.apply_diff(root, diff)
	return {"new_root": new_root.to_hex()}

func _get_or_create_rules_engine(engine_id: String) -> Object:
	if not _rules_engines.has(engine_id):
		_rules_engines[engine_id] = RulesEngineScript.new()
	return _rules_engines[engine_id]

# ============================================================================
# Scope Handlers
# ============================================================================

func _handle_scope_create(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var scope_id = data.get("scope_id", "")
	var name = data.get("name", "")
	var parent_id = data.get("parent_id", "")
	var environment_path = data.get("environment_path", "")
	var rules_overrides = data.get("rules_overrides", {})
	
	var parent = null
	if parent_id != "" and _scopes.has(parent_id):
		parent = _scopes[parent_id]
	
	var scope = ScopeScript.new(name, parent, environment_path, rules_overrides)
	_scopes[scope_id] = scope
	return {"scope_id": scope_id, "name": name}

func _handle_scope_flip(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var scope_id = data.get("scope_id", "")
	var rule_id = data.get("rule_id", "")
	var resolution = data.get("resolution", "")
	
	if not _scopes.has(scope_id):
		return {"error": "Scope not found"}
	
	var scope = _scopes[scope_id]
	scope.flip(rule_id, resolution)
	return {"success": true}

func _handle_scope_get_override(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var scope_id = data.get("scope_id", "")
	var rule_id = data.get("rule_id", "")
	
	if not _scopes.has(scope_id):
		return {"error": "Scope not found"}
	
	var scope = _scopes[scope_id]
	var override = scope.get_override(rule_id)
	return {"override": override}

# ============================================================================
# ScopeEngine Handlers
# ============================================================================

func _handle_scope_hierarchy_load(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var engine_id = data.get("engine_id", "default")
	var path = data.get("path", "")
	
	if not _scope_engines.has(engine_id):
		_scope_engines[engine_id] = ScopeEngineScript.new()
	
	var engine = _scope_engines[engine_id]
	var success = engine.load_hierarchy(path)
	return {"success": success}

func _handle_scope_hierarchy_push(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var engine_id = data.get("engine_id", "default")
	var player_id = data.get("player_id", "")
	var scope_name = data.get("scope_name", "")
	
	if not _scope_engines.has(engine_id):
		return {"error": "ScopeEngine not found"}
	
	var engine = _scope_engines[engine_id]
	var success = engine.push(player_id, scope_name)
	return {"success": success}

func _handle_scope_hierarchy_pop(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var engine_id = data.get("engine_id", "default")
	var player_id = data.get("player_id", "")
	
	if not _scope_engines.has(engine_id):
		return {"error": "ScopeEngine not found"}
	
	var engine = _scope_engines[engine_id]
	var success = engine.pop(player_id)
	return {"success": success}

func _handle_scope_hierarchy_get_stack(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var engine_id = data.get("engine_id", "default")
	var player_id = data.get("player_id", "")
	
	if not _scope_engines.has(engine_id):
		return {"error": "ScopeEngine not found"}
	
	var engine = _scope_engines[engine_id]
	var stack = engine.get_stack(player_id)
	var names: Array = []
	for scope in stack:
		names.append(scope.name)
	return {"stack": names}

func _handle_scope_hierarchy_resolve_rule(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var engine_id = data.get("engine_id", "default")
	var player_id = data.get("player_id", "")
	var rule_id = data.get("rule_id", "")
	var default_resolution = data.get("default_resolution", "TOP_WINS")
	
	if not _scope_engines.has(engine_id):
		return {"error": "ScopeEngine not found"}
	
	var engine = _scope_engines[engine_id]
	var resolution = engine.resolve_rule(player_id, rule_id, default_resolution)
	return {"resolution": resolution}

# ============================================================================
# T3 Handlers
# ============================================================================

func _handle_t3_insert(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var key = data.get("key", "")
	var value = data.get("value", {})
	var schema = data.get("schema", "default")
	
	var t3 = T3Script.new()
	var hash = t3.insert(key, value, schema)
	return {"hash": hash.to_hex()}

func _handle_t3_get(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var key = data.get("key", "")
	
	var t3 = T3Script.new()
	var value = t3.get(key)
	return {"value": value}

func _handle_t3_hash(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var path = data.get("path", "/")
	
	var t3 = T3Script.new()
	var hash = t3.hash_subtree(path)
	return {"hash": hash.to_hex()}

# ============================================================================
# StateTree Handlers
# ============================================================================

func _handle_state_tree_insert(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var key = data.get("key", "")
	var value = data.get("value", {})
	
	var tree = StateTreeScript.new()
	var hash = tree.insert(key, value)
	return {"hash": hash.to_hex()}

func _handle_state_tree_get(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var key = data.get("key", "")
	
	var tree = StateTreeScript.new()
	var value = tree.get(key)
	return {"value": value}

# ============================================================================
# SeedChain Handlers
# ============================================================================

func _handle_seed_chain_generate(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var parent_seed_hex = data.get("parent_seed", "")
	var context = data.get("context", "")
	
	var seed_chain = SeedChainScript.new()
	var parent_seed = PackedByteArray()
	if parent_seed_hex != "":
		parent_seed = PackedByteArray().hex_decode(parent_seed_hex)
	else:
		parent_seed = Crypto.random_bytes(32)
	
	var seed = seed_chain.generate(parent_seed, context)
	return {"seed": seed.to_hex(), "parent_seed": parent_seed.to_hex()}

func _handle_seed_chain_verify(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var seed_hex = data.get("seed", "")
	var parent_seed_hex = data.get("parent_seed", "")
	var context = data.get("context", "")
	
	var seed_chain = SeedChainScript.new()
	var seed = PackedByteArray().hex_decode(seed_hex)
	var parent_seed = PackedByteArray().hex_decode(parent_seed_hex)
	var valid = seed_chain.verify(seed, parent_seed, context)
	return {"valid": valid}

# ============================================================================
# LRU Cache Handlers
# ============================================================================

func _handle_lru_get(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var cache_id = data.get("cache_id", "default")
	var key = data.get("key", "")
	
	# Note: LRU caches would need to be persistent across requests
	# For now, return not found
	return {"value": null, "found": false}

func _handle_lru_put(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var cache_id = data.get("cache_id", "default")
	var key = data.get("key", "")
	var value = data.get("value", {})
	
	return {"success": true}

func _handle_lru_evict(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var cache_id = data.get("cache_id", "default")
	var key = data.get("key", "")
	
	return {"success": true}

# ============================================================================
# Definition Tree Handlers
# ============================================================================

func _handle_definition_tree_insert(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var key = data.get("key", "")
	var value = data.get("value", {})
	
	var tree = DefinitionTreeScript.new()
	var hash = tree.insert(key, value)
	return {"hash": hash.to_hex()}

func _handle_definition_tree_get(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var key = data.get("key", "")
	
	var tree = DefinitionTreeScript.new()
	var value = tree.get(key)
	return {"value": value}

# ============================================================================
# Math Handlers
# ============================================================================

func _handle_nsc9_encode(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var lat = data.get("lat", 0.0)
	var lon = data.get("lon", 0.0)
	var precision = data.get("precision", 9)
	
	var nsc9 = NSC9Script.new()
	var code = nsc9.encode(lat, lon, precision)
	return {"code": code}

func _handle_nsc9_decode(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var code = data.get("code", "")
	
	var nsc9 = NSC9Script.new()
	var result = nsc9.decode(code)
	return {"lat": result.lat, "lon": result.lon}

func _handle_icosahedral_vertex_from_coords(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var lat = data.get("lat", 0.0)
	var lon = data.get("lon", 0.0)
	var depth = data.get("depth", 9)
	
	var ico = IcosahedralScript.new()
	var vertex = ico.vertex_from_coords(lat, lon, depth)
	return {"vertex": vertex}

func _handle_icosahedral_coords_from_vertex(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var vertex = data.get("vertex", 0)
	
	var ico = IcosahedralScript.new()
	var result = ico.coords_from_vertex(vertex)
	return {"lat": result.lat, "lon": result.lon}

# ============================================================================
# Snapshot Store Handlers
# ============================================================================

func _handle_snapshot_save(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var key = data.get("key", "")
	var value = data.get("value", {})
	
	var result = _snapshot_store.save(key, value)
	return {"success": result}

func _handle_snapshot_load(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var key = data.get("key", "")
	
	var result = _snapshot_store.load(key)
	return {"value": result}

func _handle_snapshot_list(body: String) -> Dictionary:
	var data = JSON.parse_string(body)
	if not data:
		return {"error": "Invalid JSON"}
	
	var prefix = data.get("prefix", "")
	
	var keys = _snapshot_store.list_keys(prefix)
	return {"keys": keys}