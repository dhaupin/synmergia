## TargetingSystem - Generic, reusable targeting system
## Supports any entity type: players, NPCs, enemies, objects
##
## Autoload: Access via `TargetingSystem` globally
class_name TargetingSystem
extends Node

static var instance: TargetingSystem

enum EntityType {
	NONE = 0
	PLAYER = 1
	NPC = 2
	ENEMY = 4
	OBJECT = 8
	TELEPORT = 16
	LOOT = 32
	ALL = 0xFFFFFFFF
}

enum SelectionMode {
	SINGLE = 0
	MULTI = 1
	RADIAL = 2
}

class Target:
	var entity_id: String
	var entity_type: EntityType
	var entity_name: String
	var position: Vector3
	var node: Node
	var metadata: Dictionary
	
	func _init(p_id: String = "", p_type: EntityType = EntityType.NONE, 
			p_name: String = "", p_pos: Vector3 = Vector3.ZERO, p_node: Node = null):
		entity_id = p_id
		entity_type = p_type
		entity_name = p_name
		position = p_pos
		node = p_node
		metadata = {}

var _current_target: Target = null
var _target_history: Array = []
var _max_history: int = 10
var _allowed_types: int = EntityType.ALL
var _selection_mode: SelectionMode = SelectionMode.SINGLE

signal target_acquired(target: Target)
signal target_cleared(previous_target: Target)
signal target_updated(target: Target)

func _ready() -> void:
	instance = self
	Logger.info("TargetingSystem: Initialized")

static func get() -> TargetingSystem:
	return instance

func set_allowed_types(types: int) -> void:
	_allowed_types = types

func add_allowed_type(type: EntityType) -> void:
	_allowed_types |= type

func remove_allowed_type(type: EntityType) -> void:
	_allowed_types &= ~type

func set_selection_mode(mode: SelectionMode) -> void:
	_selection_mode = mode

func get_current_target() -> Target:
	return _current_target

func has_target() -> bool:
	return _current_target != null and _current_target.entity_id != ""

func set_target(entity_id: String, entity_type: EntityType, 
		entity_name: String = "", position: Vector3 = Vector3.ZERO, 
		node: Node = null, metadata: Dictionary = {}) -> void:
	
	if not _is_type_allowed(entity_type):
		return
	
	var new_target := Target.new(entity_id, entity_type, entity_name, position, node)
	new_target.metadata = metadata
	
	if _selection_mode == SelectionMode.SINGLE and _current_target:
		if _current_target.entity_id != entity_id:
			target_cleared.emit(_current_target)
	
	_add_to_history(_current_target)
	_current_target = new_target
	target_acquired.emit(new_target)

func clear_target() -> void:
	if _current_target:
		var previous := _current_target
		_current_target = null
		target_cleared.emit(previous)

func cycle_next(entities: Array) -> void:
	if entities.is_empty():
		return
	
	var current_idx := -1
	if _current_target:
		current_idx = entities.find(_current_target.entity_id)
	
	for i in range(current_idx + 1, entities.size()):
		var entity = entities[i]
		if _is_valid_entity(entity):
			_set_target_from_entity(entity)
			return
	
	for i in range(0, current_idx + 1):
		var entity = entities[i]
		if _is_valid_entity(entity):
			_set_target_from_entity(entity)
			return

func can_target(entity_type: EntityType) -> bool:
	return _is_type_allowed(entity_type)

func get_target_info() -> Dictionary:
	if not _current_target:
		return {}
	
	return {
		"id": _current_target.entity_id,
		"type": _current_target.entity_type,
		"name": _current_target.entity_name,
		"position": _current_target.position,
		"metadata": _current_target.metadata
	}

func restore_previous() -> bool:
	if _target_history.is_empty():
		return false
	
	var previous: Target = _target_history.pop_back()
	if previous and previous.entity_id != "":
		set_target(previous.entity_id, previous.entity_type, 
				previous.entity_name, previous.position, previous.node, previous.metadata)
		return true
	
	return false

func _is_type_allowed(type: EntityType) -> bool:
	return (_allowed_types & type) != 0

func _add_to_history(target: Target) -> void:
	if target and target.entity_id != "":
		_target_history.append(target)
		if _target_history.size() > _max_history:
			_target_history.pop_front()

func _is_valid_entity(entity) -> bool:
	if entity is Dictionary:
		return _is_type_allowed(entity.get("type", EntityType.NONE))
	return true

func _set_target_from_entity(entity) -> void:
	if entity is Dictionary:
		set_target(
			entity.get("id", ""),
			entity.get("type", EntityType.NONE),
			entity.get("name", ""),
			entity.get("position", Vector3.ZERO),
			null,
			entity.get("metadata", {})
		)
	elif entity is String:
		set_target(entity, EntityType.PLAYER, entity)

static func entity_type_to_string(type: EntityType) -> String:
	match type:
		EntityType.PLAYER: return "Player"
		EntityType.NPC: return "NPC"
		EntityType.ENEMY: return "Enemy"
		EntityType.OBJECT: return "Object"
		EntityType.TELEPORT: return "Teleport"
		EntityType.LOOT: return "Loot"
		_: return "Unknown"
