#!/usr/bin/env python3
"""
Frame HTTP Bridge Server v1
Exposes Synmergia frame primitives (RulesEngine, Scope, T3) via REST API.
Runs Godot headless with frame scripts loaded.
"""

import asyncio
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
import uvicorn


# Request/Response Models
class EvaluateRequest(BaseModel):
    action: str = Field(..., description="Action/rule name to evaluate")
    context: Dict[str, Any] = Field(default_factory=dict, description="Context dictionary for evaluation")
    stack: List[str] = Field(default_factory=list, description="Scope stack (scope IDs from innermost to outermost)")


class EvaluateResponse(BaseModel):
    allow: bool
    reason: str
    modified_action: Dict[str, Any]
    applied_rules: List[str]


class ScopeCreateRequest(BaseModel):
    name: str
    parent: Optional[str] = None
    environment: str = ""
    overrides: Dict[str, str] = Field(default_factory=dict)


class ScopeCreateResponse(BaseModel):
    scope_id: str
    name: str
    parent: Optional[str]


class ScopeFlipRequest(BaseModel):
    scope_id: str
    rule_id: str
    resolution: str


class ScopeFlipResponse(BaseModel):
    success: bool
    scope_id: str
    rule_id: str
    resolution: str


class TreeInsertRequest(BaseModel):
    tree_name: str  # "seed", "state", "rules", "definition"
    path: str
    value: Dict[str, Any]
    schema: str  # schema name


class TreeInsertResponse(BaseModel):
    hash: str
    path: str


class TreeGetRequest(BaseModel):
    tree_name: str
    path: str


class TreeGetResponse(BaseModel):
    value: Optional[Dict[str, Any]]
    found: bool


class HealthResponse(BaseModel):
    status: str
    version: str
    godot_ready: bool
    frame_loaded: bool


# Global state
app = FastAPI(title="Synmergia Frame Bridge", version="1.0.0")
godot_process: Optional[subprocess.Popen] = None
godot_ready = False
frame_loaded = False
scope_registry: Dict[str, Dict] = {}  # scope_id -> scope data
tree_registry: Dict[str, Dict] = {}   # tree_name -> {path -> value}


