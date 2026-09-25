## SeedSchema Resource
##
## Specification: labs/prd-seed-schema.md
## Architecture: labs/world-building-arch.md §7.1
## Sample: game/data/roots/world/seed.tres (covers all 9 type x scope combos)
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
	if typeof(path_val) != TYPE_STRING:
		return false
	if typeof(params_val) != TYPE_DICTIONARY:
		return false

	# Parameters are a free-form dictionary. Each key must be a String
	# and each value must be a supported scalar or array/dictionary.
	# Numeric scalars are accepted by _validate (the canonical encoder
	# adds length-prefixed encoding per NSC-9 style).
	for key in params_val.keys():
		if typeof(key) != TYPE_STRING:
			return false
		var v = params_val[key]
		var vt: int = typeof(v)
		if vt not in [TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_BOOL, TYPE_NIL, TYPE_ARRAY, TYPE_DICTIONARY]:
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

	func write_value(v: Variant) -> void:
		# Per-value length-prefixed encoding.
		# Numeric scalars are written with a u32 length prefix
		# followed by the value bytes, mirroring the write_string
		# pattern (NSC-9 / T3 canonical style). This removes the
		# JSON-ambiguity where "abc"+"def" would collide with
		# "ab"+"cdef".
		match typeof(v):
			TYPE_INT:
				var val: int = v
				# Signed 64-bit little-endian, stripped of
				# leading sign-extension bytes for a minimal
				# representation (still deterministic).
				var bytes: PackedByteArray = PackedByteArray()
				for i in range(8):
					bytes.append((val >> (i * 8)) & 0xFF)
				var len: int = 8
				while len > 1:
					var top: int = bytes[len - 1]
					var next_high: int = bytes[len - 2]
					# Strip the byte if it is a pure sign-extension
					# of the previous byte's high bit.
					if (top == 0x00 and (next_high & 0x80) == 0) or (top == 0xFF and (next_high & 0x80) != 0):
						len -= 1
					else:
						break
				write_u32(len)
				buffer.append_array(bytes.slice(0, len))
			TYPE_FLOAT:
				# Encode floats in a canonical textual form so the
				# encoding is stable and platform-independent.
				var repr: String = "%.17g" % v
				write_string(repr)
			TYPE_STRING:
				var str_bytes: PackedByteArray = v.to_utf8_buffer()
				write_u32(str_bytes.size())
				buffer.append_array(str_bytes)
			TYPE_BOOL:
				var bool_byte: int = 1 if v else 0
				write_u32(1)
				buffer.append(bool_byte)
			TYPE_NIL:
				write_u32(0)
			_:
				# Fallback: length-prefixed JSON for structured
				# values (Array, Dictionary).
				var json_str: String = JSON.stringify(v)
				var json_bytes: PackedByteArray = json_str.to_utf8_buffer()
				write_u32(json_bytes.size())
				buffer.append_array(json_bytes)

	func write_dict(d: Dictionary) -> void:
		var keys: Array = d.keys()
		keys.sort()
		for key in keys:
			write_string(key)
			write_value(d[key])

	func to_bytes() -> PackedByteArray:
		return buffer
