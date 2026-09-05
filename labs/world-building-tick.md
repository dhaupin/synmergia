# World-Building Tick: a single tick, end-to-end

> **Status:** Pre-commitment design discussion. The
> plan commits to a 50ms tick; this doc explores what
> actually happens inside one. Not yet folded back into
> the plan — the open questions (Q1-Q3 below) need
> resolution first.
>
> **Scope:** The design space for a single server tick.
> The 6 phases. The flywheel. The postmortem use case.
> The "embed data when hot" idea.
>
> **Companion docs:**
> - `world-building.md` §9 — the plan's tick model
> - `world-building-research.md` §9 — adaptive tick
>   rate
> - `world-building-risks.md` — N001 (tick rate),
>   N022 (re-root cost), R001 (HTML5 perf)
> - `m3-initial-world-audit.md` — current state
>
> **Date opened:** 2026-09-05

---

## 1. The question

What does a single 50ms tick do, in what order, with
what guarantees?

The plan compresses this to:
> Tick loop (read state → step world → diff → emit)

But the compression hides the interesting choices:
what work runs in the tick vs. async, how the
server handles overrun, what the heartbeat really
is, and how the tick is observed for debugging.

This doc pulls the answer apart.

---

## 2. Why a tick model matters

The tick is the heartbeat. Every other system in
the game is bounded by it:

- **LOD pyramid** (plan §14) — runs at 10 Hz, slower
  than the tick. Promotion/demotion happens between
  ticks.
- **Diff sync** (plan §11) — diffs emit on tick
  boundaries (N014). Tick alignment is what makes
  lag compensation tractable.
- **State tree** (plan §5) — re-rooted per tick (N022).
  The re-root is the tick's main op.
- **Cross-shard events** (plan §16) — coordinator
  HLC events are absorbed in the world step.
- **Persistence** (plan §12) — async to the tick,
  but batched on a tick schedule.

If the tick is wrong, every other system is wrong.
If the tick is over budget, every other system
backs up.

The tick is also where **determinism** is enforced.
Given the same state root, the same inputs, and the
same RNG state, the tick must produce the same next
state. This is what makes the state tree
content-hashable across clients.

Finally, the tick is the **load profiler**. How
long did phase 2 take? How many entities were
touched? How many diffs were emitted? These are
the numbers we'd see in any performance analysis.
The flywheel makes them continuous instead of
snapshot.

---

## 3. The vant flywheel pattern, lifted

