## SeedSchema Resource
##
## Specification: labs/prd-seed-schema.md
## Architecture: labs/world-building-arch.md §7.1
##
## Seed tree payload schema. Defines seed_type (locked/open/frame),
## visibility_scope (world/shard/instance/player), and canonical
## encoding/validation/display methods.

extends Resource
class_name SeedSchema

@export_enum("locked", "open", "frame") var seed_type: String = "locked"
@export_enum("world", "shard", "instance", "player") var visibility_scope: String = "world"
@export var version: int = 1

func _to_canonical_bytes(value: Dictionary) -> PackedByteArray:
	var writer := _CanonicalWriter.new()
	
	var seed_type_str: String = value.get("seed_type", seed_type)
	var scope_str: String = value.get("visibility_scope", visibility_scope)
	var path_str: String = value.get("path", "")
	var params_dict: Dictionary = value.get("parameters", {})
	
	writer.write_string(seed_type_str)
	writer.write_string(scope_str)
	writer.write_string(path_str)
	writer.write_dict(params_dict)
	
	return writer.to_bytes()

func _validate(value: Dictionary) -> bool:
	if not value.has("seed_type"):
		return false
	if not value.has("visibility_scope"):
		return false
	if not value.has("path"):
		return false
	if not value.has("parameters"):
		return false
	
	var seed_type_val: String = value["seed_type"]
	var scope_val: String = value["visibility_scope"]
	var path_val = value["path"]
	var params_val = value["parameters"]
	
	if seed_type_val not in ["locked", "open", "frame"]:
		return false
	if scope_val not in ["world", "shard", "instance", "player"]:
		return false
	if path_val.get_type() != TYPE_STRING:
		return false
	if params_val.get_type() != TYPE_DICTIONARY:
		return false
	
	return true

func _to_display(value: Dictionary) -> String:
	var seed_type_str: String = value.get("seed_type", seed_type)
	var scope_str: String = value.get("visibility_scope", visibility_scope)
	var path_str: String = value.get("path", "")
	var params_dict: Dictionary = value.get("parameters", {})
	
	var type_scope: String = "[%s+%s]" % [seed_type_str, scope_str]
	var path_display: String = path_str if path_str != "" else "(root)"
	var params_count: int = params_dict.size()
	var params_display: String = "(%d params)" % params_count
	
	return "%s %s %s" % [type_scope, path_display, params_display]

class _CanonicalWriter:
	var buffer: PackedByteArray = PackedByteArray()
	
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