def start_godot_headless():
    """Start Godot headless process with frame scripts."""
    global godot_process, godot_ready
    
    # Path to frame scripts
    frame_root = Path("/frame/labs/multi-iso")
    if not frame_root.exists():
        # Try relative path for development
        frame_root = Path(__file__).parent.parent.parent / "labs" / "multi-iso"
    
    # Create a minimal Godot project for frame
    project_dir = Path("/tmp/frame_project")
    project_dir.mkdir(exist_ok=True)
    
    # Write project.godot
    project_content = """[application]
config/name="SynmergiaFrame"
run/main_scene=""

[autoload]

[input]
"""
    (project_dir / "project.godot").write_text(project_content)
    
    # Copy frame scripts to project
    import shutil
    dest = project_dir / "frame"
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(frame_root, dest)
    
    # Create frame entry point
    entry_point = project_dir / "frame_entry.gd"
    entry_point.write_text(f'''
extends SceneTree

var _frame_initialized = false
var _http_server = null

func _init():
    print("Frame entry point initialized")

func _ready():
    # Load all frame primitives
    _load_frame_primitives()
    _start_http_server()
    _frame_initialized = true
    print("FRAME_READY")

func _load_frame_primitives():
    # Preload all frame classes
    preload("res://frame/kv/t3.gd")
    preload("res://frame/kv/state_tree.gd")
    preload("res://frame/kv/seed_chain.gd")
    preload("res://frame/kv/definition_tree.gd")
    preload("res://frame/kv/lru_cache.gd")
    preload("res://frame/srv/scope.gd")
    preload("res://frame/srv/scope_engine.gd")
    preload("res://frame/srv/rules_engine.gd")
    preload("res://frame/srv/rules_schema.gd")
    preload("res://frame/srv/scope_hierarchy.gd")
    preload("res://frame/math/nsc9.gd")
    preload("res://frame/math/icosahedral.gd")
    preload("res://frame/db/snapshot_store.gd")
    print("Frame primitives loaded")

func _start_http_server():
    # Use Godot's built-in HTTP server
    _http_server = HTTPServer.new()
    _http_server.bind(8081, "*")
    _http_server.request_received.connect(_on_request)
    print("HTTP server started on port 8081")

func _on_request(request: HTTPRequest):
    var response = HTTPResponse.new()
    var body = request.get_body().get_string_from_utf8()
    var json_data = JSON.parse_string(body)
    
    if json_data.error != OK:
        response.status = 400
        response.body = '{{"error": "Invalid JSON"}}'.to_utf8_buffer()
        request.respond(response)
        return
    
    var data = json_data.result
    var result = {{}}
    
    match request.get_method():
        "POST":
            match request.get_url():
                "/evaluate":
                    result = _evaluate_rule(data)
                "/scope/create":
                    result = _create_scope(data)
                "/scope/flip":
                    result = _flip_scope(data)
                "/tree/insert":
                    result = _tree_insert(data)
                "/tree/get":
                    result = _tree_get(data)
                _:
                    response.status = 404
                    response.body = '{{"error": "Not found"}}'.to_utf8_buffer()
                    request.respond(response)
                    return
        "GET":
            match request.get_url():
                "/health":
                    result = {{"status": "healthy", "godot_ready": true, "frame_loaded": _frame_initialized}}
                "/ready":
                    result = {{"status": "ready", "godot_ready": true}}
                _:
                    response.status = 404
                    response.body = '{{"error": "Not found"}}'.to_utf8_buffer()
                    request.respond(response)
                    return
    
    response.status = 200
    response.headers = ["Content-Type: application/json"]
    response.body = JSON.stringify(result).to_utf8_buffer()
    request.respond(response)

func _evaluate_rule(data):
    var action = data.get("action", "")
    var context = data.get("context", {{}})
    var stack = data.get("stack", [])
    
    # Build scope stack from IDs
    var scope_stack = []
    for scope_id in stack:
        if _scope_registry.has(scope_id):
            scope_stack.append(_scope_registry[scope_id])
    
    var rules_engine = RulesEngine.new()
    # Register default rules if needed
    return rules_engine.evaluate(action, context, scope_stack)

func _create_scope(data):
    var name = data.get("name", "")
    var parent_id = data.get("parent")
    var environment = data.get("environment", "")
    var overrides = data.get("overrides", {{}})
    
    var parent = null
    if parent_id and _scope_registry.has(parent_id):
        parent = _scope_registry[parent_id]
    
    var scope = Scope.new(name, parent, environment, overrides)
    var scope_id = "scope_" + str(Time.get_ticks_msec())
    _scope_registry[scope_id] = scope
    
    return {{"scope_id": scope_id, "name": name, "parent": parent_id}}

func _flip_scope(data):
    var scope_id = data.get("scope_id", "")
    var rule_id = data.get("rule_id", "")
    var resolution = data.get("resolution", "")
    
    if not _scope_registry.has(scope_id):
        return {{"success": false, "error": "Scope not found"}}
    
    _scope_registry[scope_id].flip(rule_id, resolution)
    return {{"success": true, "scope_id": scope_id, "rule_id": rule_id, "resolution": resolution}}

func _tree_insert(data):
    var tree_name = data.get("tree_name", "")
    var path = data.get("path", "")
    var value = data.get("value", {{}})
    var schema_name = data.get("schema", "")
    
    # Get or create tree
    if not _tree_registry.has(tree_name):
        var t3 = T3.new()
        var schema = _get_schema(schema_name)
        _tree_registry[tree_name] = {{"tree": t3, "schema": schema}}
    
    var tree_data = _tree_registry[tree_name]
    var hash = tree_data["tree"].insert(path, value, tree_data["schema"])
    return {{"hash": hash.encode_hex(), "path": path}}

func _tree_get(data):
    var tree_name = data.get("tree_name", "")
    var path = data.get("path", "")
    
    if not _tree_registry.has(tree_name):
        return {{"value": null, "found": false}}
    
    var value = _tree_registry[tree_name]["tree"].get(path)
    return {{"value": value, "found": value != null}}

func _get_schema(name):
    match name:
        "rules": return RulesSchema.new()
        "seed": return SeedSchema.new()
        "state": return StateSchema.new()
        "definition": return DefinitionSchema.new()
        _: return RulesSchema.new()

# Registry storage
var _scope_registry: Dictionary = {{}}
var _tree_registry: Dictionary = {{}}
''')
    
    # Start Godot headless
    cmd = [
        "godot",
        "--headless",
        "--path", str(project_dir),
        "--script", "frame_entry.gd"
    ]
    
    print(f"Starting Godot headless: {' '.join(cmd)}")
    godot_process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1
    )
    
    # Wait for ready signal
    for line in godot_process.stdout:
        print(f"[Godot] {line.strip()}")
        if "FRAME_READY" in line:
            godot_ready = True
            break
        if "Error" in line or "error" in line.lower():
            print(f"Godot error: {line}")
    
    return godot_process


