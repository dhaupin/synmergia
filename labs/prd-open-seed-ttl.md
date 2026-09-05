# PRD: Open Seed TTL (D032)

> **For:** sub-agent implementation
> **Phase:** 1 (per `world-building-arch.md` §14)
> **Depends on:** `prd-scope-engine.md`, `prd-login-seed-chain.md`
> **Unblocks:** dungeon reconnect, arena reconnect, instance state preservation

## 1. Introduction/Overview

For `open + instance` seeds (dungeon runs, arena matches),
the seed is held in memory on the shard for **5 minutes
after the last character logout**. Reconnect within the
window restores the same instance state. After 5 min, the
seed is GC'd and the state is finalized (locked seeds
committed, open seeds released, state snapshotted).

The TTL starts at **last logout** (not at instance
creation). Reconnect is for the **same character** (not
any player).

**Why this exists:** Per arch doc §6.3 and the validation's
Tier-1 issue #4, the open seed reconnect semantics were
unclear. D032 settles it: 5 min from last logout, same
character only, state is finalized after TTL.

**Spec ref:**
[`world-building-arch.md`](./world-building-arch.md) §6.3
(world environment TTL), `world-building-risks.md` (D032
pending)

## 2. Goals

- TTL starts at last character logout from the instance
- Reconnect within 5 min restores the same `instance_seed`
  and the same instance state tree
- Reconnect is character-scoped (same character only)
- After TTL: env is GC'd, locked seeds committed to
  manifest, open seeds released, state snapshotted
- TTL is configurable per-instance-type
- Defaults: 5 min for `open + instance`; no TTL for
  `locked + X`; frame-end for `frame + X`
- Tests cover: reconnect within window, after window,
  different character, state restoration, state
  finalization

## 3. User Stories

### US-001: OpenSeedRegistry tracks TTL

**Description:** As a developer, I need an
`OpenSeedRegistry` that tracks `character_id ->
(instance_seed, last_logout_ms)`, so reconnects can
find the right seed.

**Acceptance Criteria:**
- [ ] `OpenSeedRegistry` exists in
  `game/core/services/open_seed_registry.gd`
- [ ] Method: `func register(character_id: String, instance_seed: PackedByteArray) -> void`
- [ ] Method: `func lookup(character_id: String) -> PackedByteArray` returns the seed if
  `(now - last_logout_ms) < 300_000`, else returns empty
- [ ] Method: `func invalidate(character_id: String) -> void` removes the entry
- [ ] On lookup, if the entry is older than 5 min, it's
  automatically invalidated
- [ ] Tests: register, lookup fresh, lookup after 5min
  (returns empty + invalidates), invalidate

### US-002: LoginService uses OpenSeedRegistry on re-login

**Description:** As a developer, I need the login
service to check the OpenSeedRegistry on character
login, so a reconnect within the window reuses the
seed.

**Acceptance Criteria:**
- [ ] `core/services/login_service.gd::build_seed_receipt`
  calls `OpenSeedRegistry.lookup(character_id)` first
- [ ] If a seed is found, it's used for `instance_seed`
  in the receipt
- [ ] If not, a new seed is generated (and registered
  via `OpenSeedRegistry.register`)
- [ ] Tests: fresh login (new seed), reconnect within
  window (same seed), reconnect after window (new seed)

### US-003: State finalization at TTL expiry

**Description:** As a developer, I need the instance
state to be finalized when the TTL expires, so the
state is preserved (locked) or released (open) per
arch doc §6.3.

**Acceptance Criteria:**
- [ ] When `OpenSeedRegistry.lookup` finds an entry
  older than 5 min, it triggers a "finalize" callback
- [ ] Finalize: locked seeds are committed to the
  manifest, open seeds are released, state tree is
  snapshotted to S3 (or equivalent)
- [ ] Finalize is idempotent (calling it twice is
  safe)
- [ ] Tests: lookup old entry → finalize called once;
  finalize called twice → only one snapshot

### US-004: Configurable TTL per instance type

**Description:** As a developer, I need the TTL to be
configurable per-instance-type, so a fast-paced arena
match can have a shorter TTL than a slow dungeon.

