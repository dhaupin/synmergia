# World-Building Risks, Decisions, Numbers, Glossary

> **Status:** Tracking companion to the trio. The plan
> (`world-building.md`) commits to a path; this doc tracks
> the **operating** parts: what we're worried about, what
> we decided and why, what numbers we claimed and whether
> we've measured them, and what all the terms mean.
>
> **Scope:** This is not a design document. It does not
> argue. It records. Each row in each table is a single
> decision, risk, number, or term with the surrounding
> context someone reading the plan in 6 months would need
> to reconstruct.
>
> **Companion docs:**
> - `world-building.md` — the plan
> - `world-building-research.md` — research on §21's
>   experimental angles
> - `m3-initial-world-audit.md` — where we were at the
>   start
>
> **Date opened:** 2026-09-05

---

## How to use this doc

### Read order by role

| If you are | Read in this order |
|---|---|
| **Starting Phase 1 work** | §2 (decisions) → §3 (numbers, your targets) → §1 (risks, what to watch) |
| **Reviewing the plan** | §2 (decisions) → §1 (risks) → §4 (glossary, if a term is unfamiliar) |
| **Investigating a perf problem** | §3 (numbers) → §1 (relevant risk) → §2 (decision you may need to revisit) |
| **Future agent, fresh context** | §4 (glossary first) → §2 (decisions) → §1 (risks) |
| **Six months from now, "why did we do that?"** | §2 (decisions) — each has reasoning + trigger to revisit |

### When to add an entry

- **Risk:** when something is reasonably likely to derail
  the plan, and the plan does not already say how to handle
  it. New risks go in §1, severity/Likelihood, with the
  trigger that would tell us it's real.
