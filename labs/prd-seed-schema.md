# PRD: SeedSchema Resource

> **For:** sub-agent implementation
> **Phase:** 1 (per `world-building-arch.md` §14)
> **Depends on:** `prd-t3-substrate.md` (the substrate stores the schema ref; this schema is one of N)
> **Unblocks:** seed tree instance, seed chain derivation (D025), login seed chain (D029)

## 1. Introduction/Overview

SeedSchema is the typed payload for the seed tree. Each
node in a seed tree carries a SeedSchema. The schema
declares: `seed_type` (`locked` / `open` / `frame`),
`visibility_scope` (`world` / `shard` / `instance` /
`player`), and the three canonical methods
(`_to_canonical_bytes`, `_validate`, `_to_display`).

**Why this exists:** The seed tree (canonical recursive
tree, D025-D026) needs typed payloads. The schema is what
makes a "seed tree" different from a "state tree" — the
substrate is the same, the schema is the difference. Per
arch doc §3.3, the schema is the typed layer; per §7.1,
the seed schema is the first concrete instance.

**Spec ref:**
[`world-building-arch.md`](./world-building-arch.md) §7
(The seed tree), [`world-building.md`](./world-building.md)
§4 (Recursive seed-state recursion)

## 2. Goals

- ONE GDScript `Resource` class
- 2 `@export` fields: `seed_type`, `visibility_scope`
- 3 methods: `_to_canonical_bytes`, `_validate`, `_to_display`
- Composes with T3 substrate (the schema is passed to
  `T3.insert` as the third argument)
- One `.tres` sample file demonstrating all 9 (type × scope)
  combos
- Tests cover all 9 combos + 5 edge cases (empty path,
  deep path, special chars, missing fields, invalid enum)

## 3. User Stories

### US-001: SeedSchema class with fields

**Description:** As a developer, I need to declare a
SeedSchema with type and scope so I can attach it to a
seed tree node.

**Acceptance Criteria:**
- [ ] `SeedSchema` class exists in `game/data/roots/seed_schema.gd`, extends `Resource`
- [ ] `@export_enum("locked", "open", "frame") var seed_type: String`
- [ ] `@export_enum("world", "shard", "instance", "player") var visibility_scope: String`
- [ ] Resource can be created via the Godot editor
- [ ] Resource can be saved to `.tres` and loaded
- [ ] Field constraints show as dropdowns in the editor

### US-002: SeedSchema._to_canonical_bytes

**Description:** As a developer, I need a canonical byte
encoding so that two SeedSchemas with the same fields
produce the same bytes (determinism, D025 prerequisite).

**Acceptance Criteria:**
- [ ] `func _to_canonical_bytes(value: Dictionary) -> PackedByteArray` method exists
- [ ] Encoding is length-prefixed: `[len_seed_type:u32][seed_type_bytes][len_scope:u32][scope_bytes][len_path:u32][path_bytes][len_params:u32][params_bytes]`
- [ ] Two calls with same inputs return same bytes
- [ ] Different inputs return different bytes
- [ ] Empty path = empty path_bytes (len=0), not error
- [ ] Special characters in path don't break the encoding (length prefix disambiguates)

### US-003: SeedSchema._validate

**Description:** As a developer, I need validation so
that malformed seed data is rejected at insert time.

**Acceptance Criteria:**
- [ ] `func _validate(value: Dictionary) -> bool` method exists
- [ ] Returns `true` for valid `{seed_type, visibility_scope, path, parameters}`
- [ ] Returns `false` for missing fields
- [ ] Returns `false` for `seed_type` not in the 3 allowed values
- [ ] Returns `false` for `visibility_scope` not in the 4 allowed values
- [ ] Returns `false` for `path` that's not a String
- [ ] Returns `false` for `parameters` that's not a Dictionary

### US-004: SeedSchema._to_display

**Description:** As a developer, I need a display string
so debug logs and admin tools can show the seed info.

**Acceptance Criteria:**
- [ ] `func _to_display(value: Dictionary) -> String` method exists
- [ ] Returns human-readable string like `[locked+world] /shard_1/zone_5 (3 params)`
- [ ] Includes all four fields (type, scope, path, parameters count)
- [ ] Empty path → `(root)` instead of empty string
- [ ] 0 params → `(0 params)` not `(no params)`

### US-005: Sample .tres file

**Description:** As a developer, I need a sample
SeedSchema saved as `.tres` so I can verify the Godot
editor flow.

**Acceptance Criteria:**
- [ ] One sample `.tres` at `game/data/roots/world/seed.tres`
- [ ] Sample covers one of each type × scope combo (9 entries)
- [ ] Sample loads in the Godot editor without errors
- [ ] Sample is referenced from a doc comment in the schema

## 4. Functional Requirements

- **FR-1:** One GDScript Resource `SeedSchema` in
  `game/data/roots/seed_schema.gd`, extends `Resource`
- **FR-2:** Two `@export` fields with `@export_enum` constraints (type, scope)
- **FR-3:** Three instance methods: `_to_canonical_bytes`,
  `_validate`, `_to_display`
- **FR-4:** Composes with T3 via the schema_ref pattern (T3
  stores the reference; SeedSchema is the type)
- **FR-5:** NO autoload, NO `class_name` (the schema is a
  Resource, not a service)
