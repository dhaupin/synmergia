# PRD: StateSchema Resource

> **For:** sub-agent implementation
> **Phase:** 1 (per `world-building-arch.md` §14)
> **Depends on:** `prd-t3-substrate.md` (substrate stores the schema ref)
> **Unblocks:** state tree instance, state-only diff (D027), client sync

## 1. Introduction/Overview

StateSchema is the typed payload for the state tree. Each
node in a state tree carries a StateSchema. The schema
declares: `type` (e.g., `position`, `inventory`,
`health`), and the three canonical methods
(`_to_canonical_bytes`, `_validate`, `_to_display`).

**Why this exists:** The state tree (canonical runtime
tree, D027) needs typed payloads. Per arch doc §3.3, the
schema is the typed layer; per §8.1, the state schema is
the second concrete instance. The state tree holds
runtime state (player positions, inventories, mob HP,
etc.) and diffs efficiently per D027.

**Spec ref:**
[`world-building-arch.md`](./world-building-arch.md) §8
(The state tree), [`world-building.md`](./world-building.md)
§5 (State tree / D027 state-only diff)

## 2. Goals

- ONE GDScript `Resource` class
- 1 `@export` field: `type` (the state value category)
- 3 methods: `_to_canonical_bytes`, `_validate`, `_to_display`
- Composes with T3 substrate
- One `.tres` sample file demonstrating 4-5 state value
  types (position, inventory, health, faction, status)
- Tests cover all sample types + 5 edge cases

## 3. User Stories

### US-001: StateSchema class with field

**Description:** As a developer, I need to declare a
StateSchema with a type so I can attach it to a state tree
node.

**Acceptance Criteria:**
- [ ] `StateSchema` class exists in `game/data/roots/state_schema.gd`, extends `Resource`
- [ ] `@export_enum("position", "inventory", "health", "faction", "status", "quest", "social", "other") var type: String`
- [ ] Resource can be created via the Godot editor
- [ ] Resource can be saved to `.tres` and loaded
- [ ] Field constraints show as dropdown in the editor

### US-002: StateSchema._to_canonical_bytes

**Description:** As a developer, I need a canonical byte
encoding so two StateSchemas with the same value produce
the same bytes (D027 determinism).

**Acceptance Criteria:**
- [ ] `func _to_canonical_bytes(value: Dictionary) -> PackedByteArray` method exists
- [ ] Encoding is length-prefixed: `[type:enum_as_u8][len_entity_id:u32][entity_id_bytes][len_payload:u32][payload_bytes]`
- [ ] Two calls with same inputs return same bytes
- [ ] Different inputs return different bytes
- [ ] Payload bytes are themselves a canonical encoding (the schema is recursive for nested state)

### US-003: StateSchema._validate

**Description:** As a developer, I need validation so
malformed state data is rejected at insert time.

**Acceptance Criteria:**
- [ ] `func _validate(value: Dictionary) -> bool` method exists
- [ ] Returns `true` for valid `{type, entity_id, payload}`
- [ ] Returns `false` for missing fields
- [ ] Returns `false` for `type` not in the allowed enum
- [ ] Returns `false` for `entity_id` that's not a String
- [ ] Returns `false` for `payload` that's not a Dictionary
- [ ] Type-specific validation: `position` requires `payload` to have `x, y, z` as floats;
  `health` requires `current, max` as ints; `inventory` requires `items` as an Array

### US-004: StateSchema._to_display

**Description:** As a developer, I need a display string
so debug logs and admin tools can show the state info.

**Acceptance Criteria:**
- [ ] `func _to_display(value: Dictionary) -> String` method exists
- [ ] Returns human-readable string like `[position] player_42 @ (10, 0, -5)` or `[health] mob_99 (50/100)`
- [ ] Per-type formatting: position shows coords, health shows current/max, inventory shows item count

### US-005: Sample .tres file

**Description:** As a developer, I need a sample
StateSchema saved as `.tres` so I can verify the Godot
editor flow.

**Acceptance Criteria:**
- [ ] One sample `.tres` at `game/data/roots/world/state.tres`
- [ ] Sample covers 4-5 state types (position, inventory, health, faction, status)
- [ ] Sample loads in the Godot editor without errors
- [ ] Sample is referenced from a doc comment in the schema

## 4. Functional Requirements

- **FR-1:** One GDScript Resource `StateSchema` in
  `game/data/roots/state_schema.gd`, extends `Resource`
- **FR-2:** One `@export` field with `@export_enum`
  constraints (type)
- **FR-3:** Three instance methods: `_to_canonical_bytes`,
  `_validate`, `_to_display`
- **FR-4:** Composes with T3 via the schema_ref pattern
- **FR-5:** NO autoload, NO `class_name`
- **FR-6:** NO dependency on autoloads or game services
- **FR-7:** Determinism: same input → same canonical bytes
  (D027 prerequisite)
- **FR-8:** Type-specific validation: each `type` enum
  value has a payload shape expectation
- **FR-9:** Per-type display formatting in `_to_display`

## 5. Non-Goals (Out of Scope)

- NO state diff implementation (that's T3::diff, in the
  T3 PRD)
- NO client sync protocol (that's networking, a separate
  deliverable)
