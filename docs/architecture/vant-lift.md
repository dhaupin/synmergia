# Vant Lift Manifest — Patterns to Cherry-Pick for the Synmergia Frame

> **TL;DR:** vant's `lib/` already implements most of the
> primitives the multi-iso frame needs. This is the lift list:
> for each vant module, what it does, what maps to the
> Synmergia frame, and the priority for translation.

**Author:** drafted 2026-08-30 after a deep walk through
[vant `lib/`](https://github.com/dhaupin/vant/tree/axolotl/lib).
Synmergia and vant are sibling repos by the same author
(dhaupin / minimax). The patterns are ours to lift.

---

## The principle

Vant solved a lot of the same problems Synmergia is solving:
event-driven architecture, capability checks, multi-provider
sync, recursion guards, lineaged decision tracking, geocoded
memory. The implementations are mature (v0.8.6 → v0.9.6,
thousands of lines, multibrain stack tested).

**The rule:** when a vant module does what a multi-iso
primitive needs, **lift the pattern, not the code**. The
implementation gets re-written in GDScript. The architecture
stays.

The lift is non-copyright because dhaupin and minimax wrote
both repos together. The license is MIT on both.

---

## The lift list (priority order)

### Tier 1: Lift first (the frame's foundation)

These are the primitives the multi-iso frame cannot exist
without. Vant has them. We translate.

#### 1. `lib/recursion.js` (534 lines) → `labs/multi-iso/srv/recursion.gd`

**What it is:** Unified recursion guard for ALL operations.
Per-operation depth tracking. `check` / `release` / `guard`
(sync) + async versions. Safe primitives: `batch(items,
processor)`, `traverse(root, getChildren, visitor)`,
`lookup(start, lookupFn)`, `retry(fn)` with exponential
backoff.

**Why we need it:** Every multi-iso primitive walks trees,
intersects sets, recurses through axes. Without a recursion
guard, infinite loops are one stack overflow away. The
existing synmergia `EventBus` has no guard at all.

**The safe primitives are the gold:**
- `batch()` — for processing entity lists with depth safety
- `traverse()` — for state tree walks
- `lookup()` — for axis-coord resolution
- `retry()` — for cache fill, network sync, DB ops

**Maps to:** `labs/multi-iso/srv/recursion.gd`. The
state tree's `diff` / `apply_diff` / `re_root` all use
`traverse`. The intersection materialization uses `batch`.

**Priority:** **P0 — lift in A-2 (foundation session).**

---

#### 2. `lib/event.js` (374 lines, MERGED 3 files) → `event_hub.gd` v2

**What it is:** Unified async events: `Event`, `PubSub`,
`Queue`, `Job`. Recursion guard at every emit. Multibrain
config (per-brain event settings). `once()` wrapper,
`clear()` per-type. Channel-based PubSub with `rooms` (join
semantics). `Queue` with concurrency control + `Job` state
machine (PENDING/RUNNING/COMPLETED/FAILED).

**Why we need it:** The synmergia `EventBus` is a simple
emit/on registry. Vant's is a full event platform with:
- Recursion guard (we need it)
- Job queue (we need it for the tick math)
- PubSub channels with rooms (we need it for the spatial
  axis broadcasts)

**Maps to:** `synmergia/core/events/event_hub.gd` (rewrite
to match vant's API) + `labs/multi-iso/srv/event_bus.gd`
(frame-side equivalent, no autoload).

**Priority:** **P0 — lift in A-2 (with recursion.gd).**

---

#### 3. `lib/cache.js` (420 lines, MERGED 4 files) → `labs/multi-iso/kv/lru_cache.gd`

**What it is:** LRU cache + transparent compression (gzip) +
buffer pool. Key validation (max 256 chars), value size cap
(10MB). Async lock for concurrency. `setSecured` /
`getSecured` pipeline-backed variants. Multibrain config.

**Why we need it:** The multi-iso orchestrator's
materialized intersection tables ARE an LRU. The state
tree's content hash cache IS an LRU. The LOD pyramid's
hot regions IS an LRU. Lift vant's cache wholesale and
adapt to GDScript.

**The pipeline-backed variants are the gold:**
- `setSecured()` / `getSecured()` go through the pipeline
  (capability check + VAF validate + QoS rate limit +
  escrow approval)
- For the multi-iso frame, this means every cache operation
  is auditable and rate-limited. Critical for the server
  tick math.

**Maps to:** `labs/multi-iso/kv/lru_cache.gd` (B-6).

**Priority:** **P0 — lift in B-6.**

---

#### 4. `lib/geometry/` (6 files) → `labs/multi-iso/math/`

**What it is:** The full geometric stack:
- `icosahedral.js` — 3D coordinate system (20 faces, 30
  edges, 12 vertices of the dual dodecahedron)
- `projection.js` — barcode → coord projection
- `tilings.js` — Penrose P3 distribution (aperiodic
  quasicrystal)
- `quasicrystal.js` — quasicrystal memory addressing
- `fragmenter.js` — fragment the geometry
- `engine.js` + `index.js` + README

**The README is a goldmine:**
> "Aperiodic Quasicrystal Memory Addressing for Vant"
> "Each unique (θ, φ, depth) triple maps to a unique
> position on the convex hull."
> "Standard linear storage has inherent collision
> problems. Quasicrystal addressing solves this by
> distributing across infinite aperiodic surface."

**The barcode format:**
```
1-31814-04200-8
31814 (digits 2-6) = rotational axis (θ = arctan(sin, cos))
04200 (digits 7-11) = projection depth into icosahedron
8 = checksum (ignored for addressing)
```

**Why we need it:** This IS the NSC-9 + icosahedral +
quasicrystal math the multi-iso frame plans to use. The
synmergia NSC-9 is `9-AAA-BBB-CCCCCC` (slightly different
format but same idea). The geometry README is the math
foundation. The implementations are the answer.

**Maps to:**
- `labs/multi-iso/math/icosahedral.gd` ← `icosahedral.js`
- `labs/multi-iso/math/quasicrystal.gd` ← `quasicrystal.js`
- `labs/multi-iso/math/projection.gd` ← `projection.js`
- `labs/multi-iso/math/tilings.gd` ← `tilings.js`
- `labs/multi-iso/math/fragmenter.gd` ← `fragmenter.js`

**Priority:** **P0 — lift in B-1 (math primitives session).**
This is the actual math the multi-iso docs reference but
haven't yet implemented.

---

### Tier 2: Lift second (the frame's connective tissue)

#### 5. `lib/pipeline.js` (550 lines) → `labs/multi-iso/srv/pipeline.gd`

**What it is:** Unified security pipeline for all
operations. Modes: PUBLIC (read), PRIVATE (write), REMOTE,
DUAL, STACK. Handler chain per mode: sandbox (capability) →
VAF (validate) → QoS (rate limit) → escrow (approve).

Plus a **runtime operator**: state machine for layer
initialization (stopped → starting → running → stopping →
stopped). This is the brain's lifecycle.

**Why we need it:** The grail path's pre/mid/post
orchestration IS a pipeline. The mid-state events flow
through it. The post-state ticks are gated by it. The
pipeline is what enforces:
- "Math is async, off the read path" (QoS gate on tick)
- "Capability-checked writes" (sandbox gate)
- "Rate-limited hot paths" (QoS gate)
- "Approved state changes" (escrow gate)

**Maps to:** `labs/multi-iso/srv/pipeline.gd` (the
orchestrator's enforcement layer). Plus a thin wrapper
in `synmergia/core/services/pipeline.gd` for game-side
operations.

**Priority:** **P1 — lift in A-3 (with the state tree).**
The pipeline is the *contract* that makes the pre/mid/post
distinction enforceable.

---

#### 6. `lib/qos.js` → `labs/multi-iso/srv/qos.gd`

**What it is:** Rate limiter + circuit breaker. Per-operation
throttling, exponential backoff, auto-retry. CircuitBreaker
class with `isClosed(provider)`, `recordFailure(provider)`,
`recordSuccess(provider)`. Multibrain config.

**Why we need it:** The grail path's tick math has a budget.
If the tick exceeds the budget, the QoS gates the next tick.
The circuit breaker is the safety valve: if the cache is
spamming misses, the breaker opens and the system falls
back to direct computation until the cache recovers.

**Maps to:** `labs/multi-iso/srv/qos.gd`. Sister to
`pipeline.gd` — the pipeline calls into QoS for rate
limiting. Used by the orchestrator's tick.

**Priority:** **P1 — lift in B-3 (with the event bus).**

---

#### 7. `lib/sync.js` (623 lines) → `synmergia/core/services/sync_service.gd`

**What it is:** Multi-provider sync with circuit breaker +
escrow budget. `pushAll` (broadcast to all), `pullAny` (read
from first available), `rebase` (recover). Provider health
tracking. Recursion guard at every sync operation.

**Why we need it:** The server↔client state tree sync IS a
multi-provider sync. Server is one provider. Each connected
client is a provider. Push = server broadcasts state diff.
Pull = client requests missed state. Rebase = re-sync after
disconnect.

The circuit breaker is the answer to "what if a client
disconnects mid-sync?" — the breaker opens for that client,
the system continues for others, the breaker closes when
the client reconnects.

**Maps to:** `synmergia/core/services/sync_service.gd` (or
`labs/multi-iso/srv/sync.gd` if it stays in the frame).

**Priority:** **P1 — lift in A-3 or A-4 (state tree +
multiplayer).**

---

### Tier 3: Lift for governance & community

#### 8. `lib/realm.js` (740 lines) → `CommunityGovernance` v2

**What it is:** "Unified Decision Space" tying forum +
consensus + governance + teams. Three features that are
directly applicable:

- **Lineage tracing** — every proposal has a parent
  proposal. The chain is the audit trail. **This is the
  state tree's content-hash chain applied to governance.**
  Each governance decision is a child of the prior state.
  The lineage is the hash.

- **Trust weighting** — per-agent vote weight. Used for
  predictions, anti-cheat, faction relationships. **This
  is the social axis in the multi-iso frame.**

- **Config gates** — `requireGovernance`, `requireOrgScope`,
  `allowAnonymous`, `minVoters`, `autoCloseDays`. **These
  are the safety rails for the frame's runtime config.**

**Why we need it:** The current `CommunityGovernance`
service is a voting wrapper. The realm pattern adds:
lineage (audit), trust (per-player weight), org-scoping
(multi-tenant isolation), cron governance (scheduled
decisions).

**Maps to:** `synmergia/core/services/community_governance.gd`
v2 (extends the existing service). Or a new
`labs/multi-iso/srv/governance.gd` for the frame's
governance primitives.

**Priority:** **P2 — lift in Phase 4-5 (Track A
community).**

---

#### 9. `lib/consensus.js` → `LabsCoordinationService`

**What it is:** Distributed consensus for multi-brain
agreement. Maps directly to **multi-server state
agreement**: when shards split a state, the consensus
module coordinates the merge.

**Why we need it:** The frame's multi-iso orchestrator
spawns one or more server instances per region. When two
servers have updates to the same axis range, they
need to merge. The consensus module is the merge
protocol.

**Maps to:** `synmergia/core/services/shard_coordinator.gd`
or `labs/multi-iso/srv/consensus.gd`. Reaches for the
multi-server work in Phase 6.

**Priority:** **P2 — lift in Phase 6 (MMO scale).**

---

## What NOT to lift

Some vant libs are vant-specific (the brain is a JSON
knowledge graph, the VAF is the policy validator, the
sudo is the human override). These don't translate:

- `lib/brain.js` — vant's content graph. Synmergia's
  state tree is the equivalent; no lift needed.
- `lib/vaf.js` — vant's policy validator. Synmergia
  has SecurityService; the design overlaps.
- `lib/sudo.js` — vant's human-override layer.
  Synmergia has AdminService.
- `lib/audit.js` — vant's audit log. Synmergia's
  AUDIT.md is the design-side equivalent; runtime
  audit can be a thin shim.
- `lib/storage.js` — vant's disk I/O. Synmergia uses
  Postgres + the snapshot store; the patterns are
  different.

The other ~70 vant libs (forum, market, telegram,
discord, forum, governance, etc.) are vant's product
features. None of them are frame primitives.

---

## The lift order (for the next 4 sessions)

| Session | Lift | Lands in | Lines |
|---------|------|----------|-------|
| **A-2** | `recursion.js` | `labs/multi-iso/srv/recursion.gd` | 200 |
| **A-2** | `event.js` (core) | `event_hub.gd` v2 | 300 |
| **B-1** | `geometry/` (full) | `labs/multi-iso/math/{icosahedral,quasicrystal,projection,tilings}.gd` | 800 |
| **B-3** | `event.js` (PubSub, Queue) | `labs/multi-iso/srv/{pubsub,queue}.gd` | 400 |
| **B-3** | `qos.js` | `labs/multi-iso/srv/qos.gd` | 250 |
| **A-3** | `cache.js` | `labs/multi-iso/kv/lru_cache.gd` | 350 |
| **A-3** | `pipeline.js` | `labs/multi-iso/srv/pipeline.gd` | 400 |
| **A-3** | `sync.js` (parts) | `labs/multi-iso/srv/sync.gd` | 350 |
| **Phase 4-5** | `realm.js` (lineage, trust, gates) | `CommunityGovernance` v2 | 500 |

Total: ~3,500 lines of translation. The implementations are
proven. The contracts are battle-tested (vant is at v0.9.6
with multibrain stack in production).

**The cost of NOT lifting:** we'd write these primitives
ourselves from scratch. The recursion guard alone is a
trap we already hit (the autoload cascade). The geometry
math is non-obvious. The pipeline contract is the
*enforcement* of the grail path. Skipping the lift means
months of work to reach what vant already has.

---

## The integration model

The lift isn't a fork. It's an architectural
re-implementation:

```
vant (Node.js, MIT)         →    Synmergia frame (GDScript, MIT)
lib/recursion.js            →    labs/multi-iso/srv/recursion.gd
lib/event.js                →    event_hub.gd + labs/.../event_bus.gd
lib/cache.js                →    labs/multi-iso/kv/lru_cache.gd
lib/geometry/               →    labs/multi-iso/math/
lib/pipeline.js             →    labs/multi-iso/srv/pipeline.gd
lib/qos.js                  →    labs/multi-iso/srv/qos.gd
lib/sync.js                 →    labs/multi-iso/srv/sync.gd
lib/realm.js (parts)        →    CommunityGovernance v2
```

**Same contracts. Different language. Same author, same
intent, sibling repos.**

The vant repo stays as the *reference implementation*. We
keep tests parity (GDScript tests mirror JS tests). When
we change the frame, vant's tests are the spec.

---

## Status

- [x] Lift list (this doc)
- [x] Priority order
- [ ] Recursion guard + event bus (A-2)
- [ ] Geometry primitives (B-1)
- [ ] QoS + PubSub (B-3)
- [ ] Cache + pipeline (A-3)
- [ ] Sync (A-3/A-4)
- [ ] Governance v2 (Phase 4-5)

## See also

- [`multi-iso-frame.md`](./multi-iso-frame.md) — the
  multi-iso orchestrator. The lift list maps primitives
  to this design.
- [`multi-iso-lod-prediction.md`](./multi-iso-lod-prediction.md) —
  Part 2. The lift list maps to LOD manager, predictor,
  prefetcher, markov.
- [`grail-path.md`](./grail-path.md) — the
  pre-materialized orchestration. The pipeline + QoS
  lift enforces this contract.
- [`labs-organization.md`](./labs-organization.md) — the
  /labs/ convention. Lifted primitives land here first.
- [`labs/jolt-playground/`](../labs/jolt-playground/README.md) —
  the C++ tier (Jolt). Not a vant lift, but a sister lab.
- [`labs/polyglot-ffi/`](../labs/polyglot-ffi/README.md) —
  the Julia tier. The polyglot FFI is itself a lift of
  vant's compute.js + connectors/.
- [`labs/prd.md §10.10`](../labs/prd.md#1010-three-tiers-of-computation-the-frame-runtime) —
  the three computation tiers. The lift is the Tier 1
  (GDScript) realization of vant's patterns.
