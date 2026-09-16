## DefinitionTree wrapper over T3 + DefinitionSchema.
## Frame primitive -- NOT an autoload, NO class_name.
extends RefCounted

const T3Script = preload("res://labs/kv/t3.gd")
const DefinitionSchemaScript = preload("res://labs/kv/definition_schema.gd")

var _t3: T3Script
var _schema: DefinitionSchemaScript


func _init(t3_instance = null) -> void:
	if t3_instance != null and t3_instance is T3Script:
		_t3 = t3_instance
	else:
		_t3 = T3Script.new()
	_schema = DefinitionSchemaScript.new()


func insert_def(path: String, def_type: String, key: String, data: Dictionary) -> PackedByteArray:
	var value := {
		"def_type": def_type,
		"key": key,
		"data": data
	}
	return _t3.insert(path, value, _schema)


func get_def(path: String) -> Dictionary:
	var result := _t3.get(path)
	if result == null:
		return {}
	return result


func update_def(path: String, def_type: String, key: String, data: Dictionary) -> PackedByteArray:
	var value := {
		"def_type": def_type,
		"key": key,
		"data": data
	}
	return _t3.insert(path, value, _schema)


func find_by_type(def_type: String) -> Array:
	var results: Array = []
	_t3.walk("/", func(node_path: String, node_hash: PackedByteArray, value: Variant) -> void:
		if value is Dictionary and value.get("def_type", "") == def_type:
			results.append(node_path)
	)
	return results


func root_hash() -> PackedByteArray:
	return _t3.hash_subtree("/")


func diff_defs(old_root: PackedByteArray, new_root: PackedByteArray) -> Array:
	return _t3.diff(old_root, new_root)


func apply_diff(root: PackedByteArray, diff: Array) -> PackedByteArray:
	return _t3.apply_diff(root, diff)
