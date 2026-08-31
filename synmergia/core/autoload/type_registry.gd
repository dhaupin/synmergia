## TypeRegistry - Registers all custom types for cross-reference resolution
extends Node

func _ready() -> void:
	# Phase 1: Load all base schemas FIRST (no dependencies on other custom types)
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
	
	# Phase 2: Load entities and components (depend on schemas)
	_preload_type("res://core/entities/entity.gd")
	_preload_type("res://core/entities/status_effect.gd")
	_preload_type("res://entities/player/player_controller.gd")
	_preload_type("res://entities/enemy/enemy.gd")
	_preload_type("res://entities/npc/npc.gd")
	_preload_type("res://core/components/inventory_component.gd")
	
	# Phase 3: Load services and UI (depend on entities)
	_preload_type("res://core/services/spawn_service.gd")
	_preload_type("res://ui/targeting/target_tooltip.gd")
	_preload_type("res://ui/components/action_menu.gd")
	
	GameLog.debug("TypeRegistry: All types registered")

func _preload_type(path: String) -> void:
	var script = load(path)
	if script:
		GameLog.debug("TypeRegistry: Loaded " + path)
		pass  # Just referencing it loads the class
