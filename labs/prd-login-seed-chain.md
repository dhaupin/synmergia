# PRD: Login Seed Chain (D029)

> **For:** sub-agent implementation
> **Phase:** 1 (per `world-building-arch.md` §14)
> **Depends on:** `prd-scope-engine.md` (the per-character stack is built on the scope engine), `prd-seed-schema.md`
> **Unblocks:** open seed TTL (D032), manifest backup (D031)

## 1. Introduction/Overview

On character login, the server sends the client four
seeds (world, shard, instance, player) so the client can
verify any state tree hash it receives. The seeds are
**character-scoped** (one per character, not per account)
and are sent during the character-select step (not the
account-login step). The seeds are signed by the server
to prevent tampering.

**Why this exists:** Per arch doc §4.1 (login seed chain
contract) and the validation's Tier-1 issue #1, the
client needs the seeds to verify state. Without them,
the client can't detect a compromised or stale state.
D029 formalizes the contract: 4 seeds, character-scoped,
signed.

**Spec ref:**
[`world-building-arch.md`](./world-building-arch.md) §4.1
(login seed chain), `world-building-risks.md` (D029
pending)

## 2. Goals

- Server sends 4 seeds on character select: `world_seed`,
  `shard_seed`, `instance_seed`, `player_seed`
- Plus the world's manifest hash (so client can verify
  the seeds are consistent with the world state)
