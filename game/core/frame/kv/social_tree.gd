## SocialTree wrapper over T3 -- player relationships (arch §9).
## Frame primitive -- NOT an autoload, NO class_name.
extends RefCounted

const T3Script = preload("res://core/frame/kv/t3.gd")
const SocialSchemaScript = preload("res://core/frame/kv/social_schema.gd")

const REL_FRIEND := "friend"
const REL_GUILD := "guild"
const REL_PARTY := "party"
const REL_RIVAL := "rival"
const REL_MENTOR := "mentor"
const VALID_RELS := [REL_FRIEND, REL_GUILD, REL_PARTY, REL_RIVAL, REL_MENTOR]

var _t3: T3Script
var _schema: SocialSchemaScript


func _init(t3_instance = null) -> void:
	if t3_instance != null and t3_instance is T3Script:
		_t3 = t3_instance
	else:
		_t3 = T3Script.new()
	_schema = SocialSchemaScript.new()


## Insert an edge. rel must be one of VALID_RELS. Returns the edge's content hash.
func insert_edge(edge_path: String, rel: String, other_id: String, meta: Dictionary = {}) -> PackedByteArray:
	var value := {
		"rel": rel,
		"other_id": other_id,
		"meta": meta
	}
	return _t3.insert(edge_path, value, _schema)


## Fetch an edge at path. Empty dict if absent.
func get_edge(edge_path: String) -> Dictionary:
	var result: Variant = _t3.get_at(edge_path)
	if result == null or not result is Dictionary:
		return {}
	return result


## Remove an edge. Returns true if it existed.
func delete_edge(edge_path: String) -> bool:
	return _t3.delete(edge_path)


## All edges under a player's subtree.
func list_edges(player_root: String) -> Array:
	var results: Array = []
	_t3.walk(player_root, func(node_path: String, node_hash: PackedByteArray, value: Variant) -> void:
		if value is Dictionary and value.get("rel", "") in VALID_RELS:
			results.append(node_path)
	)
	return results


## Edges of one relationship type under player_root.
func list_by_rel(player_root: String, rel: String) -> Array:
	var results: Array = []
	_t3.walk(player_root, func(node_path: String, node_hash: PackedByteArray, value: Variant) -> void:
		if value is Dictionary and value.get("rel", "") == rel:
			results.append(node_path)
	)
	return results


## Ids of all `other_id` values for edges of one rel type under player_root.
func list_related_ids(player_root: String, rel: String) -> Array:
	var ids: Array = []
	_t3.walk(player_root, func(node_path: String, node_hash: PackedByteArray, value: Variant) -> void:
		if value is Dictionary and value.get("rel", "") == rel:
			ids.append(value.get("other_id", ""))
	)
	return ids


## Full-tree root hash (the hash diff/apply_diff operate on).
func root_hash() -> PackedByteArray:
	return _t3.hash_subtree("/")


## Root hash over a player's social subtree.
func player_root_hash(player_root: String) -> PackedByteArray:
	return _t3.hash_subtree(player_root)


## Full-tree snapshot diff. Both roots must come from root_hash()
## (T3 resolves them against this tree's snapshot history).
func diff_social(old_root: PackedByteArray, new_root: PackedByteArray) -> Array:
	return _t3.diff(old_root, new_root)


func apply_diff(root: PackedByteArray, diff: Array) -> PackedByteArray:
	return _t3.apply_diff(root, diff)


func clear() -> void:
	_t3.clear()
