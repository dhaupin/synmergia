# labs/ — Experimental Work, Aside from the Game

**The labs directory is for experiments, prototypes, and the
multi-iso frame work. It lives at the repo root, not inside the
Godot project, so it doesn't taint the stable game with
half-baked code.**

The full design rationale is in
[`docs/architecture/labs-organization.md`](../docs/architecture/labs-organization.md).
Read that first.

## The rule in one sentence

**Primitives live here. The game consumes them. When the frame
extracts, this directory IS the public API of the new project.**

## Why "labs"?

The user named it. "Labs" implies experimental / aside work, like
Chrome Labs or Mozilla Labs. It's separate from the stable game
so maintainers can work freely without worrying about breaking
the Godot project. Stuff that's not ready for the game goes
here. Stuff that graduates moves into the game.

## The layout (planned, not yet filled)

```
labs/
├── README.md                    # this file
├── multi-iso/                   # the multi-iso frame work (Sessions B-1 through B-8)
│   ├── math/                    # NSC-9, icosahedral, quasicrystal
│   ├── kv/                      # LRU, content_hash, state_tree
│   ├── srv/                     # markov, predictor, composite_table, lod_manager, axis
│   ├── db/                      # snapshot_store, migrations
│   └── tests/                   # cross-cutting tests
├── jolt-playground/             # Jolt Physics swap-in benchmark (Phase 5 decision)
├── polyglot-ffi/                # Polyglot FFI, lifted from vant
│   ├── compute.gd               # the registry
│   ├── connectors/              # base + language-specific
│   └── julia-runtime/           # Julia-side scripts (HTTP server)
├── prd.md                       # the modernized product spec
└── (future labs as needed)
```

The `multi-iso/` subdirectory is the first lab. Future labs can
go alongside it (`labs/vr-prototype/`, `labs/audio-engine/`, etc).

Two non-multi-iso labs are already drafted:

- [`jolt-playground/`](./jolt-playground/) — Jolt Physics swap-in benchmark
- [`polyglot-ffi/`](./polyglot-ffi/) — Polyglot FFI, lifted from vant, with [`julia-runtime/`](./polyglot-ffi/julia-runtime/) as the first implementation

## The principles (full list in the design doc)

1. Each primitive is its own `.gd` file. No `utils.gd` mega-file.
2. Tests are co-located: `math/nsc9.gd` has `math/test_nsc9.gd`.
3. No autoload, no `class_name` for primitives. Liftable.
4. No GameManager / EventBus / autoload dependencies. Pure.
5. New code goes here first. The game consumes from here.
6. The frame can ship in **three tiers of computation**:
   - **GDScript** for game logic (default)
   - **Julia** for vector math (via the polyglot FFI)
   - **C++ / GDExtension** for the absolute hot path (Jolt lives here)

## What goes where (mapping)

| Primitive | Lands in | Session |
|-----------|----------|---------|
| NSC-9 encode/decode | `labs/multi-iso/math/nsc9.gd` | B-1 |
| Icosahedral projection | `labs/multi-iso/math/icosahedral.gd` | B-1 |
| Quasicrystal paths | `labs/multi-iso/math/quasicrystal.gd` | B-1 |
| LRU cache | `labs/multi-iso/kv/lru_cache.gd` | B-6 |
| Content hash (SHA-256) | `labs/multi-iso/kv/content_hash.gd` | A-3 |
| State tree | `labs/multi-iso/kv/state_tree.gd` | A-3 |
| Markov chain | `labs/multi-iso/srv/markov.gd` | B-8 |
| Predictor | `labs/multi-iso/srv/predictor.gd` | B-8 |
| Composite table | `labs/multi-iso/srv/composite_table.gd` | B-6 |
| LOD manager | `labs/multi-iso/srv/lod_manager.gd` | B-7 |
| Axis base class | `labs/multi-iso/srv/axis.gd` | B-2 |
| Axis registry | `labs/multi-iso/srv/axis_registry.gd` | B-4 |
| Snapshot store | `labs/multi-iso/db/snapshot_store.gd` | A-3 |
| Migrations | `labs/multi-iso/db/migrations/` | A-3 |

## Status

This directory is **planned, not yet populated**. The design is in
[`docs/architecture/labs-organization.md`](../docs/architecture/labs-organization.md).
Sessions A-3, B-1, B-6, B-7, B-8, B-9 will populate the
subdirectories.

When you start one of those sessions, create the subdirectory +
the file + the test. Follow the rules above.

## When the frame extracts

When the multi-iso orchestrator is ready to be published as its
own project (alongside vant), the `labs/multi-iso/` directory
moves to a new repo. Synmergia becomes an example consumer. The
lab graduates to a frame.