- Plus a subscription to `/sync` broadcasts for late-joiners
- Seeds are signed (HMAC-SHA256 with server's key)
- Per-character, not per-account
- 5-min open seed TTL starts at last character logout
  (per D032)
- Tests cover: happy path, missing seeds, bad signature,
  re-login within window, re-login after window, late-join

## 3. User Stories

### US-001: SeedReceipt resource

**Description:** As a developer, I need a `SeedReceipt`
resource that holds the 4 seeds + manifest hash + signature,
so the client can deserialize the login response.

**Acceptance Criteria:**
- [ ] `SeedReceipt` class exists in
  `game/core/schemas/seed_receipt.gd`, extends `Resource`
- [ ] Fields: `world_seed: PackedByteArray`,
  `shard_seed: PackedByteArray`,
  `instance_seed: PackedByteArray`,
  `player_seed: PackedByteArray`, `manifest_hash:
  PackedByteArray`, `signature: PackedByteArray`,
  `issued_at: int` (Unix ms)
- [ ] Method: `func verify(server_key: PackedByteArray) -> bool` returns true if signature is valid
- [ ] Method: `func to_bytes() -> PackedByteArray` serializes for network transport
- [ ] Static method: `func from_bytes(b: PackedByteArray) -> SeedReceipt` deserializes

### US-002: LoginService emits SeedReceipt on character select

**Description:** As a developer, I need the login service
to emit a `SeedReceipt` event when a character is selected,
so the network layer can send it to the client.

**Acceptance Criteria:**
- [ ] `core/services/login_service.gd` has a new method
  `func build_seed_receipt(character_id: String) -> SeedReceipt`
- [ ] The method: looks up the character, walks the scope
  stack to find the relevant seed tree, derives the 4
  seeds, computes the manifest hash, signs with the
  server's key
- [ ] Emits signal `seed_receipt_ready(character_id,
  receipt: SeedReceipt)` when complete
- [ ] Network layer (`network_manager.gd`) listens to this
  signal and sends the receipt over the WebSocket as the
  first message after character-select ack
- [ ] Tests: happy path, missing character (returns null,
  emits error), missing scope (returns null)

### US-003: Client verifies and stores the receipt

**Description:** As a client developer, I need the client
to verify the receipt and store the 4 seeds, so any
future state hash can be checked.

**Acceptance Criteria:**
- [ ] Client-side `client/seed_receipt.gd` (or wherever
  client code lives) receives the receipt
- [ ] Verifies the signature using a server-key embedded
  in the client at build time
- [ ] Stores the 4 seeds in client-side config
- [ ] Stores the manifest hash for later comparison
- [ ] On bad signature: disconnects with an error toast
- [ ] On good signature: emits a `seeds_ready` event the
  rest of the client can subscribe to
- [ ] Tests: good signature, bad signature, missing fields,
  wrong key, replayed receipt (issued_at older than 60s
  → reject)

### US-004: Replay protection (issued_at timestamp)

**Description:** As a security-aware developer, I need
the client to reject receipts that are too old, so a
recorded receipt can't be replayed.

**Acceptance Criteria:**
- [ ] Receipt's `issued_at` is set by the server at
  generation time
- [ ] Client checks `now - issued_at < 60_000` (60 seconds
  tolerance)
- [ ] Reject if older
- [ ] Tests: fresh receipt (accept), 30s old (accept), 90s
  old (reject)

### US-005: /sync broadcasts for late-joiners

**Description:** As a developer, I need the server to
broadcast `world_seed` on `/sync` every 60s, so clients
that join mid-session get the current value.

**Acceptance Criteria:**
- [ ] `WorldService` (or equivalent) emits a
  `world_seed_broadcast(seed: PackedByteArray)` signal
  every 60s
- [ ] Network layer includes this in the `/sync` channel
- [ ] Late-joining clients receive the broadcast within
  60s of joining
- [ ] Shard/instance/player seeds are NOT broadcast (those
  are character-specific, not world-wide)
- [ ] Tests: broadcast fires, broadcast contains the
  current `world_seed`, no broadcast for non-world seeds

### US-006: 5-min open seed reconnect

**Description:** As a developer, I need the open seed
TTL to start at last character logout, so a player who
reconnects within 5 minutes gets the same instance state.

**Acceptance Criteria:**
- [ ] `OpenSeedRegistry` (or equivalent) tracks
  `character_id -> (instance_seed, last_logout_ms)`
- [ ] On character logout, the entry is added with the
  current timestamp
- [ ] On character login, if the entry exists and
  `now - last_logout_ms < 300_000` (5 min), reuse the
  same `instance_seed`
- [ ] If older than 5 min, generate a new `instance_seed`
  (the old instance is GC'd per D032)
- [ ] Tests: re-login within window (same seed), re-login
  after window (new seed), 5min+1ms (new seed)

## 4. Functional Requirements

- **FR-1:** One GDScript Resource `SeedReceipt` in
  `game/core/schemas/seed_receipt.gd`
- **FR-2:** LoginService emits `seed_receipt_ready` on
  character select
- **FR-3:** NetworkManager sends the receipt as the first
  message after character-select ack
- **FR-4:** Client-side seed receipt verification (HMAC-
  SHA256 with server key)
- **FR-5:** 60-second replay protection (issued_at)
- **FR-6:** /sync broadcasts `world_seed` every 60s
- **FR-7:** OpenSeedRegistry tracks 5-min TTL per
  character
- **FR-8:** Server key is loaded from a config file
  (not hardcoded), checked into source control for dev,
  rotated for prod
- **FR-9:** All seeds are 32 bytes (SHA-256 output size)

## 5. Non-Goals (Out of Scope)

- NO account-level seed delivery (per-character only)
- NO multi-factor seed encryption (HMAC-SHA256 is
  sufficient; the key is server-side)
- NO 3rd-party auth (this is in-game, not OAuth)
- NO seed rotation per-session (the seed is per-character,
  not per-session)
- NO seed commitment to the client at character-create
  time (only at character-select time; this is a future
  enhancement)

## 6. Design Considerations

- **Why per-character:** seeds are character-scoped
  (the player_seed is unique to a character, not an
  account). Per-character login flow makes this natural.
- **Why signed:** prevents a MITM from injecting fake
  seeds. The client embeds the server key at build time.
- **Why 60s replay window:** enough to cover clock skew
  - network latency, short enough to limit replay value.
- **Why 5-min open seed:** matches the open+instance TTL
  per D032. Reconnect within the window restores state.
- **Signature algorithm:** HMAC-SHA256. Fast, standard,
  doesn't need PKI.

## 7. Technical Considerations

- **Godot 4.7.2** required (uses `HMACContext`,
  `PackedByteArray`, `Resource`).
- **Tests:** in `tests/test_login_seed_chain.gd` (smoke
  test for the new login service flow).
- **Server key:** loaded from `srv/config/server.key` (a
  binary file). Generated on first run if missing, checked
  in for dev convenience. Prod uses a different key per
  environment.
- **Network protocol:** the receipt is sent as a binary
  blob (length-prefixed), not JSON. The network layer
  has a `seed_receipt` message type.

## 8. Success Metrics

- All 6 user stories have passing tests
- Login flow emits a receipt, client verifies, seeds are
  stored
- Replay protection rejects old receipts
- 5-min reconnect window restores same seed
- /sync broadcasts world_seed every 60s
- One commit, pushed to main
- `labs/world-building-arch.md` §13 component map status
  updated: D029 from `TODO` to `DONE`

## 9. Open Questions

1. **Server key rotation:** when the server key rotates,
   how do existing clients handle the new key? My read:
   the client gets the new key on next login (the key
   itself is signed by a long-lived root key). For v1,
   the key is static.
2. **Seed commitment at character create:** should the
   server commit to a player's seed at character creation
   (so the player can verify the world hasn't changed
   retroactively)? Out of scope for v1.
3. **Multi-account edge cases:** what if one account has
   multiple characters, each with a different player_seed?
   My read: each character has its own stack, each has
   its own seed. The login flow handles this naturally.

## 10. Definition of Done

- [ ] SeedReceipt Resource implemented and pushed to main
- [ ] LoginService emits seed_receipt_ready
- [ ] NetworkManager sends the receipt after character-
  select ack
- [ ] Client verifies and stores the receipt
- [ ] Replay protection works (60s window)
- [ ] /sync broadcasts world_seed every 60s
- [ ] OpenSeedRegistry tracks 5-min TTL
- [ ] Tests passing
- [ ] `labs/world-building-arch.md` §13 component map
  updated
- [ ] Single commit, conventional message format
- [ ] Smoke test: full login flow, receipt delivered,
  verified, seeds stored