[`nature.js`](https://github.com/dhaupin/vant/blob/axolotl/lib/nature.js)
in the sibling vant repo implements a hit-and-miss
engine metaphor. The core:

- A **flywheel** accumulates "chaos" (work).
- Each `tick()` decays the flywheel by a small amount.
- When the flywheel has enough momentum *and* no spark
  is in flight, fire a "spark" event.
- The spark resets the flywheel.

Two properties:

1. **Work-proportional, not clock-proportional.** You
   don't tick on a fixed schedule. You tick when
   there's enough accumulated work.
2. **Idle is cheap.** No work in → flywheel just
   decays to zero → no ticks out.

Cosmic entropy (an external entropy source) feeds
the flywheel. The flywheel persists across sessions.

### What we take

The work-proportionality. The idea that a "tick" can
mean different amounts of work at different times.
The observability of the flywheel as a load profiler.
The persistence of the flywheel across sessions.

### What we leave

The pure hit-and-miss semantics. A game world has
things that need to happen on a wall-clock schedule:
day/night, regen, buff timers, cross-shard events.
If we never tick when there's no chaos, the world
freezes.

### The hybrid

**Heartbeat floor + work-proportional batch.**

The tick fires on a clock (every 50ms, N001). The
*amount of work* in each tick is proportional to the
flywheel momentum. Idle = trivial tick. Combat = big
tick. But the tick always runs, and players always
get a response within 50ms p99.

The vant contribution is to make the
work-proportionality *explicit* and *measurable* —
the flywheel momentum becomes a first-class number
you can see, tune, and alert on.

---

## 4. The 6-phase tick structure

| # | Phase | Budget | What it does | Sync/async |
|---|---|---|---|---|
| 1 | **Input collection** | 5ms | Read WebSocket frames, parse, validate, queue. Auth + rate-limit. | sync |
| 2 | **World step** | 25ms | Apply queued inputs in deterministic order. Step mob AI, decay, regen. Pull coordinator HLC events. | sync |
| 3 | **State re-root + diff** | 10ms | Compute new root hash. Compute diff vs. previous root. | sync |
| 4 | **Diff emit** | 8ms | For each client, compute AOI diff, apply LOD, LZ4, send. Tick-alignment check (N014). | sync |
| 5 | **Persistence** | async | Snapshot state tree root to Postgres (N017). Update Redis tick cache, LRU (N013). Update materialized intersections. | async |
| 6 | **Predicted prefetch** | async | Markov predictor (N021). LOD-promote predicted chunks. Generation pass on those chunks. | async |

Total sync: 48ms. Total budget: 50ms. 2ms slack.

### Phase 1 — Input collection (5ms)

Reads the WebSocket frames that arrived since the
last tick. Parses, validates, and queues them by
player. Auth-checked and rate-limited at the boundary.

Each parsed input adds chaos to the flywheel.
Specifically, `+1` per input message; `+5` for
combat-skill messages (they trigger downstream work).

### Phase 2 — World step (25ms)

This is the main work phase. For each entity in the
active set (those with inputs this tick or with AI
decisions to make), apply the queued input or the AI
decision. In deterministic order — by tick-local
sequence, or by entity_id hash for fairness.

This phase:
- Applies player inputs (move, attack, trade, etc.)
- Steps mob AI (decision + movement)
- Decays effects (buffs, dots, regen)
- Pulls coordinator HLC events (cross-shard)
- Advances the wall clock (day/night)

The 25ms budget is a *hard cap*. If phase 2 needs
more, the overflow goes to a side queue (see Q1
below).

### Phase 3 — State re-root + diff (10ms)

Computes the new state tree root hash. Computes the
diff vs. the previous root. The diff is the unit of
sync (D010).

The cost of re-root is bounded by the number of
mutated subtrees. N022 target is <5ms p99 for v1.
If the diff is bigger, the MST upgrade path
(research doc §5) is the escape.

### Phase 4 — Diff emit (8ms)

For each connected client, compute the diff in
their AOI. Apply LOD — distant clients get L1
summaries, not L0 detail. LZ4-compress. Send over
WebSocket.

N014 invariant: every diff is sent within ±2ms of
a tick boundary. If the emit phase overruns, the
next tick starts late (see Q1).

### Phase 5 — Persistence (async)

The 25ms tick budget includes only the 4 sync phases.
Phase 5 runs after the tick has emitted and runs into
the next tick.

This is where the existing persistence work lives:
- Postgres snapshot (N017 — TBD, see risks doc)
- Redis tick cache
- Redis LRU (N013)
- Materialized intersection cache

The **flywheel snapshot** (see §5) is one more Redis
op, fired on trigger, not per tick. Costs nothing on
the hot path.

### Phase 6 — Predicted prefetch (async)

The Markov predictor (N021) estimates where each
player will be in 1s. Chunks the player is predicted
to enter are LOD-promoted. The procedural generator
runs on those chunks in the background.

If the prediction is right (N021 target: >70%), the
player experiences no LOD transition (the chunk is
already at L0 when they arrive). If wrong, the chunk
promotes on demand and the player sees a brief pop.

---

## 5. The flywheel in Synmergia

The flywheel is a shard-local accumulator of
"chaos" (work). It's a load profiler that makes
work-proportionality explicit.

### 5.1 Chaos sources

What counts as chaos:

| Source | Weight per event | Rationale |
|---|---|---|
| **Player input** | +1 (combat: +5) | The dominant source in populated shards |
| **Mob AI decision** | +10 | One mob decision triggers movement, skill use, aggro updates |
| **Cross-shard HLC event** | +50 | High impact, but rare |
| **Wall-clock pulse** | +1 per tick | The heartbeat — keeps the flywheel alive even when idle |
| **Generation pass** | +100 | The expensive one; on trigger only |

The flywheel decays at a configurable rate
(default: 0.5 per tick). High-entropy ticks accumulate
faster than they decay; idle ticks decay to zero.

### 5.2 Three states

| State | Where | When | What it means |
|---|---|---|---|
| **Ephemeral** | in-memory | normal operation | flywheel lives in shard RAM, gets logged, no I/O cost |
| **Snapshot** | Redis key, TTL'd | on trigger | full state + sub-meters + trigger metadata persisted |
| **Restored** | loaded on boot | if a recent snapshot exists | boot reads the Redis key, hydrates the flywheel, resumes |

The vast majority of the time, the flywheel is in
the first state. Transitions to/from snapshot are
*triggered*, not constant.

### 5.3 Triggers for snapshot (write)

Five triggers. The OR of these fires a snapshot.

1. **High-entropy threshold crossed.** Flywheel
   momentum > 80% of max. "We're heading into
   trouble; save the state so we can debug it."
2. **Planned event signal.** Operator signals
   "festival in 10 minutes" or "world boss spawn in
   5 minutes." Pre-emptive snapshot.
3. **Planned restart.** SIGTERM received. Save and
   exit cleanly. Next boot restores.
4. **Crash recovery** (read-side). On next boot,
   look for a recent snapshot and restore.
5. **Resource pressure.** CPU > 80% for 30s. Memory
   > 90%. Connection backlog growing. Each of these
   is "system is stressed, capture the state."

The first three are the explicit trigger list.
The fourth is the read-side companion. The fifth
makes the flywheel a *leading indicator* of
trouble, not just a record of it.

### 5.4 Triggers for *discard* (don't restore)

Equally important — the cases where the snapshot
exists but should be ignored:

1. **Snapshot older than 1 hour** (configurable).
   The world has changed; the old flywheel is
   meaningless.
2. **World seed has rolled** (manifest change).
   The new world doesn't inherit the old world's
   load profile.
3. **Operator-flagged discard.** Manual override.

Without discard rules, a stale snapshot from a
different world could be restored on a new boot and
confuse every metric. The discard rules are what
make the snapshot *trustworthy*.

### 5.5 Cost

Snapshot cost:
- One Redis write on trigger
- ~200 bytes (see §7)
- TTL: 1 hour
- One append to flywheel history log (also Redis)

Restore cost:
- One Redis read on boot
- One deserialization
- ~1ms total

Hot path: unchanged. The flywheel is purely in-memory
until a trigger fires.

---

## 6. Postmortem: load-driven vs bug-driven

The interesting thing about persisting the flywheel
isn't the persistence. It's the postmortem story.

The flywheel is a **leading indicator**. CPU and
memory are *lagging* indicators — they tell you
what happened. The flywheel tells you what was
*about to* happen. It accumulates before the work
actually happens.

### The 4-snapshot story

Imagine 4 shards all crash within an hour of each
other. Each has a recent flywheel snapshot.

- **Shard A** — flywheel=950, sub-meters:
  80% mob AI, 20% player inputs. Top contributor:
  a single mob spawn event that cascaded. The shard
  didn't crash from a normal load spike; it crashed
  from chaos accumulation faster than the tick
  could discharge. Postmortem: "tune mob AI
  throttling / cap mob spawn rate / split the
  spawn."

- **Shard B** — flywheel=950, sub-meters: 95%
  player inputs, 5% everything else. Top
  contributor: a single player's combat macro
  firing 100 skills/sec. Postmortem: "throttle that
  player / ban / rate-limit combat skill spam."

- **Shard C** — flywheel=950, sub-meters: 70%
  cross-shard, 30% time. Top contributor: a
  coordinator HLC storm from a network partition.
  Postmortem: "fix the coordinator's
  reconnection logic; this is orthogonal to
  gameplay load."

- **Shard D** — flywheel=150, sub-meters: 40%
  mob AI, 60% inputs. Postmortem: "the shard
  crashed with normal load. Find the bug."

Each shard was at 950 (or not), and the postmortem
is different. Without the flywheel snapshot, you
guess. With it, you read the answer in 30 seconds.

This is the killer use case for the flywheel. Not
performance tuning, not load balancing, not
capacity planning. **Crash forensics.**

---

## 7. Embedding data when the flywheel is hot

The user's contribution: "embed data into the
actual flywheel when it gets too hot." The
flywheel should carry *context* when it's hot, not
just a number.

### 7.1 Three payload shapes

**A. Sub-meters per chaos source.**

The flywheel has 4 sub-counters: player inputs,
mob AI, cross-shard events, time. The snapshot
records the *distribution* of chaos across sources,
not just the total.

Cost: 4 numbers (~32 bytes). Always on. Tells
postmortem: "this shard was hot because of X."

**B. Top-N chaos contributors.**

When the flywheel crosses the snapshot trigger, the
top-N chaos sources for the last 5 seconds get
baked in. "Player X's combat macro contributed 40%
of the chaos in the last 5s."

Cost: ~10 records, ~150 bytes. Fire-on-snapshot
only. Tells postmortem: "this is the actor /
entity / input type driving the load."

**C. Trigger metadata.**

The snapshot records *which* trigger fired it
(high-entropy / planned event / SIGTERM / resource
pressure). Without this, two snapshots with the
same momentum number are indistinguishable. With
it, you can filter postmortem by trigger.

Cost: 1 enum (~4 bytes). Always on. Tells
postmortem: "was this load-driven or
operator-driven?"

### 7.2 The principle: low-signal-when-calm, high-signal-when-hot

The right design is **A and C always on, B
fire-on-snapshot only**.

When the flywheel is calm, the snapshot is small —
a number, a timestamp, an enum, four sub-counters.
~50 bytes. Recording this is cheap and the data is
boring (we don't need to know the top contributor
when nothing is happening).

When the flywheel is hot, the snapshot expands
because B is firing. The forensic record is rich.
The cost is the same number of Redis writes —
just one bigger payload.

This is the vant flywheel's "only spark when
needed" principle, applied to telemetry. **Don't
record when nothing is happening. Record
aggressively when something is.**

### 7.3 Snapshot record shape

```json
{
  "shard_id": "shard_001",
  "tick": 1928374,
  "timestamp_ms": 1725532800000,
  "trigger": "high_entropy",
  "momentum": 920,
  "max_momentum": 1000,
  "sub_meters": {
    "player_inputs": 480,
    "mob_ai": 320,
    "cross_shard": 50,
    "wall_clock": 70
  },
  "top_contributors": [
    {"kind": "player_input", "id": "p_8821", "chaos": 280},
    {"kind": "mob_spawn",   "id": "m_4421", "chaos": 200},
    {"kind": "player_input", "id": "p_3304", "chaos": 90},
    ...
  ],
  "boot_count": 14,
  "since_boot_seconds": 43200
}
```

When calm, `top_contributors` is `[]` (omitted or
empty). When hot, it has 10 entries. Same Redis
key, same TTL. The shape is identical; the size
varies.

### 7.4 Why not always record everything?

Two reasons:

1. **Cost.** Recording the top-10 contributors
   every tick is 1.5KB × 20Hz = 30KB/s per shard
   to Redis. Trivial in absolute terms, but
   pointless when the data is boring.
2. **Signal-to-noise.** If every tick has a
   snapshot, postmortem has to filter the
   uninteresting 99.9% to find the interesting
   0.1%. The current design filters for us:
   snapshots only exist for the interesting ticks.

The "record when hot" pattern is the same as
on-call alerting: don't page on every log line,
page on the signal that matters.

---

## 8. The open questions

Three design choices haven't been resolved yet. The
plan has 50ms fixed (N001); this doc has the
six-phase structure above; but the operational
details of the tick are still up for grabs.

### Q1 — Overrun handling

When a tick overruns 50ms (e.g., phase 2 needs
60ms because of a combat spike), what do we do?

Three options:

- **(a) Drop the next tick.** Skip. The world
  slows by 50ms. Players see a brief "lag" but no
  desync. Simple. Hides the problem.
- **(b) Extend the tick.** Let it run to completion.
  The world advances correctly but the player sees
  100ms between updates. Bad for action combat.
- **(c) Defer to side queue.** Cap phase 2 at 25ms
  hard; overflow inputs go to a side queue. Bounded
  latency, but the queue grows. Eventually you
  need to either overflow (drop inputs) or
  load-shed (kick players).

My instinct is **(c) with explicit overflow
handling**. The side queue is itself a flywheel.
If the side queue overflows, throttle clients (R002
trigger).

### Q2 — Heartbeat floor

The vant pattern has no floor. We need one. Three
options:

- **50ms fixed** (N001 as planned) — comfortable
  for action combat. ~3% CPU for tick overhead.
- **Adaptive: 100ms idle / 50ms under load / 33ms
  in combat.** The flywheel drives the transition.
- **Always 100ms** — half the cost. Slow for
  combat, fine for everything else.

I lean **adaptive**. The N001 measurement would
become "p99 tick interval" instead of "tick
interval." Worth recording as a D-number if we
adopt this.

### Q3 — Chaos sources

What feeds the flywheel? My current draft (§5.1):

- Player inputs (primary)
- Mob AI (secondary)
- Cross-shard HLC events (rare, high-impact)
- Wall-clock pulse (the heartbeat driver)
- Generation passes (on trigger)

The question is whether wall-clock pulse is a
"chaos source" or whether it's separate. My
instinct is **separate** — the wall-clock pulse
is what *keeps* the flywheel alive, not what
*charges* it. The flywheel is then a measure of
*work*, not *time passed*.

### What's NOT a question

- **Per-shard vs per-player vs global** — one
  flywheel per shard. Per-player is too
  fine-grained; global is wrong (shards have
  independent load).
- **What counts as "hot"** — 80% of max momentum.
  Configurable. The right value is empirical;
  tune in Phase 2.
- **What gets persisted** — Redis key
  `flywheel:<shard_id>` with TTL 1 hour. Also
  append to flywheel history log.

These are settled.

---

## 9. Cross-doc index

| Looking for | Where |
|---|---|
| The plan's tick model | `world-building.md` §9 |
| Adaptive tick research | `world-building-research.md` §9 |
| Tick rate (N001) | `world-building-risks.md` §3.1 |
| Re-root cost (N022) | `world-building-risks.md` §3.5 |
| HTML5 perf risk (R001) | `world-building-risks.md` §1.1 |
| Diff wire format | `world-building.md` §11.6 |
| State tree | `world-building.md` §5 |
| Cross-shard HLC | `world-building.md` §16.5 |
| LOD prediction | `world-building.md` §14 |

---

## Document state

- Sections: 9 (this is a focused discussion, not a
  sweep).
- Length: ~700 lines.
- Status: pre-commitment design discussion.
- Open: Q1, Q2, Q3.
- Settled: flywheel three-state model, postmortem use
  case, embedded-data design, chaos source shape,
  per-shard scope.
- Next: resolve Q1-Q3 in the next discussion, then
  fold the result back into the plan as a D-number
  and an updated §9.

---

## How to read this doc without reading the whole thing

If you have 5 minutes: read §1, §4, §5.2, and §8.
You know the question, the structure, the
flywheel, and what's open.

If you have 30 minutes: add §3 (vant pattern),
§5.3-5.4 (triggers), §6 (postmortem), §7.1 (the
embedded-data idea).

If you have 2 hours: read the whole doc. The
6-phase tick, the flywheel triggers, the
forensic record, and the open questions. The
postmortem story in §6 is the killer use case
worth dwelling on.
