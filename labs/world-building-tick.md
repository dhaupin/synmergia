# World-Building Tick: a single tick, end-to-end

> **Status:** Design intent, with Q1-Q4 settled
> 2026-09-05. The plan commits to a 50ms tick; this
> doc explores what actually happens inside one
> and adds the per-player flywheel for security.
> Not yet folded back into the plan §9 — that's
> a separate pass when plan §9 is updated. New
> D-numbers in `world-building-risks.md` will
> follow.
>
> **Scope:** The design space for a single server
> tick. The 6 phases. The flywheel (shard-level
> + per-player). The postmortem use case. The
> "embed data when hot" idea. The anticheat
> pipeline. The monitorability commitment.
>
> **Companion docs:**
> - `world-building.md` §9 — the plan's tick model
> - `world-building-research.md` §9 — adaptive tick
>   rate
> - `world-building-risks.md` — N001 (tick rate),
>   N022 (re-root cost), R001 (HTML5 perf)
> - `world-building-arch.md` §10 — the tick as
>   data flow through the substrate
> - `m3-initial-world-audit.md` — current state
>
> **Date opened:** 2026-09-05
> **Last updated:** 2026-09-05 (Q1-Q4 settled,
> per-player flywheel added)

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
| **NPC event** | configurable | Per-NPC, per-event weights (see §5.6) |
| **Entity signal** | configurable | Per-entity, per-signal weights |
| **Anything else observable** | configurable | See §5.6 — the monitorability commitment |

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

### 5.6 The monitorability commitment

The user named the deeper commitment: "make
*everything monitorable* through the events system,
signals, NPCs, entities, all as needed." The
flywheel is the architectural reason this stops
being a nice-to-have and starts being necessary.

**The principle:** every signal in the system can
register as a chaos source. The flywheel doesn't
care *where* chaos comes from; it just accumulates.
The events system, signals, NPCs, entities all
become flywheel-feedable. Per-source weight is
configurable.

**What it means concretely:**

- `EventBus` already centralizes events. Every
  signal that flows through `EventBus` can
  register a chaos callback.
- Godot signals are first-class. Any `signal foo`
  can have a chaos observer attached.
- NPCs and entities are themselves event sources.
  An NPC's "decide to attack" event can feed the
  flywheel.
- New services / systems can register their chaos
  contributions at boot.

**The cost:**

- Per-event: one increment, one compare-against-
  threshold. O(1).
- Per-trigger: the existing snapshot mechanism.
- Memory: per-source weight is one int; per-event
  observer is a small callback. Trivial.

**The benefit:**

- The flywheel becomes the **single load-profiling
  abstraction** for the entire game. Not "we have
  a flywheel for the tick and a separate profiler
  for NPC AI and another for chat spam." One
  flywheel, many sub-meters, one snapshot.
- The "we forgot to monitor X" failure mode
  disappears. X either emits a signal (and feeds
  the flywheel) or it doesn't (and is invisible
  to everything). The signals/events layer is
  the contract.
- Postmortem reads the snapshot and sees *which*
  sub-system was hot, not just "the shard was
  hot." This is the load-driven vs bug-driven
  distinction from §6, generalized.

**The principle restated:** observability becomes
load-bearing. Without the flywheel, "make
everything monitorable" is an observability virtue
(a nice-to-have). With the flywheel, it's a
load-profiling necessity (a must-have). The
flywheel justifies the observability investment.

**Cross-refs:** the existing `EventBus` autoload
(see `game/core/autoload/event_bus.gd`) is the
natural registration point. New services emit
signals there; chaos observers attach. The pattern
is additive — existing services don't change,
they just become observable.

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

## 8. The settled design

Three design choices resolved 2026-09-05. Each
gets the question, the answer, and the reasoning.

### Q1 — Overrun handling

**Question:** when a tick overruns 50ms (phase 2
needs 60ms because of a combat spike), what do
we do?

**Answer:** defer to side queue **with the
flywheel as the awareness layer**.

The side queue is itself a flywheel — overflow
inputs feed a queue-flywheel that decays as
work is processed. When the queue-flywheel
exceeds its threshold, the system knows it's
overrun, and the sub-meters + top-N contributors
tell it *why* and *who*:

