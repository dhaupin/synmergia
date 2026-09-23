## LootTableResolver - Resolve LootTable resources from bare table ids.
##
## loot_table_id values in enemy data are bare ids ("loot_slime_basic"),
## the same convention Enemy._roll_and_drop_loot uses. Resolution order:
##   1. res://data/loot_tables/<id>.tres   (the convention)
##   2. the id itself as a res:// path     (tolerate direct-path authoring)
##   3. DataService.get_loot_table(id)     (runtime-registered tables)
## Static, preload-only utility: no autoload, no class_name. Returning
## null for an unresolvable id is the correct graceful answer -- callers
## log and fall back to base gold.
extends RefCounted

const LOOT_DIR := "res://data/loot_tables"


static func load_table(table_id: String) -> Resource:
	var id := table_id.strip_edges()
	if id.is_empty():
		return null

	# 1. Convention path from the bare id.
	var path := "%s/%s.tres" % [LOOT_DIR, id]
	if ResourceLoader.exists(path):
		return _load_table_at(path)

	# 2. Direct res:// path authoring.
	if id.begins_with("res://") and ResourceLoader.exists(id):
		return _load_table_at(id)

	# 3. DataService may hold the table under its resource id.
	var ds := _data_service()
	if ds != null and ds.has_method("get_loot_table"):
		var t = ds.get_loot_table(id)
		if t != null and t.has_method("roll_drop"):
			return t
	return null


static func _load_table_at(path: String) -> Resource:
	var res := ResourceLoader.load(path)
	if res == null:
		return null
	# Only accept resources that actually behave like a LootTable --
	# a schema rename or wrong script_class degrades to null, not a
	# runtime crash in the death flow.
	if res.has_method("roll_drop"):
		return res
	return null


## Runtime lookup (parse-time autoload edge in --script mode: resolve
## through the tree, never the bare identifier).
static func _data_service() -> Node:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null(NodePath("DataService"))