- NO actual state values (the schema is the type, not the
  data; values are in `.tres` instances)
- NO UI for editing
- NO integration with vant
- NO icosahedral address fields (out of scope for v1)
- NO transaction history (the state tree has no undo;
  the world snapshots if it needs to)
- NO TTL on state nodes (the world environment handles
  TTL, per arch doc §6.3)

## 6. Design Considerations

- **Type enum:** start with 7 types (position, inventory,
  health, faction, status, quest, social) + "other" as
  a catch-all. Extend as new game features are added.
- **Type-specific validation:** use a match/switch on
  `type` in `_validate` and `_to_display`. Each type has
  a small validator/formatter; adding a new type is adding
  a new branch.
- **Payload structure:** each type has a canonical payload
  shape. Position: `{x, y, z}`. Health: `{current, max}`.
  Inventory: `{items: [...]}`. The schema doesn't validate
  nested arrays; that's the payload schema's job.
- **Determinism guarantee:** relies on the encoder being
  deterministic. The schema is a Resource, so the same
  `.tres` file = same schema = same canonical bytes. No
  floating-point nondeterminism (positions are quantized
  to 0.01m, health is integer HP).

## 7. Technical Considerations

- **Godot 4.7.2** required (uses `@export_enum`,
  `PackedByteArray`, `Resource`).
- **Tests:** co-located in
  `game/data/roots/test_state_schema.gd` or
  `tests/test_state_schema.gd` (per repo convention).
- **Sample .tres file:** at
  `game/data/roots/world/state.tres`, covering 4-5 state
  types.
- **No external dependencies** beyond Godot stdlib.
- **Position quantization:** assume positions are
  quantized to 0.01m (1cm) at the game-engine level, so
  float positions are effectively integers for hash
  purposes. This is the contract; the engine enforces
  it elsewhere.

## 8. Success Metrics

- All 5 user stories have passing tests (≥ 20 assertions total)
- 7 (type) tests + 5 edge case tests passing
- One sample `.tres` file created
- One commit, pushed to main
- `labs/world-building-arch.md` §13 component map status
  updated: StateSchema from `TODO` to `DONE`

## 9. Open Questions

1. **Type enum size:** 7 types is a guess. Could be more
   (per-subsystem). Could be fewer (single "state" type
   with the discriminator in the payload). 7 is a balance
   — covers the major game systems without bloating the
   enum.
2. **Payload schema recursion:** should StateSchema
   itself contain a sub-schema for the payload? Out of
   scope for v1; the payload is a free Dictionary
   validated per-type.
3. **Schema location:** `game/data/roots/state_schema.gd`
   vs `game/core/schemas/state_schema.gd`. Per arch doc
   §6.2, the roots dir is the new home.
4. **Visibility scope:** seed trees have a `visibility_scope`
   field. Should state trees have one? No — state is
   per-scope by construction (the state tree lives at a
   scope). The scope IS the visibility.
5. **Faction/quest/social types:** are these state or
   relationships? For v1, all in the state tree; revisit
   when a separate "social tree" is added per arch doc §9.

## 10. Definition of Done

- [ ] StateSchema Resource implemented and pushed to main
- [ ] Tests co-located, all green
- [ ] One `.tres` sample file in `game/data/roots/world/state.tres`
- [ ] `labs/world-building-arch.md` §13 component map
  status updated
- [ ] Single commit, conventional message format
- [ ] Smoke test: create a StateSchema, canonicalize a
  state value, verify same input → same bytes
- [ ] Type-specific validation works: invalid `position`
  payload → `_validate` returns `false`

---

## 11. Decisions applied (2026-09-05)

Answers from the planning session that affect this PRD:

- **Schema evolution (option a - auto-upgrade on load):**
  Add a `version: int` field (default 1) to the
  StateSchema. In `_init()` (or a Godot lifecycle hook),
  check the saved version; if older, run the appropriate
  `_upgrade_vN_to_vM()` method.

- **FSM migration (the big one for StateSchema):** the
  old `core/state/state.gd` and `state_machine.gd` are
  deprecated. FSM is moving to the new architecture.
  Concretely:
  - Add `behavior_state` to the `type` enum (alongside
    position, inventory, health, faction, status, quest,
    social, other).
  - A behavior_state node in the state tree holds the
    FSM state for one entity (current_animation,
    ai_tick_state, etc.).
  - FSM transitions are computed by reading/writing
    behavior_state nodes; the per-entity FSM machinery
    becomes a thin wrapper over state tree reads/writes.
  - Old FSM code is deleted after migration (no parallel
    systems).

- **Persistent vs transient state:** the arch doc
  clarifies that the state tree holds *persistent* state
  (HP, position, inventory, quest progress, FSM
  current_state). *Transient* state (current animation
  frame, in-flight network packet) stays as Godot node
  properties. The behavior_state type holds the *current*
  FSM state, which is persistent (it survives across
  server restarts via the state tree diff).

- **Data dir:** `game/data/roots/<scope>/state.tres` per
  arch doc section 6.2.

- **D029, D030, D032, D033 integration:** state tree is
  the substrate for login flow state (D029), frame
  transient vs persistent state split (D030), instance
  state restoration (D032), and shard parameter
  criticality (D033, where critical params apply via
  state_tree.insert).