- **Decision:** when a choice is made (e.g. "spherical for
  v1") that future-you would want to know was made. New
  decisions go in §2.
- **Number:** when the plan quotes a concrete value
  ("50ms tick", "100KB/s") that someone will need to
  verify. New numbers go in §3.
- **Glossary term:** when a term appears in the plan or
  this doc and the definition is not obvious from context.
  New terms go in §4.

### When to update an entry

- A risk's likelihood changes.
- A decision's reasoning changes.
- A number is measured.
- A glossary term gets a second meaning (e.g. LOD level
  vs storage tier — see §4 conflict note).

### When to retire an entry

- A risk has been fully mitigated (move to "mitigated"
  status, then delete after 90 days clean).
- A decision has been superseded (link to the new decision,
  do not delete — the history is the value).
- A number is replaced by a more accurate measurement
  (update, do not delete).
- A glossary term is no longer used in the docs (delete).

### What this doc is NOT

- Not a design discussion. The plan discusses; this doc
  records.
- Not a todo list. §18 of the plan is the phase plan; this
  doc is the ops log.
- Not a journal. Entries are short, dated, and structured.
  Long-form reasoning lives in the plan or the research
  doc.
- Not exhaustive. Many choices in the plan are not listed
  here — only the ones a future reader would benefit from
  being reminded of. If the plan says "X is the case"
  without justifying it, that is a sign §2 needs an entry.

---

## 1. Risk register

Each risk has:
- **ID** — `R###` (preserved on update)
- **Name** — short
- **Phase** — when this matters (1, 2, 3, all, etc.)
- **Severity** — H / M / L (impact if it happens)
- **Likelihood** — H / M / L
- **Trigger** — the signal that would tell us the risk is
  becoming real
- **Mitigation** — what we do about it (today)
- **Status** — open / monitoring / mitigated / accepted
- **Owner** — who watches
- **Notes** — anything else

### 1.1 Performance risks

#### R001 — Godot HTML5 export has a perf cliff

- **Phase:** 1
- **Severity:** H
- **Likelihood:** M
- **Trigger:** Browser client at LOD L0 with 20 entities
  in AOI drops below 30 fps, or audio/Draw call count
  blows the per-frame budget.
- **Mitigation:** Profile early in Phase 1; have a
  "browser-lite" client mode (less AOI, lower LOD,
  cheaper post-FX). See plan §10.8.
- **Status:** open
- **Owner:** client team
- **Notes:** this is the single biggest reason v1 is
  spherical — smaller worlds need less client work.

#### R002 — WebSocket throughput insufficient

- **Phase:** 1, 4
- **Severity:** M
- **Likelihood:** L
- **Trigger:** Per-client bandwidth exceeds 200KB/s on
  diff traffic, or WebSocket frames exceed browser
  per-frame limit (~1MB).
- **Mitigation:** LZ4 + permessage-deflate + binary
  frames. Native fallback to ENet for power users
  (Phase 2+, see plan §10.10).
- **Status:** open
- **Owner:** transport team
- **Notes:** the CDN for static chunks (plan §11.11.4)
  removes most of the bandwidth concern if shipped early.

#### R003 — LOD pyramid mispredicts, causes stutter

- **Phase:** 3, 4
- **Severity:** M
- **Likelihood:** M
- **Trigger:** Players see visible "popping" when chunks
  promote/demote, or transition >100ms on 95p.
- **Mitigation:** Phase 4 has its own test for prediction
  accuracy; if the Markov predictor is right <70% of the
  time, we add a "preload neighbor" pass before promotion.
- **Status:** open
- **Owner:** LOD team
- **Notes:** the research doc §9 (adaptive tick rate) and
  §5 (MST) both interact with this. If diff cost dominates,
  the LOD work is a smaller fraction of the budget.

#### R004 — Procedural determinism fails across platforms

- **Phase:** 1
- **Severity:** H
- **Likelihood:** M
- **Trigger:** Two clients (any combination of Linux /
  Windows / macOS / browser) produce different content
  for the same seed + chunk address.
- **Mitigation:** Phase 1 test gate is the two-platform
  determinism check. If fails: reduce to single-platform
  v1; or restrict procedural to a pure-Rust port and call
  from GDScript. (See plan §7.13.)
- **Status:** open
- **Owner:** procedural team
- **Notes:** Godot's noise functions are deterministic
  across platforms in our testing, but third-party
  libraries (e.g. some Julia noise packages) are not.
  Avoid them in the generation pipeline.

### 1.2 Correctness & data risks

#### R005 — Postgres schema migrations break on running shards

- **Phase:** 1, 2, 3
- **Severity:** H
- **Likelihood:** M
- **Trigger:** A migration applied to one shard leaves
  it in a state where new schema operations fail, or
  where existing data is not properly transformed.
- **Mitigation:** Forward-only migrations; tested against
  a staging shard before prod. Migrations run during
  scheduled maintenance with rollback plan. (See plan
  §12.10.)
- **Status:** open
- **Owner:** storage team
- **Notes:** the bigger risk is rolling deploys —
  multiple shards on different versions. Keep the
  schema-versioning table mandatory; reject shards
  with version drift on connect.

#### R006 — Cross-shard conflict resolution causes lost updates

- **Phase:** 3
- **Severity:** M
- **Likelihood:** L
- **Trigger:** Two players edit the same ankh / hall /
  sign in different shards within the HLC window, and
  one edit silently disappears.
- **Mitigation:** Coordinator's last-write-wins is
  correct for our use cases (see plan §16.5). The HLC
  window is small enough that conflicts are rare. If
  observed in production, escalate to CRDT (plan §12.11,
  deferred to Phase 4+).
- **Status:** accepted
- **Owner:** coordinator team
- **Notes:** "rare enough to accept" is a value judgment.
  Guild master contested a placement? That's a real
  player-visible bug, not just a "rare" one. We should
  track incidents.

#### R007 — Content-hash collisions

- **Phase:** 1
- **Severity:** M (silent corruption)
- **Likelihood:** Very low (SHA-256)
- **Trigger:** Two distinct content values produce the
  same hash (would corrupt the state tree silently).
- **Mitigation:** SHA-256 is collision-resistant for our
  purposes. The canonical encoding (plan §5.4) is
  deterministic. We do NOT have an active collision test
  because false positives would mask the real problem;
  instead, we have a state-tree-root hash check on every
  diff.
- **Status:** monitoring
- **Owner:** state-tree team
- **Notes:** the real risk is canonicalization bugs, not
  hash collisions. Add a round-trip test: encode/decode
  10,000 random values, verify hash match.

#### R008 — Player-placed content is a vector for griefing

- **Phase:** 2
- **Severity:** M
- **Likelihood:** H
- **Trigger:** Players place visually-abusive ankhs,
  signs, or crops in high-traffic areas.
- **Mitigation:** Per-zone placement cap; per-player
  placement cap; admin takedown; report-and-remove flow.
  All in scope of the existing
  `CommunityGovernance` (see plan §15).
- **Status:** open
- **Owner:** governance team
- **Notes:** a world where the starting area gets covered
  in ugly signs is a world that loses players. This is
  not optional polish; it is a launch-blocker.

#### R009 — State tree diverges between client and server

- **Phase:** 1
- **Severity:** H
- **Likelihood:** M
- **Trigger:** Two clients viewing the same chunk show
  different terrain, or the same client sees terrain
  change after a logout/login.
- **Mitigation:** Phase 1 test gate: "two clients see the
  same tree after 1000 ticks" (plan §1.10). If fails:
  check canonical encoding first, then the
  hash(parent) chain, then the seed scope (§4.5).
- **Status:** open
- **Owner:** state-tree team
- **Notes:** almost always a determinism bug, almost
  never a network bug. Resist the urge to add retry
  logic; fix the cause.

### 1.3 Operational risks

#### R010 — Julia HTTP bridge is too slow

- **Phase:** 1, 2
- **Severity:** L
- **Likelihood:** L
- **Trigger:** Per-query latency to Julia >1ms, or
  per-tick batch >10ms.
- **Mitigation:** polyglot FFI in Phase 4+ (research
  doc §8). For Phase 1-3, accept the latency for
  uncached queries; rely on the LRU cache (plan §13.4)
  for hot intersections.
- **Status:** open
- **Owner:** multi-iso team
- **Notes:** the proto measured 40µs for 100K entities
  × 3 axes. Real workloads with HTTP overhead are ~5-10x
  that. Still acceptable for cached work; the cache
  matters.

#### R011 — 200 km² target unreachable on commodity hardware

- **Phase:** 4
- **Severity:** M
- **Likelihood:** L
- **Trigger:** Phase 4 measurements: 1000 concurrent
  players, full state tree, full LOD pyramid, on a
  single shard with budget hardware, exceeds CPU or
  memory target.
- **Mitigation:** We can shrink to 50 km² at any point —
  configuration not code change (plan §3.11). Or scale
  shards horizontally; or adopt edge shards (research
  doc §2) earlier.
- **Status:** open
- **Owner:** infrastructure team
- **Notes:** 50 km² is fine for a v1 launch. The 200 km²
  number is a stretch goal, not a constraint.

#### R012 — Pure-function-of-state discipline is too invasive

- **Phase:** 1, 2, 3
- **Severity:** M
- **Likelihood:** M
- **Trigger:** Engineers find that the discipline
  (every mutation is `(state, cmd, seed) →
  (state', result', seed')`) blocks more than 30% of
  planned features in Phase 1, or that the migration
  cost exceeds the wins.
- **Mitigation:** the discipline is gradual — Phase 1
  is the easy cases (procedural generation, chunk
  content). Game-logic migration in Phase 2+. If the
  cost dominates the wins, we keep the discipline for
  the "replayable" subset and accept impure for
  the rest. (See research doc §10.)
- **Status:** open
- **Owner:** state-team lead
- **Notes:** the research doc recommends this as the
  single highest-leverage discipline change. If we
  end up not doing it, that's a major decision, not
  a quiet retreat. Make it explicit in §2.

#### R013 — Coordinator process is a SPOF

- **Phase:** 3
- **Severity:** H
- **Likelihood:** M
- **Trigger:** Coordinator crashes; players see "you
  cannot join guild" errors; cross-shard events
  stall.
- **Mitigation:** HA-pair coordinator (active + standby
  with shared Postgres). Standby takes over within 5s
  on failure. (See plan §2.2, §16.)
- **Status:** open
- **Owner:** infrastructure team
- **Notes:** the user's PRD explicitly says coordinator
  is a separate process. This is the cost of that
  choice.

#### R014 — Wire format versioning breaks old clients

- **Phase:** 2
- **Severity:** M
- **Likelihood:** M
- **Trigger:** Server deploys a new wire format; old
  clients disconnect or display garbage.
- **Mitigation:** Version byte at the start of every
  frame (plan §11.6). Server tracks minimum
  supported client version. Clients below minimum
  are prompted to refresh.
- **Status:** open
- **Owner:** transport team
- **Notes:** this is the kind of thing that "just
  works" in testing and breaks in production. Add
  a staged rollout.

#### R015 — Browser audio/mic permissions rejected

- **Phase:** 1
- **Severity:** L
- **Likelihood:** M
- **Trigger:** Players in noisy environments can't
  use voice. Or browsers that don't support our
  audio codec refuse the page.
- **Mitigation:** Voice is optional in v1; chat is
  text-only. No mitigation needed for v1.
- **Status:** accepted
- **Owner:** client team
- **Notes:** tracked here so the next agent doesn't
  rediscover "we don't have voice".

### 1.4 Risk summary

- **Open:** R001, R002, R003, R004, R005, R008, R009,
  R010, R011, R012, R013, R014
- **Monitoring:** R007
- **Accepted:** R006, R015

Total: 15 risks. H severity: R001, R005, R009, R013.
The four H-severity risks are all Phase 1+ — that's
the right time to deal with them, but also when the
project has the least slack. Plan accordingly.

---

## 2. Decision log

Each decision has:
- **ID** — `D###` (preserved on update)
- **Decision** — what we chose
- **Phase** — when this applies
- **Decided** — date (ISO)
- **Alternatives rejected** — what we did not pick
- **Reasoning** — why this and not that
- **Trigger to revisit** — the signal that would make
  us change
- **Status** — committed / provisional / superseded
- **Superseded by** — link to newer decision, if any

### 2.1 World shape & scale

#### D001 — Spherical for v1, planar supported

- **Phase:** 1
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Planar-only v1
  - Spherical-only forever
- **Reasoning:** Spherical exercises the harder math
  first (icosahedral projection, antimeridian wrap,
  mixed subdivision). Planar is a degenerate spherical
  case. The geometric-addressing payoff lands on day one.
  (See plan §3.12.)
- **Trigger to revisit:** if R001 (HTML5 perf) or
  the geometric layer costs more than 5% of client
  frame budget at LOD L0, consider a planar-first v1.
- **Status:** committed
- **Superseded by:** —

#### D002 — v1 is 20 km planet, 150 km² continent

- **Phase:** 1
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - 200 km² (the original "200km²" framing in
    `scale-200km2.md`)
  - 40,000 km² full Earth-like
- **Reasoning:** 200 km² too big for v1; full Earth too
  big. 20 km planet, 150 km² continent hits the sweet
  spot of "test all the systems, ship in 6 months,
  scale later." Scaling is a config change, not a code
  change. (See plan §3.9, §3.11.)
- **Trigger to revisit:** if the 150 km² number turns
  out to be too big for Phase 1 perf targets, shrink
  to 50 km².
- **Status:** committed
- **Superseded by:** —

#### D003 — Open world first, instanced for dungeons/arena

- **Phase:** 1, 2
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Pure-instanced (WoW-style)
  - Pure-sharded (Minecraft realms)
- **Reasoning:** open-world-first exercises the
  state-tree, the LOD pyramid, the procedural
  generation, and the multi-iso orchestrator. Pure
  instances avoid the hardest problems. (See plan
  §3.9, §8.5.)
- **Trigger to revisit:** if the open-world path
  turns out to have a perf cliff that the instance
  path doesn't, we may add more instances in v2.
- **Status:** committed
- **Superseded by:** —

#### D004 — 64m chunks (planar), subdivision level 5 (spherical)

- **Phase:** 1
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - 32m chunks (more cells, more hash work)
  - 128m chunks (too coarse for AOI of 100m)
- **Reasoning:** 64m is "twice the player radius" — a
  player's AOI is fully inside at most 9 cells (3×3).
  Fits 20,480 faces for the v1 20 km planet at
  subdivision 5. (See plan §3.10.)
- **Trigger to revisit:** if the LOD pyramid in Phase 3
  shows transition >100ms, consider 32m chunks
  (denser = smaller promoted regions).
- **Status:** committed
- **Superseded by:** —


### 2.2 Architecture & topology

#### D005 — Coordinator is a separate process (not a flag)

- **Phase:** 1
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - "Coordinator mode" flag on a shard process
  - Coordinator as a service inside every shard
- **Reasoning:** Guilds and factions are not owned by
  any single shard. Cross-shard state deserves a
  process that doesn't share failure modes with
  gameplay shards. HA-pair scales independently.
  (See plan §2.1, §16.)
- **Trigger to revisit:** if R013 (coordinator SPOF)
  materializes more than once in production, reconsider
  distributed consensus. Otherwise, leave as-is.
- **Status:** committed
- **Superseded by:** —

#### D006 — WebSocket only for client↔server (browser-first)

- **Phase:** 1
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - ENet for all clients
  - WebSocket + ENet hybrid from day one
- **Reasoning:** Godot HTML5/wasm has no raw socket
  support. Browser is the v1 target. Native clients
  can opt into ENet in Phase 2+ via the P2P lane.
  (See plan §1.7, §10.10.)
- **Trigger to revisit:** if R002 (WebSocket throughput)
  fires for the power-user market we want to attract,
  bring the P2P lane earlier.
- **Status:** committed
- **Superseded by:** —

#### D007 — State tree = content-hash, not path-keyed

- **Phase:** 1
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Path-keyed KV (like Redis)
  - Append-only event log
- **Reasoning:** Content-hashing gives us diff-by-skip
  (subtrees with the same hash are unchanged). The
  re-root-per-tick is cheap. Cross-shard sync becomes
  "send the diff" instead of "send the whole tree".
  (See plan §5, §11.6.)
- **Trigger to revisit:** if R003 (LOD mispredict) +
  R009 (state tree divergence) combine to suggest the
  hash cost dominates, we can swap to MST (research
  doc §5) for the same property at lower per-tick cost.
- **Status:** committed
- **Superseded by:** —

#### D008 — Three-tier runtime: GDScript / Julia / C++

- **Phase:** 1, 4
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - GDScript only
  - GDScript + Rust
  - GDScript + Julia only (no C++)
- **Reasoning:** GDScript for game code (Godot-native).
  Julia for multi-iso orchestrator (the math is concise
  in Julia). C++ for hot paths (physics, codec, diff
  encoder). Each tier has a clear cost/benefit. (See
  plan §17, research doc §8.)
- **Trigger to revisit:** if R010 (Julia bridge slow)
  fires consistently, FFI Julia in via JLL or
  in-process (research doc §8) — and reconsider
  whether Julia is the right choice at all.
- **Status:** committed
- **Superseded by:** —

#### D009 — Player-placed content is world state, not housing-DB

- **Phase:** 2
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Separate "housing database" with its own
    storage and sync
  - World state + housing DB hybrid
- **Reasoning:** One state tree is simpler. The same
  diff protocol works for terrain, ankhs, halls,
  signs, crops. No second-class data. (See plan §1.9,
  §15.)
- **Trigger to revisit:** if R008 (griefing) becomes
  the dominant content moderation cost, we may need
  a separate anti-griefing layer that indexes
  "high-frequency-edit" content separately.
- **Status:** committed
- **Superseded by:** —

#### D010 — Diff protocol is the wire format

- **Phase:** 1
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Custom per-system messages
  - Full state snapshots every N ticks
- **Reasoning:** One protocol for all sync (gameplay,
  world, cross-shard). The content-hash diff is small.
  Client applies diffs, server emits diffs. Symmetric
  + simple. (See plan §10.3, §11.)
- **Trigger to revisit:** if diff size exceeds ~5KB
  on average, consider batching multiple diffs into
  a single frame (still diff, just compressed in
  time, not in protocol).
- **Status:** committed
- **Superseded by:** —

### 2.3 Generation & simulation

#### D011 — Generation at LOD-promotion time, not seed time

- **Phase:** 1, 2
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Generate everything at seed time
  - Generate per-tick
- **Reasoning:** Generation is expensive. Only generate
  what the player is near. Promotion is rare (a chunk
  goes from cold to warm). 99% of the world is never
  generated. (See plan §7, §14.)
- **Trigger to revisit:** if generation-on-promotion
  blocks LOD transition (R003), consider a
  pre-generation queue that runs while the player
  is far away.
- **Status:** committed
- **Superseded by:** —

#### D012 — Pure-function-of-state discipline for procedural

- **Phase:** 1
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Stateful procedural with side effects
  - Hybrid (stateful for entities, pure for terrain)
- **Reasoning:** Procedural generation is the cleanest
  case for pure functions: `(seed, address, pass) →
  content`. No state to mutate. This is the beachhead
  for the discipline; game logic in Phase 2+. (See
  plan §7, research doc §10.)
- **Trigger to revisit:** if R012 (discipline too
  invasive) fires for procedural, we may back off
  to "pure for the cacheable subset" only.
- **Status:** committed
- **Superseded by:** —


### 2.4 Storage & persistence

#### D013 — Postgres + Redis, no other tier

- **Phase:** 1
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Postgres + Memcached
  - Postgres + RocksDB
  - Custom in-memory store
- **Reasoning:** Postgres for durable state (snapshot
  roots, player-placed content, audit log). Redis for
  hot (tick cache, materialized intersections,
  session). Both have ops expertise; both are
  commodity. Don't introduce a third tier. (See plan
  §12.)
