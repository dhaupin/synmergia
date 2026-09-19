## StateTree wrapper over T3 + StateSchema.
## Frame primitive -- NOT an autoload, NO class_name.
extends RefCounted

const T3Script = preload("res://core/frame/kv/t3.gd")
const StateSchemaScript = preload("res://data/roots/state_schema.gd")

var _t3: T3Script
var _schema: StateSchemaScript
var _current_root: PackedByteArray = PackedByteArray()


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
	var result: Variant = _t3.get_at(path)
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


## Clears the underlying T3 tree state.
func clear() -> void:
	_t3.clear()

## Deletes a node at path.
func delete_state(path: String) -> bool:
	return _t3.delete(path)


## Returns a full snapshot of all nodes under scope_path as diff entries.
## Used for client resync when hash divergence is detected.
func get_full_scope_snapshot(scope_path: String) -> Array:
	return _t3.get_full_scope_snapshot(scope_path)


## Applies a full scope snapshot (from server resync) directly to the underlying T3.
## Bypasses normal insert logic - used for client resync after hash divergence.
## snapshot entries format: [path, old_hash (empty), new_hash, value_bytes]
func apply_full_snapshot(snapshot: Array, root_hash: PackedByteArray) -> void:
	for entry in snapshot:
		if not entry is Array or entry.size() < 4:
			continue
		var node_path: String = str(entry[0])
		var new_hash: PackedByteArray = entry[2]
		var value_bytes: PackedByteArray = entry[3]
		if new_hash.size() > 0 and value_bytes != null:
			var value: Variant = bytes_to_var(value_bytes)
			var schema: Resource = Resource.new()
			_t3.insert(node_path, value, schema)
	_current_root = _t3.hash_subtree("/")
	# Verify the resulting root matches expected
	if _current_root != root_hash:
		push_error("Full snapshot root hash mismatch: got %s, expected %s" % [_current_root.hex_encode(), root_hash.hex_encode()])