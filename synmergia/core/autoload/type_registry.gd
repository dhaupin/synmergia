## TypeRegistry - Registers all custom types for cross-reference resolution
extends Node

func _ready() -> void:
	# Load all base schemas (no dependencies on other custom types)
	# NOTE: Entities, components, services, and UI are loaded via autoload order
	# and don't need to be preloaded here. Preloading them caused circular
	# dependency issues when they referenced autoloads that hadn't loaded yet.
	_preload_type("res://core/schemas/item.gd")
	_preload_type("res://core/schemas/skill.gd")
	_preload_type("res://core/schemas/species.gd")
	_preload_type("res://core/schemas/character_class.gd")
	_preload_type("res://core/schemas/faction.gd")
	_preload_type("res://core/schemas/zone_data.gd")
	_preload_type("res://core/schemas/enemy_data.gd")
	_preload_type("res://core/schemas/npc_data.gd")
	_preload_type("res://core/schemas/gateway_data.gd")
	_preload_type("res://core/schemas/dwelling_data.gd")
	_preload_type("res://core/schemas/event_data.gd")
	_preload_type("res://core/schemas/quest_data.gd")
	_preload_type("res://core/schemas/target_schema.gd")
	_preload_type("res://core/schemas/loot_table.gd")
	_preload_type("res://core/schemas/ankh.gd")

	GameLog.debug("TypeRegistry: All schemas registered")

func _preload_type(path: String) -> void:
	var script = load(path)
	if script:
		GameLog.debug("TypeRegistry: Loaded " + path)
		pass  # Just referencing it loads the class