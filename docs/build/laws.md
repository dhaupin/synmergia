---
permalink: /build/laws/
layout: default
title: The Laws
description: The five laws that keep Synmergia's systems fluid instead of accruing copies, and where each one is enforced.
---

# The laws

Synmergia is not a pile of single-purpose static systems. It is a **game OS**: a lattice of **services** (`game/core/services/*.gd`, autoloaded) that read **canonical definitions** (schemas in `game/core/schemas/*.gd`, data in `game/data/**/*.tres`).

Five laws keep that lattice fluid instead of accruing copies. They are written down in full in [`AGENTS.md`](https://github.com/dhaupin/synmergia/blob/main/AGENTS.md) under "The game OS". This page is the short version, with the gate that enforces each one; AGENTS.md is the authority.

## The five laws

| Law | What it means | Enforced by |
|---|---|---|
| **1. Define from schema + data, not from code** | A system's shape is an `@export` surface in `core/schemas/`; its values are `.tres`. A service *consumes* a definition, it does not hardcode one. A `match`/`if` ladder of literals is a schema asking to exist. | `test_data_naming_lint.gd` |
| **2. One source per concept** | Canonicalize, never re-inline. When you need a value another system owns, READ it (`GameTier.color(name)`, `StatId.is_valid(key)`). If no single owner exists, make one — do not add a second copy. | `test_skill_tier_parity.gd`, `test_data_naming_lint.gd` |
| **3. Services are shared, not per-site** | Behavior every caller needs is one service the callers route through. The second call site is the signal to extract a helper, not an exception. | `test_crit_system.gd` |
| **4. Players, enemies, agents, NPCs are the same bodies** | An enemy uses skills, crit, and cooldowns through the SAME `CombatComponent` / hit table / `StatId` math a player does. `EnemyData.apply_stats_to(...)` is the one stat-copy path. Author a behavior once, on the shared body. | `test_crit_system.gd` (asserts on the SPAWNED body, not the template) |
| **5. Bands and tiers are the FIVE rungs, always** | common / rare / epic / legendary / mythic, from `GameTier`. A local 4-rung ladder or a private palette is drift. | `test_skill_tier_parity.gd` |

## The core / data boundary

`game/core/` owns **how**: schemas (`@export` shape + validation), services, loaders, algorithms, lifecycle. `game/data/` owns **what**: `.tres` values, ids, prices, stat lines, spawn tables, asset paths, catalogs, and the model/art/brand/texture/shader assets themselves.

The `@export` surface stays in core; the record that fills it moves to `game/data`. A service resolves the record through `DataService`; it does not keep a literal copy. **If a designer can change the value without changing behavior, it is data.** The authoring contract is [`labs/data-authoring-baseline.md`](https://github.com/dhaupin/synmergia/blob/main/labs/data-authoring-baseline.md).

## Vocabulary is canonical too

Two vocabularies carry the law into code:

- **`StatId`** — every stat key is spelled by `StatId`, never hand-copied. `StatId.is_valid(key)` is the check; `StatId.crit_axis_for(skill)` picks a crit axis (magical → INT, heal → WIS, else agility).
- **`GameTier`** — the five rungs, plus `GameTier.color(name)`. (`GameTier` is the current name; `SkillTier` is the retired one.)

## Identity verbs are canonical across classes

A class's FIRST `starting_skills` entry carries its family identity verb, read off `role` (TANK=control, BENDER=teleport, HEALER=heal, DD/MAGE/ROGUE=damage). The verb is a property of the **lane**, authored once and shared by every class in it — not re-invented per class. Enforced by `test_data_naming_lint.gd`.

## Where to read the full text

- [`AGENTS.md`](https://github.com/dhaupin/synmergia/blob/main/AGENTS.md) — the agent-facing reference; the five laws and the receipts.
- [`CONTRIBUTING.md`](https://github.com/dhaupin/synmergia/blob/main/CONTRIBUTING.md) — the contributor-facing short version and the PR flow.
- [`labs/data-authoring-baseline.md`](https://github.com/dhaupin/synmergia/blob/main/labs/data-authoring-baseline.md) — the data authoring contract.
- [`labs/data-engine-separation.md`](https://github.com/dhaupin/synmergia/blob/main/labs/data-engine-separation.md) — the running ledger of what has moved from engine to data.

> The rule for this repository is **one canonical home per fact**. This page summarizes and points; it does not become a second copy. When a law changes, it changes in `AGENTS.md` first.