- **Who is the contributor?** Top-N chaos
  contributors (§7) identify the player, mob
  spawn, or input type driving the load.
- **What subsystem is hot?** Sub-meters (§7)
  identify the system (movement, combat, AI,
  cross-shard).
- **Where to slim resources?** The system with
  the highest sub-meter is throttled first
  (e.g., reduce NPC AI rate, drop cosmetic
  effects, lower LOD aggression).
- **Is an exploiter involved?** Per-player
  flywheel (§9) flags suspicious players;
  inputs from flagged players get deprioritized.
- **Race conditions?** The flywheel sub-meters
  show "cross-shard HLC storm" or "input flood"
  patterns that indicate contention.
- **Health?** The flywheel momentum is a
  leading indicator of system stress; when
  above 80%, the operator dashboard surfaces it.

The side queue is the *defer* policy. The
flywheel is the *response* policy. The two
together are the answer to Q1.

The side queue overflows → throttle clients
(R002 trigger). The side queue overflows
persistently → load-shed (kick players, raise
cooldowns, etc.).

### Q2 — Heartbeat floor

**Question:** what's the heartbeat floor?

**Answer:** adaptive. The flywheel drives the
interval.

- Above some threshold (e.g., 80% of max):
  50ms heartbeat.
- Below threshold, low traffic: 100ms heartbeat.
- Idle (no players in AOI): 200ms heartbeat.

The vant pattern is adaptive by design; we're
keeping that and adding a floor (so day/night
keeps ticking when nothing else is).

The N001 measurement becomes "p99 tick interval"
not "tick interval." This is a change from the
plan's 50ms-fixed commitment; recorded as a
D-number candidate (provisional until the
plan §9 update).

### Q3 — Chaos sources

**Question:** what feeds the flywheel?

**Answer:** everything observable.

Specifically:

- All my originally-listed sources (player
  inputs, mob AI, cross-shard, wall-clock,
  generation) are valid.
- The wall-clock pulse is *both* a chaos
  source (consistent poke, +1 per tick) and
  the heartbeat driver. Same mechanism serves
  both purposes.
- **Plus:** any signal in the events system
  can register as a chaos source. NPCs,
  entities, services — any emitter can
  declare a chaos weight.

This is the **monitorability commitment**
formalized in §5.6: every signal is a chaos
source, every chaos source feeds the flywheel,
the flywheel is the single load-profiling
abstraction.

The wall-clock pulse is a chaos source. The
flywheel measures *both* time passed *and*
work done. They're the same thing, not
different things.

### Q4 — Per-shard vs per-player (now both)

**Question:** one flywheel per shard, or
per-player, or global?

**Answer:** per-shard AND per-player.

The original draft said "per-shard only."
That's still right for *shard-level* load
profiling. But the user surfaced a use case
that per-player is needed for: security /
anticheat.

Per-player flywheel is a separate abstraction
with its own sub-meters, thresholds, and
snapshot triggers. It inverts the security
model: instead of scanning every player for
anomalies, each player's flywheel IS the
anomaly detector. The per-player flywheel
is its own section. See §9.

---

## 9. Per-player flywheel: security and anticheat

The shard-level flywheel (§5) measures *shard*
load. But the user surfaced a use case where
per-player is the right scope: security.

The per-player flywheel is the **anomaly
detector**. Instead of the security team
scanning every player for cheating signals,
each player's flywheel is the scan. The
player audits themselves.

### 9.1 The inversion: self-auditing vs central scanning

**Old model:** Security scans every player
every tick (or samples, or batches). Either
way, the security layer is doing O(N) work
per tick where N is the player count, and
it's looking for the needle (the cheater) in
the haystack (every player).

**New model:** Each player has their own
flywheel. The flywheel is O(1) per tick to
update. When the flywheel is hot, the player
*is* the suspect. Security investigates
only the hot players.

This inverts the cost: instead of O(N×M)
work per tick (scan everyone for M anomaly
types), it's O(N) per tick (update every
player's flywheel) plus O(K) per trigger
where K is the small number of hot players.

