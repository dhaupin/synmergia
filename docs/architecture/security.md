# Security — Defending an Agent Framework

> **TL;DR:** Synmergia is an agent framework. Real agents (AI +
> human) play. Some will be nefarious. The defenses are
> layered, and the **recursion guard is the foundation**.

**Author:** drafted 2026-08-30 as part of the rando-in-the-mix
session. Tied to the vant lift (the recursion guard is one of
the things we just lifted from `lib/recursion.js`).

---

## The threat model

Synmergia exposes public attack surfaces to three classes of
actors:

| Class | Examples | Trust | Surface |
|-------|----------|-------|---------|
| **Human players** | Game clients, web clients | Low (must authenticate) | Network packets, chat, actions |
| **AI agents** | Vant, Claude, GPT, Gemini | Mixed (per-agent) | Tool calls, content generation, automation |
| **Game services** | Internal services, dev tools | High | Direct API access |

A **nefarious** actor of any class can attempt:

1. **Infinite loops / stack exhaustion** — emit an event that
   emits an event that emits itself, or call a tool that
   calls itself.
2. **Hash forgery** — modify state tree content hashes
   to claim a different state than reality.
3. **Unauthorized state mutation** — write to entities they
   don't own, in zones they can't access.
4. **Capability abuse** — call APIs beyond their permission
   level (read vs write, local vs remote).
5. **Rate flooding** — issue 10K requests/second to overload
   the tick budget.
6. **Predictive cheating** — use the prediction API to see
   the future and act on it.
7. **Content injection** — push malicious content (chat,
   item names, NPC dialogue) that exploits the rendering
   or other players.
8. **Trust laundering** — fake high-trust, then exploit.

---

## The defense layers

The frame's defense is layered. Each layer assumes the
layer below can fail.

### Layer 0: Recursion guard (the foundation)

