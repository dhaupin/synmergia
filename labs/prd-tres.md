# Synmergia — `prd-tres`: adopting the tresridge standard

> **Status:** DESIGN — the standard exists ([`dhaupin/tresridge`](https://github.com/dhaupin/tresridge));
> Synmergia has not adopted it yet. This doc is the adoption plan, not the standard.
> Measured against `staging` @ 2026-11-17 (1097 records, 55 families, 67 schemas).
> **Author:** Web Architecture Team
> **Purpose:** Bind the tresridge relation standard to Synmergia's 55 families, its
> runtime loader, its lints and its public Codex — so the relation layer becomes
> declared data one source deep, instead of a convention rebuilt in five places.
> **Law it obeys:** [`data-authoring-baseline.md`](./data-authoring-baseline.md) §0
> (`game/core/` owns *how*, `game/data/` owns *what*).

---

## 1. What this doc is, and what it is not

**tresridge is the standard** — the edge grammar and the resolution contract. It lives in
its own repo, `dhaupin/tresridge`:

| Doc | What it owns |
|---|---|
| [`spec/SPEC.md`](https://github.com/dhaupin/tresridge/blob/main/spec/SPEC.md) | the normative grammar (family + edge tables, five edge kinds, the resolution rule, the refusals) |
| [`labs/prd-tresridge.md`](https://github.com/dhaupin/tresridge/blob/main/labs/prd-tresridge.md) | the product contract |
| [`README.md`](https://github.com/dhaupin/tresridge/blob/main/README.md) | the front door and the CLI surface |

**Ownership.** tresridge is a **synmergia project** — it keeps the struct family's *model*
(the layout, the refusal battery, the named refusals) but is not on the family roster. It is
not registered in govstruct, has no family-domain site, and is published (if at all) on
synmergia's say-so. The reference deployment's adoption PRD is below.

**This doc is the reference deployment's adoption PRD.** It does not restate the grammar —
it binds the standard to Synmergia's reality: which families exist, which fields are edges,
where the declaration lives in the engine, and which consumers read it. Restating the
grammar here would violate the same one-source-per-concept law the standard exists to
enforce.

**The relation this doc has to [`prd-data-graph.md`](./prd-data-graph.md).** That doc is
Synmergia's *first* attempt at this — it designed the Family/Edge model and the four-step
ladder in-house, before the standard existed. It is now the **in-house history of the same
idea**: the model it reached independently is the model tresridge froze. `prd-data-graph`
stays as the design record; this doc supersedes it as the *adoption plan*, and points at
the standard rather than at a local grammar. Its ladder (§4) is kept below, re-homed onto
the standard's artifacts.

---

## 2. The problem, in one paragraph

Synmergia's 1097 `.tres` records reference each other constantly, and **none of those
relations are declared anywhere**. The knowledge is rebuilt in five places that have
already drifted: the sync allowlist (`scripts/sync_godot_data.ts`), the loader wiring
(`data_service.gd`, **42** hand-written `_scan_directory` calls), the prose rules
(`data-authoring-baseline.md` §2, §4), the Codex categories (`src/lib/codex.ts`), and a
**2272-line** hand-written regex lint (`game/tests/test_data_naming_lint.gd`) with one
bespoke scanner per relation. The full evidence — including the `currency_id` split and the
prefix contradiction — is in [`prd-data-graph.md`](./prd-data-graph.md) §1 and the standard's
[PRD §2](https://github.com/dhaupin/tresridge/blob/main/labs/prd-tresridge.md).

The measured shape of the fix, from the probe (`scripts/tresridge_probe.mjs`):

```
1097 records · 55 families
344 reference instances resolved by the rule
61 declaration edges (family.field pairs) · 12 need declaring
6 dangling
```

Naming the unit matters here - "edge" was three different things (reference instances,
declaration pairs, inferred pairs) and the counts only reconcile once separated
([SPEC §2](https://github.com/dhaupin/tresridge/blob/main/spec/SPEC.md) carries the table).
The number that matters for the work: **12 pairs** must be declared by hand, covering the
fields the rule cannot resolve. That is the entire cost of declaring what 1097 records
already assume.

---

## 3. The mapping: standard → Synmergia

The standard is general; Synmergia is the reference deployment. The split (per the
standard's [PRD §5](https://github.com/dhaupin/tresridge/blob/main/labs/prd-tresridge.md)):

| Layer | The standard owns | Synmergia owns |
|---|---|---|
| Grammar (family + edge tables) | the shape | — |
| Family vocabulary | — | the 55 families under `game/data/` |
| The declaration artifact | its schema (`relations.json`) | `game/core/data/relations.gd` — the engine's copy |
| The resolution rule | the rule text | the `.tres` id conventions it resolves against |
| The lint / graph / doctor verbs | the CLI | the CI wiring + the in-engine consumer |
| The consumers | — | `data_service.gd`, the baseline tables, the Codex |

**The declaration is authored once and read by all five consumers.** That is the whole
point: `game/core/data/relations.gd` is a *const table*, generated and committed, and
every consumer reads it instead of restating the convention.

### 3.1 The families

`game/data/` holds 55 record-bearing families (the probe's count; the tree has 60
directories, five of which — `presolve`, `shaders`, `textures`, `brand`, `art` — hold no
`.tres`). Each becomes one family row: `key` (the directory name), `schema` (the
`class_name` its records declare), `idPrefix` (the id stem). The probe already derives the
first draft — `tresridge graph` formalizes it.

### 3.2 The edges

The rule resolves 49 `(family, field)` pairs outright; **12 more must be declared**. The
residue is the interesting part:

- **12 pairs with no target convention** — declared by hand. Each is either a real edge the
  rule could not see (a `nested` path, a `virtual` id) or a `literal` field that only
  *looks* like a reference. Declaring them is the work; the standard's `literal` kind is
  what keeps that work honest. Two shapes the rule cannot express, both measured:
  - **a union target** — item ids live across `weapons/`, `armors/`, `resources/`, ... so
    the edge's target is an **array of keys**, not one family.
  - **a non-id** — `npc_offerings.service_id` holds `"BlacksmithService"`, a class name.
    It ends `_id` and is not a reference: the `literal` call.
- **6 dangling** — declared edges pointing at records that do not exist. Each is a real
  defect (the `currency_id` split is one class of them) or a `required: false` edge.
- **`currency_id`** — the sharpest one. Schemas write `"currency_gold"`, loot tables write
  `"gold"`, and the current gate (`test_content_ref_integrity.gd:85`) *accepts both* rather
  than declaring one. Adoption forces the call: pick a convention, declare it, and let the
  lint refuse the other. This is the first decision the adoption produces, and it is the
  exact class of brittle manual frame the standard exists to end.
- **The prefix contradiction** — `id_registry.gd` reserves `itm_`/`skl_`/`zn_`/`qst_`/`fct_`;
  `data-authoring-baseline.md` §2 mandates `item_`/`zone_`/`quest_`/`faction_`. The standard
  records the prefix as host-owned and does not pick a winner; Synmergia must.

---

## 4. The ladder (re-homed onto the standard)

The four steps from [`prd-data-graph.md`](./prd-data-graph.md) §4, now expressed against the
standard's artifacts. Each step names the artifact it produces and the receipt that proves it.

### Step 0 — EXTRACT (done)

`scripts/tresridge_probe.mjs` walks the tree, infers edges, reports the residue. 122 lines,
zero dependencies. **Receipt:** 1097 records / 55 families / 344 reference instances
resolved / 61 declaration pairs (49 inferred + 12 to declare) / 6 dangling.

### Step 1 — DECLARE

Author `game/core/data/relations.gd` — the family and edge tables, generated from
`tresridge graph` and committed. The 14-field residue is filled in by hand; each `literal`
field is named explicitly.

**Receipt:** `relations.gd` exists; `tresridge graph --against` is clean; the 14 fields are
each either declared or `literal`.

### Step 2 — ENFORCE

Rewrite the consumers to read the declaration:

- `data_service.gd`'s 42 `_scan_directory` calls collapse to a walk driven by the family
  table. **This is the largest single win** — the loader stops restating the family list.
- `test_data_naming_lint.gd`'s bespoke scanners are replaced by assertions over the walker.
  The 2272 lines become a thin driver over the declared graph.
- `sync_godot_data.ts`'s filesystem walk reads the same table for its category list.
- `test_content_ref_integrity.gd:85`'s `"gold" or "currency_gold"` becomes one declared
  convention.

**Receipt:** the lint is materially shorter and derives its checks from the declaration; the
loader has one family source; the currency split is resolved.

### Step 3 — PUBLISH

The declaration feeds the Codex: a "Related" panel per record, driven by the graph, so the
public site shows real relations instead of none. `labs/data-authoring-baseline.md` §4's
prose cross-reference rules become generated tables.

**Receipt:** the Codex renders relations; the baseline's §4 tables are generated, not
hand-typed.

---

## 5. Why this is not another brittle frame

The current system *is* a brittle frame: 2272 lines of regex, five drifted copies, and a
gate that accepts two conventions for one field. The standard replaces it by **declaring**
what was guessed. The three properties that make the difference:

1. **The declaration is the only source.** A consumer reads `relations.gd`; no consumer
   restates it. Adding a relation is one row, not a new scanner.
2. **Inference seeds, never decides.** The resolution rule generates the first draft; a
   conforming lint never guesses at check time. This is the standard's core discipline
   ([SPEC §6](https://github.com/dhaupin/tresridge/blob/main/spec/SPEC.md)).
3. **The refusals are nameable.** An undeclared `_id`, a dangling target, a cycle — each
   is one line naming the record and the field, at author time.

**The honest risk:** Step 2 touches the runtime loader and the primary lint, both
load-bearing. The mitigation is the ladder's ordering — declare first (Step 1, no behavior
change), enforce second (Step 2, one consumer at a time), each step with its own receipt.
No step lands without the previous step's receipt.

---

## 6. Open questions

1. **`currency_id`** — prefix or bare? The adoption forces the call. (Lean: bare `gold`,
   since loot tables outnumber schemas, but this is the owner's ruling.)
2. **The prefix contradiction** — reconcile `id_registry.gd` to the baseline, or the
   baseline to the registry? (Lean: the baseline is content truth; the registry is runtime
   and references nothing — retire the runtime prefixes.)
3. **`relations.gd` or a `.json`?** The standard's artifact is JSON. The engine reads
   GDScript best. (Lean: generate `relations.gd` from the JSON; the JSON is the source, the
   `.gd` is the engine's build output — same pattern as `godot_data.json` → the Codex.)
4. **Do the 6 dangling stay dangling?** Each needs a ruling: a real defect to fix, or a
   `required: false` edge to acknowledge.

---

## 7. Evidence (reproduce)

```bash
cd /workspace/project/synmergia
node scripts/tresridge_probe.mjs     # 1097 records, 55 families, 344 resolved instances, 6 dangling
grep -c '_scan_directory(_data_path' game/core/services/data_service.gd   # 42
wc -l game/tests/test_data_naming_lint.gd                                 # 2272
```

---

## 8. Change Log

| Date | Author | Summary |
|------|--------|---------|
| 2026-11-17 | Web Architecture Team | Initial creation. Binds the tresridge standard (`dhaupin/tresridge`) to Synmergia: the standard→deployment mapping, the 55 families / 344 reference instances / 61 declaration pairs, the four-step ladder re-homed onto the standard's artifacts, and the four open rulings (the `currency_id` split, the prefix contradiction, the artifact format, the 6 dangling). Supersedes [`prd-data-graph.md`](./prd-data-graph.md) as the adoption plan while keeping it as the design record. |
| 2026-11-17 | Web Architecture Team | Units named after the CLI landed and measured the tree directly. "Edge" had been used for three different counts (344 reference instances, 61 declaration pairs, 57 inferred pairs); the reconciliation is in the standard's SPEC §2 and every number here now names its unit. Two shapes the rule cannot express are recorded: the union target (item ids across `weapons/`/`armors/`/`resources/`) and the non-id (`service_id` holding a class name). |
