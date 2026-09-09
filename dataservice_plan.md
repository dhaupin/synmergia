# DataService Architecture Analysis & Plan

## Current State Summary

### What Exists
- **File**: `game/core/services/data_service.gd` (381 lines)
- **Role**: Canonical source for all static game data (items, enemies, skills, zones, NPCs, dialogues, etc.)
- **Loading**: Recursive directory scan via `_scan_directory()` using Godot's `DirAccess` + `load()`
- **Storage**: 15 separate `Dictionary` caches (`_skills`, `_items`, `_enemies`, `_classes`, `_species`, `_factions`, `_zones`, `_events`, `_dwellings`, `_npcs`, `_status_effects`, `_quests`, `_achievements`, `_gateways`, `_titles`)
- **Item subcategories**: 6 declared (`_weapons`, `_armors`, `_accessories`, `_consumables`, `_resources`, `_misc`) — **never populated**
- **API**: 14 typed `get_*()` methods + 14 `get_all_*()` methods + `reload_all()` / `reload_category()`
- **Special handling**: `_create_skill_book_from_id()` dynamically constructs `SkillBook` items from ID strings (`book_<skill_id>_<tier>`)

### Directory Structure Mismatch
| DataService expects | Actual layout |
|---------------------|---------------|
| `data/items/` | `data/weapons/`, `data/armors/`, `data/consumables/`, `data/resources/`, `data/misc/` |
| `data/skills/` | `data/skills/<class>/` (subdirectories by class) |
| `data/enemies/` | ✅ matches |
| `data/classes/` | ✅ matches |
| `data/npcs/` | `data/npc/` (singular) |
| `data/zones/` | ✅ matches |

**Result**: `load_items()` finds 0 files; `load_npcs()` finds 0 files.

### Usage Patterns (grep results)
- `DataService.get_skill(id)` — UI action bar, ConnectorService
- `DataService.get_item(id)` — VendorService
- `DataService.get_all_skills()` — SkillAcademyService (catalog building)
- `DataService.get_all_items()` — VendorService (shop stock)
- `DataService.get_all_quests()` — QuestService
- `DataService.get_all_npcs()` — SpawnService
- `DataService.get_all_titles()` — TitleService
- `DataService.get_achievement(id)` / `get_all_achievements()` — AchievementService
- `DataService.get_quest(id)` — QuestService

**Callers**: 8 services + 1 UI component. All use the typed `get_*` / `get_all_*` API.

### Schema Definitions
All `.tres` files use `class_name` Resources:
- `Item` (`core/schemas/item.gd`) — 326 lines, enums for category/rarity/slot, stats, durability, consumable effects
- `EnemyData` (`core/schemas/enemy_data.gd`) — 148 lines, level scaling, loot tables, AI flags
- `NPCData` (`core/schemas/npc_data.gd`) — 89 lines, vendor/blacksmith settings, `includes` for offerings
- `ZoneData` (`core/schemas/zone_data.gd`) — 158 lines, PvP modes, bounds, spawn points
- Plus: `Skill`, `CharacterClass`, `Species`, `Faction`, `EventData`, `DwellingData`, `StatusEffectData`, `QuestData`, `AchievementData`, `GatewayData`, `TitleData`

All schemas have `id` field (String) used as dictionary key.

---

## Proposed Architecture

### Design Principles
1. **Keep .tres as primary** — Godot's ResourceLoader caches parsed resources; no re-parsing on repeated `load()`
2. **Canonical typed API** — Single `get<T>(id)` per schema, no scattered paths
3. **DRY/KISS** — One scanning mechanism, configurable per schema
4. **Cache-backing ready** — Abstract `DataSource` interface; file system now, Redis later
5. **Schema versioning** — Cache keys include content hash/version; invalidation on update
6. **Explicit errors** — `Result<T, Error>` or `Option<T>` pattern; no silent nulls

### Architecture Diagram (Text)

