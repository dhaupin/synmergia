## StateSchema Resource
##
## Specification: labs/prd-state-schema.md
## Architecture: labs/world-building-arch.md §8.1
##
## State tree payload schema. Defines type (position/inventory/health/
## faction/status/quest/social/behavior_state/other) and canonical
## encoding/validation/display methods.

extends Resource
class_name StateSchema

@export_enum("position", "inventory", "health", "faction", "status", "quest", "social", "behavior_state", "other") var type: String = "position"
@export var version: int = 1

func _to_canonical_bytes(value: Dictionary) -> PackedByteArray:
	var writer := _CanonicalWriter.new()
	
	var type_str: String = value.get("type", type)
	var entity_id: String = value.get("entity_id", "")
	var payload: Dictionary = value.get("payload", {})
	
	var type_enum: int = _type_to_enum(type_str)
	writer.write_u8(type_enum)
	writer.write_string(entity_id)
	writer.write_dict(payload)
	
	return writer.to_bytes()

func _validate(value: Dictionary) -> bool:
	if not value.has("type"):
		return false
	if not value.has("entity_id"):
		return false
	if not value.has("payload"):
		return false
	
	var type_val: String = value["type"]
	var entity_id_val = value["entity_id"]
	var payload_val = value["payload"]
	
	var valid_types := ["position", "inventory", "health", "faction", "status", "quest", "social", "behavior_state", "other"]
	if type_val not in valid_types:
		return false
	if entity_id_val.get_type() != TYPE_STRING:
		return false
	if payload_val.get_type() != TYPE_DICTIONARY:
		return false
	
	match type_val:
		"position":
			if not payload_val.has("x") or not payload_val.has("y") or not payload_val.has("z"):
				return false
			if payload_val["x"].get_type() not in [TYPE_FLOAT, TYPE_INT]:
				return false
			if payload_val["y"].get_type() not in [TYPE_FLOAT, TYPE_INT]:
				return false
			if payload_val["z"].get_type() not in [TYPE_FLOAT, TYPE_INT]:
				return false
		"health":
			if not payload_val.has("current") or not payload_val.has("max"):
				return false
			if payload_val["current"].get_type() != TYPE_INT:
				return false
			if payload_val["max"].get_type() != TYPE_INT:
				return false
		"inventory":
			if not payload_val.has("items"):
				return false
			if payload_val["items"].get_type() != TYPE_ARRAY:
				return false
		"faction":
			if not payload_val.has("faction_id"):
				return false
			if payload_val["faction_id"].get_type() != TYPE_STRING:
				return false
			if not payload_val.has("standing"):
				return false
			if payload_val["standing"].get_type() not in [TYPE_FLOAT, TYPE_INT]:
				return false
		"status":
			if not payload_val.has("effects"):
				return false
			if payload_val["effects"].get_type() != TYPE_ARRAY:
				return false
		"quest":
			if not payload_val.has("quest_id"):
				return false
			if payload_val["quest_id"].get_type() != TYPE_STRING:
				return false
			if not payload_val.has("progress"):
				return false
			if payload_val["progress"].get_type() != TYPE_INT:
				return false
		"social":
			if not payload_val.has("relations"):
				return false
			if payload_val["relations"].get_type() != TYPE_DICTIONARY:
				return false
		"behavior_state":
			if not payload_val.has("current_state"):
				return false
			if payload_val["current_state"].get_type() != TYPE_STRING:
				return false
			if not payload_val.has("ai_tick_state"):
				return false
		"other":
			pass
	
	return true

func _to_display(value: Dictionary) -> String:
	var type_str: String = value.get("type", type)
	var entity_id: String = value.get("entity_id", "")
	var payload: Dictionary = value.get("payload", {})
	
	match type_str:
		"position":
			var x = payload.get("x", 0)
			var y = payload.get("y", 0)
			var z = payload.get("z", 0)
			return "[position] %s @ (%.2f, %.2f, %.2f)" % [entity_id, x, y, z]
		"health":
			var current = payload.get("current", 0)
			var max_hp = payload.get("max", 0)
			return "[health] %s (%d/%d)" % [entity_id, current, max_hp]
		"inventory":
			var items = payload.get("items", [])
			return "[inventory] %s (%d items)" % [entity_id, items.size()]
		"faction":
			var faction_id = payload.get("faction_id", "")
			var standing = payload.get("standing", 0.0)
			return "[faction] %s -> %s (%.2f)" % [entity_id, faction_id, standing]
		"status":
			var effects = payload.get("effects", [])
			return "[status] %s (%d effects)" % [entity_id, effects.size()]
		"quest":
			var quest_id = payload.get("quest_id", "")
			var progress = payload.get("progress", 0)
			return "[quest] %s: %s (%d%%)" % [entity_id, quest_id, progress]
		"social":
			var relations = payload.get("relations", {})
			return "[social] %s (%d relations)" % [entity_id, relations.size()]
		"behavior_state":
			var current_state = payload.get("current_state", "")
			return "[behavior_state] %s: %s" % [entity_id, current_state]
		"other":
			return "[other] %s" % entity_id
	
	return "[%s] %s" % [type_str, entity_id]

func _type_to_enum(type_str: String) -> int:
	match type_str:
		"position": return 0
		"inventory": return 1
		"health": return 2
		"faction": return 3
		"status": return 4
		"quest": return 5
		"social": return 6
		"behavior_state": return 7
		"other": return 8
	return 8

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