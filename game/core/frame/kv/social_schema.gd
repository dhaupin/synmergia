## SocialSchema Resource -- social tree edge schema (arch §9).
extends Resource
class_name SocialSchema

@export var version: int = 1

func _to_canonical_bytes(value: Dictionary) -> PackedByteArray:
	var writer := _CanonicalWriter.new()
	var rel: String = value.get("rel", "friend")
	var other_id: String = value.get("other_id", "")
	var meta: Dictionary = value.get("meta", {})
	var rel_enum: int = _rel_to_enum(rel)
	writer.write_u8(rel_enum)
	writer.write_string(other_id)
	writer.write_dict(meta)
	return writer.to_bytes()

func _validate(value: Dictionary) -> bool:
	if not value.has("rel"):
		return false
	if not value.has("other_id"):
		return false
	# Untrusted input: read as Variant and type-check before use (a typed
	# local would THROW on a wrong-typed field instead of returning false).
	var rel_val = value["rel"]
	var other_val = value["other_id"]
	var valid_rels := ["friend", "guild", "party", "rival", "mentor"]
	if typeof(rel_val) != TYPE_STRING or rel_val not in valid_rels:
		return false
	if other_val.get_type() != TYPE_STRING:
		return false
	if value.has("meta"):
		var meta_val = value["meta"]
		if meta_val.get_type() != TYPE_DICTIONARY:
			return false
	return true

func _to_display(value: Dictionary) -> String:
	var rel: String = value.get("rel", "friend")
	var other_id: String = value.get("other_id", "")
	return "%s -> %s" % [rel, other_id]

func _rel_to_enum(rel_str: String) -> int:
	match rel_str:
		"friend": return 0
		"guild": return 1
		"party": return 2
		"rival": return 3
		"mentor": return 4
	return 0

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
