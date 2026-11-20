# Tresridge — the `.tres` Spine

> **Status:** ACTIVE (map; the thing it maps already exists and runs every build).
> **Author:** Web Architecture Team
> **Measured against:** `staging` @ 2026-11-17 — 67 schemas, 55 families,
> 1097 records, 344 inferred relation edges.

**Tresridge is the map of the content spine: how a `.tres` is authored, validated,
loaded, published, and rendered — and where each law and gate lives.**

It is a *ridge*: the raised line that connects the peaks. It owns no content and no
behavior. Every fact below is a citation to the file that owns it.

### What this doc is NOT

- **Not a restatement of the five laws.** Those are [`AGENTS.md`](../AGENTS.md) §"The
  game OS" (laws 1-5). Tresridge cites them.
- **Not a restatement of authoring rules.** Those are
  [`data-authoring-baseline.md`](./data-authoring-baseline.md) §2 (id/filename) and §4
  (cross-references). Tresridge cites them.
- **Not a new struct, not a forge.** `gamestruct` is the a11y/agents lane; the Forge is
  the blacksmith's in-world station (`forge_balance_data.gd`, `prd-story.md`). Neither
  is this. Tresridge is the spine those systems read.

The test for this doc: **if it can be derived from another file, it must be a link to
that file.** Anything stated twice here is a bug in this doc (law 2 — one source per
concept).

---

## 1. The peaks — layer inventory

Seven layers. Each row names the artifact, what it owns, and the gate that guards it.

| # | Layer | Artifact (owner) | Owns | Gate |
|---|---|---|---|---|
| 1 | **Schema** | `game/core/schemas/*.gd` (67 with `class_name`) | the `@export` shape | `tsc` n/a; shape checked by lint |
| 2 | **Data** | `game/data/<family>/*.tres` (55 dirs, 1097 files) | the values | `test_data_naming_lint.gd`, `test_item_catalog.gd`, `test_content_ref_integrity.gd` |
| 3 | **Relations** | *implicit today* — see [`prd-data-graph.md`](./prd-data-graph.md) | which field points at which family | the same lint |
| 4 | **Runtime** | `game/core/services/data_service.gd` + consumers | loading records into memory | 214 `game/tests/test_*.gd` via `godot_test_runner.sh` |
| 5 | **Producer** | `scripts/sync_godot_data.ts` | the web payload + vocab | `npm run verify:codex` |
| 6 | **Payload** | `src/data/godot_data.json` (generated) | the frozen snapshot | `scripts/verify_codex.mjs` |
| 7 | **Presentation** | `src/pages/*.tsx`, `src/lib/codex.ts` | the public Codex + site | `tsc`, `prestruct-build.mjs` SEO audit |

Layers 1-3 are the engine's; 5-7 are the web's; layer 4 is the bridge. The boundary
between 3 and 5 is where the current hodgepodge lives.

---

## 2. The boundary contracts

Each edge in the spine has a contract. Break it and the failure is silent.

### 2.1 Schema → Data  *(layer 1 → 2)*

A `.tres` names its schema by script path and its class by `script_class`:

```
[gd_resource type="Resource" script_class="QuestData" load_steps=2 format=3]
[ext_resource type="Script" path="res://core/schemas/quest_data.gd" id="1"]
```

- The schema's `class_name` **must** match the `script_class` in the file.
- The id **must** equal the basename (`data-authoring-baseline.md` §2).
- **Contract:** a record is valid only if schema, class, id and filename agree.

### 2.2 Data → Producer  *(layer 2 → 5)*

`scripts/sync_godot_data.ts` walks `game/data/` and emits `src/data/godot_data.json`.

- **Discovery is by filesystem, not allowlist.** Any dir under `game/data/` with ≥1
  `.tres` becomes a payload category. (Was a hardcoded 37-name array until
  2026-11-17 — the drift this doc exists to prevent.)
- **Contract:** every `.tres` on disk appears in the payload. Guarded by the
  `nothing skipped` check in `verify_codex.mjs`.
- **Enums are read off the schemas**, never hand-copied (`GodotVocab` in the producer).
  This is law 2 applied at the web boundary.

### 2.3 Producer → Payload  *(layer 5 → 6)*

