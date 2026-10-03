## MemorySchema Resource -- memory tree payload schema (arch §9).
extends Resource
class_name MemorySchema

@export var version: int = 1

func _to_canonical_bytes(value: Dictionary) -> PackedByteArray:
	var writer := _CanonicalWriter.new()
	var kind: String = value.get("kind", "fact")
	var content: Dictionary = value.get("content", {})
	var weight: float = value.get("weight", 1.0)
	var kind_enum: int = _kind_to_enum(kind)
	writer.write_u8(kind_enum)
	writer.write_f32(weight)
	writer.write_dict(content)
	return writer.to_bytes()

func _validate(value: Dictionary) -> bool:
	if not value.has("kind"):
		return false
	if not value.has("content"):
		return false
	# Untrusted input: read as Variant and type-check before use. A typed
	# local (var kind_val: String = ...) THROWS on a wrong-typed field
	# instead of letting _validate return false.
	var kind_val = value["kind"]
	var content_val = value["content"]
	var valid_kinds := ["observation", "event", "relationship", "goal", "fact"]
	if typeof(kind_val) != TYPE_STRING or kind_val not in valid_kinds:
		return false
	if content_val.get_type() != TYPE_DICTIONARY:
		return false
	if value.has("weight"):
		var w = value["weight"]
		if w.get_type() != TYPE_FLOAT and w.get_type() != TYPE_INT:
			return false
	return true

func _to_display(value: Dictionary) -> String:
	var kind: String = value.get("kind", "fact")
	var content: Dictionary = value.get("content", {})
	return "memory[%s] (%d fields)" % [kind, content.size()]

func _kind_to_enum(kind_str: String) -> int:
	match kind_str:
		"observation": return 0
		"event": return 1
		"relationship": return 2
		"goal": return 3
		"fact": return 4
	return 4

class _CanonicalWriter:
	var buffer: PackedByteArray = PackedByteArray()

	func write_u8(val: int) -> void:
		buffer.append(val & 0xFF)

	func write_f32(val: float) -> void:
		# A real IEEE-754 float32 (audit round 19). The old body stored
		# int(val * 1000) -- a 1/1000-quantized int under a float name,
		# which folded distinct nearby weights into one content hash.
		var packed := PackedByteArray()
		packed.resize(4)
		packed.encode_float(0, val)
		buffer.append_array(packed)

	func write_string(s: String) -> void:
		var bytes: PackedByteArray = s.to_utf8_buffer()
		write_u32(bytes.size())
		buffer.append_array(bytes)

	func write_dict(d: Dictionary) -> void:
		var json_str: String = JSON.stringify(d)
		write_string(json_str)

	func write_u32(val: int) -> void:
		buffer.append(val & 0xFF)
		buffer.append((val >> 8) & 0xFF)
		buffer.append((val >> 16) & 0xFF)
		buffer.append((val >> 24) & 0xFF)

	func to_bytes() -> PackedByteArray:
		return buffer
