# Synmergia — The Data Graph: A Formal `.tres` Relation System

> **Status:** DESIGN — the relation layer does not exist yet. This doc specifies it.
> Measured against `staging` @ 2026-11-17 (1097 records, 55 families, 67 schemas).
> **Author:** Web Architecture Team
> **Purpose:** Replace the current implicit, hand-maintained web of `.tres`
> cross-references with a declared, machine-checkable relation graph — one source
> of truth that the runtime, the lints, the docs and the public Codex all read.
> **Law it obeys:** [`data-authoring-baseline.md`](./data-authoring-baseline.md) §0
> (`game/core/` owns *how*, `game/data/` owns *what*).

---

## 1. The problem, precisely

Synmergia's content is 1097 `.tres` records across 55 families. They reference each
other constantly — a quest names an NPC, a recipe names items, a loot table names a
currency, a gateway names two zones. **None of those relations are declared anywhere.**
They are conventions that exist only in the heads of authors and in the regexes of one
2272-line test.

That produces four concrete costs, all measured:

**1. Every consumer re-derives the same knowledge.** A directory→schema→id mapping is
rebuilt at least three times, in three languages, and the copies have already drifted:

| Copy | Where | State |
|---|---|---|
| Sync allowlist | `scripts/sync_godot_data.ts` | was a 37-name array; **fixed** 2026-11-17 (now a filesystem walk) |
| Loader wiring | `game/core/services/data_service.gd` | ~40 hand-written `_scan_directory(dir, type)` calls |
| Prose rules | `labs/data-authoring-baseline.md` §2, §4 | a table of prefixes and ref rules, enforced by hand |

**2. The enforcement is a hand-written parser.** `game/tests/test_data_naming_lint.gd`
is 2272 lines of bespoke regex per relation — `_string_array_field`, `_dict_keys_field`,
`_bracket_block`, `_quest_ids_in`, `_objective_regex`. Each new relation is another
hand-written scanner. This is the brittle, manual frame: it encodes knowledge that
should be *declared* as *code that guesses*.

**3. Two registries contradict each other.** `game/core/utils/id_registry.gd` reserves
`itm_`, `skl_`, `zn_`, `qst_`, `fct_` for content ids. `data-authoring-baseline.md` §2
mandates `item_`/`res_`/`wep_`, `zone_`, `quest_`, `faction_`. Both are "the law",
neither is authoritative, and `id_registry` is used by no content path.

**4. Real defects hide in the gaps.** A convention-only resolver (prototype,
`scripts/tresridge_probe.mjs`) extracts **344 relations** and immediately finds:

- **`currency_id` uses two incompatible conventions.** Schemas write
  `"currency_gold"`; every `loot_tables/*.tres` writes `"gold"`. Same field name,
  different resolution, nothing declares which is right — 5 dangling edges.
- **1 virtual id** (`item_id = "book_akkan_rune_chain_legendary"`) that legitimately
  resolves to no file; documented in prose (§4) and therefore invisible to any tool.

Neither would survive a declared graph.

---

## 2. The model

Three layers. Dependencies point one way only.

```
  game/core/schemas/*.gd          SHAPE     what fields exist and their GDScript types
        │  declares
        ▼
  game/core/data/relations.gd     EDGES     which fields point at which family
        │  binds
        ▼
  game/data/**/*.tres             VALUES    the shipped records
```

### 2.1 Family — the unit of everything

A **family** is one directory under `game/data/` bound to one schema. It is the single
concept that today is spelled four different ways (a sync category, a loader call, a
baseline table row, a Codex category). One Family record, read by all four.

```
Family {
  key:        "npc"                 # the directory, and the id stem
  schema:     NPCSchema             # class_name of the .gd in core/schemas/
  id_prefix:  "npc_"                # or "" for bare ids
  filename:   "id"                  # filename == id, always (baseline §2)
}
```

### 2.2 Edge — a declared relation

An **edge** is declared once, per `(schema, field)`, and read by everything.

```
Relation {
  field:    "giver_npc_id"
  target:   "npc"          # a Family key
  kind:     "ref"          # see below
  required: true           # dangling = build error
}
```

**Edge kinds** — the five shapes that actually occur in the corpus:

| Kind | Meaning | Example |
|---|---|---|
| `ref` | scalar id → family | `giver_npc_id → npc` |
| `refs` | array of ids → family | `required_quests → quests` |
| `nested` | path into an array-of-dicts | `entries[].item_id → items` |
| `virtual` | resolvable by pattern, no file | `book_<skill_id>_<tier> → skills` |
| `literal` | opaque, never resolved | `terrain_backend_id` |

`literal` is load-bearing: it is how a field that merely *looks* like a reference is
explicitly cleared, so the "no undeclared `_id` field" check can be absolute.

### 2.3 Resolution rule (the one convention that survives)

The prototype establishes that a single rule resolves most edges with no declaration:

> **The target family is the last family token in the field name, pluralised.**
> `giver_npc_id` → `npc` · `source_zone_id` → `zones` · `secondary_loot_table_id` → `loot_tables`

This is *inference*, not the contract. It exists to seed the declaration (ladder step
1) and to keep authoring pleasant. **The declared graph is authoritative**; the rule is
how we generate its first draft. Measured residue: the rule resolves **344 edges** and
leaves **14 fields** that must be declared by hand.

---

## 3. The artifacts

