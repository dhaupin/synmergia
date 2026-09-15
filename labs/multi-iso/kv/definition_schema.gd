## DefinitionSchema Resource — definition tree payload schema.
## Architecture: labs/world-building-arch.md §9
extends Resource
class_name DefinitionSchema

@export_enum("zone","npc","loot_table","quest","dialogue","item","skill","other") var def_type: String = "zone"
@export var version: int = 1

func _to_canonical_bytes(value: Dictionary) -> PackedByteArray:
	var writer := _CanonicalWriter.new()
	var def_type_str: String = value.get("def_type", def_type)
	var key: String = value.get("key", "")
	var data: Dictionary = value.get("data", {})
	var type_enum: int = _type_to_enum(def_type_str)
	writer.write_u8(type_enum)
	writer.write_string(key)
	writer.write_dict(data)
	return writer.to_bytes()

func _validate(value: Dictionary) -> bool:
	if not value.has("def_type"):
		return false
	if not value.has("key"):
		return false
	if not value.has("data"):
		return false
	var def_type_val: String = value["def_type"]
	var key_val = value["key"]
	var data_val = value["data"]
	var valid_types := ["zone","npc","loot_table","quest","dialogue","item","skill","other"]
	if def_type_val not in valid_types:
		return false
	if key_val.get_type() != TYPE_STRING:
		return false
	if data_val.get_type() != TYPE_DICTIONARY:
		return false
	return true

func _to_display(value: Dictionary) -> String:
	var def_type_str: String = value.get("def_type", def_type)
	var key: String = value.get("key", "")
	var data: Dictionary = value.get("data", {})
	var field_count: int = data.size()
	return "[%s] %s (%d fields)" % [def_type_str, key, field_count]

func _type_to_enum(type_str: String) -> int:
	match type_str:
		"zone": return 0
		"npc": return 1
		"loot_table": return 2
		"quest": return 3
		"dialogue": return 4
		"item": return 5
		"skill": return 6
		"other": return 7
	return 7

class _CanonicalWriter:
	var buffer: PackedByteArray = PackedByteArray()

	func write_u8(val: int) -> void:
		buffer.append(val & 0xFF)

	func write_u32(val: int) -> void:
		buffer.append(val & 0xFF)
		buffer.append((val >> 8) & 0xFF)
		buffer.append((val >> 16) & 0xFF)
		buffer.append((val >> 24) & 0xFF)

	func write_string(s: String) -> void:
		var bytes: PackedByteArray = s.to_utf8_buffer()
		write_u32(bytes.size())
		buffer.append_array(bytes)

	func write_dict(d: Dictionary) -> void:
		var json_str: String = JSON.stringify(d)
		write_string(json_str)

	func to_bytes() -> PackedByteArray:
		return buffer