```
┌─────────────────────────────────────────────────────────────────┐
│                        DataService (Autoload)                    │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Public API (canonical)                                    │  │
│  │  • get_item(id) → Result<Item>                             │  │
│  │  • get_enemy(id) → Result<EnemyData>                       │  │
│  │  • get_skill(id) → Result<Skill>                           │  │
│  │  • get_npc(id) → Result<NPCData>                           │  │
│  │  • get_zone(id) → Result<ZoneData>                         │  │
│  │  • get_all<T>() → Array<T>                                 │  │
│  │  • query_items(filter: ItemFilter) → Array<Item>           │  │
│  │  • reload_schema(schema_name) → void                       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Schema Registry                                           │  │
│  │  • Map: schema_name → SchemaConfig                         │  │
│  │  • SchemaConfig: { resource_type, data_paths[], id_field,  │  │
│  │     version_field?, cache_key_prefix, loader_hints }       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                   │
│              ┌───────────────┼───────────────┐                   │
│              ▼               ▼               ▼                   │
│  ┌──────────────────┐ ┌──────────────┐ ┌──────────────────┐    │
│  │ FileDataSource   │ │ RedisCache   │ │ CompositeSource  │    │
│  │ (current)        │ │ (future)     │ │ (fallback chain) │    │
│  │ - DirAccess scan │ │ - GET/SET    │ │ - Try primary    │    │
│  │ - load() .tres   │ │ - TTL=long   │ │ - On miss, try   │    │
│  │ - content hash   │ │ - Invalidate │ │   fallback       │    │
│  └──────────────────┘ └──────────────┘ └──────────────────┘    │
│                              │                                   │
│                              ▼                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  In-Memory Caches (per schema)                             │  │
│  │  _cache: Dictionary<String, Resource>  // id → resource    │  │
│  │  _version: String  // content hash or schema version       │  │
│  └───────────────────────────────────────────────────────────┘  │
```

### Schema Registry Configuration (Example)

```gdscript
# In DataService._ready() or static const
const SCHEMA_REGISTRY: Dictionary = {
    "item": {
        "resource_type": "Item",
        "data_paths": ["res://data/weapons", "res://data/armors", 
                       "res://data/consumables", "res://data/resources", "res://data/misc"],
        "id_field": "id",
        "cache_key_prefix": "item:",
        "subcategory_field": "item_category",  # for filtering
    },
    "enemy": {
        "resource_type": "EnemyData",
        "data_paths": ["res://data/enemies"],
        "id_field": "id",
        "cache_key_prefix": "enemy:",
    },
    "skill": {
        "resource_type": "Skill",
        "data_paths": ["res://data/skills"],
        "id_field": "id",
        "cache_key_prefix": "skill:",
        "recursive": true,  # skills/class/subclass/
    },
    "npc": {
        "resource_type": "NPCData",
        "data_paths": ["res://data/npc"],  # singular!
        "id_field": "id",
        "cache_key_prefix": "npc:",
    },
    "zone": {
        "resource_type": "ZoneData",
        "data_paths": ["res://data/zones"],
        "id_field": "id",
        "cache_key_prefix": "zone:",
    },
    # ... quest, achievement, gateway, title, status_effect, etc.
}
```

---

## Method Signatures for New Canonical API

### Core Access Methods
```gdscript
## Get single resource by ID — returns Result for explicit error handling
func get_item(id: String) -> Result[Item]:
    # Checks _item_cache, falls back to data source, caches result

func get_enemy(id: String) -> Result[EnemyData]:
func get_skill(id: String) -> Result[Skill]:
func get_npc(id: String) -> Result[NPCData]:
func get_zone(id: String) -> Result[ZoneData]:
func get_quest(id: String) -> Result[QuestData]:
func get_achievement(id: String) -> Result[AchievementData]:
func get_gateway(id: String) -> Result[GatewayData]:
func get_title(id: String) -> Result[TitleData]:
func get_status_effect(id: String) -> Result[StatusEffectData]:
func get_faction(id: String) -> Result[Faction]:
func get_species(id: String) -> Result[Species]:
func get_character_class(id: String) -> Result[CharacterClass]:
func get_event(id: String) -> Result[EventData]:
func get_dwelling(id: String) -> Result[DwellingData]:

## Generic getter for dynamic schema access
func get(schema_name: String, id: String) -> Result[Resource]:

## Get all resources of a schema
func get_all_items() -> Array[Item]:
func get_all_enemies() -> Array[EnemyData]:
# ... one per schema

func get_all(schema_name: String) -> Array[Resource]:
```

