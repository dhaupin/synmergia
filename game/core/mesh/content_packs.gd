## ContentPacks - THE PHASE 3.2 PER-SHARD CONTENT-PACK RESOLVER.
##
## A content pack (ContentPackData, data/content_packs/*.tres) bundles
## enemy + quest ids under one name. A shard can DISABLE a bundle through
## the SAME shard-mesh lever as Phase 3.1 tuning: the `disabled_content_packs`
## ShardParameter on the LOCAL shard (a critical param, so a write is
## effective and readable immediately).
##
## This is a LOCAL READ, never a shared write: the mesh's hashed/shared
## identity stays uniform across shards (labs/prd-shard-mesh.md sec.3.2).
## Absent a disable, EVERY pack is enabled -- the uniform default is not
## negotiable, exactly like the tuning lever.
##
## The service is passed in (not resolved as a bare autoload) so script-mode
## receipts need no registered autoload. Static-only: no autoload, no
## instance state, so the gates (QuestService / SpawnService) can call the
## pure predicates on any thread without touching the tree.

extends RefCounted
class_name ContentPacks

const PackScript = preload("res://core/schemas/content_pack_data.gd")

## The ShardParameter that carries the disabled pack ids for a shard
## (comma-separated, matching the definition's string type). LOCAL only.
const DISABLED_PARAM := "disabled_content_packs"

## Path prefix for the pack definitions on disk.
const _PACK_DIR := "res://data/content_packs/"

const ResourceScan = preload("res://core/frame/srv/resource_scan.gd")

## Cache of loaded packs: pack_id -> ContentPackData. Loaded lazily once.
static var _packs: Dictionary = {}
static var _loaded: bool = false

## Load every ContentPackData under data/content_packs/. Export-safe scan
## (the pack stores .tres as .res + .tres.remap). Cached after first call;
## call reload() in a receipt to pick up fresh data.
static func load_packs() -> void:
        _packs = {}
        for p in ResourceScan.list_resources(_PACK_DIR):
                var res: Resource = load(p)
                if res is PackScript:
                        _packs[str(res.id)] = res
        _loaded = true

static func reload() -> void:
        _loaded = false
        load_packs()

static func _ensure_loaded() -> void:
        if not _loaded:
                load_packs()

## All pack ids, sorted.
static func pack_ids() -> Array[String]:
        _ensure_loaded()
        var out: Array[String] = []
        for pid in _packs.keys():
                out.append(str(pid))
        out.sort()
        return out

## The pack with this id, or null.
static func get_pack(pack_id: String) -> Resource:
        _ensure_loaded()
        return _packs.get(pack_id)

## The set of disabled pack ids for a shard, parsed from the
## `disabled_content_packs` ShardParameter (comma-separated string).
## `sp` is the ShardParameters service (null -> nothing disabled).
static func disabled_set(shard_id: String, sp: Node) -> Dictionary:
        var out: Dictionary = {}
        if sp == null or shard_id == "" or not sp.has_method("get_param"):
                return out
        var raw: Variant = sp.get_param(shard_id, DISABLED_PARAM)
        if raw == null:
                return out
        for tok in str(raw).split(","):
                var t := tok.strip_edges()
                if t != "":
                        out[t] = true
        return out

## True when the named pack is disabled on the shard. Unknown pack ids are
## treated as enabled (a typo never silently removes content).
static func is_pack_disabled(pack_id: String, shard_id: String, sp: Node) -> bool:
        if pack_id == "":
                return false
        return disabled_set(shard_id, sp).has(pack_id)

## The pack that OWNS a content id, or "" when no pack claims it. The
## gates use this so an id outside every pack is never disabled.
static func pack_owning_enemy(enemy_id: String) -> String:
        _ensure_loaded()
        for pid in _packs.keys():
                var pack: Resource = _packs[pid]
                if pack != null and enemy_id in pack.enemy_ids:
                        return str(pid)
        return ""

static func pack_owning_quest(quest_id: String) -> String:
        _ensure_loaded()
        for pid in _packs.keys():
                var pack: Resource = _packs[pid]
                if pack != null and quest_id in pack.quest_ids:
                        return str(pid)
        return ""

## THE GATE PREDICATES. True when the content id is ALLOWED on the shard
## (its owning pack, if any, is not disabled). An id owned by no pack, or
## a shard with no disable, is always allowed.
static func enemy_enabled(enemy_id: String, shard_id: String, sp: Node) -> bool:
        var pid := pack_owning_enemy(enemy_id)
        if pid == "":
                return true
        return not is_pack_disabled(pid, shard_id, sp)

static func quest_enabled(quest_id: String, shard_id: String, sp: Node) -> bool:
        var pid := pack_owning_quest(quest_id)
        if pid == "":
                return true
        return not is_pack_disabled(pid, shard_id, sp)

## The running SceneTree, or null in a bare harness.
static func _tree() -> SceneTree:
        var ml: Variant = Engine.get_main_loop()
        if ml is SceneTree:
                return ml
        return null

## Resolve the LOCAL shard id + ShardParameters from the running tree.
## Returns {shard_id, sp}; both empty/null when unavailable (an isolated
## harness), which the predicates treat as "nothing disabled".
static func _local_scope() -> Dictionary:
        var t := _tree()
        if t == null:
                return {"shard_id": "", "sp": null}
        var sm: Node = t.root.get_node_or_null("ShardManager")
        var sp: Node = t.root.get_node_or_null("ShardParameters")
        var sid := ""
        if sm != null and "shard_id" in sm:
                sid = str(sm.shard_id)
        return {"shard_id": sid, "sp": sp}

## Game-gate convenience: is this enemy allowed on the LOCAL shard? The
## spawn gates call this so they carry no shard plumbing of their own.
static func local_enemy_enabled(enemy_id: String) -> bool:
        var scope := _local_scope()
        return enemy_enabled(enemy_id, str(scope["shard_id"]), scope["sp"])

## Game-gate convenience: is this quest allowed on the LOCAL shard?
static func local_quest_enabled(quest_id: String) -> bool:
        var scope := _local_scope()
        return quest_enabled(quest_id, str(scope["shard_id"]), scope["sp"])

## Every pack with its owned ids and disabled state, for the operator board:
## [{id, name, disabled, enemy_count, quest_count}, ...] sorted by id.
static func board(shard_id: String, sp: Node) -> Array:
        _ensure_loaded()
        var disabled := disabled_set(shard_id, sp)
        var out: Array = []
        for pid in pack_ids():
                var pack: Resource = _packs[pid]
                out.append({
                        "id": str(pid),
                        "name": str(pack.display_name) if pack != null else str(pid),
                        "disabled": disabled.has(str(pid)),
                        "enemy_count": pack.enemy_ids.size() if pack != null else 0,
                        "quest_count": pack.quest_ids.size() if pack != null else 0,
                })
        return out

## Write the disabled set for a shard through ShardParameters (the lever).
## The set is written as a sorted comma-separated string. Returns true when
## the write was handed to the service.
static func write_disabled(shard_id: String, ids: Array, sp: Node, actor_id: String = "") -> bool:
        if sp == null or shard_id == "" or not sp.has_method("set_param"):
                return false
        var sorted: Array[String] = []
        for i in ids:
                var t := str(i).strip_edges()
                if t != "" and not sorted.has(t):
                        sorted.append(t)
        sorted.sort()
        sp.set_param(shard_id, DISABLED_PARAM, ",".join(sorted), actor_id)
        return true
