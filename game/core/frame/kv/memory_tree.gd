## MemoryTree wrapper over T3 -- AI agent memory (arch §9).
## Frame primitive -- NOT an autoload, NO class_name.
extends RefCounted

const T3Script = preload("res://core/frame/kv/t3.gd")
const MemorySchemaScript = preload("res://core/frame/kv/memory_schema.gd")

const KIND_OBSERVATION := "observation"
const KIND_EVENT := "event"
const KIND_RELATIONSHIP := "relationship"
const KIND_GOAL := "goal"
const KIND_FACT := "fact"
const VALID_KINDS := [
	KIND_OBSERVATION, KIND_EVENT, KIND_RELATIONSHIP,
	KIND_GOAL, KIND_FACT,
]

var _t3: T3Script
var _schema: MemorySchemaScript


func _init(t3_instance = null) -> void:
	if t3_instance != null and t3_instance is T3Script:
		_t3 = t3_instance
	else:
		_t3 = T3Script.new()
	_schema = MemorySchemaScript.new()


## Insert a memory. kind must be one of VALID_KINDS.
## Returns the new content hash of the memory node.
func insert_memory(agent_path: String, kind: String, content: Dictionary, weight: float = 1.0) -> PackedByteArray:
	var value := {
		"kind": kind,
		"content": content,
		"weight": weight
	}
	return _t3.insert(agent_path, value, _schema)


## Fetch a memory at path. Empty dict if absent.
func get_memory(agent_path: String) -> Dictionary:
	var result: Variant = _t3.get_at(agent_path)
	if result == null or not result is Dictionary:
		return {}
	return result


## Update = re-insert at same path (T3 content-addresses, so insert is upsert).
func update_memory(agent_path: String, kind: String, content: Dictionary, weight: float = 1.0) -> PackedByteArray:
	return insert_memory(agent_path, kind, content, weight)


## Remove a memory. Returns true if it existed.
func delete_memory(agent_path: String) -> bool:
	return _t3.delete(agent_path)


## All memory paths under an agent's subtree.
func list_memories(agent_root: String) -> Array:
	var results: Array = []
	_t3.walk(agent_root, func(node_path: String, node_hash: PackedByteArray, value: Variant) -> void:
		if value is Dictionary and value.get("kind", "") in VALID_KINDS:
			results.append(node_path)
	)
	return results


## Memories of one kind under agent_root.
func list_by_kind(agent_root: String, kind: String) -> Array:
	var results: Array = []
	_t3.walk(agent_root, func(node_path: String, node_hash: PackedByteArray, value: Variant) -> void:
		if value is Dictionary and value.get("kind", "") == kind:
			results.append(node_path)
	)
	return results


## Full-tree root hash (the hash diff/apply_diff operate on).
func root_hash() -> PackedByteArray:
	return _t3.hash_subtree("/")


## Root hash over an agent's memory subtree.
func agent_root_hash(agent_root: String) -> PackedByteArray:
	return _t3.hash_subtree(agent_root)


## Full-tree snapshot diff. Both roots must come from root_hash()
## (T3 resolves them against this tree's snapshot history).
func diff_memories(old_root: PackedByteArray, new_root: PackedByteArray) -> Array:
	return _t3.diff(old_root, new_root)


func apply_diff(root: PackedByteArray, diff: Array) -> PackedByteArray:
	return _t3.apply_diff(root, diff)


func clear() -> void:
	_t3.clear()
