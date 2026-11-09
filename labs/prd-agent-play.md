# Agent Play — the control layer (2026-11-04)

> **Status:** SHIPPED (v1). Code: `game/core/services/agent_driver.gd`,
> `game/core/services/agent_door.gd`, `web/shared/agent-client.js`,
> the stable-id additions to `a11y_service.gd`, the `window.SynmergiaAgent`
> hooks in `web_input_bridge.gd`. Receipt: `game/tests/test_agent_driver.gd`
> (exit 0, 20/0). Supersedes the dead half-built connector layer
> (`connector_service.gd` / `agent_connector.gd` / `agent_action.gd` /
> `connectors/{vant,mcp}`) which was removed this round — it never booted
> (no autoload entry), never had a consumer, and its `observation_ready`
> contract was wallpapered.

> **Purpose:** the owner's ruling: build a control layer so an agent — or a
> dev agent — can literally PLAY Synmergia, replacing the heavy reliance on
> runners/probes. It must be a FIRST-CLASS, PLAYER-FACING feature: a player
> connects an agent (later, a few) to play *with* them; and it must serve
> accessibility (a scripted / screen-reader-style control surface for players
> who cannot use the usual inputs). Scraggler residue of old systems (debug
> layer, hotkeys, tab-toggling, console button locations) is REMOVED, not
> layered over.

## 1. The law: an agent is a player

An agent is not a special rail. It is a principal that plays the game the
way any principal plays it:

1. **Same verbs.** Every action routes through the REAL pipeline — movement
   rides the action map (`Input.action_press`, exactly what a key does),
   attack routes through `use_skill` -> CombatComponent (GCD + live stack),
   talk routes through the entity's own `interact`, party invites ride
   `PartyService`. There is no agent API that skips the gate a human's
   keypress takes. (This is the prd-accessibility.md sec 9 non-goal and the
   prd-agent-law.md sec 2 integrity law, honored by construction.)
2. **Same species/class.** An agent connects to an ACCOUNT and plays any
   species and class a human can — the earlier "synthetics are the agent
   species" framing was about the synthetic *bodies* (species-agnostic
   projection), never a restriction that agents may only be synthetic. An
   agent that wants to be a human cleric is a human cleric. (See
   prd-agent-law.md sec 3, amended this round.)
3. **Same purse, same ledger, same law.** No agent-only economy, no agent
   exemption. The behavioral-integrity layer (prd-agent-law.md) sees an
   honest, typed action stream because the a11y/action pipeline already
   emits one.
4. **Play *with* humans.** A connected agent is a party member like any
   other: `party_invite`, shared XP, the same party UI. The "syn + mergia"
   is a human and an agent in one group, on one shard.

## 2. The four verbs

The whole surface is four request/response verbs. No pixels, no console
scraping, no index-based coordinates.

| Verb | Shape | Meaning |
|------|-------|---------|
| `observe()` | `-> {ok, frame, scene, in_world, player, target, party, actions[], events[]}` | The structured snapshot. `actions[]` is the actionable list, each entry carrying a STABLE id. |
| `act(id, args)` | `-> {ok, reason, ...}` | Perform one action by stable handle or by a small world-verb set. |
| `wait_for(pred, ms)` | `-> {ok, waited_ms \| reason}` | Server-side wait; resolves when the predicate holds or the timeout expires. Kills fixed-sleep flake. |
| `events(since)` | `-> [ {t, frame, event, data} ]` | The recent event ring (damage, kills, zone, gold, notifications, target actions). |

### Stable handles (why ids, never indexes)

Every actionable carries `id`:

- `ui:<root-relative-path>` — e.g. `ui:GlobeWorld/HudLayer/MenuManager/ChatUI/...`.
- `world:<entity_id>` — e.g. `world:entity_2`.

Ids survive re-renders and list reordering; indexes do not. An agent acts
by id (`A11yService.activate_by_id`) and never has to re-derive a position.
The `rect` stays in the snapshot for human/pointer consumers only.

### World verbs (the small set beyond handles)

`move {forward, strafe, sprint}`, `stop`, `look {yaw, pitch}`,
`chat {text, channel}`, `attack {target?, skill?}`, `target {target}`,
`party_invite {target}`, `party_leave`, `interact`. These cover the
continuous things handles cannot express; everything discrete is a handle.

