# `labs/`

Working directory for design, frame staging, and experimental
code. Shipped game lives in `game/`.

Not a source of truth. For product spec read `prd.md`; for
systems architecture read `world-building-arch.md`; for
current code state read `m3-initial-world-audit.md`.

## What's recorded here

| What | Where | Status |
|------|-------|--------|
| Product spec | `prd.md` | Living |
| Database + persistence PRD | `prd-db.md` | Authoritative for adapter layer |
| Per-component specs | `prd-*.md` (Phase 2 deliverables) | Living, churn-y. List in `prd.md` sec. 16 Phase 2. |
- [`prd-geometry.md`](./prd-geometry.md) — Vant fragmenter / geometric addressing
| Systems architecture | `world-building-arch.md` | Authoritative for frame design |
| World / netcode / persistence | `world-building.md` | Living |
| Tick model | `world-building-tick.md` | Living |
| Risk register, decisions, numbers | `world-building-risks.md` | Living |
| Experimental angles | `world-building-research.md` | Research notes |
| Spherical-planet specifics | `world-building-spherical.md` | Living |
| Code state snapshot | `m3-initial-world-audit.md` | Reference |
| Session continuity | `TASKS.md` | Living; for cross-session handoff |
| Frame primitives | `../game/core/frame/` | Consolidated from legacy multi-iso; NSC-9, T3, Scope, Rules, etc. |
| Physics swap-in | `jolt-playground/` | Design only |
| Polyglot FFI | `polyglot-ffi/` | Design only |
| Archive | `archive/` | Old, do not trust without checking |

## Adapter layer status

The adapter layer is the typed contract between game services
and storage backends (Postgres / Redis / in-memory). Spec is
in `prd-db.md` sec. 5-10; code lives at `game/adapters/`.
As of 2026-09-07:

- Three base interfaces (`PersistenceStore`, `CacheStore`,
  `MemoryStore`) with global `class_name`
- In-memory impls complete (`MemoryPersistenceStore`,
  `MemoryCacheStore`, `MemoryStore`); the persistence one
  supports a useful SQL subset for tests + dev
- HTTP-backed `PostgresStore` and `RedisStore` are complete
  against their wire protocols; both `pg-bridge` and
  `redis-bridge` sidecars are built and tested
- `AdapterRegistry` (autoload) maps store names to instances
- `BackendFactory` (autoload) reads env, walks the manifest
  of 60+ named stores, registers each with the right backend
- 5 test files at `game/tests/adapters/`
- First migration `V20260907_001__init_accounts.sql` exists and
  is tested; schemas 3.1–3.2 LOCKED 2026-09-07

See `game/adapters/README.md` for the developer guide.

## Conventions

Match `AGENTS.md`: tabs for GDScript, no autoload /
`class_name` / `GameManager` dependency on frame primitives,
standard Godot autoloads in `game/`, `prd-*.md` format is User
Stories / FR / Non-Goals / DoD.

Deployment: see `../DEPLOY.md`.