@app.on_event("startup")
async def startup_event():
    global godot_ready, frame_loaded
    
    # For v1, we'll use a simplified approach without full Godot
    # The frame logic will be implemented in Python for the bridge
    # Real Godot integration comes in Phase 4+
    
    print("Starting Frame Bridge v1 (Python implementation)")
    godot_ready = True
    frame_loaded = True
    
    # Initialize default scopes
    scope_registry["world"] = {
        "id": "world",
        "name": "world",
        "parent": None,
        "environment": "",
        "overrides": {}
    }
    scope_registry["shard"] = {
        "id": "shard",
        "name": "shard",
        "parent": "world",
        "environment": "",
        "overrides": {}
    }
    scope_registry["instance"] = {
        "id": "instance",
        "name": "instance",
        "parent": "shard",
        "environment": "",
        "overrides": {}
    }


@app.on_event("shutdown")
async def shutdown_event():
    global godot_process
    if godot_process:
        godot_process.terminate()
        try:
            godot_process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            godot_process.kill()


# API Endpoints
@app.get("/health", response_model=HealthResponse)
async def health():
    return HealthResponse(
        status="healthy",
        version="1.0.0",
        godot_ready=godot_ready,
        frame_loaded=frame_loaded
    )


@app.get("/ready")
async def ready():
    return {"status": "ready", "godot_ready": godot_ready}


@app.post("/evaluate", response_model=EvaluateResponse)
async def evaluate_rule(req: EvaluateRequest):
    """Evaluate a rule using the RulesEngine."""
    # Build scope stack from scope IDs
    scope_stack = []
    for scope_id in req.stack:
        if scope_id in scope_registry:
            scope_stack.append(scope_registry[scope_id])
    
    # Simple rule evaluation logic (Python port of RulesEngine)
    # In v1, we implement core logic here; full Godot integration later
    result = evaluate_rule_python(req.action, req.context, scope_stack)
    return EvaluateResponse(**result)


@app.post("/scope/create", response_model=ScopeCreateResponse)
async def create_scope(req: ScopeCreateRequest):
    """Create a new scope in the hierarchy."""
    scope_id = f"scope_{int(time.time() * 1000)}"
    scope_data = {
        "id": scope_id,
        "name": req.name,
        "parent": req.parent,
        "environment": req.environment,
        "overrides": req.overrides
    }
    scope_registry[scope_id] = scope_data
    return ScopeCreateResponse(scope_id=scope_id, name=req.name, parent=req.parent)


@app.post("/scope/flip", response_model=ScopeFlipResponse)
async def flip_scope(req: ScopeFlipRequest):
    """Flip a rule override on a scope."""
    if req.scope_id not in scope_registry:
        raise HTTPException(status_code=404, detail="Scope not found")
    
    scope_registry[req.scope_id]["overrides"][req.rule_id] = req.resolution
    return ScopeFlipResponse(
        success=True,
        scope_id=req.scope_id,
        rule_id=req.rule_id,
        resolution=req.resolution
    )


@app.post("/tree/insert", response_model=TreeInsertResponse)
async def tree_insert(req: TreeInsertRequest):
    """Insert a value into a T3 tree."""
    if req.tree_name not in tree_registry:
        tree_registry[req.tree_name] = {}
    
    # Simple hash for v1
    import hashlib
    content = json.dumps(req.value, sort_keys=True)
    hash_val = hashlib.sha256(f"{req.path}{content}".encode()).hexdigest()[:64]
    
    tree_registry[req.tree_name][req.path] = req.value
    return TreeInsertResponse(hash=hash_val, path=req.path)


@app.post("/tree/get", response_model=TreeGetResponse)
async def tree_get(req: TreeGetRequest):
    """Get a value from a T3 tree."""
    if req.tree_name not in tree_registry:
        return TreeGetResponse(value=None, found=False)
    
    if req.path not in tree_registry[req.tree_name]:
        return TreeGetResponse(value=None, found=False)
    
    return TreeGetResponse(value=tree_registry[req.tree_name][req.path], found=True)


# Python implementation of RulesEngine evaluation (v1 bridge)
RESOLUTION_TOP_WINS = "TOP_WINS"
RESOLUTION_BOTTOM_WINS = "BOTTOM_WINS"
RESOLUTION_PREDICATE_GATED = "PREDICATE_GATED"
RESOLUTION_ALL_WINS_WITH_EFFECT = "ALL_WINS_WITH_EFFECT"