| Artifact | Role | Replaces |
|---|---|---|
| `game/core/data/relations.gd` | **The single source of truth.** Family + Relation tables, as data. | baseline §2/§4 prose, scattered mappings |
| `game/tools/data_graph.gd` | Generic walker: loads the graph, walks `game/data/`, returns resolved edges + dangling + orphans. | the 2272-line regex lint internals |
| `game/tests/test_data_graph.gd` | Thin assertions over the walker (prefix, filename==id, ref resolution, cycles, orphans). | `test_data_naming_lint.gd` scanners |
| `scripts/tresridge_probe.mjs` | Web-side extractor. Emits the graph for the Codex. | `sync_godot_data.ts` hardcoded category knowledge |
| `labs/data-authoring-baseline.md` §2/§4 | **Generated** from `relations.gd`. | hand-maintained tables |
| Codex "Related" panel | Public, navigable edges + an orphan/dangling report. | nothing today |

**One declaration, six consumers.** That is the whole point: the knowledge is written
once and cannot drift, because every consumer reads the same table.

---

## 4. The ladder

### Step 0 — EXTRACT (done, prototype)
`scripts/tresridge_probe.mjs` infers edges by the resolution rule and reports the residue.
Run it: `node scripts/tresridge_probe.mjs`. Current output: 344 edges, 14 undeclared
fields, 6 dangling.

### Step 1 — DECLARE
- [ ] Author `game/core/data/relations.gd`: one Family per directory, one Relation per
      `(schema, field)` edge.
- [ ] Migrate the **14 residue fields** (`secondary_loot_table_id`, `template_id`,
      `boss_template_id`, `equipment_ids`, `controller_id`, `feeds_thermal_id`,
      `deck_visual_id`, `roll_id`, `sku_id`, `dungeon_id`, `dialogue_id`, `effect_id`,
      `terrain_backend_id`, `horde_config_id`) — each either gets a target or is marked
      `literal`.
- [ ] **Resolve the `currency_id` split** (§1 cost 4): decide prefix-or-bare and make
      both the schemas and the loot tables obey it. This is a real bug, not a style
      question.
- [ ] Record the skill-book virtual pattern (`book_<skill_id>_<tier>`) as a `virtual`
      edge so it stops being prose.
- [ ] Reconcile `id_registry.gd` prefixes with the baseline, or delete the unused
      registry. Two laws cannot both be canonical.

### Step 2 — ENFORCE
- [ ] Implement `game/tools/data_graph.gd` (generic walker over the declared graph).
- [ ] Rewrite `test_data_naming_lint.gd` as assertions over the walker — target: a few
      hundred lines, no bespoke regex. Keep the same 30 check *names* so the gate
      contract in the baseline does not change.
- [ ] Add checks the regex frame could never do: **dangling refs**, **orphans**
      (records nothing references), **cycles** (quest chains, gateways) — the prototype
      already carries a `_ach_cycle_dfs`, which is a hint this is wanted.
- [ ] Add a **coverage check**: every `@export var *_id` in a schema has a Relation or
      is marked `literal`. This is what makes the system self-maintaining — a new
      field cannot slip in undeclared.
- [ ] Wire the walker into the runtime: `data_service.gd`'s ~40 hand-written
      `_scan_directory` calls become a loop over the Family table.

### Step 3 — PUBLISH
- [ ] Codex: render edges as a "Related" panel on every entry, both directions.
- [ ] Public orphan/dangling report (`/codex/graph`) — the community sees the same
      graph we do, consistent with the unfiltered-view law in
      [`prd-codex.md`](./prd-codex.md).
- [ ] Generate `labs/data-authoring-baseline.md` §2/§4 from `relations.gd` so the prose
      cannot drift from the graph.

---

## 5. Why this is not another brittle frame

| Failure mode of the current system | How the graph removes it |
|---|---|
| Knowledge duplicated in N places, drifts | One table, N readers |
| New relation = new hand-written scanner | New relation = one table row |
| New family = edits in 3 languages | New family = dir + schema + Family row |
| Dangling refs invisible until runtime | A lint check, on every build |
| Undeclared `_id` fields accumulate | Coverage check fails the build |
| Prose documents the rules | Prose is generated from the rules |
| Agents must remember conventions | The graph is the convention |

The last row is the point of the request. Today, correct data depends on an author (or
an agent) *remembering* the baseline. Under the graph, correctness is a property of the
build: an undeclared reference, a dangling target, or a new family that forgot its row
fails CI, not a code review.

---

## 6. Open questions

- **Where does the graph live at runtime?** `relations.gd` as a preloaded const is
  simplest; a generated `.tres` would let designers edit it, but re-introduces
  generated-artifact drift. Lean: GDScript const, generated docs.
- **`nested` paths need a mini-spec.** `entries[].item_id` is a path expression; the
  grammar for it should be pinned before Step 1 so the walker and the extractor agree.
- **Does `template_id` / `boss_template_id` point at a family that exists?** The
  prototype could not resolve it; if there is no `templates/` family, these are either
  `literal` or a missing family.
- **Item families are five directories, one schema.** `Item` spans `weapons/ armors/
  accessories/ consumables/ resources/ items/`. The Family model must allow one schema
  → many directories, or the Codex's item split breaks.

---

## 7. Evidence (reproduce)

```
node scripts/tresridge_probe.mjs
  schemas with class_name: 67
  records: 1097 across 55 dirs
  relations extracted: 344
  dangling: 6
  fields with no target convention: 14
```

---

## 8. Change Log

| Date | Author | Summary |
|------|--------|---------|
| 2026-11-17 | Web Architecture Team | Initial creation. Measured the implicit relation web (344 edges, 14 undeclared fields, 6 dangling) via `scripts/tresridge_probe.mjs`; specified the Family/Relation model, the five edge kinds, the resolution rule, and a four-step ladder (extract → declare → enforce → publish). |
