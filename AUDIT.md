# Synmergia MMORPG Engine — Session Audit

**Date:** 2026-08-29 (UI systems session)
**Engine:** Godot 4.7.2
**Language:** GDScript
**Architecture:** Authoritative Server

---

## Executive Summary

This audit is **session-scoped** — it tracks the work being done in the current
session on UI systems & components. The previous Godot 4.7 upgrade / parse-error
audit is closed; this file now drives the new UI work.

**Current focus:** UI systems & components are partially built but largely
unwired. Several foundational pieces (`UIPanel`, `UIStyles`, `InteractionLayer`,
event-bus signals for health/buffs/inventory) are in place but only loosely
connected. This session turns them into a coherent system.

**Working principles:**
- `UIPanel` is the source of truth for any panel UI — all social, admin,
  community, inventory, and report panels adopt it.
- `UIStyles` is the source of truth for colors, fonts, panel/button styles.
  No hardcoded `Color(0.x, ...)` or `StyleBoxFlat.new()` in UI files outside
  `UIStyles` itself.
- `UIManager` (autoload) owns the UI scene tree lifecycle: HUD chrome,
  tooltips, panels, buff bar, inventory UI.
- `InteractionLayer` (autoload) is the single point for input semantics
  (tap, long-press, drag, double-tap, swipe, hover, action). Panels and HUD
  consume its signals, they don't re-implement input handling.
- Component → UI data flow uses the event-hub signals (`health_changed`,
  `buff_added/removed/refreshed`, `xp_gained`, `level_up`, `item_*`).

---

## Phase A — UIPanel adoption ⬜ TODO

`UIPanel` is brand new and currently unused. Every panel that rebuilds its own
overlay + close logic should be migrated onto it.

**Targets (currently `extends Control`):**
- `ui/components/inventory_ui.gd`
- `ui/social/trade_ui.gd`
- `ui/social/guild_ui.gd`
- `ui/social/party_ui.gd`
- `ui/social/friends_list.gd`
- `ui/social/character_transfer_ui.gd`
- `ui/community/voting_ui.gd`
- `ui/admin/admin_dashboard.gd`
- `ui/player/report_dialog.gd`

**For each:**
- Change `extends Control` → `extends UIPanel`.
- Drop the local overlay/header/close logic; use `UIPanel._setup_overlay()` and
  the `_setup_panel / _setup_header / _setup_content / _on_open / _on_close`
  hooks.
- Replace hand-rolled `StyleBoxFlat.new()` with `UIStyles.create_panel_style()`.
- Replace hardcoded `Color(0.x, ...)` with `UIStyles.COLORS.*`.
- Preserve existing public API and signals so callers keep working.

**Out of scope (do not migrate):**
- `ui/menus/main_menu.gd` — scene-based, not a popup panel.
- `ui/targeting/target_tooltip.gd` — already self-contained, not a centered panel.
- `ui/components/menu_manager.gd` — HUD chrome, not a popup.
- `ui/components/action_menu.gd` — context menu, different lifecycle.

**Validation:**
- `godot --headless --quit` still loads with zero parse errors.
- Each migrated panel opens/closes via the same `UIPanel.open(player_id) / close()`
  API as the base.

---

## Phase B — UIManager as single UI owner ⬜ TODO

Currently `UIManager` only creates `TargetTooltip`. It should own the full UI
scene tree for in-game state.

**Decision:** `MenuManager` lives as a child of `UIManager` (not its own
autoload). One lifecycle owner; HUD lives and dies with the UI manager.

**UIManager becomes the owner of:**
- `MenuManager` (HUD chrome — action bar, quick slots, status bars, buff bar slot)
- `TargetTooltip` (already)
- `BuffBar` (newly promoted to a top-level child)
- `InventoryUI`, `TradeUI`, `GuildUI`, `PartyUI`, `FriendsList`,
  `CharacterTransferUI`, `VotingUI`, `AdminDashboard`, `ReportDialog`

**Public API on `UIManager`:**
- `open_panel(name: String, player_id: String)` — instantiates if needed,
  delegates to `MenuManager` for stack tracking.
- `close_panel(name: String)`
- `toggle_panel(name: String, player_id: String)`
- `close_all_panels()`
- `show_hud() / hide_hud()`
- `update_hp / update_mp / update_xp` — pass-through to `MenuManager`.

**Hookups:**
- `GameManager.game_started` → instantiate owned UI nodes.
- `GameManager.game_ended` → `queue_free()` everything except persistent autoload
  shell.
- `GameManager.game_state_changed` → show/hide HUD based on `PLAYING` vs
  `MAIN_MENU` / `CHARACTER_SELECT`.

**Validation:**
- One call (`UIManager.open_panel("inventory", local_player_id)`) opens inventory.
- Scene tree on game end has no leaked UI nodes.
- No duplicate `MenuManager` (the static-instance guard already prevents it).

---

