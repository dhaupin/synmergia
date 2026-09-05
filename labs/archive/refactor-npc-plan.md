# NPC System Refactor — Plan

> Status: PLANNED
> Branch: `labs/captures`
> Date: 2026-09-04

## Goal

Refactor all NPC entity classes from hardcoded behavior to a data-driven,
schema+data architecture. The frame (`/labs/`) stays clean of game-specific
concepts. The game layer defines NPC behavior through `.tres` data files.

**Design principles:**
- Untyped Dictionary for includes (string-based type system; `.tres` files provide
  editor-side structure validation)
- One unified entity class (`NPCEntity`) that reads includes
- No per-NPC-type entity classes (no `BlacksmithNPC`, `BankNPC`, etc.)
- `NPCData` is the single source of NPC identity; includes compose behavior

---

## Architecture

### Current State

| Layer | Status |
|---|---|
| `core/schemas/npc_data.gd` | Exists, has `npc_type` enum, `sell_categories`, pricing |
| `data/npcs/*.tres` | Exist (6 files) but `load_npcs()` never called |
| `core/entities/blacksmith_npc.gd` | Hardcoded, ignores NPCData |
| `core/entities/skill_academy_npc.gd` | Hardcoded, ignores NPCData |
| `entities/npcs/bank_npc.gd` | `@export` vars, not NPCData |
| `core/services/data_service.gd` | `load_npcs()` defined but never called |
| `data/npc_offerings/` | Does not exist |
| `core/schemas/npc_offering.gd` | Does not exist |
| `core/services/vendor_service.gd` | Does not exist |
| `ui/components/shop_ui.gd` | Does not exist |
| `core/entities/npc_entity.gd` | Does not exist |

### Target State

```
NPCEntity (entity class)
  ├── npc_data_id (exported, set by SpawnService)
  └── reads NPCData
        └── includes: Array[Dictionary]
              └── [{type: "offering", ref_id: "..."}]

data/npc_offerings/<id>.tres   ← vendor, service, quest_giver, dialogue
data/npcs/<id>.tres             ← name, greeting, includes[], pricing
```

All NPC behavior is in data files. Zero hardcoded entity classes per NPC type.

---

## Offerings

### Concept

An **offering** is what an NPC provides when the player interacts with them.
It is NOT limited to stores — a blacksmith repair, a bank vault, a quest line,
and a dialogue tree are all offerings.

`data/npc_offerings/` — the data folder for all offering definitions.

### Offering Types

| type string | Description | Example |
|---|---|---|
| `"vendor"` | Buy/sell items for gold | General store, armory, potions |
| `"service"` | One-shot service (repair, respec) | Blacksmith repair, skill respec |
| `"quest_giver"` | Quest list | Main story NPC, side quest giver |
| `"dialogue"` | Conversation tree | Flavor NPCs, cutscene triggers |
| `"bank"` | Vault access | Banker NPC |

The `type` string is the discriminator. Each offering `.tres` declares its own type.
New offering types can be added without changing the schema.

### Schema: npc_offering.gd

```gdscript
## npc_offering.gd
extends Resource

@export var id: String = ""
@export var type: String = ""            # "vendor" | "service" | "quest_giver" | "dialogue" | "bank"
@export var display_name: String = ""

# --- vendor type ---
@export var stock_mode: String = "by_category"  # "by_category" | "by_item_id" | "mixed"
@export var sell_categories: Array[int] = []    # Item.ItemCategory values vendor sells
@export var buy_categories: Array[int] = []     # Item.ItemCategory values vendor buys
@export var catalog_items: Array[Dictionary] = [] # [{item_id, qty, price_override}] for MIXED
@export var unlimited_stock: bool = true
@export var stock_qty: int = 99
@export var price_multiplier: float = 1.0
@export var restock_trigger: String = "close"  # "close" | "daily" | "never"
@export var restock_amount: int = -1           # -1 = full restock

# --- service type ---
@export var service_id: String = ""   # maps to BlacksmithService, SkillAcademyService, etc.
@export var service_params: Dictionary = {}

# --- quest_giver type ---
@export var quest_ids: Array[String] = []   # list of quest IDs this NPC offers

# --- dialogue type ---
@export var dialogue_id: String = ""          # maps to data/dialogues/<id>.tres
```

