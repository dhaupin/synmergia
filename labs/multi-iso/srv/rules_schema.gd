## Ported from vant axolotl lib/brain.js
## RulesSchema Resource — rule node payload for the rules tree.
## Spec: labs/world-building-arch.md В§5.1
extends Resource

class_name RulesSchema

@export var rule_id: String = ""
@export_enum("TOP_WINS", "BOTTOM_WINS", "PREDICATE_GATED", "ALL_WINS_WITH_EFFECT") var resolution: String = "TOP_WINS"
@export var default_allow: bool = true
@export var version: int = 1

func _to_canonical_bytes(value: Dictionary) -> PackedByteArray:
	var writer := _CanonicalWriter.new()
	var rule_id_str: String = value.get("rule_id", rule_id)
	var resolution_str: String = value.get("resolution", resolution)
	var default_allow_val: bool = value.get("default_allow", default_allow)
	writer.write_string(rule_id_str)
	writer.write_string(resolution_str)
	writer.write_u8(1 if default_allow_val else 0)
	return writer.to_bytes()

func _validate(value: Dictionary) -> bool:
	if not value.has("rule_id"):
		return false
	if not value.has("resolution"):
		return false
	if not value.has("default_allow"):
		return false
	var rule_id_val = value["rule_id"]
	var resolution_val = value["resolution"]
	var default_allow_val = value["default_allow"]
	if rule_id_val.get_type() != TYPE_STRING:
		return false
	if rule_id_val == "":
		return false
	var valid_resolutions := ["TOP_WINS", "BOTTOM_WINS", "PREDICATE_GATED", "ALL_WINS_WITH_EFFECT"]
	if resolution_val not in valid_resolutions:
		return false
	if default_allow_val.get_type() != TYPE_BOOL:
		return false
	return true

func _to_display(value: Dictionary) -> String:
	var rule_id_str: String = value.get("rule_id", rule_id)
	var resolution_str: String = value.get("resolution", resolution)
	var default_allow_val: bool = value.get("default_allow", default_allow)
	var allow_str := "true" if default_allow_val else "false"
	return "[%s] %s (allow=%s)" % [resolution_str, rule_id_str, allow_str]

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

	func to_bytes() -> PackedByteArray:
		return buffer
