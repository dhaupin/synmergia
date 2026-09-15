# QC Gap Analysis: Missing Autoloads & Undeclared Identifiers

Generated from parse errors (`godot --check-only`) and smoke test failures.

---

## MISSING AUTOLOADS (Smoke Test Failures)

| # | Missing Autoload | Test File | Root Cause | Fix Strategy |
|---|------------------|-----------|------------|--------------|
| 1 | `AutoResponseService` | `test_auto_response_signals.gd:19-23` | Service exists at `core/services/auto_response_service.gd` but not registered in `project.godot` `[autoload]` section | Add `AutoResponseService="*res://core/services/auto_response_service.gd"` to `[autoload]` |
| 2 | `ChatService` | `test_notif_migration_chat.gd:27-37` | Service exists at `core/services/chat_service.gd` but not registered in `project.godot` `[autoload]` section | Add `ChatService="*res://core/services/chat_service.gd"` to `[autoload]` |
| 3 | `QuestService` | `test_notif_migration_quest.gd:28-38` | Service exists at `core/services/quest_service.gd` but not registered in `project.godot` `[autoload]` section | **ALREADY PRESENT** at line 94 of project.godot — test failure may be load-order related (ensure before NotificationService consumers) |

---

## UNDECLARED IDENTIFIERS (Parse Errors)