- **Trigger to revisit:** if Redis becomes the
  bottleneck at >10K concurrent sessions, evaluate
  whether a tier-zero in-process LRU
  (per-shard) makes sense. Probably not — Redis
  scales horizontally too.
- **Status:** committed
- **Superseded by:** —

#### D014 — CDN for static chunks is Phase 1

- **Phase:** 1
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Defer CDN to Phase 4+
  - Self-hosted S3-compatible store
- **Reasoning:** Content-hash means the CDN can
  trivially serve chunks. Massive bandwidth win
  (~10x reduction) for negligible effort. The chunk
  is the address. (See plan §11.11.4.)
- **Trigger to revisit:** if the CDN cost >2x the
  self-host cost, evaluate self-host. (Probably
  never; CDN is cheap.)
- **Status:** committed
- **Superseded by:** —

#### D015 — Last-write-wins for cross-shard conflicts (Phase 1-3)

- **Phase:** 1, 2, 3
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - CRDT (commutative) for everything
  - Operational transform (OT)
  - Pessimistic locking
- **Reasoning:** Most cross-shard conflicts are rare
  (two players editing the same ankh). When they
  happen, last-write-wins is acceptable. CRDT is the
  v2 upgrade (deferred to Phase 4+). (See plan
  §12.11, §16.5.)