### 9.2 What it tracks

Each player has a flywheel with sub-meters
per system:

| Sub-meter | What it counts | Threshold for "hot" |
|---|---|---|
| **Movement** | Distance per tick, speed, teleport count, fast-travel uses | >1.5x normal speed for >2s |
| **Combat — hits** | Successful hits per tick, crit rate, hit timing | <100ms hit intervals sustained |
| **Combat — cooldowns** | Skill uses per tick, gap between uses, downtime | Skill used before cooldown ends |
| **Chat** | Messages per minute, channel-switches, social calls | >60 msg/min or rapid channel-switching |
| **Trade** | Trade opens per minute, items per trade, gold moved | >10 trades/min or anomalous gold flow |
| **Loot** | Loot rolls per minute, rare-drop rate, drop-distance | Drop rate >3x expected |
| **Instance / fast-travel** | Enters per minute, fast-travel uses | >5 enters/min |

Each sub-meter has its own threshold and
decay rate. The combined momentum is the
weighted sum.

### 9.3 Thresholds

Per sub-meter, two thresholds:

- **Warn:** crossed → log the event, no
  action. Lets us see what's normal before
  we alert.
- **Trigger:** crossed → snapshot, notify
  AutoResponseService.

Defaults (configurable, calibrated in
Phase 2):

- Movement warn: 1.2x normal, trigger: 1.5x.
- Hit timing warn: <200ms, trigger: <100ms.
- Cooldown warn: <cooldown × 0.9, trigger:
  <cooldown × 0.5.
- Chat warn: 30 msg/min, trigger: 60 msg/min.
- Trade warn: 5 trades/min, trigger: 10 trades/min.

The right values are empirical; tune in
Phase 2 with real player data.

### 9.4 What gets snapshotted

When a sub-meter crosses its trigger
threshold, a snapshot of the player's
recent activity is taken:

```json
{
  "player_id": "p_8821",
  "shard_id": "shard_001",
  "tick": 1928374,
  "timestamp_ms": 1725532800000,
  "trigger_submeter": "movement",
  "trigger_value": 1.7,
  "recent_movement": [
    {"tick": 1928360, "x": 100.0, "y": 200.0, "speed": 0.5},
    {"tick": 1928361, "x": 100.7, "y": 200.0, "speed": 14.0},
    ...
  ],
  "recent_combat": [...],
  "recent_trades": [...],
  "session_minutes": 23,
  "previous_snapshots_in_session": 2
}
```

The snapshot goes to `suspicious:<player_id>`
in Redis (TTL 1 hour). The snapshot IS the
evidence — for AutoResponse, for
postmortem, for player support, for cheat
reports.

### 9.5 The anticheat pipeline

The per-player flywheel is the **input
signal** for the existing security services.
The pipeline:

1. **Per-tick:** every player's flywheel
   sub-meters increment based on their
   activity. O(1) per player.
2. **Per-trigger:** when a sub-meter
   crosses threshold, the snapshot fires
   (§9.4) and goes to `suspicious:<player_id>`.
3. **AutoResponse listens:** the existing
   `AutoResponseService` (see
   `game/core/services/auto_response_service.gd`)
   subscribes to the suspicious key. It
   decides what action to take:
   - First offense: warn
   - Repeated: mute
   - Severe: restrict
   - Critical: kick or ban
4. **AppFirewall / SecurityService** also
   listen. They bring their own context
   (rate limits, exploit signatures).
5. **Evidence preserved:** the snapshot is
   the audit trail. Players can appeal;
   appeals review the snapshot.

This is data-driven security. The
AutoResponse service doesn't have to scan
anyone; it reacts to flywheel triggers.

### 9.6 What this maps to in existing code

The codebase already has:

- `SecurityService` — anti-cheat, rate
  limiting
- `AutoResponseService` — admin alerts,
  moderation (with `action_taken` /
  `player_warned` signals)
- `AppFirewall` — request throttling,
  ban management

The per-player flywheel is the input signal
for all three. The existing services
already have the response side; this adds
the trigger side.