- **FR-6:** NO dependency on autoloads or game services
- **FR-7:** Determinism: same input → same canonical bytes
  (D025 prerequisite)
- **FR-8:** Canonical encoding uses length-prefixed fields
  to avoid string-ambiguity attacks

## 5. Non-Goals (Out of Scope)

- NO seed chain derivation function (that's
  `seed_chain.gd`, a separate deliverable, per arch doc
  §7.2)
- NO actual seed values (the schema is the type, not the
  data; values are in the `.tres` instances)
- NO UI for editing (the `.tres` file is the source of
  truth; the Godot editor is for inspection only)
- NO runtime validation hookup (the schema's `_validate`
  is called by T3 callers, not by T3 itself)
- NO integration with vant (the schema is Synmergia-
  native; vant's barcode is a different concept)
- NO icosahedral address fields (out of scope for v1;
  future when spatial layer is added per arch doc §11
  Phase 4)

## 6. Design Considerations

- **Field constraints:** use `@export_enum` for the type
  and scope fields so the Godot editor shows a dropdown.
  This catches typos at edit time, not run time.
- **Canonical encoding:** use length-prefixed strings
  (`[len:u32][bytes]`) so the encoding is unambiguous.
  Avoids the `"abc" + "def"` vs `"ab" + "cdef"` ambiguity.
- **Determinism guarantee:** relies on the encoder being
  deterministic. The schema is a Resource, so the same
  `.tres` file = same schema = same canonical bytes. No
  floating-point or time-based fields.
- **Field naming:** `seed_type` and `visibility_scope`
  (GDScript convention is snake_case for fields).
- **Parameters field:** a free-form `Dictionary` for
  per-seed config (e.g., `{"depth": 3, "biome": "forest"}`).
  Validated as Dictionary, not validated deeper (the
  per-seed schema is the schema's job, not the parent's).

## 7. Technical Considerations

- **Godot 4.7.2** required (uses `@export_enum`,
  `PackedByteArray`, `Resource`).
- **Tests:** co-located in
  `game/data/roots/test_seed_schema.gd`. If co-location
  in `data/` is awkward (data/ is a resource dir, not a
  code dir), put tests in `tests/test_seed_schema.gd`
  per the existing convention.
- **Sample .tres file:** at
  `game/data/roots/world/seed.tres`, covering all 9
  (type × scope) combos as a single sample.
- **No external dependencies** beyond Godot stdlib.

## 8. Success Metrics

- All 5 user stories have passing tests (≥ 20 assertions total)
- 9 (type × scope) combo tests + 5 edge case tests
  passing
- One sample `.tres` file created
- One commit, pushed to main
- `labs/world-building-arch.md` §13 component map status
  updated: SeedSchema from `TODO` to `DONE`

## 9. Open Questions

1. **Field naming:** `seed_type` vs `seedType` vs `kind`?
   GDScript convention is snake_case for fields. Picked
   `seed_type`.
2. **Schema location:** `game/data/roots/seed_schema.gd`
   vs `game/core/schemas/seed_schema.gd` (the existing
   convention)? Per arch doc §6.2, the roots dir is the
   new home. The existing `core/schemas/` stays for non-
   tree schemas (character data, item data, etc.).
3. **Parameters validation:** deep-validate the parameters
   dict, or accept any dict? Out of scope for v1; the
   parameters schema is per-seed-type.
4. **Multi-iso axes:** should SeedSchema carry the
   icosahedral address for spatial seeds? Out of scope
   for v1; future when spatial layer is added.

## 10. Definition of Done

- [ ] SeedSchema Resource implemented and pushed to main
- [ ] Tests co-located, all green
- [ ] One `.tres` sample file in `game/data/roots/world/seed.tres`
- [ ] `labs/world-building-arch.md` §13 component map
  status updated
- [ ] Single commit, conventional message format
- [ ] Smoke test: create a SeedSchema, canonicalize a
  seed value, verify same input → same bytes

---

## 11. Decisions applied (2026-09-05)

Answers from the planning session that affect this PRD:

- **Schema evolution (option a - auto-upgrade on load):**
  Add a `version: int` field (default 1) to the
  SeedSchema. In `_init()` (or a Godot lifecycle hook),
  check the saved version; if older, run the appropriate
  `_upgrade_vN_to_vM()` method. Each new schema version
  ships with its upgrade method.

- **Login flow (D029):** the 4 seeds the client receives
  on character select (world, shard, instance, player)
  all conform to SeedSchema - the schema defines the
  type/scope per seed, and the seed chain derivation
  (per arch doc section 7.2) operates on SeedSchema values.

- **Per-character scoping:** seeds are character-scoped,
  not account-scoped. The login flow is per-character.
  This is enforced by the login service, not the schema
  itself (the schema doesn't know about accounts vs
  characters).

- **Data dir:** `game/data/roots/<scope>/seed.tres` per
  arch doc section 6.2. The 9 (type x scope) combos in
  US-005 are 9 entries in a single `seed.tres`, or 9
  separate files. Implementation choice - either is fine.

- **FSM migration:** the old `core/state/state.gd` and
  `state_machine.gd` are deprecated. FSM is moving to
  the new architecture (placeholder in StateSchema PRD
  for `behavior_state` type). SeedSchema is unaffected
  by FSM migration.