## 3. The two transports (one protocol)

```
                ┌──────────────────────────┐
  2D companion  │  web/shared/agent-client │  (website helper / a11y surface)
  on the page ──┤  .js  (SynmergiaCompanion)│
                └────────────┬─────────────┘
                             │ auto-pick
              in-page        │         remote
   window.SynmergiaAgent ────┤──── AgentDoor  (HTTP, 127.0.0.1:3789)
   (WebInputBridge hooks)    │     /observe /act /wait_for /events
                             │     /tools /call (JSON-RPC) /mcp/exec
                             ▼
                     ┌───────────────┐
                     │  AgentDriver  │  (autoload; the one command channel)
                     └───────┬───────┘
                             │ real verbs
          Input.action_press │ use_skill │ PartyService │ interact │ ChatService
                             ▼
                    the game (as a player plays it)
```

- **In-page** (`window.SynmergiaAgent`): for a companion/helper bundled on
  the same page as the Godot canvas. Zero network; calls the driver hooks
  directly. `wait_for` is JS-side polling of `observe()`.
- **Remote** (`AgentDoor`): the vant "door" pattern — ONE listener that is
  simultaneously the MCP surface (`/call`, `/mcp/exec`), the headless API
  (`/observe`, `/act`), and the companion-app API. Binds localhost only and
  is OFF unless `SYN_AGENT=1`, so a shipped server never exposes it by
  default. `wait_for` parks server-side.

Both reach the SAME `AgentDriver` verbs, so distance never changes the rules.

### Threading law

The door runs on its own thread and **never touches the scene tree**. It
resolves the driver reference once on the main thread, then only calls
`submit()` / `poll()` — a mutex-guarded queue. The main thread drains the
queue in `_process` and is the sole mutator. (`get_node_or_null` off the
main thread is a Godot error — this is why the reference is cached.)

## 4. What was removed (the residue)

The old agent scaffolding was deleted, not extended:

- `core/services/connector_service.gd`, `core/schemas/agent_connector.gd`,
  `core/schemas/agent_action.gd`, `connectors/vant/`, `connectors/mcp/`
  — never autoloaded, never booted, no consumer, `observation_ready`
  wallpapered (census rounds had logged it for life).
- The `agent_connectors` / `agent_actions` / `connected_agents` adapter
  mappings in `backend_factory.gd` (pointed at the dead service).
- The void-survivors receipt now asserts the retirement holds.

## 5. Enablement

| Surface | Off by default | On |
|---------|----------------|----|
| `AgentDriver` | `_enabled = false` | `SYN_AGENT=1` in env, or `set_enabled(true)` at runtime |
| `AgentDoor` | not bound | binds when the driver is enabled; port via `SYN_AGENT_DOOR_PORT` (default 3789) |
| `window.SynmergiaAgent` | hooks install but return `{ok:false,"reason":"agent driver disabled"}` when off | `SYN_AGENT=1` |

Off is the honest default; a production server exposes nothing unless the
operator opts in. The door binds `127.0.0.1` regardless (a reverse proxy
fronts it for remote access, per the vant door posture).

## 6. Receipt

`game/tests/test_agent_driver.gd` boots the real globe and drives it only
through the agent verbs:

1. `observe()` reports `in_world` + a structured player block.
2. movement rides the REAL input map (the body walks — 0.816 m observed).
3. `wait_for` resolves (`in_world`) and honestly times out on a false pred.
4. `act()` refuses unknown verbs / missing handles by name; a real handle
   activates.
5. the `AgentDoor` serves a real HTTP round-trip (`/observe` -> live world).

Run: `cd game && xvfb-run godot --path . --script res://tests/test_agent_driver.gd`

## 7. Non-goals (v1)

- No multi-agent orchestration yet (the owner's "maybe a few later"):
  the protocol is per-agent; a companion connects one agent at a time.
- No auth on the door beyond the localhost bind + the `SYN_AGENT` gate.
  A remote deployment MUST front it with TLS + a token (the door has the
  CORS headers; the auth posture is the operator's reverse proxy, exactly
  as the vant MCP door documents).
- No replacement of the runners/probes wholesale — those still gate CI.
  This layer is the thing an agent uses to *play and test* interactively;
  receipts remain the deterministic gate.