## Phase C — Component → UI data flow ⬜ TODO

The event-hub signals exist but currently have no UI consumers. This phase
makes the UI reactive to game state.

**Event-bus status check (first task in this phase):**
- `EntityEvents`, `CombatEvents`, `InventoryEvents`, `SystemEvents` are
  defined under `core/events/` but **none are autoloaded**.
- Confirm wiring path: who emits the signal today, who should consume it in the
  UI. Likely path: services emit → UI subscribes via `EntityEvents.<signal>`.
- Decision needed: autoload them directly, or have `EventHub` forward/re-export.

**Wiring targets:**
| UI component | Source event(s) | Action |
|---|---|---|
| `MenuManager.update_hp` | `health_changed(entity_id, current, max, delta)` (filter to local player) | Update HP bar |
| `MenuManager.update_xp` | `xp_gained` (filter to local) | Update XP bar |
| `MenuManager.level_up_bump` | `level_up` | Flash/notification |
| `BuffBar.add_buff` | `buff_added` / `buff_applied` | Create icon |
| `BuffBar.update_buff` | `buff_refreshed` | Refresh remaining-time |
| `BuffBar.remove_buff` | `buff_removed` / `buff_expired` | Remove icon |
| `InventoryUI.refresh_slot` | `item_picked_up` / `item_moved` / `item_equipped` / `item_unequipped` | Update slot |
| `InventoryUI.update_gold` | `gold_gained` / `gold_spent` | Update gold label |
| `TradeUI` refresh | `trade_requested` / `trade_completed` | Open/close trade |
| `FriendsList` refresh | `FriendsService` signals (if any) / polling | Refresh list |

**Stubs to clear along the way:**
- `trade_ui.gd:147` "TODO: Get actual items from TradeService or InventoryService"
- `trade_ui.gd:153` "not implemented" select-item flow
- `trade_ui.gd:187` "TODO: Notify target via network"
- `buff_bar.gd:64` "placeholder colored rect" → real icon loading
- `inventory_ui.gd:201` "Set icon (placeholder for now)" → real icon loading
- `ui_styles.gd:102` `close_btn.pressed.connect(func(): pass)` placeholder

**Validation:**
- Stub a fake local player, emit `health_changed` from a debug scene, watch HP
  bar move.
- Add/remove a buff via console, watch `BuffBar` show/hide icon.

---

## Phase D — Touch / HUD / InteractionLayer polish ⬜ TODO

The HUD (`MenuManager`) is not instantiated; the touch story is partial.

**`MenuManager` (HUD) build-out:**
- Register it under `UIManager` (per Phase B).
- Implement real progress-bar drawing using `UIStyles` colors.
- Action bar slots bind to InteractionLayer `action_triggered("skill_1" ..
  "skill_8")` for keyboard/mouse and gamepad face buttons.
- Quick-access slots bind to `action_triggered("quick_1" .. "quick_4")`.
- Buff bar mounts into the HUD chrome (not a sibling popup).

**Touch / input unification via `InteractionLayer`:**
- `UIPanel._on_overlay_click` accepts `InputEventScreenTouch` in addition to
  `InputEventMouseButton`.
- `TargetTooltip` already uses `InteractionLayer.tap` — leave it.
- Global ESC handling moves into `MenuManager._input` and walks
  `_open_panels` from top to bottom.
- Drag-to-close on `TargetTooltip` (already exists) — make it consistent across
  any draggable popovers added later.

**No new input handling in individual panels.** If a panel needs to react to
input, it connects to an `InteractionLayer` signal — never `_input` directly.

**Validation:**
- Action bar slot lights up on corresponding gamepad / keyboard press.
- ESC closes the topmost open panel.
- Touch outside any panel closes it.

---

## Phase E (stretch) — Theme tokens ⬜ TODO

ROADMAP TODO "Add UI theme customization" (Player Shell Customization section).

- Move `UIStyles.COLORS` dictionary into a `Theme` resource (`.tres`) with
  fields for bg, border, text, accent, status colors.
- `UIStyles.COLORS` becomes a fallback default; load order:
  1. Player-saved theme preference (TODO beyond this session)
  2. Theme resource
  3. Hardcoded defaults in `UIStyles`
- Drop-in: existing `UIStyles.COLORS.xxx` reads still work, but they pull from
  the active theme resource when one is set.

**Stretch only** — not blocking. Cut from scope if time runs out.

---

## Decisions log

- **MenuManager location:** child of `UIManager` (not its own autoload).
  Rationale: single lifecycle owner; UI chrome shouldn't outlive `UIManager`.
- **Input handling:** all panels/HUD consume `InteractionLayer` signals.
  `_input` is only acceptable in `InteractionLayer` itself and in
  `MenuManager` for top-level keybinding routing.
- **Event bus:** use the `core/events/*.gd` signal files. Phase C first task is
  to confirm autoload path (direct autoload vs `EventHub` re-export).
