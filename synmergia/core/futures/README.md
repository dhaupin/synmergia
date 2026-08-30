# core/futures — Independent Primitives

**This directory is the staging area for the multi-iso frame.**

The full design rationale is in
[`docs/architecture/futures-organization.md`](../../../../docs/architecture/futures-organization.md).
Read that first.

## The rule in one sentence

**Primitives live here. Services consume them. When the frame
extracts, this directory IS the public API.**

## The layout (planned, not yet filled)

```
core/futures/
├── math/        # NSC-9, icosahedral, quasicrystal
├── kv/          # LRU cache, content hash, state tree
├── srv/         # Markov, predictor, composite table, LOD manager, axes
├── db/          # Snapshot store, query builders, migrations
└── README.md    # this file
```

## The principles (full list in the design doc)

1. Each primitive is its own `.gd` file. No `utils.gd` mega-file.
2. Tests are co-located: `math/nsc9.gd` has `math/test_nsc9.gd`.
3. No autoload, no `class_name` for primitives. Liftable.
4. No GameManager / EventBus / autoload dependencies. Pure.
5. New code goes here first. Services consume from here.

## What goes where (mapping)

| Primitive | Lands in | Session |
|-----------|----------|---------|
| NSC-9 encode/decode | `math/nsc9.gd` | B-1 |
| Icosahedral projection | `math/icosahedral.gd` | B-1 |
| Quasicrystal paths | `math/quasicrystal.gd` | B-1 |
| LRU cache | `kv/lru_cache.gd` | B-6 |
| Content hash (SHA-256) | `kv/content_hash.gd` | A-3 |
| State tree | `kv/state_tree.gd` | A-3 |
| Markov chain | `srv/markov.gd` | B-8 |
| Predictor | `srv/predictor.gd` | B-8 |
| Composite table | `srv/composite_table.gd` | B-6 |
| LOD manager | `srv/lod_manager.gd` | B-7 |
| Axis base class | `srv/axis.gd` | B-2 |
| Axis registry | `srv/axis_registry.gd` | B-4 |
| Snapshot store | `db/snapshot_store.gd` | A-3 |
| Migrations | `db/migrations/` | A-3 |

## Why "futures"?

The user named this. It's the area where future primitives live —
not yet integrated, but being developed as independent tools.
When the frame extracts, this directory moves to a new repo.

## Status

This directory is **planned, not yet populated**. The design is in
`docs/architecture/futures-organization.md`. Sessions A-3, B-1, B-6,
B-7, B-8, B-9 will populate the subdirectories.

When you start one of those sessions, create the subdirectory +
the file + the test. Follow the rules above.