`src/data/godot_data.json` is **generated**. `data-authoring-baseline.md` §6: do not
hand-edit it, do not commit a local regeneration.

- **Contract:** the payload is a pure function of `game/data/` + `game/core/schemas/`.

### 2.4 Payload → Presentation  *(layer 6 → 7)*

`src/lib/codex.ts` `buildCodex()` reads the payload; `CodexPage.tsx` renders it.

- Entry ids **must be globally unique** — namespaced `family:id` (8 cross-family
  collisions were fixed 2026-11-17).
- **Contract:** the Codex shows every payload entry; nothing is filtered
  ([`prd-codex.md`](./prd-codex.md)).

### 2.5 Runtime  *(layer 4)*

`data_service.gd` loads records into typed dictionaries keyed by id.

- **Contract:** `get_<thing>(id)` resolves exactly the ids the lint guarantees exist.
- **Known debt:** ~42 hand-written `_scan_directory(dir, type)` calls restate the
  family list the producer now discovers. One table should drive both — see
  [`prd-data-graph.md`](./prd-data-graph.md) ladder step 2.

---

## 3. Invariants that cross layers

These hold *across* the spine. Each is owned elsewhere; listed here so the spine is
readable end-to-end. **Do not re-derive them from this list — read the owner.**

| Invariant | Owner | Spans layers |
|---|---|---|
| id == filename, always | `data-authoring-baseline.md` §2 | 2 → 4 → 5 → 6 |
| ids unique repo-wide | `data-authoring-baseline.md` §2 | 2 |
| one vocabulary — `StatId` keys, no hand-spelled stats | `AGENTS.md` law 2 | 1 → 2 → 4 |
| bands/tiers are five-rung (common→mythic) | `AGENTS.md` law 2, `GameTier` | 1 → 2 → 6 |
| identity verbs canonical per class | `AGENTS.md` §"Identity verbs" | 1 → 2 |
| define from schema + data, not code | `AGENTS.md` law 1 | 1 → 4 |
| enums read from schemas, never copied | `scripts/sync_godot_data.ts` header | 1 → 6 |
| every reference resolves to a real record | `data-authoring-baseline.md` §4 | 2 → 4 |

---

## 4. The gates

