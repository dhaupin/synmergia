## StateTree wrapper over T3 + StateSchema.
## Frame primitive -- NOT an autoload, NO class_name.
extends RefCounted

const T3Script = preload("res://labs/kv/t3.gd")
const StateSchemaScript = preload("res://data/roots/state_schema.gd")

var _t3: T3Script
var _schema: StateSchemaScript


func _init(t3_instance = null) -> void:
	if t3_instance != null and t3_instance is T3Script:
		_t3 = t3_instance
	else:
		_t3 = T3Script.new()
	_schema = StateSchemaScript.new()


func insert_state(path: String, entity_id: String, state_type: String, payload: Dictionary) -> PackedByteArray:
	var value := {
		"type": state_type,
		"entity_id": entity_id,
		"payload": payload
	}
	return _t3.insert(path, value, _schema)


func get_state(path: String) -> Dictionary:
	var result := _t3.get(path)
	if result == null:
		return {}
	return result


func update_state(path: String, entity_id: String, state_type: String, payload: Dictionary) -> PackedByteArray:
	var value := {
		"type": state_type,
		"entity_id": entity_id,
		"payload": payload
	}
	return _t3.insert(path, value, _schema)


func diff_states(old_root: PackedByteArray, new_root: PackedByteArray) -> Array:
	return _t3.diff(old_root, new_root)


func apply_diff(root: PackedByteArray, diff: Array) -> PackedByteArray:
	return _t3.apply_diff(root, diff)


func root_hash() -> PackedByteArray:
	return _t3.hash_subtree("/")