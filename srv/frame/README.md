# Synmergia Frame Bridge

HTTP bridge service for the Synmergia frame (T3 substrate + Scope Engine + Rules Engine).

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  synmergia (Godot Game Server)                              │
│  - QoSService, SecurityService, AppFirewall, AutoResponse  │
│  - FrameClient (GDScript HTTP client)                       │
│                    ↓ HTTP/REST                              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  frame-bridge (Python FastAPI)                              │
│  - RulesEngine evaluation                                   │
│  - Scope hierarchy management                               │
│  - T3 tree operations (seed, state, rules, definition)     │
│  - Godot headless integration (Phase 4+)                   │
│                    ↓                                        │
└─────────────────────────────────────────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
        PostgreSQL                    Redis
     (manifest, persisted)         (cache, sessions)
```

## API Endpoints

### Health & Readiness
- `GET /health` - Service health status
- `GET /ready` - Readiness probe

### RulesEngine
- `POST /evaluate` - Evaluate a rule
  ```json
  {
    "action": "rate_limit",
    "context": {"player_id": "p1", "action_rate": 15.0},
    "stack": ["player_scope_1", "instance", "shard", "world"]
  }
  ```
  Response:
  ```json
  {
    "allow": true,
    "reason": "TOP_WINNS: default",
    "modified_action": {...},
    "applied_rules": []
  }
  ```

### Scope Management
- `POST /scope/create` - Create a new scope
  ```json
  {
    "name": "player_123",
    "parent": "instance",
    "environment": "",
    "overrides": {"rate_limit": "BOTTOM_WINS"}
  }
  ```
- `POST /scope/flip` - Flip a rule override on a scope
  ```json
  {
    "scope_id": "scope_abc",
    "rule_id": "rate_limit",
    "resolution": "BOTTOM_WINS"
  }
  ```

### T3 Tree Operations
- `POST /tree/insert` - Insert value into tree
  ```json
  {
    "tree_name": "rules",
    "path": "/shard_1/zone_5/rate_limit",
    "value": {"rule_id": "rate_limit", "resolution": "TOP_WINS", "default_allow": true},
    "schema": "rules"
  }
  ```
- `POST /tree/get` - Get value from tree
  ```json
  {
    "tree_name": "rules",
    "path": "/shard_1/zone_5/rate_limit"
  }
  ```

## Running Locally

### With Docker Compose
```bash
cd srv/frame
docker-compose up --build
```

### Python Only (Development)
```bash
cd srv/frame
pip install -r requirements.txt
python frame_server.py
```

Server starts on `http://localhost:8080`

## Integration with Game Services

Game services use `FrameClient` (GDScript) to communicate with the frame bridge:

```gdscript
var frame_client = FrameClient.new("http://frame:8080")

# Evaluate a rule
var result = frame_client.evaluate_rule("rate_limit", {
    "player_id": player_id,
    "action_rate": action_rate,
    "quality": quality
}, scope_stack)

if result.allow:
    # Action allowed
    pass
else:
    # Action denied/throttled
    throttle_player(player_id, result.reason)
```

### Circuit Breaker & Fallback

`FrameClient` implements a circuit breaker pattern:
- **CLOSED**: Normal operation, requests go to frame bridge
- **OPEN**: Frame bridge failing, requests use local RulesEngine fallback
- **HALF_OPEN**: Testing if frame bridge recovered

Local fallback uses the same RulesEngine from `labs/multi-iso/srv/rules_engine.gd`.

## Frame Primitives (from labs/multi-iso/)

The frame bridge exposes these primitives:

| Primitive | Location | Purpose |
|-----------|----------|---------|
| T3 | `labs/multi-iso/kv/t3.gd` | Content-hash Merkle-Patricia trie |
| StateTree | `labs/multi-iso/kv/state_tree.gd` | Runtime state tree |
| SeedChain | `labs/multi-iso/kv/seed_chain.gd` | Recursive seed derivation |
| DefinitionTree | `labs/multi-iso/kv/definition_tree.gd` | Static data catalog |
| LRUCache | `labs/multi-iso/kv/lru_cache.gd` | In-memory caching |
| SnapshotStore | `labs/multi-iso/db/snapshot_store.gd` | State snapshotting |
| Scope | `labs/multi-iso/srv/scope.gd` | Hierarchy node with overrides |
| ScopeEngine | `labs/multi-iso/srv/scope_engine.gd` | Hierarchy walker |
| RulesEngine | `labs/multi-iso/srv/rules_engine.gd` | Generic rule evaluator |
| RulesSchema | `labs/multi-iso/srv/rules_schema.gd` | Rule payload schema |
| NSC-9 | `labs/multi-iso/math/nsc9.gd` | Spatial encoding |
| Icosahedral | `labs/multi-iso/math/icosahedral.gd` | Spatial projection |

## Phase Roadmap

- **Phase 1** ✅: Frame primitives in `labs/multi-iso/`, used directly by game services
- **Phase 2** 🔄: HTTP bridge (this container) - game services call via FrameClient
- **Phase 3**: Coordinator extract - cross-shard coordination
- **Phase 4**: FFI/Polyglot - direct Godot integration, Rust GDExtension

## Configuration

Environment variables:
- `PORT` - HTTP port (default: 8080)
- `LOG_LEVEL` - Log level (default: INFO)
- `POSTGRES_HOST` - PostgreSQL host
- `POSTGRES_PORT` - PostgreSQL port
- `REDIS_HOST` - Redis host
- `REDIS_PORT` - Redis port

## Testing

```bash
# Health check
curl http://localhost:8080/health

# Evaluate rule
curl -X POST http://localhost:8080/evaluate \
  -H "Content-Type: application/json" \
  -d '{"action": "rate_limit", "context": {"player_id": "test", "action_rate": 10}, "stack": []}'

# Create scope
curl -X POST http://localhost:8080/scope/create \
  -H "Content-Type: application/json" \
  -d '{"name": "test_scope", "parent": "world"}'
```