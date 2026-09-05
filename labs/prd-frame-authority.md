# PRD: Frame Seed Authority (D030)

> **For:** sub-agent implementation
> **Phase:** 1 (per `world-building-arch.md` §14)
> **Depends on:** `prd-scope-engine.md`, `prd-seed-schema.md`
> **Unblocks:** dream sequences, tutorial cells, jail cells, any "frame" content

## 1. Introduction/Overview

A "frame" is a transient, scoped environment where the
rules can be different (a dream, a tutorial, a jail cell).
The frame seed is **server-authoritative**: the server
generates the frame_seed, sends it to the client on frame
entry, and the client uses it for visual determinism.
Any persistent state (XP, items, etc.) goes to the state
tree, not the frame tree.

**Why this exists:** Per arch doc §4.2 (frame seed
authority) and the validation's Tier-1 issue #2, the
frame's authority model was ambiguous. D030 settles it:
server-side always. The frame env is built server-side,
seeded server-side, and never persisted.

**Spec ref:**
[`world-building-arch.md`](./world-building-arch.md) §4.2
(frame seed authority), `world-building-risks.md` (D030
pending)

## 2. Goals

- Frame env is server-side only (never client-side for
  state)
- Server generates the `frame_seed` on frame entry, sends
  to client
- Client uses `frame_seed` for visual determinism (client-
  side particle effects, UI animations, etc.)
- Persistent state (XP, items, faction) goes to the
  player's state tree, not the frame tree
- Frame env is GC'd at frame end (per arch doc §6.3
  per-scope-type TTL)
- Cross-frame state leak: explicitly prohibited
- Tests cover: frame entry, frame persistence (none),
  frame end, state leak prevention

## 3. User Stories

### US-001: FrameService creates frame env on entry

**Description:** As a developer, I need a `FrameService`
that creates a frame environment when a player enters
a frame, so the server has the source of truth.

**Acceptance Criteria:**
- [ ] `FrameService` exists in
  `game/core/services/frame_service.gd`
- [ ] Method: `func enter_frame(player_id: String, frame_id: String) -> bool`
- [ ] On entry: creates a new scope (push onto the
  player's stack), generates a new `frame_seed` (32
  bytes from `Crypto.random_bytes(32)`), initializes
  the frame's seed tree and state tree, sends the
  `frame_seed` to the client
- [ ] The frame's state tree is empty on creation (no
  cross-frame leak)
- [ ] Method: `func exit_frame(player_id: String) -> bool`
- [ ] On exit: pops the scope, GC's the frame env,
  signals any "frame complete" listeners (XP awarded,
  etc.)
- [ ] Tests: enter, exit, double-enter (rejected), exit
  without enter (rejected)

### US-002: Client receives and uses frame_seed

**Description:** As a client developer, I need the
client to receive the `frame_seed` and use it for
visual determinism.

**Acceptance Criteria:**
- [ ] Client receives `frame_seed` as part of the frame
  entry message
- [ ] Client stores the `frame_seed` in client-side
  config (scoped to the frame)
- [ ] Client uses `frame_seed` to seed the visual RNG
  (particle effects, UI animations, decorative layouts)
- [ ] On frame exit, client discards the `frame_seed`
- [ ] Tests: receive, store, use, discard

### US-003: Persistent state goes to state tree, not frame tree

**Description:** As a developer, I need the contract
that any state that should survive the frame end goes to
the player's state tree, not the frame tree.

**Acceptance Criteria:**
- [ ] Documented in `FrameService` docstring: "any
  persistent state must be written to the player's state
  tree, not the frame tree"
- [ ] Code review checklist: any state mutation during
  a frame that should persist must call
  `state_tree.insert(...)`, not `frame_tree.insert(...)`
- [ ] Tests: a state mutation during a frame that
  targets the state tree is preserved after frame exit;
  a state mutation that targets the frame tree is
  discarded

### US-004: Frame env GC at frame end

**Description:** As a developer, I need the frame
environment to be GC'd when the frame ends, so memory
doesn't leak.

**Acceptance Criteria:**
- [ ] `FrameService.exit_frame` removes the frame scope
  from the player's stack
