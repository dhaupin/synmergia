## EventHub - Unified event system interface
##
## Wraps all domain-specific event buses under one autoload
extends Node

const SpawnMetadata = preload("res://core/events/spawn_metadata.gd")
## Forwarding signals for backward compatibility (maps to entity_events)
signal entity_spawned(entity, metadata: SpawnMetadata)
signal entity_died(entity, killer, metadata: SpawnMetadata)
signal player_died(entity, killer)
signal player_resurrected(entity, source: String)
signal self_resurrected(entity)
signal player_respawned(entity, position: Vector3, mode)
signal entity_despawned(entity_id: String, reason: String)
signal entity_killed(entity_id: String, killer_id: String)
signal entity_targeted(target_id: String, source_id: String)
signal skill_executed(caster_id: String, skill_id: String, target_ids: Array)
signal revive_completed(entity, success: bool)
## Direct combat signals (emitted by health_component.take_damage and
## Enemy.take_damage; consumed by AggroComponent for threat tracking).
signal damage_dealt(source, target, amount: int, damage_type: String)

## Spawn metadata for entity lifecycle events
## SpawnMetadata now lives in core/events/spawn_metadata.gd
## Domain-specific event buses (use these to emit/listen)
var entity
var combat
var inventory
var system

func _ready() -> void:
	# Load and instantiate domain event buses
	# Using load() to ensure classes are available
	var entity_class = load("res://core/events/entity_events.gd")
	var combat_class = load("res://core/events/combat_events.gd")
	var inventory_class = load("res://core/events/inventory_events.gd")
	var system_class = load("res://core/events/system_events.gd")

	entity = entity_class.new()
	combat = combat_class.new()
	inventory = inventory_class.new()
	system = system_class.new()

	add_child(entity)
	add_child(combat)
	add_child(inventory)
	add_child(system)

	# Forward entity_events to direct signals for backward compatibility
	entity.spawned.connect(_on_entity_spawned)
	entity.died.connect(_on_entity_died)

	GameLog.info("EventHub: Initialized")

func _on_entity_spawned(entity_id: String, zone_id: String, position: Vector3) -> void:
	entity_spawned.emit(entity_id, null)

func _on_entity_died(entity_id: String, killer_id: String, damage_type: String) -> void:
	player_died.emit(entity_id, killer_id)
	entity_died.emit(entity_id, killer_id, null)

## Get event summary for debugging
func get_summary() -> Dictionary:
	return {
		"entity_events": entity.get_event_count(),
		"combat_events": combat.get_event_count(),
		"inventory_events": inventory.get_event_count(),
		"system_events": system.get_event_count(),
	}

## Clear all event history
func clear_all_history() -> void:
	entity.clear_history()
	combat.clear_history()
	inventory.clear_history()
	system.clear_history()
