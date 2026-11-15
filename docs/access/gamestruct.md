---
permalink: /access/gamestruct/
layout: default
title: gamestruct
description: The shared accessibility and agent contract, the pinned Synmergia carrier, and the boundary between the world and the protocol.
---

# gamestruct, the common carrier

<p class="lede">gamestruct is the shared contract between a surface and two audiences: a person using assistive technology and a machine agent. Synmergia implements the world side; gamestruct owns the generic tree, lanes, and transport projections.</p>

## What it owns

| Piece | What it carries |
|---|---|
| **Primitives** | `observe`, `act`, `wait_for`, `events`, plus the optional `see` |
| **Tree** | Stable handles, parent/child order, roles, names, values, descriptions, and actions |
| **Human lane** | Render, focus order, the flat a11y dump, and the CI audit |
| **Agent lane** | The MCP tool catalog, affordances, and dispatch |
| **HTTP binding** | `/observe`, `/act`, `/wait_for`, `/events`, `/see`, `/health` |
| **MCP binding** | JSON-RPC 2.0 `initialize`, `tools/list`, `tools/call`, plus direct `observe`, `events`, and `see` |
| **Adapters** | Synmergia (world), Vant (brain), a plain web form, and a live DOM subtree |

The contract is small on purpose. A surface describes its state once as a semantic tree; the human lane and agent lane are two readings of that tree, and both act through the same `act()`.

## What Synmergia owns

- The door routes and the game verbs behind them.
- The seats, accounts, and characters.
- The in-world action bridge and the `ui:` / `world:` handle set.
- The coordinator and its sign-off gate.
- The engine annotations and the accessibility settings.

The MCP protocol is not reimplemented in the Godot door. The door transports the primitives; gamestruct projects them into MCP when a host asks for that view.

## The pinned carrier

Synmergia pins gamestruct in `package.json`:

```json
"gamestruct": "github:dhaupin/gamestruct#447a0e4ae7aaaa3f338b56300dbb55481cdb2e14"
```

The installed package is **1.1.0**. The commit pin is the reproducibility anchor; `bun.lock` carries the resolved package and integrity. The repository's `npm run verify:lane` receipt imports the package the way a companion brain would and checks the parts Synmergia depends on: the role vocabulary, `Bridge`, the agent tool catalog, `DoorClient`, and the Synmergia adapter's `doorNodes` normalizer.

## The handle law

The door's `actions[].id` is already the stable handle: `ui:<root-relative-path>` for controls and `world:<entity_id>` for world entities. The Synmergia adapter reuses that string unchanged. It never re-slugs a door handle, because the door resolves the exact string.

```js
import { buildBridge } from 'gamestruct/adapters/synmergia';

const door = (verb, args) => fetch(`http://127.0.0.1:3789/${verb}`, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify(args || {}),
}).then((r) => r.json());

const bridge = buildBridge(snapshot, {
  send: door,
  see: door,
});

await bridge.act('ui:MainMenu/MenuButtons/StartButton');
```

`buildBridge` folds one `observe()` snapshot. A live host rebuilds or refreshes the bridge as the door's state changes; it does not hold a stale tree. Omit `see` and the bridge is honestly blind: `see()` refuses and the agent catalog advertises no `see` tool. A surface that can render pixels gets the optional fifth primitive; the descriptor carries a path or URL, not the bytes.

## Two lanes, one audit

- `human.render(bridge)` returns the node list and focus order; a host maps it to its platform AT API, such as AccessKit in Godot or ARIA on the web.
- `human.a11yDump(bridge)` is the flat text proof, one line per node in traversal order.
- `human.audit(bridge)` is a gate: interactive node with no name, interactive node with no action, image with no alt text.
- `agent.toolCatalog(bridge)` returns one MCP-shaped tool per actionable node, with an `inputSchema` and the handle it drives.
- `agent.toolCall(bridge, name, args)` dispatches onto the same `act()`; there is no second code path.

Run the audit before shipping a new surface. Passing it does not mean the surface is beautiful; it means a person who cannot see it can use it.

## The eyes

`see` is optional and additive. The Synmergia door captures the live frame to a PNG and returns `{ ok, path, url, bytes, width, height }`. The agent reads the file with its own vision. A blind surface must refuse instead of returning a fake or empty image, and its catalog must not advertise the tool.

## Updating the carrier

1. Change the pin in `package.json` to the new gamestruct commit.
2. Run `bun install` so `bun.lock` matches.
3. Run `npm run verify:lane`, `npm run lint`, and the docs build.
4. Run the engine a11y and agent receipts that cover the changed surface.

Do not vendor the package or copy its MCP binding into the game. The family rule is one owner for the protocol; drift starts when a second copy appears.

## Read the contract

- [gamestruct docs](https://docs.creadev.org/gamestruct/) - the guides, including bindings, adapters, and the human and agent lanes.
- [The specification](https://github.com/dhaupin/gamestruct/blob/main/SPEC.md) - normative rules N1-N24 and the node shape.
- [gamestruct on GitHub](https://github.com/dhaupin/gamestruct) - source, tests, and release history.
- [The Synmergia adapter](https://github.com/dhaupin/gamestruct/blob/main/lib/adapters/synmergia.mjs) - the world-side mapping.

gamestruct is MIT-licensed and dependency-free. It is a protocol and a reference implementation, not a game engine, an auth server, or a UI renderer.