| Gate | Command | Catches |
|---|---|---|
| **Data naming lint** | `godot --headless --path game --script res://tests/test_data_naming_lint.gd` | prefix law, filename==id, ~30 ref checks |
| **Item catalog** | `godot --headless --path game --script res://tests/test_item_catalog.gd` | item family identity, authored words, recipe bill |
| **Content ref integrity** | `godot --headless --path game --script res://tests/test_content_ref_integrity.gd` | loot/offering/enemy ids resolve |
| **Tres relation gate** | `node <tresridge>/bin/cli.mjs lint game/data --decl game/data/relations.json` | every declared edge resolves, no undeclared `_id`, no cycles (the standard's verdict) |
| **Tres drift gate** | `node <tresridge>/bin/cli.mjs graph game/data --against game/data/relations.json` | the declaration the tree implies vs the committed one (added / removed / changed) |
| **Full game sweep** | `sh scripts/godot_test_runner.sh [-j N]` | 214 `test_*.gd` |
| **Codex verify** | `npm run verify:codex` | vocab, coverage, fidelity, nothing-skipped |
| **Web build** | `npm run build` | `sync:data` → `verify:codex` → `tsc` → prerender + SEO audit |
| **Lane verify** | `npm run verify:lane` | the parallel-lane contract |

`npm run build` is the one command that runs the whole web half. The game half is
`godot_test_runner.sh`.

### The tres relation gate in CI

`.github/workflows/tres-ci.yml` runs the two tres gates plus a reproducibility check on
every change to `game/data/**` or `scripts/gen-relations.mjs`. The standard is not on npm
yet, so the lane clones `dhaupin/tresridge` at a **pinned commit** (`TRESRIDGE_REF` in the
lane env) - the family's pinned-linter rule: a floating linter is a random CI.

**The lane needs `TRESRIDGE_TOKEN`.** `dhaupin/tresridge` is private and this repository is
public, so the default `GITHUB_TOKEN` cannot read it - it is scoped to this repository
only. Add a fine-grained PAT with `Contents: read` on `dhaupin/tresridge` as the
`TRESRIDGE_TOKEN` secret. A missing secret fails the lane by name; it never skips.

**A pin is a claim about the linter, so the lane tests the claim.** The `Pin canary` step
builds a two-record tree, points the pinned CLI one level above it, and requires exit `2`
(the root refusal) - then requires the correct root to pass. Without it, moving
`TRESRIDGE_REF` could move the gate onto a linter that passes everything, and the lane
would stay green while measuring nothing. This is not hypothetical: the previous pin
(`de22ac8`) accepted a root above the tree root, printed `0 edges inferred`, and exited
`0`.

To move the pin: bump `TRESRIDGE_REF`, re-run `npm run gen:relations`, and commit the pin
and any declaration delta together. The reproducibility step refuses a stale
`relations.json` (it regenerates and byte-compares), so a tree change that should have
moved the declaration cannot land quietly. If the canary fails, the new pin cannot judge a
tree - fix the standard before moving the pin.

Locally, the same three steps run with `TRESRIDGE=/path/to/tresridge/bin/cli.mjs`.

---

## 5. How to add X

| You want to add… | Do this | Files touched |
|---|---|---|
| **a record** in an existing family | author the `.tres`; id = basename; run the lint | 1 (data) |
| **a family** | new dir + new schema + a baseline §2 table row | 3 (dir, schema, doc) |
| **a relation** | declare `(schema, field) → target` — today: baseline §4 prose + a lint check | 2 |
| **a field** on a schema | `@export` in the schema; if it ends `_id`, it is a relation | 1 |
| **a Codex page** | `src/pages/` + route | 1-2 |
| **a gate** | `game/tests/test_*.gd`, or a check in `verify_codex.mjs` | 1 |

The **family** row is the tell: adding one today touches three languages. Collapsing
that to one is the point of [`prd-data-graph.md`](./prd-data-graph.md).

---

## 6. Tooling inventory

| Tool | Layer | Role |
|---|---|---|
| `scripts/sync_godot_data.ts` | 5 | walks `game/data/`, emits payload + vocab |
| `scripts/verify_codex.mjs` | 6 | payload gates (vocab, coverage, fidelity, nothing-skipped) |
| `scripts/prestruct-build.mjs` | 7 | prerender + SEO audit |
| `scripts/tresridge_probe.mjs` | 3 | **probe** — infers relation edges; seeds the declaration |
| `game/core/services/data_service.gd` | 4 | runtime loader |
| `game/tools/data_graph.gd` | 3 | *does not exist yet* — the declared graph walker. `game/tools/` today holds only diagnostics/probes |

---

## 7. The relation layer — the spine's weakest joint

Layers 1, 2 and 4-7 each have an owner and a gate. **Layer 3 does not.** Relations are
conventions: rebuilt in the producer, restated in the baseline, and enforced by a
2272-line hand-written regex lint.

The full specification — Family/Relation model, five edge kinds, the resolution rule,
and the four-step ladder — is [`prd-data-graph.md`](./prd-data-graph.md). Tresridge
owns the *position* of that layer in the spine; that doc owns the *design*.

**The measured symptom** (prototype, `node scripts/tresridge_probe.mjs`):

```
344 edges inferred · 14 fields need declaration · 6 dangling
```

And the sharpest one, a convention the lint has learned to tolerate rather than
resolve:

```gdscript
# game/tests/test_content_ref_integrity.gd:85
if cid == "gold" or cid == "currency_gold":
```

`currency_id` is written `"currency_gold"` by schemas and `"gold"` by every
`loot_tables/*.tres`. Rather than declare which is canonical, the gate accepts both.
That line is the brittle manual frame in miniature: knowledge that should be
*declared* is instead *guessed*, twice.

---

## 8. Change Log

| Date | Author | Summary |
|------|--------|---------|
| 2026-11-17 | Web Architecture Team | Initial creation. Maps the seven content layers, their boundary contracts, the cross-layer invariants (by reference), the gate inventory, the "how to add X" recipes, and the tooling inventory. Positions [`prd-data-graph.md`](./prd-data-graph.md) as the layer-3 design and names the `currency_id` split as the canonical example of undeclared convention. |