The pattern is additive:

- New service: `PlayerFlywheelService`
  (autoload) — manages per-player flywheels.
- `PlayerFlywheelService` exposes
  `flywheel_hot(player_id) -> bool` and
  emits `player_suspicious(player_id, snapshot)`.
- `AutoResponseService` connects to
  `player_suspicious` and decides action.
- `SecurityService` reads
  `suspicious:<player_id>` for evidence.
- `AppFirewall` rate-limits players whose
  flywheel is hot.

### 9.7 Cost

**Memory:** 5,000 players × ~200 bytes per
flywheel = 1MB. Trivial.

**Per-tick:** 5,000 × O(1) increment =
~50K ops/sec at 20Hz, ~100K ops/sec at 50Hz.
Trivial.

**Per-trigger:** one snapshot to Redis.
~200 bytes. Triggered only on the small
fraction of hot players. Trivial.

**Hot path:** unchanged. The flywheel
update is O(1) per player; the threshold
check is O(1) per player; the snapshot is
fired only on threshold crossing.

### 9.8 Tradeoffs and limits

**False positives:** the flywheel doesn't
know what's cheating; it knows load is high.
A genuinely fast player (high movement sub-
meter) might trigger the threshold without
cheating. Calibrate thresholds with real
data. Have an appeal process.

**Careful cheaters:** a cheater who is
careful and matches expected load can evade
the flywheel. This is true of any anomaly
detector. The flywheel catches the *loud*
cheaters; the *quiet* ones still need other
detection. The flywheel is one signal among
many, not a silver bullet.

**Privacy:** the per-player flywheel is
*behavioral* data, not content. We track
"player moved fast" not "player said X."
This is consistent with the existing
moderation model. The snapshot doesn't
include chat content.

**Cost vs savings:** the cost is O(N) per
tick, which is trivial. The savings is
"security doesn't have to scan." For a
5,000-player shard, that's the difference
between O(5000×M) work and O(5000+M) work
per tick. Real.

### 9.9 The principle: detect by instrumentation

This is the same pattern as shard-level
load profiling, applied to player
behavior. The flywheel IS the detector.
The player IS the audit. The cost is
O(1) per tick. The savings is "don't scan
everyone."

The pattern generalizes: any time you have
"find the bad actors in a population,"
build them a per-entity flywheel and let
the flywheel do the detecting. The same
abstraction (flywheel + sub-meters +
thresholds + snapshot) works for shard
load, player behavior, NPC AI, etc.

---

## 10. Cross-doc index

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
| Monitorability commitment | this doc §5.6 |
| Per-player flywheel | this doc §9 |
| Per-shard flywheel | this doc §5 |

---

## Document state

- Sections: 10 (5 new since the first version:
  §5.6 monitorability commitment, §8 settled
  design, §9 per-player flywheel, plus renumbering).
- Length: ~950 lines.
- Status: design intent (Q1-Q4 settled 2026-09-05;
  awaiting commitment to plan §9 + risks doc
  D-numbers).
- Settled: Q1 (defer + flywheel awareness), Q2
  (adaptive heartbeat), Q3 (everything monitorable),
  Q4 (per-shard AND per-player).
- New: per-player flywheel as anticheat / security
  instrumentation. Maps to existing
  SecurityService / AutoResponseService / AppFirewall.
- Next: when plan §9 is updated, fold the
  settled-design content into the plan; add
  D-numbers to `world-building-risks.md` for
  the adaptive heartbeat, the defer-with-
  flywheel policy, and the monitorability
  commitment.

---

## How to read this doc without reading the whole thing

If you have 5 minutes: read §1, §4, §5.2, and §8.
You know the question, the structure, the
flywheel, and what's settled.

If you have 30 minutes: add §3 (vant pattern),
§5.6 (monitorability), §6 (postmortem story),
§7.1 (embedded data), §9.1 (the inversion).

If you have 2 hours: read the whole doc. The
6-phase tick, the flywheel triggers, the
forensic record, the per-player inversion.
The postmortem story in §6 and the
self-auditing anticheat in §9 are the
killer use cases worth dwelling on.
