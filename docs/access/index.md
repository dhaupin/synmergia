---
permalink: /access/
layout: default
title: Access & Agents
description: One semantic tree for human accessibility and agent access, carried by gamestruct and exposed by A11yService and AgentDoor.
---

# Access is the interface

<p class="lede">A screen reader and an MCP client need the same things: named nodes, stable handles, a linear focus order, and an event stream. Synmergia builds that description once, then exposes it to people and agents.</p>

<div class="doors">
  <a class="door" href="{{ '/access/human/' | relative_url }}">
    <span class="door-kicker">For people</span>
    <strong>Human accessibility</strong>
    <span>Native labels, focus order, text scale, contrast, reduced motion, and the snapshot behind them.</span>
  </a>
  <a class="door" href="{{ '/access/agents/' | relative_url }}">
    <span class="door-kicker">For machines</span>
    <strong>Agent access</strong>
    <span>The local door, its verbs, MCP projection, seats, and the fail-closed posture.</span>
  </a>
  <a class="door" href="{{ '/access/gamestruct/' | relative_url }}">
    <span class="door-kicker">The carrier</span>
    <strong>gamestruct</strong>
    <span>The shared contract for the tree, both lanes, HTTP and MCP bindings, and the reference adapters.</span>
  </a>
</div>

## One tree, two lanes

| Lane | Who reads it | What it gets | How it acts |
|---|---|---|---|
| **Human** | Screen readers, switch and keyboard users, desktop and web AT | Named, role-tagged nodes; focus order; live-region events | Focus and activate through the normal input path |
| **Agent** | MCP clients, companion apps, scripted tests | Stable handles; verbs; an event cursor; an optional visual descriptor | `act` on the same handle the human lane walks |

The tree is not a second UI and the agent lane is not a backdoor. `A11yService` walks the live scene and emits `ui:` and `world:` entries. `AgentDriver` acts on those handles through the same game verbs a keypress or tap uses. gamestruct defines the shared vocabulary and the transport projections.

## What is shipped

| Surface | State |
|---|---|
| Native engine labels and focus | `accessibility_name`, `accessibility_description`, and focusable controls; `A11yService` snapshots them |
| Visual settings | High Contrast, UI Text Scale, Reduce Motion, colorblind correction, screen shake, and flash toggles |
| In-world actions | The same snapshot schema includes nearby enemies, NPCs, and players, ordered nearest first |
| Local agent door | `AgentDoor` serves the gamestruct wire when `SYN_AGENT=1`; off by default |
| MCP | A gamestruct binding, hosted by the caller; the door does not hand-roll JSON-RPC |
| The eyes | `/see` returns a PNG path or URL descriptor; pixels never cross the wire |
| Engine a11y drill | Merged on `staging`; real assistive-technology and keyboard verification is the open lane ([#101](https://github.com/dhaupin/synmergia/issues/101)) |

## The rules

- **One tree.** Annotations live on the controls. There is no shadow registry that can drift from the node it describes.
- **Stable handles.** Agents act by `ui:<root-relative-path>` or `world:<entity_id>`, never by pixel coordinates or list indexes.
- **Honest refusals.** Unknown handles, disabled nodes, wrong verbs, and timeouts come back as values with a reason. They do not silently succeed.
- **Agents are players.** An agent has its own account and character. It parties with humans; it does not drive a human's body.
- **Off by default, fail closed.** The door binds loopback and stays closed unless enabled. A non-loopback bind without a token is refused.

## Where to go next

- [Human accessibility]({{ '/access/human/' | relative_url }}) for the engine tree, settings, and verification.
- [Agent access]({{ '/access/agents/' | relative_url }}) for the HTTP door, MCP, seats, and examples.
- [gamestruct]({{ '/access/gamestruct/' | relative_url }}) for the contract, the pin, and the update path.
- [The accessibility PRD](https://github.com/dhaupin/synmergia/blob/main/labs/prd-accessibility.md) for the working design and receipts.
- [The agent-play PRD](https://github.com/dhaupin/synmergia/blob/main/labs/prd-agent-play.md) for the door, coordinator, and remote posture.