---

## NPCEntity

### core/entities/npc_entity.gd

Single entity class for all NPCs. Reads `npc_data_id` from SpawnService,
loads `NPCData` from DataService, resolves includes, routes `interact()`.

```gdscript
## npc_entity.gd
extends Entity
class_name NPCEntity

@export var npc_data_id: String = ""

var _npc_data: NPCData = null
var _offerings: Array[Dictionary] = []   # resolved from NPCData.includes

var _proximity_enabled: bool = false
var _npc_position: Vector3 = Vector3.ZERO

# DataService is an autoload
const DataService = preload("res://core/services/data_service.gd")

func _ready() -> void:
    _load_npc_data()
    _resolve_offerings()

func _load_npc_data() -> void:
    if npc_data_id.is_empty():
        return
    if DataService == null:
        return
    _npc_data = DataService.get_npc(npc_data_id)

func _resolve_offerings() -> void:
    if not _npc_data:
        return
    for inc: Dictionary in _npc_data.includes:
        var inc_type: String = inc.get("type", "")
        var inc_id: String = inc.get("ref_id", "")
        if inc_type == "offering":
            var offering: Resource = load("res://data/npc_offerings/" + inc_id + ".tres")
            if offering:
                _offerings.append({
                    "type": offering.type,
                    "data": offering
                })

func interact(player_id: String) -> void:
    if _offerings.is_empty():
        return
    # Route to first offering; future: multi-offering menu
    var offering: Dictionary = _offerings[0]
    match offering.type:
        "vendor":
            ShopUI.open_for_offering(player_id, offering.data, _npc_data)
        "service":
            _route_service(player_id, offering.data)
        "bank":
            BankUI.open_for_npc(player_id)
        "quest_giver":
            QuestUI.open_for_npc(player_id, offering.data.quest_ids)
        "dialogue":
            DialogUI.open_for_npc(player_id, offering.data.dialogue_id)

func set_proximity(pos: Vector3, enabled: bool) -> void:
    _npc_position = pos
    _proximity_enabled = enabled

func _process(delta: float) -> void:
    if not _proximity_enabled:
        return
    if not is_instance_valid(GameManager):
        return
    var player = GameManager.get_local_player()
    if player and _npc_position.distance_to(player.global_position) > 8.0:
        if MenuManager:
            MenuManager.close_menu(_get_panel_for_offering())

func _get_panel_for_offering() -> String:
    if _offerings.is_empty():
        return ""
    return _offerings[0].type  # maps to panel name

# Query method for ActionMenu — does this NPC have a specific offering type?
func has_offering_type(type: String) -> bool:
    for o in _offerings:
        if o.type == type:
            return true
    return false
```

---

## NPCData Update

### core/schemas/npc_data.gd

Add one field to the existing schema (no other changes):

```gdscript
# In npc_data.gd, add:
@export var includes: Array[Dictionary] = []
# Each entry: {type: "offering", ref_id: "general_store"}
```

---

## NPC Data Files

### data/npcs/ — update existing + add new

| File | includes |
|---|---|
| `general_store_town.tres` | `[{type: "offering", ref_id: "general_store"}]` |
| `general_store_capital.tres` | same, different `location_type` |
| `armory_capital.tres` | `[{type: "offering", ref_id: "armory"}]` |
| `armory_town.tres` | same, different `location_type` |
| `potions_village.tres` | `[{type: "offering", ref_id: "potions"}]` |
| `blacksmith_capital.tres` | `[{type: "offering", ref_id: "blacksmith_service"}]` |
| `blacksmith_town.tres` | same |
| `skill_academy_capital.tres` | `[{type: "offering", ref_id: "skill_academy"}]` |
| `bank_capital.tres` | `[{type: "offering", ref_id: "bank_vault"}]` |

### data/npc_offerings/ — new files

