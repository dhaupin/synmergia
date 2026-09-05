# PRD: Shard Parameter Criticality (D033)

> **For:** sub-agent implementation
> **Phase:** 1 (per `world-building-arch.md` §14)
> **Depends on:** `prd-t3-substrate.md` (the params live in the state tree)
> **Unblocks:** boss-defeat events, world-event triggers, season transitions

## 1. Introduction/Overview

Shard parameters (e.g., `boss_defeated`, `respawn_rate_modifier`,
`season_active`, `world_event_active`) can be flagged
`critical: bool`. Critical parameters bypass the 5-min
coalesce window (D024) and are applied immediately. Non-
critical parameters coalesce for 5 min before applying.
Criticality is **config-time, not runtime** (avoids
exploits).

**Why this exists:** Per arch doc §7.4 and the validation's
Tier-1 issue #5, the critical/non-critical distinction was
unclear. D033 settles it: each parameter has a `critical`
flag in its definition; the writer checks the flag and
either applies immediately or queues for coalesce.

**Spec ref:**
[`world-building-arch.md`](./world-building-arch.md) §7.4
(critical parameters), `world-building-risks.md` (D033
pending)

## 2. Goals

- Each shard parameter has a `critical: bool` field in
  its definition
- Critical parameters apply immediately (no 5-min wait)
- Non-critical parameters coalesce for 5 min, then apply
- Criticality is config-time (set in the parameter's
  schema), not runtime
- Audit log for every critical parameter application
- Defaults: `boss_defeated` (critical),
  `respawn_rate_modifier` (non-critical),
  `season_active` (critical),
  `world_event_active` (non-critical)
- Tests cover: critical applies immediately, non-critical
  coalesces, audit log captures critical, config-time
  enforcement

## 3. User Stories

### US-001: ShardParameterDefinition resource

**Description:** As a developer, I need a
`ShardParameterDefinition` resource that declares a
parameter's name, type, default value, and criticality.

**Acceptance Criteria:**
- [ ] `ShardParameterDefinition` class exists in
  `game/core/schemas/shard_parameter_definition.gd`,
  extends `Resource`
- [ ] Fields: `name: String`, `type: String` (int, float,
  bool, string, enum), `default_value: Variant`,
  `critical: bool`, `description: String`
- [ ] The resource can be saved to `.tres` and loaded
- [ ] One `.tres` per parameter, in
  `game/data/roots/world/parameters/`

### US-002: ShardParameters service

**Description:** As a developer, I need a
`ShardParameters` service that reads the definitions and
applies parameter writes (immediate for critical,
coalesced for non-critical).

**Acceptance Criteria:**
- [ ] `ShardParameters` autoload in
  `game/core/services/shard_parameters.gd`
- [ ] Method: `func set(shard_id: String, param_name: String, value: Variant) -> void`
- [ ] If the parameter is critical, apply immediately
  to the shard's state tree, log to audit, emit a
  `param_applied` signal
- [ ] If the parameter is non-critical, queue for the
  5-min coalesce window
- [ ] Method: `func flush(shard_id: String) -> void` —
  forces all queued parameters to apply now
- [ ] Coalesce window: 5 minutes (300,000 ms)
- [ ] Tests: critical applies immediately, non-critical
  queues, flush works, multiple writes to the same
  non-critical parameter coalesce to one application

### US-003: Coalesce window

**Description:** As a developer, I need the 5-min
coalesce window to batch multiple writes to non-critical
parameters, so we don't spam the state tree.

**Acceptance Criteria:**
- [ ] Non-critical parameters are queued in a per-shard
  Dictionary
- [ ] A timer fires every 5 min (per shard) to apply all
  queued parameters
- [ ] If the same parameter is written twice within the
  window, only the latest value is applied
- [ ] Tests: 2 writes to same param → 1 application;
  write + flush → 1 application; write + write + 5min
  wait → 1 application

### US-004: Audit log for critical parameters

**Description:** As a security-aware developer, I need
every critical parameter application logged, so admins
can audit who did what.

**Acceptance Criteria:**
- [ ] `ShardParameters._apply_critical` writes to
  `GameLog` with: timestamp, shard_id, param_name,
  new_value, actor_id (the player or system that
  triggered the write)