- **Trigger to revisit:** if R006 (lost updates) is
  observed >1/week in production, escalate CRDT.
- **Status:** provisional
- **Superseded by:** —

### 2.5 Deferrals and promotions

#### D016 — P2P chunk sync PROMOTED from deferred to Phase 2

- **Phase:** 2
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Keep P2P as Phase 4+ (original PRD §10.4)
  - Server-mediated only, no peer
- **Reasoning:** User flagged as high-leverage. Native
  clients on good networks can pull chunks from each
  other, reducing server bandwidth. (See plan §10.10.)
- **Trigger to revisit:** if NAT-traversal failures
  exceed 20% of native-client connections, revert
  to server-mediated only.
- **Status:** committed
- **Superseded by:** —

#### D017 — Jolt Physics deferred to Phase 5+

- **Phase:** 5+
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Jolt from Phase 1
  - Godot Physics 3D only, forever
- **Reasoning:** Godot Physics 3D is good enough for
  v1-v4. Jolt is 2-5x faster and fully deterministic,
  but the integration cost is real. Phase 5 is the
  "we have the player count to justify it" gate.
  (See plan §19.3, research doc §7.)
- **Trigger to revisit:** if v4 ships and physics
  dominates server CPU, move Jolt to Phase 4.
- **Status:** committed
- **Superseded by:** —

#### D018 — Quasicrystal experimental deferred to Phase 6

- **Phase:** 6
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Penrose tiling from Phase 1
  - Ammann-Beenker from Phase 1
- **Reasoning:** Icosahedral geometry works for v1
  with mixed subdivision levels. Quasicrystal is a
  research project, not a production path. Only
  pursued if icosahedral seams become user-noticeable.
  (See plan §19.3, research doc §1.)
- **Trigger to revisit:** if player-visible seams
  appear on the v1 planet, move the research
  budget to Phase 4. (Likely never.)
- **Status:** committed
- **Superseded by:** —

#### D019 — Edge shards deferred to Phase 4+

- **Phase:** 4+
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Edge shards from Phase 1
  - Edge shards from Phase 2
- **Reasoning:** Edge shards are an
  infrastructure-for-scale choice. We don't need them
  until >5000 active players per shard. Building
  them earlier is premature. (See plan §19.3, research
  doc §2.)
- **Trigger to revisit:** if Phase 3 measurements
  show >5000 active players per shard in production,
  move edge shards to Phase 3+.
- **Status:** committed
- **Superseded by:** —

### 2.6 Decision summary

- **Committed:** D001, D002, D003, D004, D005, D006,
  D007, D008, D009, D010, D011, D012, D013, D014,
  D016, D017, D018, D019, D020, D021, D022, D023,
  D024
- **Provisional:** D015 (last-write-wins — explicit
  revisit trigger)

Total: 24 decisions. 23 committed, 1 provisional.
The provisional one (D015) is the one most likely
to be re-litigated.

### 2.7 Tick model decisions (D020-D024)

The five new decisions in this batch are all
related to the tick model and the flywheel pattern
(see plan §9.14-9.17, `labs/world-building-tick.md`
for the full discussion). Settled 2026-09-05.

#### D020 — Adaptive heartbeat, flywheel-driven

- **Phase:** 1+
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - 50ms fixed (original plan §9.1)
  - 100ms fixed (half the cost, slow for combat)
  - 33ms fixed (smoother but unnecessary)
- **Reasoning:** The vant flywheel pattern is
  adaptive by design. A 50ms-fixed heartbeat wastes
  ~3% of CPU on idle shards. Adaptive
  (50/100/200ms based on flywheel momentum) keeps
  the response time low under load and lets idle
  shards breathe. The N001 measurement becomes
  "p99 tick interval" instead of "tick interval."
  (See plan §9.1.)
- **Trigger to revisit:** if N001 measurements
  show idle shards spending >10% CPU on tick
  overhead, lower the floor further. If combat
  shards show p99 > 75ms, raise the high-load
  rate.
- **Status:** committed
- **Superseded by:** —

#### D021 — Defer with flywheel as awareness layer

- **Phase:** 1+
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Drop next tick on overrun (hides the problem)
  - Extend the tick (bad for action combat)
  - Defer to side queue, no awareness (can't tell
    which subsystem to thin)
- **Reasoning:** The side queue is the defer
  policy; the flywheel is the response policy.
  Together they answer: who, what subsystem,
  where to slim, is there an exploiter, is there
  a race, what's the health. Without the
  flywheel, deferral is just "hide inputs." With
  it, deferral is informed. (See plan §9.9,
  tick-doc §8 Q1.)
- **Trigger to revisit:** if load-shedding
  triggers fire on >10% of ticks, redesign
  (probably with explicit overflow policies).
- **Status:** committed
- **Superseded by:** —

#### D022 — Monitorability commitment (everything is a chaos source)

- **Phase:** 1+
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Chaos sources are the curated list (player
    inputs, mob AI, cross-shard, time)
  - Chaos sources are per-service opt-in
- **Reasoning:** Without "everything is a chaos
  source," observability is opt-in. New
  services can be added without being observed.
  With the commitment, every signal in the events
  system is automatically flywheel-feedable. The
  flywheel becomes the single load-profiling
  abstraction for the entire game. The cost is
  trivial (per-event O(1)); the benefit is
  structural. (See plan §9.17, tick-doc §5.6.)
- **Trigger to revisit:** if EventBus observers
  themselves become a bottleneck (unlikely; O(1)
  per event), reconsider.
- **Status:** committed
- **Superseded by:** —

#### D023 — Per-player flywheel for security and anticheat

- **Phase:** 2 (after shard-level flywheel lands)
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Centralized security scan (O(N×M) per tick)
  - Sampled anomaly detection (latency + misses)
  - Per-player flywheel *only* (loses shard-level
    load profiling)
- **Reasoning:** Inverts the security model.
  Instead of scanning every player, each
  player's flywheel IS the anomaly detector.
  Cost: O(N) per tick + O(K) per trigger. The
  per-player snapshot is the evidence for
  AutoResponse. Maps to existing
  SecurityService / AutoResponseService /
  AppFirewall. (See plan §9.16, tick-doc §9.)
- **Trigger to revisit:** if the snapshot
  evidence is insufficient for player appeals
  (false positive rate), add additional
  context. If a careful cheater consistently
  evades, supplement with other detection
  signals.
- **Status:** committed
- **Superseded by:** —

#### D024 — Flywheel snapshot triggers and discard rules

- **Phase:** 1+ (shard-level), 2+ (per-player)
- **Decided:** 2026-09-05
- **Alternatives rejected:**
  - Always-persist (I/O cost on hot path)
  - Never-persist (loses postmortem value)
  - Persist without discard rules (stale
    snapshots are dangerous)
- **Reasoning:** Ephemeral by default; snapshot
  on trigger; restore on boot if recent. Five
  write triggers: high-entropy (>80% of max),
  planned event, SIGTERM, resource pressure,
  crash recovery. Three discard rules: >1h old,
  world seed rolled, operator flag. Hot path
  unchanged (one Redis op on trigger, not per
  tick). (See plan §9.14, tick-doc §5.3-5.4.)
- **Trigger to revisit:** if Redis becomes a
  bottleneck, move snapshot to Postgres or a
  per-shard mmap'd file. If discard rules
  discard too aggressively, extend the TTL.
