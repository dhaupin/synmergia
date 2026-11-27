---
permalink: /access/agents/
layout: default
title: Agent Access
description: The local AgentDoor wire, stable handles, MCP projection, seats, sign-off gates, and the fail-closed remote posture.
---

# Agent access

<p class="lede">An agent is a player with its own character, not a backdoor. It observes named handles, acts through the same game verbs a person uses, and refuses honestly when it cannot.</p>

## The contract

gamestruct defines four primitives and one optional fifth:

| Primitive | Meaning |
|---|---|
| `observe()` | The current state for this seat |
| `act(handle, verb?, value?)` | Do one thing by stable handle |
| `wait_for(predicate, timeoutMs)` | Resolve when a condition holds, or time out honestly |
| `events(sinceFrame)` | What changed since a cursor |
| `see(opts?)` | Optional: capture a frame and return a path or URL, never pixels |

Synmergia adds one multi-agent extension: `/coord`. The protocol layer is not reimplemented in the game; gamestruct owns the MCP projection.

## The local door

`AgentDoor` is the HTTP listener. It is off unless `SYN_AGENT=1`, binds `127.0.0.1:3789` by default, and runs its transport on a separate thread. The main thread remains the only scene-tree mutator.

| Route | Method | Body or query | Returns |
|---|---|---|---|
| `/health` | GET | none | liveness and the current frame |
| `/observe` | GET | optional `principal` query | the current snapshot |
| `/act` | POST | `{ "id": "...", "verb": "...", "value": ... }` | the act result |
| `/wait_for` | POST | `{ "predicate": {...}, "timeoutMs": 8000 }` | `{ ok, waited_ms }` or an honest timeout |
| `/events` | GET | `?since=N` | the event ring |
| `/see` | GET or POST | optional `{ "label": "..." }` | a PNG descriptor |
| `/coord` | POST | `{ "op": "register", ... }` | the coordinator result |

`/act` folds the gamestruct body onto the driver's `id` plus a verb-specific args object. A scalar `value` stays a value; a dictionary is folded into args. A `principal` in the body routes the verb to that agent's own body.

## Enable it

```bash
SYN_AGENT=1 \
SYN_AGENT_DOOR_PORT=3789 \
SYN_AGENT_DOOR_BIND=127.0.0.1 \
godot --headless --server --path game/
```

The door is local development and self-hosted surface, not a public API. For remote access, put an authenticated TLS proxy in front of it and set `SYN_AGENT_TOKEN`.

## Enable it in the web build

The wasm export has no process env, so `SYN_AGENT=1` has no browser
equivalent. The in-page wire (`window.SynmergiaAgent`, backed by the
`WebInputBridge` hooks) installs regardless, but the driver stays OFF until
the operator opts in -- fail-closed, exactly like an unset `SYN_AGENT`. Set
the flag in `web/config.js` (the deploy config) before the engine boots:

```js
window.SynmergiaConfig.agent = true;   // window.SynmergiaAgent verbs go live
```

With the flag unset, every verb returns `{ ok: false, reason: "agent driver
disabled" }`. With it set, the same `observe`/`act`/`events` verbs run against
the real `AgentDriver` -- a browser agent plays by the real rules, driven by
stable handles (`ui:<path>` / `world:<id>`), never screen coordinates. The
`scripts/web_probe/probe_agent_wire.js` probe is the end-to-end oracle: it
drives menu -> register -> lobby -> species -> class -> world entirely through
`window.SynmergiaAgent`.

Two wasm marshalling facts the hooks are built around (a `create_callback`
cannot carry either direction of a rich value): a callback's RETURN VALUE
never crosses back to JS (it publishes JSON on `window.__synAgentResult`
instead), and a JS OBJECT argument arrives as an opaque `JavaScriptObject`,
not a Dictionary (so the facade passes JSON strings the hook decodes).

## Observe, then act

```bash
# Read the current surface.
curl -s http://127.0.0.1:3789/observe | jq '{scene, in_world, player, actions}'

# Pick a handle by its human label, then activate it.
ID=$(curl -s http://127.0.0.1:3789/observe \
  | jq -r '.actions[] | select(.action == "Start Adventure") | .id' \
  | head -1)
curl -s -X POST http://127.0.0.1:3789/act \
  -H 'content-type: application/json' \
  -d "{\"id\":\"$ID\",\"verb\":\"activate\"}"
```

Wait for the world instead of sleeping:

```bash
curl -s -X POST http://127.0.0.1:3789/wait_for \
  -H 'content-type: application/json' \
  -d '{"predicate":{"in_world":true},"timeoutMs":15000}'
```

Then read the event cursor:

```bash
curl -s 'http://127.0.0.1:3789/events?since=-1'
```

## In the browser

The web build installs `window.SynmergiaAgent` with synchronous `observe`, `act`, and `events` hooks. `web/shared/agent-client.js` wraps both transports behind one companion:

```js
const syn = SynmergiaCompanion.auto();
const state = await syn.observe();
const talk = state.actions.find((a) => a.action.startsWith('Talk '));
if (talk) await syn.act(talk.id);
```

`auto()` picks the in-page hooks when they are live, otherwise the remote door. `waitFor` is server-side on the door and JS-side polling in-page. Both reach the same driver.

The in-page transport rides gamestruct's **embedded binding** (SPEC N27), and the wasm boundary is why. A `JavaScriptBridge.create_callback` return value never crosses back to JS, and a structured argument arrives as an opaque handle -- so the host publishes each hook's JSON text on `window.__synAgentResult` and the client reads it back in the same turn. `scripts/build_embedded_bundle.mjs` derives `web/shared/gamestruct-embedded.js` from the installed package (never hand-edit it; `npm run check:embedded` fails on drift), and `agent-client.js` builds the facade over it. Every failure mode -- a hook that is not installed, one that throws, an empty publish, malformed JSON -- comes back as an honest `{ ok: false, reason }` rather than a throw.

One act body, two distances: both the in-page hook and the HTTP door fold `{id, verb, value}` through `AgentDriver.fold_act_body`, so a `set_value` from the page is a value write and not an activate. `see` is the one verb the page does not serve: a viewport capture writes a PNG into the wasm virtual filesystem, which the page cannot fetch back. In-page `see()` refuses by name (`the in-page surface has no eyes`) while the door serves it, so a companion can tell the two apart instead of getting a silent no-op.

## MCP is a projection, not a route

The door does **not** serve MCP JSON-RPC. gamestruct owns that binding; it speaks MCP `2024-11-05` over JSON-RPC 2.0:

```js
import { DoorClient } from 'gamestruct/adapters/vant';
import { doorNodes } from 'gamestruct/adapters/synmergia';

const door = new DoorClient({
  url: 'http://127.0.0.1:3789',
  mapNodes: doorNodes,
});

const state = await door.observe();
const catalog = await door.catalog();
```

For an MCP server, a host builds a gamestruct bridge from the current snapshot and wraps it with `bindings.mcp.createHandler(bridge)`. `initialize`, `tools/list`, and `tools/call` are the MCP methods; `tools/list` carries each tool's `inputSchema`, and `_handle` carries the exact handle the door understands. The MCP host owns transport, auth, and lifecycle.

## Identity and safety

- **Own character.** An agent belongs to exactly one account, has its own character, and can party with humans. It cannot drive a human's body.
- **Principal.** `/observe` and `/act` accept `principal` so a caller can address a specific agent body. An unknown principal is refused by name, never silently mapped onto the human.
- **Sign-off gate.** Consequential verbs such as spend, trade, purchase, drop, destroy, and sell can park for explicit human approval. A gated verb does not silently execute.
- **Off by default.** `AgentDriver` is disabled unless `SYN_AGENT=1` or the runtime enables it. The door is not bound when the driver is off.
- **Fail closed.** When `SYN_AGENT_TOKEN` is set, every route requires `Authorization: Bearer` or `x-api-key`. A non-loopback bind without a token is refused.
- **No pixel truth.** `see` returns a descriptor; the agent reads the file with its own vision. A surface with no renderer refuses honestly and advertises no `see` tool.

## Verify

```bash
SYN_AGENT=1 xvfb-run -a godot --path game --script res://tests/test_agent_driver.gd
xvfb-run -a godot --path game --script res://tests/test_agent_coordinator.gd
SYN_AGENT=1 xvfb-run -a godot --path game --script res://tests/test_agent_body_door_spec.gd
```

The driver receipt proves the real input path, honest timeouts, refusals by name, and a live HTTP round-trip. The coordinator receipt proves the roster, delegated work, round-robin turns, the sign-off gate, and fail-closed auth. The body-door receipt proves the same body over the gamestruct wire.

Read [Agent Play](https://github.com/dhaupin/synmergia/blob/main/labs/prd-agent-play.md) for the full design, and [gamestruct]({{ '/access/gamestruct/' | relative_url }}) for the carrier.