### Query/Filter Methods (for common access patterns)
```gdscript
## Item queries
func query_items(filter: ItemFilter) -> Array[Item]:
    # ItemFilter: { category?: ItemCategory, rarity?: Rarity, 
    #               equip_slot?: EquipSlot, min_level?: int, max_level?: int }

func get_items_by_category(category: Item.ItemCategory) -> Array[Item]:
func get_items_by_slot(slot: Item.EquipSlot) -> Array[Item]:

## Enemy queries
func get_enemies_in_zone(zone_id: String) -> Array[EnemyData]:
func get_enemies_by_type(enemy_type: EnemyData.EnemyType) -> Array[EnemyData]:
func get_enemies_by_level_range(min_level: int, max_level: int) -> Array[EnemyData]:

## NPC queries
func get_npcs_in_zone(zone_id: String) -> Array[NPCData]:
func get_vendors(zone_id: String = "") -> Array[NPCData]:
func get_blacksmiths(zone_id: String = "") -> Array[NPCData]:

## Zone queries
func get_zones_for_level(level: int) -> Array[ZoneData]:
func get_safe_zones() -> Array[ZoneData]:
func get_pvp_zones() -> Array[ZoneData]:
```

### Lifecycle & Management
```gdscript
## Initialize / load all schemas (called in _ready)
func initialize() -> void:

## Reload a specific schema (dev / content update)
func reload_schema(schema_name: String) -> void:

## Reload all
func reload_all() -> void:

## Get cache stats
func get_cache_stats() -> Dictionary:
    # { "item": { count: 42, version: "abc123", memory_kb: 128 }, ... }

## Check if schema is loaded
func is_loaded(schema_name: String) -> bool:

## Get schema version (content hash)
func get_schema_version(schema_name: String) -> String:
```

### Result Type (GDScript pattern)
```gdscript
# Lightweight Result type (can be inner class or separate file)
class_name Result
var is_ok: bool
var value: Variant
var error: String

static func ok(v: Variant) -> Result:
    var r := Result.new()
    r.is_ok = true
    r.value = v
    return r

static func err(msg: String) -> Result:
    var r := Result.new()
    r.is_ok = false
    r.error = msg
    return r

func unwrap() -> Variant:
    assert(is_ok, "Called unwrap() on Err: " + error)
    return value

func unwrap_or(default: Variant) -> Variant:
    return value if is_ok else default

func map(func: Callable) -> Result:
    return Result.ok(func.call(value)) if is_ok else self
```

**Usage in callers**:
```gdscript
var result := DataService.get_item("wep_iron_sword")
if result.is_ok:
    var item: Item = result.value
    # use item
else:
    GameLog.warn("Item not found: " + result.error)
    # handle missing
```

---

## Migration Path

### Phase 1: Fix Directory Mismatch & Populate Subcategories (Immediate)
1. Update `SCHEMA_REGISTRY` with correct `data_paths` for each schema
2. Implement single generic `_load_schema(schema_name)` using registry
3. Populate `_weapons`, `_armors`, etc. from `item_category` enum during load
4. Add `Result` type (inner class in DataService or `core/utils/result.gd`)
5. Change `get_item(id)` to return `Result[Item]` (breaking change — see Phase 2)

### Phase 2: API Migration (Non-breaking → Breaking)
1. **Add new methods** with `Result` return: `get_item_v2(id) → Result[Item]`
2. **Deprecate old methods**: Mark `get_item(id)` with `@deprecated` or keep returning `Item?` but log warning
3. **Update callers** one by one (8 services + 1 UI) to use `Result` API
4. **Remove old methods** after all callers migrated

### Phase 3: DataSource Abstraction (Future-Proofing)
1. Extract `DataSource` interface:
   ```gdscript
   class_name DataSource
   func load_schema(schema_name: String, config: Dictionary) -> Dictionary  # id → Resource
   func get_version(schema_name: String) -> String
   ```
2. Implement `FileDataSource` (wraps current `_scan_directory` logic)
3. Make DataService accept `DataSource` in constructor (or via setter for autoload)
4. **Later**: Implement `RedisDataSource` / `CompositeDataSource` without touching callers

