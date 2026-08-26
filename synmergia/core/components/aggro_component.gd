## AggroComponent - Threat/aggro tracking
## Attached to entities that generate threat (enemies track who attacks them)
class_name AggroComponent
extends Node

signal target_changed(old_target: Entity, new_target: Entity)
signal threat_changed(target: Entity, threat_amount: int)
signal threat_overflow(source: Entity)
signal out_of_combat()

@export var aggro_range: float = 15.0  # Detection radius
@export var threat_decay_rate: float = 1.0  # Threat lost per second when out of combat
@export var max_threat_per_target: int = 10000
@export var threat_transfer_on_death: bool = true

var _threat_table: Dictionary = {}  # Entity -> threat amount
var _current_target: Entity = null
var _is_in_combat: bool = false
var _out_of_combat_timer: float = 0.0
@export var out_of_combat_delay: float = 5.0  # Seconds before out of combat

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	if not _is_in_combat:
		return
	
	# Check for out of combat
	_out_of_combat_timer += delta
	if _out_of_combat_timer >= out_of_combat_delay:
		_end_combat()
	else:
		_decay_threat(delta)

## Add threat for a target
func add_threat(target: Entity, amount: int) -> void:
	if not is_instance_valid(target):
		return
	
	# Initialize threat entry if needed
	if not _threat_table.has(target):
		_threat_table[target] = 0
	
	# Add threat
	_threat_table[target] = min(_threat_table[target] + amount, max_threat_per_target)
	
	# Enter combat if this is the first significant threat
	if not _is_in_combat and amount > 0:
		_enter_combat(target)
	
	threat_changed.emit(target, _threat_table[target])
	
	# Update target if needed
	_update_target()

## Reduce threat on a target (taunt removal, etc.)
func reduce_threat(target: Entity, amount: int) -> void:
	if _threat_table.has(target):
		_threat_table[target] = max(0, _threat_table[target] - amount)
		threat_changed.emit(target, _threat_table[target])

## Remove all threat from a target
func clear_threat(target: Entity) -> void:
	_threat_table.erase(target)
	if _current_target == target:
		_update_target()

## Clear all threat
func clear_all_threat() -> void:
	_threat_table.clear()
	_set_target(null)

## Get highest threat target
func get_highest_threat_target() -> Entity:
	var highest_threat := 0
	var highest_target: Entity = null
	
	for target in _threat_table:
		if is_instance_valid(target):
			if _threat_table[target] > highest_threat:
				highest_threat = _threat_table[target]
				highest_target = target
	
	return highest_target

## Get threat amount for target
func get_threat(target: Entity) -> int:
	return _threat_table.get(target, 0)

## Get all threat targets
func get_all_threat_targets() -> Array[Entity]:
	return _threat_table.keys()

## Set target
func set_target(new_target: Entity) -> void:
	if _current_target != new_target:
		var old := _current_target
		_current_target = new_target
		target_changed.emit(old, new_target)

func _set_target(new_target: Entity) -> void:
	if _current_target != new_target:
		var old := _current_target
		_current_target = new_target
		target_changed.emit(old, new_target)

func _update_target() -> void:
	var new_target := get_highest_threat_target()
	_set_target(new_target)

## Enter combat state
func _enter_combat(first_target: Entity) -> void:
	_is_in_combat = true
	_out_of_combat_timer = 0.0
	
	# Set initial target
	if not _current_target:
		_set_target(first_target)

## End combat state
func _end_combat() -> void:
	_is_in_combat = false
	_out_of_combat_timer = 0.0
	_threat_table.clear()
	_set_target(null)
	out_of_combat.emit()

## Decay threat over time (when out of combat)
func _decay_threat(delta: float) -> void:
	var decay_amount := int(threat_decay_rate * delta)
	
	for target in _threat_table:
		if is_instance_valid(target):
			_threat_table[target] = max(0, _threat_table[target] - decay_amount)
			
			# Remove targets with 0 threat
			if _threat_table[target] <= 0:
				_threat_table.erase(target)
	
	# Update target if current has 0 threat
	if _current_target and _threat_table.get(_current_target, 0) <= 0:
		_update_target()

## Transfer threat to another source (on death, etc.)
func transfer_threat_to(source: Entity) -> void:
	if not threat_transfer_on_death:
		return
	
	# Give all current threat to the new source
	for target in _threat_table:
		if is_instance_valid(target) and target.has_method("aggro_component"):
			var threat := _threat_table[target]
			target.aggro_component.add_threat(source, threat)

## Check if entity is in aggro range
func is_in_aggro_range(position: Vector3, target_position: Vector3) -> bool:
	return position.distance_to(target_position) <= aggro_range

## Handle target death
func on_target_death(target: Entity) -> void:
	_threat_table.erase(target)
	
	if _current_target == target:
		_update_target()

## Get threat info for debugging
func get_threat_info() -> Dictionary:
	var info: Dictionary = {
		"in_combat": _is_in_combat,
		"current_target": _current_target.name if _current_target else null,
		"threats": []
	}
	
	for target in _threat_table:
		if is_instance_valid(target):
			info["threats"].append({
				"target": target.name,
				"threat": _threat_table[target]
			})
	
	return info
