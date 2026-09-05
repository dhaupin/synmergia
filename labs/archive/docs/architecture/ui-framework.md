# UI Framework — Completing the Circle

> **TL;DR:** The UI is incomplete because it's a stub for a
> *framework that all agents can use*. The frame is the
> data; the UI is the presentation; the bridge is what
> we're missing. This doc sketches the bridge.

**Author:** drafted 2026-08-30 as part of the rando-in-the-mix
session. Tied to the existing
[`islands-builds-godot.md`](./islands-builds-godot.md) and
[`unified-nsc9-islands-builds.md`](./unified-nsc9-islands-builds.md).

---

## The problem

The Islands POC is a good start. `UIPanel` is the source
of truth for panels. `UIStyles` is the source of truth for
colors/fonts. `UIManager` owns the scene tree. But the
*circle* isn't closed:

- The frame writes to the state tree
- The state tree is materialized as composite tables
- The UI *reads* from `EntityService.get_all()` directly
  (or some similar global)
- The UI writes to the orchestrator via events
- The events update the state tree
- The state tree re-roots
- The UI doesn't re-render automatically

**The UI is decoupled from the state.** When the state
changes, the UI has to poll, or the UI has to subscribe,
or the UI has to refresh manually. This is why it feels
incomplete.

The fix: a **reactive bridge** between the orchestrator
and the UI. The UI subscribes to *axis queries*, not
entities. When the pre-state (the materialized
intersection) changes, the UI re-renders.

This is the same pattern as React's hooks, Vue's
reactivity, or SolidJS's signals. The difference: the
"signal" is an axis query, not a single value.

---

## The reactive bridge

```gdscript
# game/core/ui/axis_query.gd
class_name AxisQuery
extends RefCounted

var _orchestrator: Orchestrator
var _axes: Dictionary
var _on_change: Callable
var _last_signature: String

func _init(orchestrator: Orchestrator, axes: Dictionary, on_change: Callable) -> void:
    _orchestrator = orchestrator
    _axes = axes
    _on_change = on_change
    _last_signature = _compute_signature()

func current() -> Array:
    return _orchestrator.query(_axes)

func has_changed() -> bool:
    var sig := _compute_signature()
    if sig != _last_signature:
        _last_signature = sig
        return true
    return false

func _compute_signature() -> String:
    # Content hash of the queried intersection
    return _orchestrator.signature(_axes)
```

The `AxisQuery` is the bridge. It's a *signal* that
*changes* when the underlying axis intersection changes.
The UI subscribes to the query, the query is invalidated
on tick, the UI re-renders.

```gdscript
# In a UI panel:
var my_party_query := AxisQuery.new(
    orchestrator,
    {"party": player.party_id, "faction": player.faction},
    _on_party_changed
)

func _process(_delta: float) -> void:
    if my_party_query.has_changed():
        _render_party(my_party_query.current())
```

This is **the circle**:

```
Frame writes to state tree
  → state tree re-roots on tick
    → composite tables update
      → axis query signature changes
        → UI re-renders
```

No polling. No event subscription. No manual refresh.
The UI just *reads*. The orchestrator tells the UI when
the read would return something different.

---

## The framework that all agents can use

The user said: *"This is an agent framework, designed to
allow you all to play with us all."*

The UI must be **renderable by an agent, not just a human**.
This means:

1. **Schema-driven UI** — every UI panel is described by
   a schema. The schema says "this panel shows a list of
   entities, with these fields, in this layout." An agent
   reads the schema and produces a UI plan.
2. **A11y by default** — every interactive element has a
   label, a role, a description. The agent (or screen
   reader) can navigate it.
3. **Deterministic rendering** — given the same state, the
   same UI renders. Two agents viewing the same world see
   the same UI.
4. **Action + intent model** — every UI action emits an
   intent, not a mutation. The orchestrator decides what
   the intent does. The UI doesn't know the consequences.
5. **State-aware actions** — which actions are valid
   depends on the state. The framework pre-computes
   *action sets* per UI state. The UI shows what can be
   done, not what can't.

The current `UIPanel` is 80% of the way there. It needs
the schema layer and the action model. Lift the patterns
from vant's `forum.js` (which has a similar schema-driven
panel system).

---

## The action model

```gdscript
# game/core/ui/action.gd
class_name UIAction
extends RefCounted

var id: String
var label: String
var intent: String         # "attack", "trade", "use"
var target_axes: Dictionary # what axis query this applies to
var requires: Array        # capabilities needed
var available: bool        # computed from current state

func is_available(orchestrator: Orchestrator, ctx: Context) -> bool:
    return (
        available
        and Sandbox.can(ctx, _required_capability())
        and orchestrator.query(target_axes).size() > 0
    )
```

The UI panel declares *what actions it could expose*. The
framework pre-computes which are *available* for the
current state. The UI shows only the available ones.

This is the *intent-driven* UI. The player sees "Attack"
because there's something to attack. The UI never shows
"Attack" when there's nothing to attack. The state knows.

---

## The 5 things to do

1. **Lift the `AxisQuery` class** from this doc into
   `game/core/ui/axis_query.gd` (Tier 1, A-3)
2. **Wrap every `UIPanel`** in a `UIPanel.react_to(state)`
   method that uses `AxisQuery`
3. **Add the `UIAction` model** to `game/core/ui/`
4. **Add the schema layer** for `UIPanel` (lift from vant's
   `forum.js` panels)
5. **Wire `UIManager` to the orchestrator** so panels
   register their queries on `_ready` and re-render on
   `state_changed`

After these 5, the circle is closed. The UI is reactive.
The frame is the data. The agents can render.

---

## The agent use case

Imagine an AI agent (Claude, GPT, etc.) playing the game.
The agent needs to:
1. See what's around it
2. Decide what to do
3. Take an action

With the reactive bridge:
1. `AxisQuery({"spatial": position, "radius": 20})` returns
   nearby entities
2. The agent's LLM reasons about the result
3. The agent calls `UIAction.attack(target).execute()`,
   which is an intent, which the orchestrator validates
   and applies

The agent never touches the state tree directly. The
agent never calls services. The agent just reads via
queries and writes via actions. The framework enforces
the rules.

**This is the same pattern that React + Redux use for
human UI, but applied to game state for agent UI.** The
"signal" is an axis query. The "action" is an intent.
The "reducer" is the orchestrator's tick.

---

## Why this is novel

Most game UIs are direct-coupled: UI knows about entity
X, polls it every frame, updates the label. This is
wasteful and brittle.

The reactive bridge:
- The UI doesn't know about specific entities
- The UI subscribes to a *query*
- The query is content-hashed
- The UI re-renders only when the hash changes
- An agent can introspect the query and reproduce the UI

The same UI works for humans (via Godot rendering) and
agents (via the query signature + the schema). **One
framework, two consumers.** That's the circle.

---

## See also

- [`islands-builds-godot.md`](./islands-builds-godot.md) —
  the existing Islands POC. The reactive bridge extends
  it.
- [`unified-nsc9-islands-builds.md`](./unified-nsc9-islands-builds.md) —
  the original exploration.
- [`grail-path.md`](./grail-path.md) — the pre/mid/post
  contract. The UI is the read path.
- [`multi-iso-frame.md`](./multi-iso-frame.md) — the
  orchestrator. The `query()` method is the read API.
- [`security.md`](./security.md) — the agent framework's
  security. The UI's actions go through the pipeline.
- [`vant-lift.md`](./vant-lift.md) — lift
  `lib/forum.js`'s schema-driven panel system.
