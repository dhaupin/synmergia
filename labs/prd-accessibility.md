# PRD: Synmergia Accessibility & Agent-Action Layer (S-A11Y)

> **Status:** SHIPPED (all five rounds landed -- R35 menus, R36 HUD,
> R37 world entities, R38 engine settings + contrast audit, R39
> graveyard cleanup; see labs/TASKS.md)
> **Owner:** world-frame-architect
> **Created:** 2026-10-05, out of the R32/R33 live-WASM probe rounds
> **Supersedes:** every previous partial attempt (see sec 8, Graveyard)

## 1. The one-paragraph thesis

Synmergia's UI is a forest of absolutely-positioned Controls that no
screen reader, no agent, and no test can enumerate without pixel
guessing. We fixed this five times with five partial hacks (a11y
properties that did not exist yet, an F13 overlay, tab-cycle helpers,
one-off `[CS]` geometry dumps, a hover-reading debug panel). The
discovery of R33 is that **Godot 4.7.2 ships AccessKit natively**
(`accessibility_name` / `accessibility_description` / focus modes on
every Control, verified on our binary), which means ONE tree of
annotations -- maintained on the nodes themselves -- can simultaneously
feed: real assistive technology on desktop, the browser accessibility
tree (via AccessKit's web adapter) for web players, our agent/probe
layer, and the in-world interaction layer. One source of truth, four
consumers, zero parallel hacks.

## 2. Who consumes what (the four-beak bird)

| Consumer | Reads | Gets |
|----------|-------|------|
| Desktop AT (NVDA/VoiceOver) | Engine AccessKit tree (`accessibility_name/description`, focus) | Native screen reader support, Tab/arrow nav |
| Web AT + web players | AccessKit web adapter -> DOM a11y tree over the canvas | Browser-native reader support; keyboard-only play |
| Agents / probes / e2e tests | `A11yService` snapshot (JSON of the same tree) | "What can I act on right now, and where is it" -- no pixel guessing |
| In-world players + agents | InteractionLayer already does range interaction; the same snapshot format extends to world entities/actions | The "what can I do here" instinct, in-world |

The load-bearing principle: **annotations live on the Controls, not in
a side-car registry.** A side-car goes stale the moment someone adds a
button and forgets the registry. Engine properties cannot rot away from
the node they describe, and AccessKit ships them to every consumer for
free.

## 3. The canonical contract: Actionable

Every interactable Control gets, at construction time:

- `accessibility_name` -- the action from the USER's side, imperative,
  English: "Play as Guest", "Enter World", "Attack the Wolf".
- `accessibility_description` -- the consequence, one clause:
  "Creates a temporary account and opens the character lobby".
- `focus_mode = FOCUS_ALL` -- every actionable is keyboard-reachable,
  desktop and mobile, in scene-declared order (TAB = next; each menu
  already has cycle handlers we keep).

Naming: the accessibility_name IS the canonical action id humans and
agents share. Where a stable machine key is also needed (analytics,
telemetry, cross-language), a Control's `name` (node path leaf) is the
machine key; the human string rides in accessibility_name. Never invent
a THIRD id.

Rule of thumb for copy: `accessibility_name` = what it does (button
text or better), `accessibility_description` = what happens if you use
it, so a screen reader user or an agent can decide WITHOUT seeing the
layout.

## 4. A11yService (the one new autoload)

Small, boring, load-bearing. No shadow registry: it WALKS the live
scene tree on demand.

```
signal focusables_changed   # emitted on tree_changed / scene swap (debounced)

func snapshot() -> Array[Dictionary]
#   [{ "path": "MainMenu/MenuButtons/StartButton",
#      "kind": "button", "action": "Start Adventure",
#      "detail": "Opens the login screen",
#      "rect": {"x":..,"y":..,"w":..,"h":..},   # canvas px
#      "focused": false, "disabled": false, "visible": true }]
#   Order = focus order (tree order filtered to actionable kinds).

func focus_next() -> void      # wraps viewport gui_get_next_focus...
func focus_prev() -> void
func activate(index: int) -> bool   # by snapshot index: emits pressed
func focus(index: int) -> bool
func dump() -> void            # one line per actionable -> GameLog (agents)
```

- `snapshot()` cost: a tree walk, only on demand (agents poll; the web
  bridge exposes it the same way). No per-frame work, ever.
- `dump()` lines are the contract our e2e probes parse. The R33 `[CS]`
  card dumps die in favor of `A11yService.dump()`.
- In-world extension (sec 6) reuses EXACTLY this snapshot shape, so
  agent code written for menus works in the world.

## 5. The web bridge (agents + web AT)

Two small additions to the existing `web/shared/input.js` +
`web_input_bridge.gd` contract:

1. `window.SynmergiaA11y.snapshot()` -- JS side polls
   `WebInputBridge.a11y_snapshot()` (a JS eval of A11yService.snapshot,
   already the established drain pattern; JSON, not JS objects).
2. Agent actions go THROUGH the existing input pipeline (clicks by
   snapshot rect center, keys as keyCodes) -- the agent plays by the
   same rules as a human, so anticheat sees nothing anomalous.

The engine-side expose (a11y tree -> browser DOM) is AccessKit's web
platform adapter, wired by Godot's own web export when accessibility
support is enabled in project settings (Auto). That arrives with the
engine integration work in sec 7, not from our code.

## 6. In-world: the same layer, bigger world

The world is not a second system. InteractionLayer resolves
range-based actions on entities; the a11y snapshot gains entity-sourced
entries shaped identically:

```
{ "path": "world/entity:wolf_42", "kind": "entity",
  "action": "Attack Wolf", "detail": "Level 3, 40m away",
  "rect": {"x":..,"y":..,"w":..,"h":..},   # screen-space projection
  "focused": false, "disabled": false }
```

Focus order in-world = screen-distance from crosshair/center, so TAB
cycles world targets the same way it cycles menu buttons. This is what
makes the layer "flexible enough to run in the game world": same
snapshot schema, same activation verb, same consumer code -- the
in-world entries are produced by a small bridge from
InteractionLayer/EntityService instead of the UI tree walk. Targeted
for a later round once the UI half is proven.

## 7. Implementation rounds (each lands green)

1. **A11yService + menu annotations** -- the service, then the five
   menu scenes (main_menu, login, lobby, character_select, settings)
   annotated with name/description/focus. Probe: playwright boots,
   pulls snapshot, clicks Guest by ACTION name, lands in lobby. This
   is the R33 probe, rewritten against the contract instead of pixel
   guesses and one-off dumps.
2. **HUD + in-game surfaces** -- HUD widgets, target frame, dialogs,
   pause. Probe: enter world via snapshot-driven clicks; pause; resume.
3. **In-world entity actions** -- the InteractionLayer bridge (sec 6).
   Probe: snapshot contains "Attack Wolf" near a spawn; activate it.
4. **Engine settings + web AT pass** -- accessibility support enabled
   (Auto), mobile/tablet focus review (the game already self-detects
   `Mode=2 Mobile=true` on web), high-contrast audit against UIStyles.
   Probe: OS screen reader smoke on desktop + manual web pass.
5. **Cleanup round** -- execute the dispositions in sec 8, delete the
   graveyard, update AGENTS.md one-paragraph note.

## 8. The Graveyard (dispositions -- rework/remove)

| Artifact | Where | Disposition |
|----------|-------|-------------|
| `apply_accessibility()` stub that drops name/description ("properties do not exist" comment) | `ui_styles.gd` ~348 | Rework: set the REAL properties (verified present), keep signature |
| `create_accessible_button` / `create_nbutton` / `nname`/`ndescription` mangled params (bad find/replace of a-prefixed names) | `ui_styles.gd`, `ui_panel.gd` | Rework: restore sane names, wire real properties; keep callers compiling |
| `accessible_string` / `accessible_description` keys in login.tscn + main_menu.tscn (2 scenes; property does not exist on Button in 4.7.2 -- engine uses `accessibility_name`) | `login.tscn`, `main_menu.tscn` | Remove keys; re-express as real `accessibility_name` in sec 7.1 |
| F13 concept (browser key 124 -> KEY_F13 in the web bridge) with nothing consuming F13 in the game | `web_input_bridge.gd:241` mapping is dead code today | Keep the key mapping (harmless, forward-compatible); the debug overlay concept it was meant to open becomes A11yService.dump() on a NEW, agent-only JS hook, not a human hotkey |
| Tab-cycle focus helpers duplicated per menu (`_cycle_focus` in main_menu.gd, login.gd, lobby.gd) | 3 menu scripts | Rework into A11yService.focus_next/prev (one implementation; menus keep their TAB handler calling the service) |
| DebugOverlay hover/deepest-control walker (`_get_hovered_control`/`_find_deepest`, F11 panel) | `debug_overlay.gd` | Keep for humans (F11 hover inspector is genuinely useful); its tree-walk logic seeds A11yService.snapshot()'s walker. No removal. |
| One-off `[CS]` geometry dumps (reverted before commit) | (not in tree) | Dead -- superseded by A11yService.dump() |
| InputManager self-detecting `Mode=2 Mobile=true` on web (from the R33 log) | `input_manager.gd` | Not a11y per se; flagged so sec 7.4 reviews touch focus order on mobile |

## 9. Non-goals

- No custom screen reader protocol. AccessKit IS the protocol.
- No agent backdoor that bypasses the input pipeline (anticheat
  fairness: agents click like humans).
- No per-frame tree scanning; snapshots are on-demand.
- No new id namespace beyond node path + accessibility_name.

## 10. Success criteria

1. An agent (or the R33 probe) can boot -> guest -> create character ->
   enter world -> pause using ONLY A11yService snapshot data, zero
   hardcoded coordinates, zero per-scene debug prints.
2. A keyboard-only human can do the same (TAB order reaches every
   actionable; Enter activates; focus visible).
3. Godot editor + NVDA on desktop reads every menu control's name and
   description (sec 7.4 smoke).
4. `git grep "guessing"` returns no probe code: no coordinate tables,
   no stage-screenshot diffs, no one-off dumps anywhere.