### Phase 4: Schema Versioning & Invalidation
1. Compute content hash per schema on load (hash of all resource IDs + modified times)
2. Store `_schema_versions: Dictionary<String, String>`
3. On `reload_schema()` or startup, compare version; if changed, invalidate cache
4. Redis cache keys: `{prefix}{id}:{version}` — automatic invalidation on version bump

### Phase 5: Query API & Performance
1. Add `query_items(filter)` and common filtered getters
2. Build secondary indexes on load (category → [ids], slot → [ids], zone → [npc_ids])
3. Profile memory; consider `WeakRef` for rarely-accessed schemas if needed

---

## Risks & Open Questions

### Risks
| Risk | Impact | Mitigation |
|------|--------|------------|
| **Breaking API change** (`get_item` → `Result`) | All 9 callers must update | Phase 2 dual-API period; automated codemod possible |
| **Directory mismatch fix changes IDs** | If filename-based fallback used, IDs may shift | Verify all `.tres` have explicit `id` field (they do) |
| **Memory growth** with 200+ resources | ~200 resources × ~2KB = ~400KB, negligible | Monitor; Godot ResourceLoader already caches |
| **Redis cache complexity** | Premature optimization | Defer until multi-shard profiling shows need |
| **Circular dependency** (DataService → schemas → DataService) | Parse errors | Schemas are `class_name` Resources, no DataService refs |

### Open Questions
1. **Result type location**: Inner class in `DataService` vs shared `core/utils/result.gd`? (Shared enables reuse in other services)
2. **Subcategory caches**: Keep `_weapons`, `_armors` etc. as derived views (filtered on load) or remove and use `query_items()` only?
3. **SkillBook dynamic creation**: Keep in `get_item()` or move to `ItemFactory` service? (Currently only place with dynamic logic)
4. **Lazy vs eager loading**: Current = eager (all in `_ready`). Switch to lazy (load on first `get_*`)? Reduces startup time but adds latency on first access.
5. **Editor integration**: Should DataService expose `get_all_*()` for inspector/debug? (Yes — keep for dev tools)
6. **Content hot-reload**: Watch `data/` for changes and auto-reload in editor? (Nice-to-have, not required)

### Decisions Needed
- [ ] Adopt `Result` type project-wide or just in DataService?
- [ ] Lazy-load schemas or keep eager?
- [ ] Keep item subcategory dictionaries or replace with query API?
- [ ] Extract `DataSource` interface now or wait for Redis need?

---

## Next Steps
1. **Immediate**: Fix `data_paths` in registry to match actual directory structure
2. **This sprint**: Implement generic `_load_schema()` + `Result` type + new `get_*()` methods
3. **Next sprint**: Migrate 9 callers to `Result` API
4. **Backlog**: DataSource abstraction, query API, versioning

---

## Appendix: Current vs Proposed Method Mapping

| Current | Proposed | Notes |
|---------|----------|-------|
| `get_item(id)` → `Item?` | `get_item(id)` → `Result[Item]` | Breaking |
| `get_all_items()` → `Dictionary` | `get_all_items()` → `Array[Item]` | Type change |
| `get_enemy(id)` → `EnemyData?` | `get_enemy(id)` → `Result[EnemyData]` | Breaking |
| `get_skill(id)` → `Skill?` | `get_skill(id)` → `Result[Skill]` | Breaking |
| `get_npc(id)` → `NPCData?` | `get_npc(id)` → `Result[NPCData]` | Breaking (was returning null) |
| `get_zone(id)` → `ZoneData?` | `get_zone(id)` → `Result[ZoneData]` | Breaking |
| `get_quest(id)` → `QuestData?` | `get_quest(id)` → `Result[QuestData]` | Breaking |
| `get_achievement(id)` → `AchievementData?` | `get_achievement(id)` → `Result[AchievementData]` | Breaking |
| `get_all_skills()` → `Dictionary` | `get_all_skills()` → `Array[Skill]` | Type change |
| `reload_category("items")` | `reload_schema("item")` | Rename |
| `_create_skill_book_from_id()` | Move to `ItemFactory.create_skill_book()` | Separation of concerns |