- [ ] Log level: INFO (not DEBUG, not WARNING)
- [ ] Tests: critical write → log entry exists with the
  right fields

### US-005: Criticality is config-time

**Description:** As a developer, I need the
`ShardParameters.set` method to refuse runtime
criticality changes, so a player can't escalate a
non-critical parameter to critical.

**Acceptance Criteria:**
- [ ] `set` reads the criticality from the parameter
  definition (the `.tres`), not from the caller
- [ ] No `set_critical(param_name, bool)` public method
- [ ] Tests: `set` always reads the `.tres`; runtime
  flag manipulation is impossible

### US-006: Default criticality

**Description:** As a developer, I need the default
criticality to match the spec, so the game works out
of the box.

**Acceptance Criteria:**
- [ ] One `.tres` per default parameter in
  `game/data/roots/world/parameters/`:
  - `boss_defeated.tres` (critical: true)
  - `respawn_rate_modifier.tres` (critical: false)
  - `season_active.tres` (critical: true)
  - `world_event_active.tres` (critical: false)
- [ ] All 4 files load without errors
- [ ] Tests: each `.tres` is loaded, criticality is
  correct

## 4. Functional Requirements

- **FR-1:** `ShardParameterDefinition` Resource
- **FR-2:** `ShardParameters` autoload with `set`,
  `flush`, audit, coalesce
- **FR-3:** 5-min coalesce window (300,000 ms)
- **FR-4:** Audit log for critical parameters (INFO level
  via `GameLog`)
- **FR-5:** Criticality is config-time (from the `.tres`,
  not the caller)
- **FR-6:** 4 default `.tres` files

## 5. Non-Goals (Out of Scope)

- NO runtime criticality changes (config-time only)
- NO per-player criticality (all players on a shard
  share the same criticality)
- NO UI for editing criticality (the `.tres` is the
  source of truth)
- NO critical parameters for player-level state
  (parameters are shard-level; player-level state goes
  through the state tree directly)

## 6. Design Considerations

- **Why config-time criticality:** a runtime criticality
  flag would be an exploit vector (player escalates
  their own modifier to critical to bypass the 5-min
  wait). Config-time is data, not code, and is harder
  to tamper with.
- **Why 5-min coalesce:** matches the existing D024
  decision. The 5-min window is a game design choice,
  not a technical limit.
- **Why INFO log level:** admins need to see critical
  parameter applications; DEBUG would hide them. WARNING
  would imply something is wrong; INFO is "this
  happened, FYI."

## 7. Technical Considerations

- **Godot 4.7.2** required (uses `Timer`, `Dictionary`,
  `Resource`).
- **Tests:** in `tests/test_critical_params.gd`.
- **State tree integration:** `ShardParameters.set`
  applies by calling `state_tree.insert(path, value,
  StateSchema)` on the shard's state tree.
- **Coalesce timer:** one Timer per shard, started on
  the first non-critical write, fires every 5 min.

## 8. Success Metrics

- All 6 user stories have passing tests
- Critical parameter applies immediately
- Non-critical parameter coalesces for 5 min
- Audit log captures critical applications
- 4 default `.tres` files
- One commit, pushed to main
- `labs/world-building-arch.md` §13 component map status
  updated: D033 from `TODO` to `DONE`

## 9. Open Questions

1. **Coalesce window duration:** 5 min is the spec
   default. Should it be configurable per shard? My
   read: yes, via a `coalesce_window_ms: int` field on
   the shard's environment. Out of scope for v1.
2. **Per-parameter flush:** should `flush` flush a
   single parameter, or all queued? My read: all
   queued. Single-parameter flush is a v2 concern.

## 10. Definition of Done

- [ ] `ShardParameterDefinition` Resource implemented
- [ ] `ShardParameters` autoload implemented
- [ ] 4 default `.tres` files
- [ ] Tests passing
- [ ] `labs/world-building-arch.md` §13 component map
  updated
- [ ] Single commit, conventional message format
- [ ] Smoke test: write critical param → applied
  immediately; write non-critical → queued; flush →
  applied
