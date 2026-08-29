## TypeRegistry - Forces registration of all custom types
## Must be the FIRST autoload to ensure types are available
extends Node

func _ready() -> void:
	# Register all schema types using ResourceLoader
	# This makes class_name declarations available globally
	var schema_paths := [
		"res://core/schemas/item.gd",
		"res://core/schemas/zone_data.gd",
		"res://core/schemas/species.gd",
		"res://core/schemas/skill.gd",
		"res://core/schemas/faction.gd",
		"res://core/schemas/character_class.gd",
		"res://core/schemas/enemy_data.gd",
		"res://core/schemas/npc_data.gd",
		"res://core/schemas/quest_data.gd",
		"res://core/schemas/dwelling_data.gd",
		"res://core/schemas/gateway_data.gd",
		"res://core/schemas/event_data.gd",
		"res://core/schemas/status_effect_data.gd",
		"res://core/schemas/loot_table.gd",
		"res://core/schemas/agent_action.gd",
		"res://core/schemas/agent_connector.gd",
		"res://core/schemas/ankh.gd",
		"res://core/schemas/target_schema.gd",
	]

	for path in schema_paths:
		if ResourceLoader.exists(path):
			# Just loading triggers class_name registration
			var _schema = load(path)
			# Immediately release to avoid memory accumulation
			pass