- **Status:** committed
- **Superseded by:** —

---

## 3. Numbers ledger

Each number has:
- **ID** — `N###`
- **Claim** — what the plan says
- **Target** — the value the plan commits to
- **Phase** — when it matters
- **Source** — where in the plan
- **How to measure** — the test that produces this
  number
- **Current** — the latest measurement (or `—` if
  unmeasured)
- **Status** — target / measured / pending / missed
- **Notes** — anything else

### 3.1 Time & frequency

#### N001 — Server tick rate (adaptive, D020)

- **Claim:** tick at 50ms (20 Hz) under high load;
  100ms (10 Hz) under normal load; 200ms (5 Hz) when
  idle. Driven by shard-level flywheel momentum.
- **Target:** p99 of *tick interval* < 75ms under
  high load; < 125ms under normal; < 250ms idle.
- **Phase:** 1.
- **Source:** plan §9.1, D020.
- **How to measure:** record tick interval + the
  flywheel bucket (high / normal / idle) for each
  tick over 10,000 ticks. Assert:
  - p99 high-load interval < 75ms
  - p99 normal-load interval < 125ms
  - p99 idle interval < 250ms
  - Adaptive rate transitions happen within 5 ticks
    of flywheel crossing a threshold.
- **Current:** —.
- **Status:** target (unmeasured).
- **Notes:** the tick is the heartbeat. Everything
  downstream (LOD, diff, sync) is bounded by it.
  The N001 measurement is "p99 tick interval" not
  "tick interval" — D020 changed the shape of this
  number. This is the first number to be measured in
  Phase 1.

#### N002 — LOD tick rate

- **Claim:** LOD pyramid runs at 10 Hz.
- **Target:** 10 Hz (100ms cycle).
- **Phase:** 3.
- **Source:** plan §14, §9.12.
- **How to measure:** time the `_lod_tick()` body over
  10,000 ticks with 1000 active players; assert
  p95 < 100ms.
- **Current:** —.
- **Status:** target (unmeasured).
- **Notes:** the LOD tick does prediction, promotion,
  demotion. Slower than the main tick by design —
  it batches more work.

#### N003 — Diff sync rate

- **Claim:** state diffs emit at 2 Hz to client.
- **Target:** 2 Hz (500ms cycle).
- **Phase:** 1.
- **Source:** plan §11.
- **How to measure:** time between consecutive
  diff frames from server to a stationary client.
- **Current:** —.
- **Status:** target (unmeasured).
- **Notes:** the diff rate is decoupled from the
  tick rate. A stationary client with no nearby
  changes gets fewer diffs; near combat gets more.
  This is a max, not a constant.

### 3.2 Space & geometry

#### N004 — v1 planet radius

- **Claim:** v1 planet is 20 km radius.
- **Target:** 20 km.
- **Phase:** 1.
- **Source:** plan §3.9.
- **How to measure:** static config; verified by
  reading `data/worlds/v1.tres`.
- **Current:** 20 km (config).
- **Status:** target.
- **Notes:** v1. v2 is 100 km. v3 is 1000+ km.
  Same code, different config.

#### N005 — v1 landmass

- **Claim:** one continent, 150 km².
- **Target:** 150 km².
- **Phase:** 1.
- **Source:** plan §3.9, §3.11.
- **How to measure:** static config; verified by
  reading `data/worlds/v1.tres`.
- **Current:** 150 km² (config).
- **Status:** target.
- **Notes:** the continent is configured by the
  biome / coastline generator. The "150 km²"
  is the design target; the actual generated
  area depends on the generator.

#### N006 — Chunk size (planar)

- **Claim:** 64m chunks.
- **Target:** 64m cube.
- **Phase:** 1.
- **Source:** plan §3.10, D004.
- **How to measure:** static config; verified by
  chunk address arithmetic.
- **Current:** 64m (config).
- **Status:** target.
- **Notes:** see D004 for the why. Denser chunks
  (32m) are an option if R003 fires.

#### N007 — Chunk count (v1 planet)

- **Claim:** 20,480 faces at subdivision 5.
- **Target:** 20,480.
- **Phase:** 1.
- **Source:** plan §3.10.
- **How to measure:** static calc — `20 × 4^5`.
- **Current:** 20,480 (calc).
- **Status:** target.
- **Notes:** average edge ~250m, average face area
  ~0.24 km². Hot 1% (205 faces) in RAM; the rest
  is content-hashed and immutable.

#### N008 — AOI radius

- **Claim:** AOI defaults to 100m.
- **Target:** 100m.
- **Phase:** 1.
- **Source:** plan §11.2.
- **How to measure:** server config; client
  request.
- **Current:** 100m (config).
- **Status:** target.
- **Notes:** client can request VOI-extension
  (scouting, map view); server can grant
  expanded AOI on demand.

#### N009 — Region size

- **Claim:** 256m–2km group of chunks.
- **Target:** 256m (4×4 chunks) – 2km (32×32 chunks).
- **Phase:** 1, 2.
- **Source:** plan §5.11 (region table).
- **How to measure:** static config + procedural
  generator; verified by inspection.
- **Current:** 256m–2km (config).
- **Status:** target.
- **Notes:** regions are the authoring unit.
  Designers place content "in region R" rather
  than "at world coordinate X".

#### N010 — Projection cost

- **Claim:** ~1µs per axis per entity at spawn.
- **Target:** <5µs per axis per entity.
- **Phase:** 1.
- **Source:** plan §6.7.
- **How to measure:** benchmark with 100,000 entities.
  Compare to `iso_math.py` proto (40µs for 3 axes).
- **Current:** 40µs / 3 axes (proto).
- **Status:** measured (proto).
- **Notes:** the proto measured 40µs for 3-axis
  intersection with 100K entities. Per-axis is
  ~13µs. Above the target, but the proto is
  Python, not GDScript; we expect 5-10x speedup.

### 3.3 Network & bandwidth

#### N011 — Per-client bandwidth

- **Claim:** 60–100KB/s per client for diff traffic.
- **Target:** <100KB/s.
- **Phase:** 1.
- **Source:** plan §11.10.
- **How to measure:** 10-minute soak with 100
  clients doing various activities (combat,
  trade, travel); measure per-client bandwidth.
- **Current:** —.
- **Status:** target (unmeasured).
- **Notes:** this is the "browser-friendly" budget.
  Above 100KB/s, R002 (WebSocket throughput) is
  at risk.

#### N012 — Per-tick diff size

- **Claim:** ~5KB per diff frame (stationary) to
  ~20KB (combat).
- **Target:** <5KB stationary, <20KB combat.
- **Phase:** 1.
- **Source:** plan §11.10.
- **How to measure:** measure diff frame size
  across 10,000 frames in each scenario.
- **Current:** —.
- **Status:** target (unmeasured).
- **Notes:** the diff size drives N011. A
  stationary player gets fewer diffs (a few KB
  per minute) but they're bigger; a combat
  player gets many small diffs.

#### N013 — LRU cache size

- **Claim:** 1000 entries in Redis.
- **Target:** 1000 entries.
- **Phase:** 1.
- **Source:** plan §13.4.
- **How to measure:** Redis `OBJECT IDLETIME`;
  measure hit rate over 10,000 queries.
- **Current:** 1000 (config).
- **Status:** target.
- **Notes:** 1000 entries × ~1KB each = ~1MB Redis
  memory. Trivial. The right size is empirical;
  tune in Phase 2.

#### N014 — Tick alignment

- **Claim:** diffs are tick-aligned (sent on tick
  boundaries, not mid-tick).
- **Target:** 100% tick-aligned.
- **Phase:** 1.
- **Source:** plan §11.3.
- **How to measure:** record send timestamp;
  assert all are within ±2ms of a tick boundary.