- **2026-08-29 (Phase A):** UIPanel can't be a real `Control` base until the
  child calls `super._ready()` (or the autoload is registered). The first
  parse-only check failed because `UIPanel._ready` referenced the
  `GameLog` autoload. **Decision:** `UIPanel` uses `print()` for its
  internal "panel opened/closed" log so it parses standalone. External
  logging stays in services/components.
- **2026-08-29 (Phase A):** panels with a custom `open(player_id, ...)`
  signature (ReportDialog) or a different name (TradeUI.open_trade,
  VotingUI.open with voter id) override `UIPanel.open` and call
  `super.open(player_id)` after capturing extra state. TradeUI wraps its
  HBox content in a VBox to accommodate `_setup_header`.
- **2026-08-29 (Phase A):** the `closed` signal that every panel emitted
  on hide is kept as a local alias of `panel_closed` (forwarded in
  `_ready`) so existing callers keep working. Phase B can rename.
- **2026-08-29 (Phase A):** `buff_bar.gd` and `admin_toolbar.gd` are HUD
  widgets (HBoxContainer / top-right anchored toggle), not centered
  popup panels. **Decision:** leave them on `extends Control` / original
  base. Phase D will introduce a `UIWidget` base for HUD chrome.
- **2026-08-29 (Phase A):** `admin_dashboard.gd` is a 478-line monolith
  with a pre-existing parse error at line 324 (unclosed paren) and a
  tightly coupled `_ready` (creates `AdminShell`, all 5 tabs, refresh
  timer in one method). **Decision:** defer the full UIPanel migration —
  it needs its own dedicated session. Document in follow-up list.
- **2026-08-29 (Phase A):** `--headless --import` populates the class
  cache, which resolves the bulk of the 135 baseline errors
  (`Could not find type X` cascade). After import, the steady-state
  baseline is 78 unique errors — all in `core/` (pre-existing), zero in
  any UI file I've touched.

---

## Pre-flight finding (2026-08-29)

**Baseline reality:** the project loads at runtime — the main menu prints
`Main menu loaded` — but `godot --headless --quit` (and `--check-only` on
individual files) emits a long list of `SCRIPT ERROR` lines. These come in
two flavors:

1. **Autoload-resolution errors** — services reference each other through
   global autoload names (`EntityService`, `GameLog`, `TargetingManager`,
   `TargetTooltip`…) and the parse pass in headless mode can't resolve them
   in isolation. Non-fatal at runtime because autoloads register globally
   before scripts execute.
2. **Real parse errors** — `Cannot infer the type of "result" variable`,
   `Identifier "vbox" not declared`, `Function "_log_action()" not found in
   base self`, etc. Some are pre-existing bugs; some appear because the
   headless check fails after an upstream autoload fails.

**Validation gate for this session (revised):**

- **Per-file parse correctness:** `godot --headless --check-only
  --script res://<file>` on each file I touch. This catches MY errors and
  surfaces the file's own pre-existing ones. Autoload-resolution errors
  are expected and ignored.
- **Runtime smoke test:** the project's actual `godot --headless
  --path synmergia` run still prints `Main menu loaded`. That's the
  success line. Total SCRIPT ERROR count should not increase after my
  changes; ideally it decreases.
- **Baseline numbers (2026-08-29, before this session's edits):**
  - Runtime SCRIPT ERROR / Parse Error / Failed-to-load lines: **135 unique**
  - Main menu load: ✅
- **Target after Phase A:** no increase in error count, ideally a small
  decrease from fixing the `:=` inference bugs we replace with explicit
  types.

---

## Status

| Phase | Status |
|---|---|
| A — UIPanel adoption | 🟡 In progress (8/9 done — admin_dashboard deferred) |
| B — UIManager owns UI | ⬜ TODO |
| C — Component → UI wiring | ⬜ TODO |
| D — Touch / HUD / InteractionLayer | ⬜ TODO |
| E — Theme tokens (stretch) | ⬜ TODO |

**Phase A progress (2026-08-29):**
- `UIPanel` fixed to parse standalone (GameLog → print).
- Migrated: `inventory_ui.gd`, `friends_list.gd`, `party_ui.gd`,
  `guild_ui.gd`, `trade_ui.gd`, `character_transfer_ui.gd`, `voting_ui.gd`,
  `report_dialog.gd`. All extend `UIPanel`, use `UIStyles.create_panel_style`
  + `UIStyles.COLORS.*`, forward `closed` → `panel_closed`, and have
  explicit typed returns in place of `:=` inferences.
- Deferred: `admin_dashboard.gd` (478 lines, pre-existing parse error at
  line 324, needs dedicated session). `buff_bar.gd` and `admin_toolbar.gd`
  intentionally skipped — they're HUD widgets, not popups.
- **Runtime smoke test:** main menu still loads, error count unchanged
  (78 unique / 126 total — all in `core/`, none in any migrated UI file).

Updated as the session progresses.