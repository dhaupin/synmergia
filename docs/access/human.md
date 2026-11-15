---
permalink: /access/human/
layout: default
title: Human Accessibility
description: Native engine labels, A11yService snapshots, focus order, visual settings, web hooks, and the checks behind them.
---

# Human accessibility

<p class="lede">The accessibility tree is built from the controls themselves. A screen reader, a switch user, and a keyboard-only player all read the same named nodes and walk the same focus order.</p>

## The tree lives on the controls

Every actionable control should carry two engine properties:

- `accessibility_name` - the action from the user's side, imperative and specific: `Start Adventure`, `Enter World`, `Attack the Wolf`.
- `accessibility_description` - the consequence in one clause: `Opens the login screen`, `Creates a temporary account and opens the lobby`.

Actionable controls also take focus, so a keyboard or switch user can reach them. The annotation is not stored in a side table; `A11yService` walks the live scene tree on demand. A button that is added without a label is visible to the walker but fails the naming contract, which is exactly what the audit should surface.

## What a snapshot contains

`A11yService.snapshot()` returns an ordered array in focus order. UI entries and nearby world entities share the same shape:

```json
{
  "id": "ui:MainMenu/MenuButtons/StartButton",
  "path": "MainMenu/MenuButtons/StartButton",
  "kind": "button",
  "action": "Start Adventure",
  "detail": "Opens the login screen",
  "focused": false,
  "disabled": false
}
```

A world entry uses the same fields. Both kinds include a screen-space rectangle:

```json
{
  "id": "world:entity_2",
  "path": "world/entity:entity_2",
  "kind": "entity",
  "action": "Attack Wolf",
  "detail": "13m away, level 3",
  "focused": false,
  "disabled": false
}
```

The order matters. Menu entries follow the live tree. World entries are appended after the UI and sorted nearest first across enemies, NPCs, and players. Tab order and agent focus order read that same list.

## Focus and activation

The service exposes the small set of verbs both lanes need:

| Method | What it does |
|---|---|
| `snapshot()` | Walk the live tree and return the ordered action list |
| `dump()` | Print one `[A11Y]` JSON line per actionable; the probe contract |
| `focus_next()` / `focus_prev()` | Move focus through the snapshot, wrapping at the ends |
| `activate(index)` / `activate_by_id(id)` | Activate a button or an annotated control through its real input path |
| `set_value_by_id(id, value)` | Write a text field or range through focus and the normal change signal |

A secret field reports only `<set>` or empty in the snapshot. The password itself never leaves the process.

## Settings that change the surface

The Settings panel carries the visual and motion controls. These are the labels a player sees:

| Setting | Range or values | What it changes |
|---|---|---|
| **High Contrast Mode** | On / off | High-contrast panel and focus styles, including the 4.5:1 contrast check |
| **UI Text Scale** | 0.8x to 1.5x | Scales UI text across the HUD and panels |
| **Reduce Motion** | On / off | Disables UI transitions, animations, and particle effects |
| **Colorblind Mode** / **Colorblind Type** | On / off; deuteranopia, protanopia, tritanopia | Applies the color-correction shader |
| **Screen Shake** | On / off | Camera shake |
| **Flash Effects** | On / off | Critical and damage flashes |

`UIStyles` carries the effective colors, focus styles, text scale, and motion checks. If the copy or the range changes in `settings_panel.gd`, update this table in the same pull request.

## Keyboard and screen readers

- **Desktop AT** uses Godot's native AccessKit properties. The project setting is `accessibility_support` in `game/project.godot`; verify it on the target platform rather than assuming a build is exposing the tree.
- **Keyboard play** uses the scene focus order. Every actionable should take focus and show a visible focus style; the menus route Tab through the shared service.
- **Web AT** depends on the engine's web accessibility adapter. The web bridge also exposes an agent-only dump hook: `window.__synA11yDump()` prints the stream and sets `window.__synA11yLast` for probes. Do not treat that hook as a human hotkey.

## What good looks like

- Every interactive control has a name and a consequence.
- The control takes focus, and focus is visible.
- State is communicated as text, not color alone.
- The control appears in `snapshot()` with a stable `ui:` or `world:` id.
- The action routes through the real game verb, never a side-channel.
- High contrast, text scale, and reduce motion are respected.

## Verify

Run the focused receipts before changing a control or the service:

```bash
sh ./scripts/godot_test_runner.sh test_a11y_service
sh ./scripts/godot_test_runner.sh test_a11y_contrast
```

The web probe rig boots the real export and consumes the `[A11Y]` stream:

```bash
sh scripts/pack_web.sh
xvfb-run -a node scripts/web_probe/probe_boot.js
xvfb-run -a node scripts/web_probe/probe_a11y.js
```

Read `scripts/web_probe/README.md` first. The login flow changed when guest play retired, so a probe's journey may need the current account path.

## Verification status

The engine accessibility drill merged on `staging`; the open lane is real
assistive-technology and keyboard verification
([#101](https://github.com/dhaupin/synmergia/issues/101)). Treat this page as
the published contract and `labs/prd-accessibility.md` as the working design.
If a control's label, focus behavior, or snapshot shape changes, ship the docs
change with the receipt.

This page describes the shipped surface. It is not a WCAG certification, and it does not claim native voice control.