- **Current:** —.
- **Status:** target (unmeasured).
- **Notes:** this is what makes lag compensation
  tractable. If it slips, R009 (state tree
  divergence) is more likely.

### 3.4 Storage tiers

#### N015 — L1 (summary) chunk size

- **Claim:** ~5KB per L1 summary chunk.
- **Target:** <5KB.
- **Phase:** 1, 3.
- **Source:** plan §5.11 (LOD table).
- **How to measure:** serialize a representative
  L1 summary (4×4 L0 aggregate); measure bytes.
- **Current:** —.
- **Status:** target (unmeasured).
- **Notes:** the L1 contains biome, poi count,
  mob count, no terrain mesh. This is the
  "neighborhood summary" tier.

#### N016 — All-hash total

- **Claim:** 655KB for all 20,480 v1 chunks (just
  hashes).
- **Target:** <1MB.
- **Phase:** 1.
- **Source:** plan §3.10.
- **How to measure:** `20,480 × 32 bytes` = 655,360
  bytes.
- **Current:** 655,360 (calc).
- **Status:** target.
- **Notes:** just the hash pointers. The full
  L0 content for hot chunks is much larger
  (each chunk is a few MB uncompressed).

#### N017 — Snapshot frequency

- **Claim:** Postgres snapshot every N ticks
  (TBD).
- **Target:** TBD; tradeoff between recovery
  time and write cost.
- **Phase:** 1, 2.
- **Source:** plan §12.4.
- **How to measure:** recovery time vs write
  throughput, swept.
- **Current:** —.
- **Status:** target (TBD).
- **Notes:** this is a "we'll set it in Phase 2"
  number. The plan does not commit. Tracked
  here so it doesn't get lost.

#### N018 — Migration rate

- **Claim:** forward-only migrations; tested on
  staging before prod.
- **Target:** 100% migrations staged.
- **Phase:** 1+.
- **Source:** plan §12.10, R005.
- **How to measure:** count migrations that hit
  prod without staging; assert zero.
- **Current:** — (no migrations yet).
- **Status:** target.
- **Notes:** the policy is clear; the measurement
  is the count of bypasses.

### 3.5 Concurrency & scale

#### N019 — Max players per shard

- **Claim:** up to 5,000 active players per shard.
- **Target:** 5,000.
- **Phase:** 4.
- **Source:** plan §18.4, ShardManager default.
- **How to measure:** production load test
  (10K concurrent); assert p95 tick < 50ms.
- **Current:** 5,000 (config).
- **Status:** target.
- **Notes:** the original `ShardManager.max_players_per_shard`
  default. Above 5K, edge shards (D019) come
  online. Below 5K, no edge shards needed.

#### N020 — ECS primitive cost

- **Claim:** per-entity work scales linearly with
  the entity count; ECS primitive handles 10K
  entities in microseconds.
- **Target:** <10µs per entity per tick.
- **Phase:** 2.
- **Source:** plan §9.13, research doc §10.
- **How to measure:** benchmark with 10,000
  entities; measure per-tick cost.
- **Current:** —.
- **Status:** target (unmeasured).
- **Notes:** the "ECS primitive" is the v2 path
  toward the pure-function discipline. v1
  is signal-based; ECS is the migration.

#### N021 — Markov predictor accuracy

- **Claim:** Markov predictor (player movement)
  >70% accurate.
- **Target:** >70%.
- **Phase:** 3, 4.
- **Source:** plan §14, R003.
- **How to measure:** compare predicted vs actual
  player position 1s ahead, over 10,000
  predictions.
- **Current:** —.
- **Status:** target (unmeasured).
- **Notes:** <70% accuracy fires R003. The
  research doc §9 (adaptive tick) provides
  a complementary path.

#### N022 — Re-root cost

- **Claim:** re-rooting the state tree per tick
  is <5ms for v1.
- **Target:** <5ms.
- **Phase:** 1.
- **Source:** plan §5.7.
- **How to measure:** benchmark; assert p99 < 5ms
  across 10,000 ticks with 1000 active entities.
- **Current:** —.
- **Status:** target (unmeasured).
- **Notes:** the re-root is "compute new root
  hash, return diff". If the diff cost is
  >5ms, MST (research doc §5) is the path.

#### N023 — Snapshot write cost

- **Claim:** Postgres snapshot write is <100ms
  p95.
- **Target:** <100ms p95.
- **Phase:** 2.
- **Source:** plan §12.4.
- **How to measure:** measure the snapshot-store
  write; assert p95 < 100ms.
- **Current:** —.
- **Status:** target (unmeasured).
- **Notes:** the write is one of the few
  blocking operations in the tick. If it
  exceeds 100ms, it has to be async or batched.

#### N024 — Flywheel snapshot write cost (D024)

- **Claim:** Redis snapshot write is <2ms p95.
- **Target:** <2ms p95.
- **Phase:** 1.
- **Source:** plan §9.14, D024.
- **How to measure:** time the snapshot write
  (`flywheel:<shard_id>` SET); assert p95 < 2ms
  over 10,000 snapshots.
- **Current:** —.
- **Status:** target (unmeasured).
- **Notes:** the snapshot is fired on trigger,
  not per tick. So this is per-trigger, not
  per-tick. The 2ms budget is generous (Redis
  SET is sub-millisecond); we want headroom
  for serialization. If exceeded, switch from
  inline JSON to MessagePack.

#### N025 — Per-player flywheel update cost (D023)

- **Claim:** per-player flywheel update is O(1)
  with <1µs p99 per player per tick.
- **Target:** <1µs p99 per player.
- **Phase:** 2.
- **Source:** plan §9.16, D023.
- **How to measure:** with 5,000 connected
  players, time the per-tick flywheel update
  loop; assert total < 5ms (so 1µs per player
  p99).
- **Current:** —.
- **Status:** target (unmeasured).
- **Notes:** this is the *anticheat* hot path.
  Every player, every tick. If the cost grows,
  the design breaks. O(1) per player is the
  budget; O(1) per *sub-meter* is the
  sub-budget (7 sub-meters per player, each
  incrementing one int).

#### N026 — Tick-alignment jitter (D020)

- **Claim:** diffs emit within ±2ms of tick
  boundary. (Carried over from N014 — this
  number verifies the *adaptive* tick
  preserves alignment under variable rate.)
- **Target:** p99 jitter < 5ms.
- **Phase:** 1.
- **Source:** plan §9.1, D020.
- **How to measure:** record `time_now - tick_n*interval`
  for each emitted diff; assert p99 absolute
  jitter < 5ms. Run for 10,000 ticks at each
  rate bucket (high, normal, idle).
- **Current:** —.
- **Status:** target (unmeasured).
- **Notes:** the adaptive heartbeat is a
  change from the plan's 50ms-fixed
  commitment. The alignment guarantee must
  hold at *all three* rates — high, normal,
  idle. If jitter exceeds 5ms at any rate,
  the lag-compensation math in §9.7 breaks
  down (the 500ms rewind window was
  calculated against 50ms tick boundaries).

### 3.6 Numbers summary

- **Total:** 26 numbers.
- **Targets (unmeasured):** N001, N002, N003, N011,
  N012, N014, N015, N020, N021, N022, N023, N024,
  N025, N026 (14)
- **Targets (TBD):** N017 (1)
- **Targets (config-only):** N004, N005, N006,
  N008, N009, N013, N016, N018, N019 (9)
- **Measured:** N010 (1)
- **Missed:** 0 (none yet)