**Every public API surface** must be wrapped in a recursion
guard. The pattern is lifted from vant
[`lib/recursion.js`](https://github.com/dhaupin/vant/blob/axolotl/lib/recursion.js):

```gdscript
# labs/multi-iso/srv/recursion.gd
class_name RecursionGuard

const _depths: Dictionary = {}  # operation -> depth
const MAX_DEPTH: int = 10

static func check(operation: String) -> Dictionary:
    var current: int = _depths.get(operation, 0)
    if current >= MAX_DEPTH:
        return {allowed=false, depth=current, max=MAX_DEPTH}
    _depths[operation] = current + 1
    return {allowed=true, depth=current + 1, max=MAX_DEPTH}

static func release(operation: String) -> void:
    var current: int = _depths.get(operation, 1)
    _depths[operation] = max(0, current - 1)

# Usage:
func some_api_call(args: Dictionary) -> Dictionary:
    var check := RecursionGuard.check("some_api_call")
    if not check.allowed:
        return {error="Recursion depth exceeded", code="E_RECURSION"}
    try:
        return _do_work(args)
    finally:
        RecursionGuard.release("some_api_call")
```

**Every emit, every tool call, every tree walk, every
state mutation** goes through this. No exceptions. The
default max depth is 10; deep operations override per-call.

**This is the single most important security primitive.**
Without it, a single malicious packet can DoS the server.

The vant `recursion.js` goes further: it provides
**safe primitives** (`batch`, `traverse`, `lookup`, `retry`)
that build the recursion guard *into* the operation. Lift
those too.

### Layer 1: Capability check (who can do what)

Every operation has a capability. Read, write, network,
admin, remote. The capability is checked before the
operation runs. This is the sandbox layer.

```gdscript
# labs/multi-iso/srv/sandbox.gd
class_name Sandbox

enum Capability { READ, WRITE, NETWORK, ADMIN, REMOTE }

static func can(ctx: Object, cap: Capability) -> bool:
    # Per-context capability set
    var allowed: Array = ctx.get_capabilities()
    return cap in allowed
```

The pattern comes from vant's `sandbox.js`. Lift the
concept: every service gets a `can(capability)` method that
the pipeline calls before invoking.

### Layer 2: Validation (input is not garbage)

Every input is validated before it reaches the logic. Type
checks, range checks, format checks. The pattern is vant's
`vaf.js` (Validation And Filtering).

```gdscript
# labs/multi-iso/srv/validator.gd
static func check_string(value: String, max_length: int = 256) -> bool:
    return value.length() > 0 and value.length() <= max_length

static func check_int(value: int, min: int, max: int) -> bool:
    return value >= min and value <= max
```

Lift the validation patterns from vant's `vaf.js`. The key
invariants:

- String length ≤ 256 (cache key)
- Integer ranges (no negative counts, no overflow)
- Array sizes (no 1M-element payloads)
- Content types (chat is plain text, items are schema)

### Layer 3: Rate limit (no flooding)

Every operation has a rate limit. The QoS layer
(`qos.gd`, lifted from vant's `qos.js`) enforces it.

```gdscript
# labs/multi-iso/srv/qos.gd
class_name QoS

const _buckets: Dictionary = {}  # operation -> {tokens, last_refill}

static func check(operation: String, max_per_minute: int = 60) -> bool:
    # Token bucket algorithm
    var now := Time.get_ticks_msec()
    var bucket: Dictionary = _buckets.get(operation, {tokens=max_per_minute, last=now})
    var elapsed := (now - bucket.last) / 1000.0
    var refill := int(elapsed * max_per_minute / 60.0)
    bucket.tokens = min(max_per_minute, bucket.tokens + refill)
    bucket.last = now
    if bucket.tokens > 0:
        bucket.tokens -= 1
        _buckets[operation] = bucket
        return true
    return false
```

The circuit breaker (also from vant) is the safety valve:
if a player is being rate-limited too often, the breaker
opens and they get hard 429s for a cooldown period.

### Layer 4: Pipeline (composition)

The pipeline composes all the above. Every public API
goes through the pipeline:

```gdscript
# labs/multi-iso/srv/pipeline.gd (lifted from vant pipeline.js)
enum Mode { PUBLIC, PRIVATE, REMOTE, DUAL, STACK }

func run(ctx: Context, op: Callable, mode: Mode = Mode.PUBLIC) -> Variant:
    var chain := _get_chain(mode)
    # chain = [sandbox.can(cap), validator.check(input), qos.check(op), escrow.approve]
    for handler in chain:
        if not handler(ctx):
            return {error="Pipeline blocked", layer=handler.name}
    return op.call()
```

The pipeline modes map to intent:
- **PUBLIC** — read-only (no side effects)
- **PRIVATE** — local state mutation
- **REMOTE** — cross-server or cross-region
- **DUAL** — both read and write
- **STACK** — multi-brain (multi-tenant)

This is the **enforcement layer** for the grail path. Every
read = PUBLIC. Every write = PRIVATE. Every sync = REMOTE.
Every tick = DUAL. Every multi-tenant = STACK.

### Layer 5: Audit (the trail)

Every operation is logged. The audit log is content-hashed
and content-addressable. The chain is the timeline.

```gdscript
# game/core/services/audit_service.gd
func log_operation(op: String, ctx: Context, result: Variant) -> void:
    var entry := {
        "op": op,
        "ctx_hash": content_hash(ctx),
        "result_hash": content_hash(result),
        "tick": _current_tick,
        "actor": ctx.actor_id,
    }
    _log.append(entry)
    _state_tree.append("audit:" + _current_tick, entry)
```

The vant `lib/audit.js` pattern: every module emits audit
events. The audit service subscribes to all of them.

### Layer 6: Content hash chain (anti-tamper)

The state tree is content-hashed. Every change is a
transition from one root hash to another. The chain is
the integrity proof.

If a malicious actor modifies a state record directly (not
through the orchestrator), the content hash breaks, and
the next tick detects the divergence. **The state tree is
self-validating.**

This is the line: "state tree, globals, syncs, asyncs, are
extremely important." The state tree is the source of
truth. The content hash is the proof. The recursion guard
is what keeps the chain from being weaponized.

---

## What each layer defends

| Layer | Defends against | Cost | Bypassable? |
|-------|-----------------|------|-------------|
| 0: Recursion guard | Infinite loops, stack exhaustion | ~0 (one dict lookup) | No (universal) |
| 1: Capability check | Unauthorized operations | ~0 (one set lookup) | If capability is wrong |
| 2: Validation | Garbage input, type confusion | ~0 (per-call) | If validation is wrong |
| 3: Rate limit | Flooding, DoS | ~0 (per-call) | If rate is too high |
| 4: Pipeline | Composition errors | ~0 (function call) | If chain is wrong |
| 5: Audit | After-the-fact forensics | O(log size) | No (always) |
| 6: Content hash | State tampering | O(1) per query | If hash collides |

The recursion guard is the *only* layer that's truly
universal. Everything else can be misconfigured. The
recursion guard cannot — if you call it before every
operation, infinite loops are impossible.

---

## The agent framework angle

The user said: *"This is an agent framework, designed to
allow you all to play with us all. Some will be nefarious
though."*

This is the *real* threat model. An agent (AI or human) can
issue thousands of operations per second. The agent's tool
calls are recursive by nature: "find a target" → "attack
target" → "find next target" → "attack" → ... Each call
becomes a state mutation. Each state mutation is a
write. Each write is a tick-bound operation.

Without the recursion guard, an agent's tool call chain
will eventually loop. The agent might be malicious (trying
to DoS). The agent might be buggy (recursive tool calling
without depth limits). Either way, the result is the same:
the server gets stuck in a loop.

**The recursion guard is the agent framework's seatbelt.**
It's not optional. It's not nice-to-have. It's the
difference between a server that survives 10K agents and
one that crashes when the third agent goes recursive.

```gdscript
# Every agent tool call must look like this:
func agent_tool_call(agent_id: String, tool: String, args: Dictionary) -> Variant:
    var op := "agent:%s:%s" % [agent_id, tool]
    var check := RecursionGuard.check(op)
    if not check.allowed:
        return {error="Agent recursion exceeded", depth=check.depth}
    try:
        return Pipeline.run(agent_ctx, func(): return _tool_dispatch(tool, args), Mode.PRIVATE)
    finally:
        RecursionGuard.release(op)
```

The per-agent + per-tool key means each agent's recursion
is tracked separately. One agent going rogue doesn't
block others.

---

## The 5 things to do first

1. **Lift `lib/recursion.js`** → `labs/multi-iso/srv/recursion.gd`
   (the foundation, P0)
2. **Wrap every event emit** in `EventBus._emit()` with a
   recursion guard
3. **Wrap every public service method** in a pipeline call
4. **Add per-agent rate limits** in `QoS.check()`
5. **Add content-hash validation** on every state tree
   read

After these 5, the frame is hardened against the most
common attack vectors. The rest is defense in depth.

---

## See also

- [`vant-lift.md`](./vant-lift.md) — the lift manifest.
  `recursion.js`, `pipeline.js`, `qos.js`, `sandbox.js` are
  all on the list.
- [`grail-path.md`](./grail-path.md) — the pre/mid/post
  orchestration. The pipeline IS the grail's enforcement.
- [`multi-iso-frame.md`](./multi-iso-frame.md) — the
  orchestrator. The recursion guard is the first thing
  the orchestrator calls.
- [`labs/prd.md §10.6`](../../labs/prd.md) — the state tree
  design. The content hash chain is Layer 6 here.
- The security skill (always-on): apply least privilege,
  validate all inputs, use secure storage, never expose
  secrets in errors.