# Default rules registered
DEFAULT_RULES = {
    "rate_limit": {"resolution": RESOLUTION_TOP_WINS, "default_allow": True},
    "connection_quality": {"resolution": RESOLUTION_TOP_WINS, "default_allow": True},
    "throttle_action": {"resolution": RESOLUTION_TOP_WINS, "default_allow": False},
    "teleport_check": {"resolution": RESOLUTION_TOP_WINS, "default_allow": False},
    "speed_hack_check": {"resolution": RESOLUTION_TOP_WINS, "default_allow": False},
    "item_duplication_check": {"resolution": RESOLUTION_TOP_WINS, "default_allow": False},
    "input_anomaly_check": {"resolution": RESOLUTION_TOP_WINS, "default_allow": False},
    "permission_check": {"resolution": RESOLUTION_BOTTOM_WINS, "default_allow": True},
    "restrict_player": {"resolution": RESOLUTION_TOP_WINS, "default_allow": True},
    "ip_can_connect": {"resolution": RESOLUTION_BOTTOM_WINS, "default_allow": True},
    "failed_attempt_check": {"resolution": RESOLUTION_TOP_WINS, "default_allow": False},
    "block_ip": {"resolution": RESOLUTION_TOP_WINS, "default_allow": True},
    "ban_player": {"resolution": RESOLUTION_BOTTOM_WINS, "default_allow": False},
    "connection_limit_check": {"resolution": RESOLUTION_TOP_WINS, "default_allow": False},
    "spam_response": {"resolution": RESOLUTION_ALL_WINS_WITH_EFFECT, "default_allow": True},
    "speedhack_response": {"resolution": RESOLUTION_TOP_WINS, "default_allow": False},
    "teleport_hack_response": {"resolution": RESOLUTION_TOP_WINS, "default_allow": False},
    "item_duplication_response": {"resolution": RESOLUTION_TOP_WINS, "default_allow": False},
    "auto_kick_threshold": {"resolution": RESOLUTION_TOP_WINS, "default_allow": False},
}


def evaluate_rule_python(action: str, context: Dict, stack: List[Dict]) -> Dict:
    """Evaluate a rule using Python port of RulesEngine logic."""
    rule = DEFAULT_RULES.get(action)
    if not rule:
        return {
            "allow": False,
            "reason": f"no rule registered for action: {action}",
            "modified_action": context.copy(),
            "applied_rules": []
        }
    
    resolution = rule["resolution"]
    default_allow = rule["default_allow"]
    
    # Check scope overrides (innermost first for TOP_WINS)
    applied_rules = []
    allow = None
    
    if resolution == RESOLUTION_TOP_WINS:
        # Innermost scope wins
        for scope in stack:
            if action in scope.get("overrides", {}):
                override = scope["overrides"][action]
                applied_rules.append(override)
                if override in [RESOLUTION_TOP_WINS, RESOLUTION_BOTTOM_WINS, RESOLUTION_ALL_WINS_WITH_EFFECT]:
                    allow = True
                elif override == RESOLUTION_PREDICATE_GATED:
                    allow = False
                break
        if allow is None:
            allow = default_allow
        reason = f"TOP_WINS: {'innermost scope' if applied_rules else 'default'}"
    
    elif resolution == RESOLUTION_BOTTOM_WINS:
        # Outermost scope wins
        for scope in reversed(stack):
            if action in scope.get("overrides", {}):
                override = scope["overrides"][action]
                applied_rules.append(override)
                if override in [RESOLUTION_TOP_WINS, RESOLUTION_BOTTOM_WINS, RESOLUTION_ALL_WINS_WITH_EFFECT]:
                    allow = True
                elif override == RESOLUTION_PREDICATE_GATED:
                    allow = False
                break
        if allow is None:
            allow = default_allow
        reason = f"BOTTOM_WINS: {'outermost scope' if applied_rules else 'default'}"
    
    elif resolution == RESOLUTION_ALL_WINS_WITH_EFFECT:
        any_allow = False
        any_deny = False
        for scope in stack:
            if action in scope.get("overrides", {}):
                override = scope["overrides"][action]
                applied_rules.append(override)
                if override in [RESOLUTION_TOP_WINS, RESOLUTION_BOTTOM_WINS, RESOLUTION_ALL_WINS_WITH_EFFECT]:
                    any_allow = True
                elif override == RESOLUTION_PREDICATE_GATED:
                    any_deny = True
            else:
                applied_rules.append("default")
                any_allow = True
        allow = any_allow and not any_deny
        reason = f"ALL_WINS_WITH_EFFECT: {len(applied_rules)} rules applied"
    
    else:
        allow = default_allow
        reason = f"UNKNOWN_RESOLUTION: fallback to default_allow"
    
    return {
        "allow": allow,
        "reason": reason,
        "modified_action": context.copy(),
        "applied_rules": applied_rules
    }


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)