**Acceptance Criteria:**
- [ ] `InstanceTypeDefinition` resource with
  `name: String`, `default_ttl_ms: int` (default 300000)
- [ ] One `.tres` per instance type, in
  `game/data/roots/world/instance_types/`
- [ ] `OpenSeedRegistry` reads the TTL from the
  definition
- [ ] Default: 5 min for `dungeon`, `arena`, `raid`
- [ ] Tests: custom TTL is honored, default 5 min is
  the fallback

### US-005: State restoration on reconnect

**Description:** As a player, I want my dungeon state
restored if I reconnect within the TTL, so a brief
disconnect doesn't lose my progress.

**Acceptance Criteria:**
- [ ] On reconnect within window, the instance env is
  re-attached to the player
- [ ] The instance's state tree is the same as before
  logout (deterministic by seed)
- [ ] The player sees the same mobs, same layout, same
  quest state
- [ ] Tests: reconnect within window → same state
  tree root hash

### US-006: Per-character scope (not per-account)

**Description:** As a developer, I need the reconnect
TTL to be per-character, so two characters on the same
account don't share state.

**Acceptance Criteria:**
- [ ] `OpenSeedRegistry` is keyed by `character_id`,
  not `account_id`
- [ ] Two characters on the same account have
  independent TTLs
- [ ] Tests: same account, two characters → independent
  entries

## 4. Functional Requirements

- **FR-1:** `OpenSeedRegistry` autoload
- **FR-2:** `register`, `lookup`, `invalidate` methods
- **FR-3:** 5-min default TTL (configurable per
  instance type)
- **FR-4:** State finalization on TTL expiry
- **FR-5:** Reconnect within window restores same state
- **FR-6:** Per-character scoping

## 5. Non-Goals (Out of Scope)

- NO per-account TTL (per-character only)
- NO cross-shard reconnect (TTL is per-shard)
- NO state checkpointing during the TTL (state is in
  memory; only snapshotted on TTL expiry)
- NO client-side prediction during reconnect (the
  server is the source of truth)

## 6. Design Considerations

- **Why last-logout, not creation:** a player might be
  in a dungeon for 30 min, then disconnect for 1 min.
  Last-logout TTL gives them the 1 min to reconnect
  without losing state. Creation-time TTL would expire
  during a long session.
- **Why same character only:** different characters
  should not share instance state (they're separate
  game entities). Per-character scoping enforces this.
- **Why idempotent finalize:** if the timer fires twice
  (bug, restart, etc.), we don't want to snapshot
  twice. Idempotence makes the code robust.

## 7. Technical Considerations

- **Godot 4.7.2** required (uses `Timer`, `Dictionary`).
- **Tests:** in `tests/test_open_seed_ttl.gd`.
- **State finalization:** calls a `state_finalizer.gd`
  helper (out of scope for this PRD; assumed to exist
  or be a future deliverable).
- **Manifest commit:** the locked seeds are committed
  to the `WorldManifest` (Postgres). The open seeds are
  released (no commit). The state tree is snapshotted
  to S3 (or equivalent) for audit.

## 8. Success Metrics

- All 6 user stories have passing tests
- Reconnect within window restores state
- TTL expiry triggers finalize
- Per-character scoping works
- One commit, pushed to main
- `labs/world-building-arch.md` §13 component map status
  updated: D032 from `TODO` to `DONE`

## 9. Open Questions

1. **Snapshot storage:** where do TTL-expiry snapshots
   go? My read: S3 (or equivalent), 30-day retention.
   For v1, just the call interface; the storage backend
   is a separate concern.
2. **Multi-shard reconnect:** what if a player logs out
   on shard A and logs in on shard B? My read: state
   is lost (different shard, different instance_seed).
   Cross-shard reconnect is a v2 concern.

## 10. Definition of Done

- [ ] `OpenSeedRegistry` autoload implemented
- [ ] `InstanceTypeDefinition` Resource implemented
- [ ] LoginService integrates with the registry
- [ ] State finalization on TTL expiry
- [ ] Tests passing
- [ ] `labs/world-building-arch.md` §13 component map
  updated
- [ ] Single commit, conventional message format
- [ ] Smoke test: enter dungeon, logout, reconnect
  within 5 min, verify same state tree root hash