| File | type | Notes |
|---|---|---|
| `general_store.tres` | `"vendor"` | BY_CATEGORY: misc, resources, accessories, consumables |
| `armory.tres` | `"vendor"` | BY_CATEGORY: weapons, armors |
| `potions.tres` | `"vendor"` | BY_CATEGORY: consumables |
| `blacksmith_service.tres` | `"service"` | `service_id: "blacksmith"`, repair logic |
| `skill_academy.tres` | `"service"` | `service_id: "skill_academy"` |
| `bank_vault.tres` | `"bank"` | Opens BankUI directly |

---

## VendorService

### core/services/vendor_service.gd

Handles all gold transactions for `"vendor"` offerings.

```gdscript
func buy_item(player_id: String, offering, npc_data, item_id: String, qty: int) -> Dictionary:
    # 1. Resolve item from DataService.get_item(item_id)
    # 2. Calculate price:
    #    base = item.buy_price * qty
    #    * npc_data.sell_multiplier
    #    * offering.price_multiplier
    #    * location_type modifier (TOWN=1.0, DUNGEON=2.0, etc.)
    # 3. Check stock (if !unlimited_stock)
    # 4. Deduct gold from player inventory
    # 5. Add item to player inventory
    # 6. Decrement stock if limited
    # Returns {success, message, item}

func sell_item(player_id: String, offering, npc_data, item_id: String, qty: int) -> Dictionary:
    # 1. Find item in player inventory
    # 2. Check offering.buy_categories contains item.item_category
    # 3. Calculate price: item.sell_price * qty * npc_data.buy_multiplier
    # 4. Add gold, remove item from inventory

func get_stock(offering, item_id: String) -> int:
    # Returns current stock for item_id (in-memory or persisted)

func restock_offering(offering) -> void:
    # Called on close or daily reset
```

**Stock persistence:** Initially in-memory (single-server). Multi-server needs
Redis or Postgres. Design deferred — start with in-memory, document the gap.

---

## ShopUI

### ui/components/shop_ui.gd

Panel opened when player interacts with a `"vendor"` NPC.

```
┌─ Shop: Armory (Capital) ──────────────┐
│ [Buy]  [Sell]                         │
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐          │
│ │item│ │item│ │item│ │item│          │
│ └────┘ └────┘ └────┘ └────┘          │
│                          Your Gold: 500│
│                      [Leave Shop]     │
└──────────────────────────────────────┘
```

- **Buy tab:** Grid of catalog items (filtered by offering.sell_categories from DataService).
  Shows icon, name, price (with modifiers applied), quantity selector.
- **Sell tab:** Player inventory filtered by offering.buy_categories.
  Shows items player can sell here.
- **Proximity:** `_process()` auto-closes if player > 8m from NPC (same as BlacksmithUI).

---

## DataService Fixes

### core/services/data_service.gd

```gdscript
# In load_all_data(), add:
func load_all_data() -> void:
    # ... existing ...
    load_npcs()           # ADD: was missing
    load_offerings()      # ADD: new

# Add:
func load_offerings() -> void:
    _offerings = _scan_directory(_data_path + "npc_offerings", "npc_offering")
    GameLog.info("DataService: Loaded %d offerings" % _offerings.size())

var _offerings: Dictionary = {}

func get_offering(id: String) -> Resource:
    return _offerings.get(id)
```

---

## ActionMenu Update

### ui/components/action_menu.gd

Currently switches on `NPCData.NPCType`. After refactor, switch on offering types.

```gdscript
# OLD (line 99):
if npc_data.npc_type == NPCData.NPCType.SKILL_ACADEMY:
    _add_option("Skill Academy", "skill_academy")

# NEW:
if npc_entity.has_offering_type("service"):
    if offering.data.service_id == "skill_academy":
        _add_option("Skill Academy", "skill_academy")
```

The `action_menu.gd` needs to be updated to check `NPCEntity` offering types
instead of `NPCData.npc_type` when building the context menu.

---

## NPC Proximity (Unified)

The current proximity check lives in `BlacksmithUI` and `SkillAcademyUI` panels.
After the refactor, proximity lives on `NPCEntity._process()` — when the player
walks away, the NPC calls `MenuManager.close_menu(panel_id)`.

