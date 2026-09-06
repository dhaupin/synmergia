# labs/ — Frame & Design Documentation

**The labs directory contains:**
1. **Frame primitives** — the multi-iso frame work (extractable to its own project)
2. **Design documentation** — PRD and world-building specs

See the [PRD](./prd.md) for the product spec and the world-building docs for technical architecture.

> **Deployment:** For Docker deployment and operations, see [`DEPLOY.md`](../DEPLOY.md) at the project root.

## Directory Structure

```
labs/
├── README.md                    # this file
├── multi-iso/                   # the frame primitives
│   ├── math/                   # NSC-9, icosahedral, quasicrystal
│   ├── kv/                     # LRU, content_hash, state_tree
│   ├── srv/                    # markov, predictor, composite_table, lod_manager, axis
│   ├── db/                     # snapshot_store, migrations
│   └── tests/                  # cross-cutting tests
├── prd.md                      # product requirements document
├── prd-*.md                    # PRD specs (T3 substrate, scope engine, etc)
├── world-building*.md           # world + architecture documentation
├── jolt-playground/            # Jolt Physics benchmark
└── polyglot-ffi/               # Polyglot FFI exploration
```

## Key Documents

| Document | Purpose |
|----------|---------|
| [`prd.md`](./prd.md) | Product requirements — what we're building |
| [`world-building.md`](./world-building.md) | World + network + persistence design |
| [`world-building-arch.md`](./world-building-arch.md) | Systems architecture — how it fits together |
| [`world-building-tick.md`](./world-building-tick.md) | Server tick model |
| [`world-building-risks.md`](./world-building-risks.md) | Risks and mitigations |
| [`DEPLOY.md`](../DEPLOY.md) | Docker deployment and operations |

## The Frame

The **frame** is what can be extracted to its own project:

1. **T3 substrate** (`multi-iso/kv/t3.gd`) — content-hash tree primitive
2. **Scope engine** (`multi-iso/srv/scope.gd`) — hierarchy walker, scope stack
3. **Rules engine** (`multi-iso/srv/rules_engine.gd`) — behavior evaluator
4. **Spatial layer** (`multi-iso/math/`) — NSC-9, icosahedral, quasicrystal math
5. **LRU cache** (`multi-iso/kv/lru_cache.gd`) — generic LRU
6. **Snapshot store** (`multi-iso/db/snapshot_store.gd`) — Postgres persistence

See [PRD §12](./prd.md#12-technical-architecture) for full frame architecture.
