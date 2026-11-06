## ContentPackData - Declares a named, per-shard content bundle.
##
## A content pack groups content ids (enemies, quests) under ONE name so a
## shard can enable or disable the whole bundle through the shard-mesh
## lever (labs/prd-shard-mesh.md sec.3.2). The gate is a LOCAL READ of the
## shard's `disabled_content_packs` ShardParameter -- never a shared write.
##
## data/content_packs/*.tres files declare the bundles; filename == id
## (the `pack_` prefix), matching the repo's data-id convention.
##
## Absent a disable, every pack is enabled (the uniform default). This is
## the SAME honesty rule the Phase 3.1 tuning lever enforces: a per-shard
## override is a read on one process and never leaks into shared identity.
extends Resource
class_name ContentPackData

## Stable pack id; matches the .tres filename without extension.
@export var id: String = ""

## Human-readable name for the operator surface.
@export var display_name: String = ""

## One-line summary of what the pack adds.
@export var description: String = ""

## Enemy template ids (data/enemies) this pack owns.
@export var enemy_ids: Array[String] = []

## Quest ids (data/quests) this pack owns.
@export var quest_ids: Array[String] = []

## Whether every id above resolves against DataService truth. Used by the
## receipt to refuse a phantom SKU (an id that names no content).
func missing_refs(ds: Node) -> Array[String]:
        var missing: Array[String] = []
        if ds == null:
                return missing
        for eid in enemy_ids:
                if not ds.has_method("get_enemy") or ds.get_enemy(eid) == null:
                        missing.append("enemy:" + eid)
        for qid in quest_ids:
                if not ds.has_method("get_quest") or ds.get_quest(qid) == null:
                        missing.append("quest:" + qid)
        return missing