The `NPCEntity.set_proximity(pos, enabled)` method is called by `PlayerController`
when opening an NPC panel, just like the current pattern.

---

## TypeRegistry Update

### core/autoload/type_registry.gd

Add new preloads:

```gdscript
# After npc_data:
_preload_type("res://core/schemas/npc_offering.gd")
# After entities:
_preload_type("res://core/entities/npc_entity.gd")
```

---

## Implementation Phases

### Phase 1 — Shop + Offering Foundation
1. `core/schemas/npc_offering.gd` — schema
2. `data/npc_offerings/general_store.tres`
3. `data/npc_offerings/armory.tres`
4. `data/npc_offerings/potions.tres`
5. `core/services/vendor_service.gd`
6. `ui/components/shop_ui.gd`
7. `data/npcs/general_store_town.tres` — updated with includes
8. Smoke test

### Phase 2 — NPCEntity + Service Routing
9. `core/entities/npc_entity.gd` — unified entity
10. `core/schemas/npc_data.gd` — add includes field
11. Fix `DataService.load_npcs()` in `load_all_data()`
12. Add `DataService.load_offerings()`
13. `data/npcs/*.tres` — populate includes field for all 6 existing files
14. `core/services/vendor_service.gd` — routing for service types
15. BankUI update to use `bank_vault` offering
16. `TypeRegistry` preloads updated
17. Smoke test

### Phase 3 — Migrate Existing Hardcoded NPCs
18. `data/npc_offerings/blacksmith_service.tres` — type=`"service"`, `service_id: "blacksmith"`
19. `data/npc_offerings/skill_academy.tres` — type=`"service"`, `service_id: "skill_academy"`
20. `data/npc_offerings/bank_vault.tres` — type=`"bank"`
21. Migrate `BlacksmithNPC` → `NPCEntity` with `blacksmith_service` include
22. Migrate `SkillAcademyNPC` → `NPCEntity` with `skill_academy` include
23. Migrate `BankNPC` → `NPCEntity` with `bank_vault` include
24. Update `SpawnService` to use `NPCEntity` for all NPC spawns
25. Delete `blacksmith_npc.gd`, `skill_academy_npc.gd`, `bank_npc.gd`
26. `ui/components/action_menu.gd` — update to use offering types instead of NPCType
27. Smoke test

### Phase 4 — Quest + Dialogue Offerings
28. `data/npc_offerings/quest_giver_template.tres` — type=`"quest_giver"`, `quest_ids: []`
29. `data/npc_offerings/dialogue_template.tres` — type=`"dialogue"`, `dialogue_id: ""`
30. Update `NPCEntity.interact()` for quest_giver and dialogue types
31. QuestUI integration (open via offering, show quest list)
32. Action menu quest options (available quests, turn-in, tracked quest)
33. Smoke test

---

## Smoke Tests

After each phase, run:
```bash
./tools/godot --headless --path synmergia --script res://tests/test_notification_toast.gd
./tools/godot --headless --path synmergia --script res://tests/test_login_flow.gd
```

After Phase 3:
```bash
./tools/godot --headless --path synmergia --script res://tests/test_hud_integration.gd
./tools/godot --headless --path synmergia --script res://tests/test_auto_response_signals.gd
```

---

## Deferred / Out of Scope

- **Stock persistence** (Redis/Postgres) — design deferred, in-memory for Phase 1
- **Multi-offering NPCs** (shop + quest at same NPC) — Phase 4 covers the data
  model; UI for multi-offering selector deferred
- **NPC spawn templates** (`SpawnService` waypoint definitions) — update to reference
  `NPCEntity` instead of hardcoded classes (Phase 3)
- **LootTable changes** — already data-driven, no changes needed
- **ItemDatabase** — DataService already handles this; no separate service needed

---

## Session Log

- 2026-09-04: Plan written. Agreed on: `data/npc_offerings/` naming,
  untyped Dictionary for includes, refactor existing NPCs, stock management
  for limited-stock vendors (deferred), quest UI separate from shop panel.