The 11 unmeasured targets are the Phase 1
measurement list. They should be measured in
order: N001 (tick) → N022 (re-root) → N014
(tick alignment) → N012 (diff size) → N011
(bandwidth) → ...

---

## 4. Glossary

Alphabetical. Each term has:
- **Definition** — what it means
- **Cross-refs** — where it appears in the trio
- **Conflict note** — if the term has a second
  meaning elsewhere

### Terms A–C

- **AABB** — Axis-Aligned Bounding Box. Used for
  spatial bounds on planar maps. *See plan §3.1,
  glossary §20.*

- **Address cell** — The unit of the address space:
  a chunk for planar worlds, an icosahedral face
  for spherical. The state tree, the LOD pyramid,
  and the geometric layer all key off this. *See
  plan §6.*

- **AOI** — Area of Interest. The volume around a
  player that the server sends diffs for. Default
  100m (see N008). *See plan §11.2.* Synonym:
  **VOI**.

- **Axis** — A single dimension of the multi-iso
  orchestrator's query space (spatial, factional,
  temporal, social, game-specific). The
  orchestrator intersects across multiple axes.
  *See plan §6, §13.*

- **Biome** — A climate / vegetation type
  (forest, plains, lake, mountain, etc.). One of
  the procedural generation passes. *See plan
  §7.5.*

- **BSP** — Binary Space Partition. A subdivision
  scheme; mentioned in the research doc §1
  (quasicrystal) as a comparison to Penrose /
  Ammann-Beenker tilings.

- **CDN** — Content Delivery Network. For static
  chunks (D014), the CDN serves the
  content-hashed file directly. *See plan
  §11.11.4.*

- **Chunk** — 64m spatial unit (planar) or ~62m
  triangular unit (spherical). The LOD pyramid's
  smallest cell. Content-hashed and immutable
  once promoted. *See plan §3.10, D004, N006.*

- **Conflict** — When two clients edit the same
  state in the HLC window, the coordinator
  resolves. Default is last-write-wins (D015).
  CRDT is the v2 upgrade. *See plan §16.5,
  R006.*

- **Coordinator** — The cross-shard process. Owns
  guilds, factions, character master records,
  world events, auction house. HA-pair scales
  independently. *See plan §2.1, §16, D005,
  R013.*

- **CRDT** — Commutative Replicated Data Type. The
  v2 alternative to last-write-wins. Deferred to
  Phase 4+ (D015). *See plan §12.11.*

### Terms D–L

- **Diff** — The list of state-tree changes
  between two root hashes. The unit of sync
  (D010). *See plan §5.6, §10.3, §11.*

- **DOTS** — Diff-over-the-wire state-tree sync
  format. The D010 commitment: every sync
  message is a state-tree diff, applied by the
  client. *See plan §11.6.*

- **Edge shard** — A thin "world cache" process
  near clients, for AOI + chunk cache +
  prediction. Deferred to Phase 4+ (D019) until
  >5000 active players per shard. *See research
  doc §2.*

- **ECS** — Entity-Component-System. The v2 path
  toward the pure-function discipline. v1 is
  signal-based. *See plan §9.13, research doc §10,
  N020.*

- **ENet** — UDP-based reliable transport. The
  native-client P2P lane (Phase 2+, D016). v1
  clients use WebSocket only. *See plan §1.7,
  §10.10.*

- **FSM** — Finite State Machine. The existing
  `game/core/state/` (state.gd + state_machine.gd)
  implements a generic FSM (idle/run/jump/fall).
  Naming collision with the "state tree" is
  documented in the audit. *See audit §4.1.*

