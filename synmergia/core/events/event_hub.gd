## EventHub - Unified event system interface
## Wraps all domain-specific event buses under one autoload
## Replaces the monolithic event_bus.gd
class_name EventHub
extends Node

## Domain-specific event buses
var entity: EntityEvents
var combat: CombatEvents
var inventory: InventoryEvents
var system: SystemEvents

## Legacy signal aliases (for backward compatibility)
## These forward to the new domain buses
signal entity_spawned(entity_id: String, zone_id: String, position: Vector3)
signal entity_despawned(entity_id: String, reason: String)
signal entity_died(entity_id: String, killer_id: String, damage_type: String)
signal player_resurrected(entity_id: String, source: String)
signal player_died(entity_id: String, killer_id: String)
signal player_respawned(entity_id: String, position: Vector3, mode: int)

signal skill_executed(caster_id: String, skill_id: String, targets: Array)
signal damage_dealt(attacker_id: String, target_id: String, damage: int, damage_type: String)
signal buff_applied(target_id: String, buff_id: String, source_id: String)

signal item_picked_up(entity_id: String, item_id: String)
signal gold_changed(entity_id: String, amount: int)

signal server_started(version: String)
signal server_shutdown()
signal player_connected(player_id: String)
signal player_disconnected(player_id: String, reason: String)

func _ready() -> void:
	_initialize_buses()
	_connect_legacy_signals()
	GameLog.info("EventHub: Initialized with %d event buses" % 4)

func _initialize_buses() -> void:
	entity = EntityEvents.new()
	combat = CombatEvents.new()
	inventory = InventoryEvents.new()
	system = SystemEvents.new()
	
	add_child(entity)
	add_child(combat)
	add_child(inventory)
	add_child(system)

func _connect_legacy_signals() -> void:
	# Entity -> Legacy forwarding
	entity.spawned.connect(_forward_spawned)
	entity.despawned.connect(_forward_despawned)
	entity.died.connect(_forward_died)
	entity.resurrected.connect(_forward_resurrected)
	
	# Combat -> Legacy forwarding
	combat.skill_executed.connect(_forward_skill)
	combat.damage_dealt.connect(_forward_damage)
	combat.buff_applied.connect(_forward_buff)
	
	# Inventory -> Legacy forwarding
	inventory.item_picked_up.connect(_forward_item_pickup)
	inventory.gold_gained.connect(_forward_gold_gained)
	inventory.gold_spent.connect(_forward_gold_spent)
	
	# System -> Legacy forwarding
	system.server_started.connect(_forward_server_started)
	system.server_stopping.connect(_forward_server_shutdown)
	system.player_connected.connect(_forward_player_connected)
	system.player_disconnected.connect(_forward_player_disconnected)

## Legacy signal forwarders
func _forward_spawned(entity_id: String, zone_id: String, position: Vector3) -> void:
	entity_spawned.emit(entity_id, zone_id, position)

func _forward_despawned(entity_id: String, reason: String) -> void:
	entity_despawned.emit(entity_id, reason)

func _forward_died(entity_id: String, killer_id: String, damage_type: String) -> void:
	entity_died.emit(entity_id, killer_id, damage_type)

func _forward_resurrected(entity_id: String, source: String) -> void:
	player_resurrected.emit(entity_id, source)

func _forward_skill(caster_id: String, skill_id: String, targets: Array) -> void:
	skill_executed.emit(caster_id, skill_id, targets)

func _forward_damage(attacker_id: String, target_id: String, damage: int, damage_type: String, critical: bool) -> void:
	damage_dealt.emit(attacker_id, target_id, damage, damage_type)

func _forward_buff(target_id: String, buff_id: String, source_id: String, duration: float) -> void:
	buff_applied.emit(target_id, buff_id, source_id)

func _forward_item_pickup(entity_id: String, item_id: String, slot: int) -> void:
	item_picked_up.emit(entity_id, item_id)

func _forward_gold_gained(entity_id: String, amount: int, source: String) -> void:
	gold_changed.emit(entity_id, amount)

func _forward_gold_spent(entity_id: String, amount: int, destination: String) -> void:
	gold_changed.emit(entity_id, -amount)

func _forward_server_started(version: String, port: int) -> void:
	server_started.emit(version)

func _forward_server_shutdown(reason: String) -> void:
	server_shutdown.emit()

func _forward_player_connected(player_id: String) -> void:
	player_connected.emit(player_id)

func _forward_player_disconnected(player_id: String, reason: String) -> void:
	player_disconnected.emit(player_id, reason)

## Utility: Get event summary
func get_summary() -> Dictionary:
	return {
		"entity_events": entity.get_event_count(),
		"combat_events": combat.get_event_count(),
		"inventory_events": inventory.get_event_count(),
		"system_events": system.get_event_count(),
	}