| # | Error | File:Line | Root Cause | Fix Strategy |
|---|-------|-----------|------------|--------------|
| 1 | `res://ui/admin/admin_dashboard.gd` — cannot preload/resolve | `menu_manager.gd:231` | File exists but may have parse errors preventing load; or path mismatch | Verify `admin_dashboard.gd` parses cleanly; check for UTF-8 chars (emoji in comments) |
| 2 | `NotifKind.WARNING` — enum value doesn't exist | `menu_manager.gd:610` | `notification_kind.gd` enum has `SECURITY_WARNING` not `WARNING` | Replace `NotifKind.WARNING` → `NotifKind.SECURITY_WARNING` |
| 3 | `QoSService` — not declared | `menu_manager.gd:638` | `QoSService` IS an autoload (line 40 project.godot) but accessed as bare identifier in static context; static functions can't see autoloads directly | Use `root.get_node_or_null("QoSService")` in static context, or move check to instance method |
| 4 | `_kv_ignored` — not declared | `chat_service.gd:773-774` | Constant `_kv_ignored` referenced but not defined (only `_kv_player_settings` exists) | Define `const _kv_ignored := "chat:ignored:"` or remove dead code in `_load_chat_state()` |
| 5 | `accessible_name` / `accessible_description` — Control properties | `shop_ui.gd:108-111` | `accessible_name`/`accessible_description` added in Godot 4.4; project uses 4.7.2 so should work — but `ShopUI` extends `UIPanel` which may not expose them | Ensure `UIPanel` inherits `Control`; properties are on `Control` not `PanelContainer` — move to `_ready()` after `super._ready()` |
| 6 | `actions` / `npc_data` — not declared | `action_menu.gd:7,108` | Local variable `actions` shadows nothing; `npc_data` parameter exists but `_filter_npc_actions` uses undefined `actions` | `_filter_npc_actions` signature expects `(actions, npc_data)` but called with only `npc_data` — fix call site or signature |
| 7 | `_filter_npc_actions()` — not in base | `action_menu.gd:139` | Method defined but call passes wrong args (see #6) | Fix call: `_filter_npc_actions(actions, _npc_data)` |
| 8 | `has_key()` — Dictionary method removed in Godot 4.7.2 | `chat_service.gd` ×7, `action_menu.gd`, `auto_response_service.gd`, `waypoint_service.gd` | Godot 4 removed `Dictionary.has_key()`; use `dict.has(key)` or `key in dict` | Replace all `.has_key(x)` → `.has(x)` |
| 9 | `has_method()` called on class directly | `test_base.gd:5` | `has_method()` is an instance method, not static; test calls `SomeClass.has_method("foo")` | Instantiate first: `SomeClass.new().has_method("foo")` or use `has_method` on instance |
| 10 | `UIStyles` already in parent | `action_menu.gd:176` | `ActionMenu` extends `UIPanel` which already preloads `UIStyles`; duplicate `const UIStyles` causes shadow warning | Remove `const UIStyles = preload(...)` from `ActionMenu` |
| 11 | `Performance.TIME_SCRIPT` — nonexistent | `menu_manager.gd:789` | Godot `Performance` singleton has `TIME_PROCESS`, `TIME_PHYSICS_PROCESS`, `TIME_FPS` — no `TIME_SCRIPT` | Replace `Performance.TIME_SCRIPT` → `Performance.TIME_PROCESS` |
| 12 | `Void function returning a value` | `action_menu.gd:176` | `_filter_npc_actions` declared `func _filter_npc_actions(...) -> void:` but returns `filtered` array | Change return type to `Array` or remove return |
| 13 | `Array assigned to Dictionary` | `quest_service.gd:83,121` | Variable annotated `Dictionary` but assigned array literal `[]` | Fix type annotation: `var available: Array = []` |
| 14 | `player_id type cannot be inferred` | `quest_service.gd:454` | Lambda parameter type inference fails in `filter(func(t): ...)` | Add explicit type: `filter(func(t: int): ...)` |
| 15 | `space used for indentation` (mixed tabs/spaces) | `waypoint_service.gd:174` | Line 174 uses spaces (`    _player_waypoints...`) while file uses tabs | Convert line 174-179 to tabs (run `cat -A` to verify) |
| 16 | `unexpected if in class body` | `npc_entity.gd` | `if` statement at class level (outside function) — likely stray code or missing `func` | Move logic into a method or `_ready()` |
| 17 | `Resource.has()` / `.get(key)` — removed in Godot 4.7.2 | `data_service.gd:117` (14 resource types), `login_service.gd:230` | `Resource.has()` removed; use `resource.get("key", null)` + null-check or `resource.get("key") != null` | Replace `resource.has("id")` → `resource.get("id") != null` |
| 18 | `DictStore.has()` — method doesn't exist | `login_service.gd:230,248` | `DictStore` has `has_key()` not `has()` | Replace `store.has(key)` → `store.has_key(key)` |
| 19 | `CacheWrapper.smembers()` — method not exposed | `server_manager.gd` (implied) | `CacheWrapper` only exposes basic KV ops; `smembers` exists on `MemoryCacheStore`/`CacheStore` but not wrapped | Add `func smembers(key) -> Array` to `CacheWrapper` delegating to `_store.smembers(key)` |
| 20 | `Nil assigned to Dictionary` | `server_manager.gd:348` | Variable typed `Dictionary` assigned `null` from `store.get()` which returns `Variant` | Add null-coalesce: `var data: Dictionary = store.get(...) as Dictionary ?? {}` |

---

## DETAILED ROOT CAUSE NOTES

### Autoload Registration Order
- `AutoResponseService`, `ChatService` must be added to `[autoload]` in `project.godot`
- Load order matters: services that emit signals in `_ready()` must come **after** their consumers
- Current order has `NotificationService` (line 60) before `AutoResponseService` (missing) and `ChatService` (missing) — add them before `NotificationService` or after but ensure signal connections use `call_deferred()`

### Dictionary.has_key() Migration
**Files affected (grep `.has_key`):**
- `chat_service.gd`: lines 477, 480, 494, 601, 620, 636, 639, 646, 651
- `action_menu.gd`: line 116 (for `actions` array — different issue)
- `auto_response_service.gd`: lines 64, 68, 89
- `waypoint_service.gd`: lines 160, 172, 222, 277, 285, 313, 345, 349, 426, 430, 488, 553
- `server_manager.gd`: none directly
- `login_service.gd`: lines 230, 248 (DictStore, not Dictionary)

**Pattern:** `.has_key(key)` → `.has(key)` for Dictionary; `store.has(key)` → `store.has_key(key)` for DictStore

### Resource.has() Migration
**File: `data_service.gd:117`** — 14 resource type checks all use `resource.has("id")`
```gdscript
# Current (broken):
if resource and resource.has("id"):

# Fix:
if resource and resource.get("id", null):
```

### CacheWrapper Missing Methods
`CacheWrapper` (cache wrapper for services) only exposes:
- `get_value`, `set_value`, `set_nx`, `remove`, `exists`, `expire`, `incr`, `incr_by`, `incr_with_ttl`

Missing from `CacheStore` interface: `hset`, `hget`, `hget_all`, `hdel`, `sadd`, `srem`, `smembers`, `sismember`, `lpush`, `rpush`, `lpop`, `lrange`, `llen`

**Fix:** Add delegating methods to `CacheWrapper` for each missing operation.

### MenuManager Static Context Issue
`MenuManager._on_main_menu_panel_requested()` (static) accesses `QoSService` bare at line 638. Static methods cannot access autoloads directly.

**Fix:** Move permission check to instance method or resolve via `get_tree().root.get_node_or_null("QoSService")`.

### ShopUI Accessibility Properties
`accessible_name`/`accessible_description` are `Control` properties. `ShopUI` extends `UIPanel` which extends `PanelContainer` → `Control`. The issue is setting them in `_setup_accessibility()` called from `_ready()` before the node is in tree — move to `_on_open()` or ensure `super._ready()` runs first.

### NPC Entity "unexpected if in class body"
Need to view full `npc_entity.gd` to locate the stray `if`. Likely a copy-paste artifact.

---

## RECOMMENDED FIX ORDER

1. **Add missing autoloads** to `project.godot` (AutoResponseService, ChatService)
2. **Fix parse blockers** (Resource.has, DictStore.has, has_key, mixed indentation)
3. **Fix enum/constant mismatches** (NotifKind.WARNING, Performance.TIME_SCRIPT)
4. **Fix method signatures/returns** (_filter_npc_actions, Array vs Dictionary)
5. **Add CacheWrapper missing methods** (smembers, hash/set/list ops)
6. **Fix static context autoload access** (MenuManager QoSService)
7. **Clean up duplicate preloads** (UIStyles in ActionMenu)
8. **Verify test load order** (QuestService already in autoloads)