- **Flywheel** — A shard-local accumulator of
  "chaos" (work). A hit-and-miss engine pattern
  ported from the sibling vant repo's
  [`nature.js`](https://github.com/dhaupin/vant/blob/axolotl/lib/nature.js).
  Three states: ephemeral (in-memory, normal
  operation), snapshot (Redis, fired on trigger),
  restored (loaded on boot if recent). The
  flywheel is the load profiler for the tick;
  it makes work-proportionality explicit and
  observable. *See plan §9.14, D020-D022, D024,
  `labs/world-building-tick.md` §5.*

- **Flywheel snapshot** — The persisted record
  of a flywheel's state, written to Redis on
  trigger. Contains momentum, trigger enum,
  sub-meters (where is the chaos coming from),
  and top-N contributors (who is the actor).
  When calm: ~50 bytes. When hot: ~200 bytes
  with forensic detail. Low-signal-when-calm,
  high-signal-when-hot. *See plan §9.14,
  tick-doc §7.*

- **GDScript** — Godot's native scripting
  language. The v1 game-tier runtime. *See plan
  §17, D008.*

- **Grail path** — Read = lookup, write = command.
  Materialize intersections; don't compute at
  query time. The performance contract that the
  multi-iso orchestrator implements. *See plan
  §13, `docs/architecture/grail-path.md`.*

- **Hash** — SHA-256 of (canonical_encoding(value)
  ‖ hash(parent)). The Merkle property. *See
  plan §5.4.*

- **HLC** — Hybrid Logical Clock. Used in
  cross-shard conflict resolution. Vector clock
  + wall-clock. *See plan §16.5.*

- **Hot chunk** — A chunk at LOD L0 (full) in
  RAM. The "1% hot" rule: only 1% of the world
  is hot at any time. *See plan §3.10, N007.*

- **Instance** — A scoped subtree of the state
  tree with its own seed and lifecycle. Used for
  dungeons, party halls, arenas. *See plan
  §3.9, §8.*

- **Julia** — A dynamic programming language used
  for the multi-iso orchestrator. Concise math
  + good parallelism. *See plan §6, §13, D008,
  R010.*

- **L0 / L1 / L2 / L3** — LOD level. L0 = full
  (terrain mesh, all entities), L1 = summary
  (biome + counts), L2 = cold (just hash), L3 =
  archived (off the shard). **Conflict note**:
  storage tiers also use L0/L1/L2/L3. The plan
  always disambiguates with "LOD level L0" vs
  "tier L0". *See plan §14, §20.*

- **LOD** — Level of Detail. The pyramid of
  representations (L0 to L3) the player sees.
  Promoted/demoted based on AOI and time. *See
  plan §14.*

- **LRU** — Least Recently Used. The cache
  eviction policy. Used for the materialized
  intersection cache (N013). *See plan §13.4.*

### Terms M–R

- **Manifest** — The world's metadata: shape,
  seeds, shard partitions. Read by all shards
  on boot. *See plan §4.7, §3.11.*

- **Monitorability commitment** — Every signal
  in the events system can register as a chaos
  source. The flywheel is the architectural
  reason "make everything monitorable" stops
  being a nice-to-have and starts being a
  load-profiling necessity. Observability
  becomes load-bearing. *See plan §9.17, D022,
  `labs/world-building-tick.md` §5.6.*

- **Markov** — A stochastic model where the next
  state depends only on the current. Used for
  player-movement prediction (N021). *See plan
  §14.4.*

- **Materialized intersection** — A precomputed
  query result, cached. The "grail path" property.
  *See plan §13, N013.*

- **Merkle suffix tree** — A content-hash trie
  that replaces the path-keyed state tree. O(K)
  diffs instead of O(N). The Phase 4+ upgrade
  path if N022 (re-root cost) misses. *See
  research doc §5.*

- **MST** — see Merkle suffix tree.

- **Multi-iso orchestrator** — The control plane
  for multi-dimensional state. APIs: query(),
  emit(), tick(). *See plan §6, §13, D008.*

- **NSC-9** — A 12-digit code
  (`9-AAA-BBB-CCCCCC`) encoding facility, axis,
  and sequence per entity. The geometric
  addressing layer's identifier. *See plan §6.2,
  §20.*

- **Override** — A hand-authored content layer
  placed over a procedurally-generated chunk
  (e.g. `town.tres` overrides the underlying
  biome). *See plan §7.11.*

- **Pass** — A single step in the procedural
  pipeline (terrain, biome, poi, mob_spawn, …).
  *See plan §7.3.*

- **P2P lane** — Native-client direct
  peer-to-peer chunk sync. Phase 2+ (D016).
  WebSocket-only browser clients don't use it.
  *See plan §10.10.*

- **Per-player flywheel** — A flywheel scoped to
  a single player rather than a whole shard.
  Same pattern (chaos, sub-meters, thresholds,
  snapshot) but smaller scope: 7 sub-meters
  (movement, combat-hits, combat-cooldowns,
  chat, trade, loot, instance). The per-player
  flywheel is the **anomaly detector** for
  security and anticheat — it inverts the
  model so each player audits themselves, and
  security investigates only the hot players.
  Cost: ~1MB memory, O(N) per tick, one
  snapshot per trigger. *See plan §9.16, D023,
  `labs/world-building-tick.md` §9.*

- **Player-placed content** — Ankhs, guild halls,
  houses, signs, crops. Stored in the state
  tree, no separate housing DB. *See plan §1.9,
  §15, D009, R008.*

- **Predicted view** — The client's local
  approximation of the state tree, ahead of the
  authoritative server. Lag compensation. *See
  plan §11.4.*

- **Procedural generation** — The pipeline that
  produces world content from seeds. Runs at
  LOD-promotion time (D011), not seed time.
  *See plan §7.*

- **Projection** — Mapping a world coordinate to
  an address cell (icosahedral face, planar
  chunk). ~1µs per axis per entity (N010). *See
  plan §6.7.*

- **Re-root** — Recomputing the state-tree root
  hash after a mutation. The tick's main
  operation. <5ms target (N022). *See plan §5.7.*

- **Region** — 256m–2km group of chunks. The
  authoring unit. *See plan §5.11, N009.*

### Terms S–Z

- **Seed** — A 64-bit integer used as the root
  of the procedural RNG. Scopes: world, shard,
  instance. *See plan §4.*

- **Shard** — A horizontal scaling unit of the
  world. One process. One spatial partition.
  Max 5,000 active players (N019). *See plan
  §2.2, §16.*

- **Snapshot** — A persisted state of the
  state tree at a tick. Postgres stores
  snapshot roots. *See plan §12.4, N017.*

- **State tree** — The content-hash persistent
  tree that holds all game state. The substrate
  for sync, multi-iso, LOD, generation. *See
  plan §5, D007.*

- **Storage tier** — In-memory / on-disk / Redis
  / Postgres. **Conflict note**: same names
  (L0/L1/L2/L3) as LOD levels. *See plan §20.*

- **Subdivision** — Splitting an icosahedral face
  into smaller faces. Level 5 = 20 × 4⁵ = 20,480
  faces (N007). *See plan §3.10.*

- **Tick** — One 50ms cycle of the server. The
  only place where authoritative state changes.
  *See plan §9.1, N001.*

- **Tier** — see Storage tier.

- **Tick alignment** — Diffs sent on tick
  boundaries, not mid-tick. 100% alignment
  (N014). *See plan §11.3.*

- **Transport** — WebSocket for v1, ENet for
  native-only P2P. v1 is browser-first (D006).
  *See plan §10.*

- **Trigger** — A measurement that would change
  a decision (D###) or confirm a risk (R###).
  Examples: N001 >50ms fires R-tick-budget; N022
  >5ms fires D007-revisit (MST).

- **Vant** — A sibling repo by the same author.
  9 vant libraries map to multi-iso frame
  primitives. *See `docs/architecture/vant-lift.md`.*

- **VOI** — Volume of Interest. Same as AOI; we
  use both interchangeably. *See plan §20.*

- **VOI-extend** — A temporary expansion of AOI
  (scouting, map view, etc.). *See plan §20.*

- **WebSocket** — TCP-based, browser-friendly
  message transport. v1 client↔server. *See plan
  §1.7, §10.*

- **World seed** — The root seed for an entire
  world. Immutable. Source of all open-world
  determinism. *See plan §4.1.*

- **Zone** — Hand-authored, gameplay-rule scope
  (PvP mode, level range, instance flag). Lives
  above the spatial grid. *See plan §8.*

### 4.1 Conflict notes (in one place)

The two known naming collisions worth tracking:

1. **LOD level vs Storage tier** (both use L0/L1/L2/L3).
   Resolution: in context, we always say "LOD
   level L0" or "tier L0". This is the rule from
   plan §20.

2. **FSM vs state tree** (in `game/core/state/`).
   The `state.gd` + `state_machine.gd` are
   finite-state machines (idle/run/jump/fall).
   The "state tree" we are building is the
   content-hash persistent tree (§5). Different
   things, similar names. *See audit §4.1.*

### 4.2 Acronyms cheat sheet

| Acronym | Means |
|---|---|
| AOI | Area of Interest |
| BSP | Binary Space Partition |
| CDN | Content Delivery Network |
| CRDT | Commutative Replicated Data Type |
| ECS | Entity-Component-System |
| FSM | Finite State Machine |
| HLC | Hybrid Logical Clock |
| LOD | Level of Detail |
| LRU | Least Recently Used |
| MST | Merkle Suffix Tree |
| P2P | Peer-to-Peer |
| SPOF | Single Point of Failure |
| VOI | Volume of Interest |

---

## 5. Cross-doc index

What lives in each doc, where to look for what:

| Looking for | In this doc | In trio |
|---|---|---|
| "Why is X the case?" | §2 (decision log) | plan §X, research doc |
| "What's the worst that could happen?" | §1 (risk register) | plan §19 |
| "What's that number we promised?" | §3 (numbers ledger) | plan §X, research doc |
| "What does Y mean?" | §4 (glossary) | plan §20 |
| "What changed since last review?" | §1 status, §2 status, §3 status | git log |
| "What's the user's overall intent?" | — | plan §1 (Principles) |
| "What's the project state today?" | — | audit (m3-initial-world-audit.md) |
| "What's the experimental path?" | — | research doc §1-§10 |
| "How do these compose?" | — | research doc §11 |

## Document state

- Sections: 5 (risks, decisions, numbers, glossary,
  cross-doc index) + new §2.7 (tick model decisions).
- Length: ~1,800 lines.
- Total entries: 15 risks, 24 decisions (D020-D024
  added for the tick model), 26 numbers (N024-N026
  added for the flywheel), ~65 glossary terms
  (Flywheel, Flywheel snapshot, Per-player
  flywheel, Monitorability commitment added).
- Status: tracking companion to the trio.
- Last full review: 2026-09-05.
- Last update: 2026-09-05 (tick model spec
  promotion — D020-D024, N024-N026, glossary
  additions, plan §9.1/§9.2/§9.9/§9.14-§9.17
  updated).
- Next review: when Phase 1 measurement list (N001,
  N022, N014, N012, N011, ...) starts producing
  numbers — then the "Current" column gets real.

---

## How to read this doc without reading the whole thing

If you have 5 minutes: read §2.6 (decision summary),
§1.4 (risk summary), §3.6 (numbers summary). You now
know the operational state of the project.

If you have 30 minutes: read §1.1 (perf risks),
§2.1-2.3 (the main decisions), §3.1-3.2 (the main
numbers). You know the technical commitments and
where they could go wrong.

If you have 2 hours: read the whole doc. By the end
you know what we promised, what we worry about, and
why every choice was made. The "trigger to revisit"
column is the cheat sheet for the future.

