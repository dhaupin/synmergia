---
permalink: /build/frame/
layout: default
title: The Frame
description: The reusable core in game/core/frame - what is real today, what stays game-specific, and why there is no install command yet.
---

# The frame is real. The package is not.

Synmergia is two things: a working world, and a reusable core. The core lives in [`game/core/frame/`](https://github.com/dhaupin/synmergia/tree/main/game/core/frame). It is MIT-licensed, covered by co-located tests, and used by the game every day.

It is not yet a package. There is no registry name, version, install command, or compatibility promise to give you. That is a distribution gap, not a hidden feature.

> **Status (15 November 2026):** in-repo. Copying the source is the only way to use the frame in another project today. A standalone package is planned; this page gets the install path when the package exists.

## What is in the frame

The frame is the part that does not know Synmergia's classes, quests, or factions. It provides the substrate a world can be built on.

| Layer | Where | What it gives you |
|---|---|---|
| **State tree** | `kv/t3.gd` | A content-hash tree with deterministic insert, diff, apply, and snapshots |
| **Seed derivation** | `kv/seed_chain.gd` | Hierarchical deterministic seeds: the same input produces the same world |
| **Typed trees** | `kv/definition_tree.gd`, `kv/memory_tree.gd`, `kv/social_tree.gd`, `kv/state_tree.gd` | Conventions for building typed trees over T3 |
| **Scopes and rules** | `srv/scope.gd`, `srv/scope_engine.gd`, `srv/rules_engine.gd` | Hierarchy walking, scope overrides, and action decisions |
| **World math** | `math/` | Icosahedral and spherical coordinates, NSC-9, Penrose and pentagrid, world shape |
| **Spatial geometry** | `geometry/` | Fragmenting a sphere into workable cells, chunks, and prop chunks |
| **Snapshots and progress** | `db/snapshot_store.gd`, `bridge/progress_bridge.gd` | A storage seam and a progress-event seam |
| **Schema bases** | `schemas/seed_schema.gd`, `schemas/state_schema.gd` | Canonical encoding and validation hooks |

Most directories carry co-located `test_*.gd` files. Those tests are the executable spec for the primitive next to them.

The frame is **not** [gamestruct]({{ '/access/gamestruct/' | relative_url }}). gamestruct carries the human and agent access contract. The frame carries world state, scopes, rules, and geometry. They meet at the door, not in the package.

## What stays with the game

The frame is a core, not a game. These layers are Synmergia's, and a different world replaces them:

- The canonical trees and declarations under `game/data/roots/` and `game/data/`.
- The game services under `game/core/services/`: combat, classes, quests, guilds, economy, and the rest.
- The UI and scenes under `game/ui/` and `game/scenes/`.
- The adapter wiring that chooses a persistence or cache backend.
- The Codex, lore, and rules content on the website.

That split is deliberate. Copying the frame does not give you Synmergia; it gives you primitives. You still write your own schemas, trees, services, and surface.

## The rules that make extraction possible

- **Path-loaded, not autoloaded.** Most primitives are loaded with `preload("res://core/frame/...")`; a few value types opt into `class_name`. There is no global service graph to boot before using T3.
- **Pure where it matters.** The math and geometry layer has no persistence, no scene-tree requirement, and no `GameManager` dependency.
- **The caller supplies meaning.** The frame takes schemas, scopes, and data from the game. It does not read the game's canon by itself.
- **Tests travel with the code.** Most primitives have a co-located test. Some schema tests still load `res://data`, so a standalone package would still need a test-harness pass.
- **`main` is not a version.** Until a release exists, pin a commit.

## Use it inside this repository

```gdscript
const T3 = preload("res://core/frame/kv/t3.gd")
const RulesEngine = preload("res://core/frame/srv/rules_engine.gd")

var tree := T3.new()
var rules := RulesEngine.new()
```

The one Godot runner can run a co-located test by name, or every `test_*.gd` with `--all`:

```bash
sh ./scripts/godot_test_runner.sh test_t3
sh ./scripts/godot_test_runner.sh --all
```

The current project targets Godot 4.7.2. A different engine version is an untested port, not a supported install.

## Use it from another project today

Copy `game/core/frame/` and its co-located tests, keep the MIT notice, and rewrite the `res://core/frame/...` preload paths for wherever you place the directory. That is a source copy, not a supported dependency.

Do not copy `game/data/` or `game/core/services/` and call the result the frame. The useful boundary is the primitives, not the MMORPG.

## What an install command would promise

A package needs more than a tarball. Before this page can carry an install command, the frame needs:

- a published artifact and a stable package name;
- a version and a changelog;
- a supported Godot range;
- a test command that runs outside this repository;
- a licence and notice that travel with the artifact.

Those are the promises an install command makes. Until they exist, a package badge would be marketing, not a contract.

## Where to go next

- [Frame architecture](https://github.com/dhaupin/synmergia/blob/main/labs/world-building-arch.md) - the long-form design reference.
- [Testing]({{ '/build/testing/' | relative_url }}) - the runner, CI, and the local loop.
- [Local setup]({{ '/build/local-setup/' | relative_url }}) - Godot, Node, Bun, and the repository scripts.
- [Open an issue](https://github.com/dhaupin/synmergia/issues) if you want to build on the frame or help define the package boundary.