- [ ] The frame env's trees (seed, state) are explicitly
  freed
- [ ] No references to the frame env remain after exit
  (verifiable via a `_refcount` debug print in dev mode)
- [ ] Tests: exit_frame → trees are null, stack is popped

### US-005: Cross-frame state leak prevention

**Description:** As a developer, I need a test that
verifies a state mutation in one frame doesn't leak to
another frame, so exploits are impossible by construction.

**Acceptance Criteria:**
- [ ] Test: player enters frame A, sets state, exits
  frame A. Player enters frame B. State from frame A
  is not visible in frame B.
- [ ] Test: player enters frame A, sets state, attempts
  to read state via `frame_tree.get("/...")` after exit.
  Returns null.
- [ ] Tests are part of `test_frame_authority.gd` smoke
  test

## 4. Functional Requirements

- **FR-1:** `FrameService` autoload in
  `game/core/services/frame_service.gd`
- **FR-2:** `enter_frame(player_id, frame_id)` creates a
  frame scope, generates `frame_seed`, builds env, sends
  to client
- **FR-3:** `exit_frame(player_id)` pops the scope, GC's
  the env
- **FR-4:** `frame_seed` is 32 bytes from
  `Crypto.random_bytes(32)`
- **FR-5:** Frame env's state tree is empty on creation
- **FR-6:** Persistent state mutations must target the
  player's state tree, not the frame tree
- **FR-7:** Frame env is GC'd at exit; no references
  remain

## 5. Non-Goals (Out of Scope)

- NO client-side frame state (the frame is server-side
  always)
- NO frame persistence across sessions (frames are
  ephemeral)
- NO frame state checkpointing (no save/restore)
- NO cross-frame inheritance (each frame is fresh)
- NO client-predicted frame entry (the server is the
  source of truth; client waits for the seed)

## 6. Design Considerations

- **Why server-authoritative:** prevents client-side
  exploits (player could fake a "completed dream" by
  locally generating a "completion" state). With server
  authority, the client can only render what's in the
  frame; the server decides what was achieved.
- **Why client uses frame_seed for visuals:** the client
  needs *some* determinism for visual effects. The
  frame_seed is a fine input for that — it's the
  server-provided seed for this frame.
- **Why state tree, not frame tree, for persistence:**
  the frame tree is GC'd at exit. Anything that should
  survive must be in the player's persistent state tree.
  This is enforced by convention + tests, not by the
  type system.

## 7. Technical Considerations

- **Godot 4.7.2** required (uses `Crypto.random_bytes`,
  `PackedByteArray`).
- **Tests:** in `tests/test_frame_authority.gd`.
- **Network protocol:** frame entry message includes
  `frame_id` and `frame_seed`. Frame exit message is a
  simple ack.
- **No external dependencies** beyond Godot stdlib.

## 8. Success Metrics

- All 5 user stories have passing tests
- Frame entry creates env, sends seed
- Frame exit GCs env, no leaks
- Cross-frame state leak prevention test passes
- One commit, pushed to main
- `labs/world-building-arch.md` §13 component map status
  updated: D030 from `TODO` to `DONE`

## 9. Open Questions

1. **Frame types:** should frame types be configured
   (per-frame-id rules), or hardcoded? My read: a
   `frame_config.tres` per frame type, loaded by
   `FrameService.enter_frame`. Out of scope for v1
   (just hardcode the dream tutorial as the example).
2. **XP / rewards at frame end:** should `exit_frame`
   trigger a "rewards" callback? My read: yes, via a
   signal. Frame content (e.g., a quest step) subscribes
   to the signal and grants rewards. Out of scope for
   the FrameService itself.

## 10. Definition of Done

- [ ] `FrameService` implemented and pushed to main
- [ ] enter_frame / exit_frame work
- [ ] Client receives frame_seed
- [ ] Cross-frame leak test passes
- [ ] Tests passing
- [ ] `labs/world-building-arch.md` §13 component map
  updated
- [ ] Single commit, conventional message format
- [ ] Smoke test: enter frame, mutate state, exit frame,
  verify GC
