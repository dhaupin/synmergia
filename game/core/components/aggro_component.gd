## AggroComponent - Threat/aggro tracking
## Attached to entities that generate threat (enemies track who attacks them)
## The honest telemetry set: target_changed (focus flips -- the HUD
## threat sense consumes), threat_overflow (a source's threat hits the
## cap -- first real emit at the clamp leg), out_of_combat (the fight
## ends). threat_changed was REMOVED (no-void: every meaningful leg it
## covered is either a target flip or an overflow; the per-hit number
## spoke to zero consumers for its whole life).
extends Node
class_name AggroComponent


signal target_changed(old_target, new_target)
signal threat_overflow(source)
signal out_of_combat()

## Threat multipliers per damage type. Set on the component to model
## tank kits (e.g. {"physical": 0.5} halves physical threat taken) or
## enrage mechanics (multipliers above 1.0).
@export var threat_modifiers: Dictionary = {}

@export var aggro_range: float = 15.0  # Detection radius
## THE ROAD RESPECT (the enemy law): an optional supplier (target
## position -> clearance 0..1). Clearance 0 = the target stands on a
## cartway: the detection gate DROPS - travelers walking a road stay
## un-harassed. The globe wires TerrainGen.road_clearance_at in via a
## position mapper (the law's one definition lives in terrain_gen).
@export var road_respect: bool = false
@export var road_clear_supplier: Callable = Callable()
@export var threat_decay_rate: float = 1.0  # Threat lost per second when out of combat
@export var max_threat_per_target: int = 10000
@export var threat_transfer_on_death: bool = true
@export var heal_threat_factor: float = 0.5  # Heal threat = heal amount * factor
@export var taunt_resist: bool = false  # Bosses may ignore taunts

var _threat_table: Dictionary = {}  # Entity -> threat amount
var _current_target = null
var _is_in_combat: bool = false
var _out_of_combat_timer: float = 0.0
@export var out_of_combat_delay: float = 5.0  # Seconds before out of combat

# Taunt state (tank grab). _taunt_source is force-locked as target until
# the remaining seconds tick to zero (driven by _process delta, so it
# respects pause/testing). While taunted, _update_target() keeps the source.
var _taunt_source = null
var _taunt_remaining_sec: float = 0.0

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	# Expire an active taunt
	if _taunt_source != null:
		_taunt_remaining_sec -= delta
		if not is_instance_valid(_taunt_source) or _taunt_remaining_sec <= 0.0:
			var expired = _taunt_source
			_taunt_source = null
			_update_target()
			target_changed.emit(expired, _current_target)

	if not _is_in_combat:
		return

	# Check for out of combat
	_out_of_combat_timer += delta
	if _out_of_combat_timer >= out_of_combat_delay:
		_end_combat()
	else:
		_decay_threat(delta)

## Add threat for a target. amount may be negative for aggro dumps
## (e.g. feign-death debuffs); threat floors at 0.
func add_threat(target, amount: int, damage_type: String = "") -> void:
	if not is_instance_valid(target):
		return

	# Apply per-damage-type threat modifiers (tank kits / enrage).
	var modified: int = amount
	if not threat_modifiers.is_empty() and damage_type != "":
		if threat_modifiers.has(damage_type):
			modified = int(round(float(amount) * float(threat_modifiers[damage_type])))

	# Initialize threat entry if needed
	if not _threat_table.has(target):
		_threat_table[target] = 0

	# THE OVERFLOW LEG (the signal earns its first real emit): the
	# table cannot rise past max_threat_per_target -- when THIS add
	# would push the entry through the cap for the first time, the
	# source's threat has overflowed (the HUD threat sense rows it).
	var previous: int = int(_threat_table[target])

	# Add threat (negative amounts allowed for dumps; floor at 0)
	_threat_table[target] = clampi(_threat_table[target] + modified, 0, max_threat_per_target)

	if previous < max_threat_per_target and int(_threat_table[target]) >= max_threat_per_target \
			and modified > 0:
		threat_overflow.emit(target)

	# Enter combat if this is the first significant threat
	if not _is_in_combat and modified > 0:
		_enter_combat(target)

	# Update target if needed (respects active taunts)
	_update_target()

## Record a damaging hit: applies the damage-type modifier to the table.
## CombatSystem/enemy code should call this instead of add_threat so the
## damage type drives the modifier lookup.
func add_damage_threat(attacker, amount: int, damage_type: String = "physical") -> void:
	add_threat(attacker, amount, damage_type)

## Record a heal: nearby enemies gain threat on the healer proportional
## to the heal amount (scaled by heal_threat_factor).
func record_heal_threat(healer, heal_amount: int) -> void:
	if heal_threat_factor <= 0.0 or not is_instance_valid(healer):
		return
	var threat: int = int(round(float(heal_amount) * heal_threat_factor))
	if threat > 0:
		add_threat(healer, threat)

## Taunt (tank grab): force-lock target for duration_msec. While the
## taunt is active, _update_target() will not switch away. A taunting
## tank also gets enough threat to stay on top after the taunt expires.
func taunt(tank, duration_msec: int = 3000, sticky_threat: int = 1000) -> bool:
	if taunt_resist or not is_instance_valid(tank):
		return false
	var was_target = _current_target
	_taunt_source = tank
	_taunt_remaining_sec = float(duration_msec) / 1000.0
	# Sticky threat: place the tank at the top of the table so the
	# switch-back after expiry feels natural, not a snap to second place.
	if not _threat_table.has(tank):
		_threat_table[tank] = 0
	var top = get_highest_threat_target()
	if top != null and top != tank:
		_threat_table[tank] = mini(get_threat(top) + sticky_threat, max_threat_per_target)
	_is_in_combat = true
	_out_of_combat_timer = 0.0
	_set_target(tank)
	target_changed.emit(was_target, tank)
	return true

## True while a taunt force-locks the target.
func is_taunted() -> bool:
	return _taunt_source != null

## Reduce threat on a target (taunt removal, aggro dumps, etc.)
func reduce_threat(target, amount: int) -> void:
	if _threat_table.has(target):
		_threat_table[target] = maxi(0, _threat_table[target] - amount)

## Multiply a target's threat by a fraction (percentage aggro dumps,
## e.g. 0.5 = lose half your threat). Floors at 0.
func scale_threat(target, factor: float) -> void:
	if _threat_table.has(target):
		_threat_table[target] = int(float(_threat_table[target]) * clampf(factor, 0.0, 1.0))

## Remove all threat from a target
func clear_threat(target) -> void:
	_threat_table.erase(target)
	if _current_target == target:
		_update_target()

## Clear all threat
func clear_all_threat() -> void:
	_threat_table.clear()
	_taunt_source = null
	_set_target(null)

## Get highest threat target
func get_highest_threat_target():
	var highest_threat := 0
	var highest_target = null

	for target in _threat_table:
		if is_instance_valid(target):
			if _threat_table[target] > highest_threat:
				highest_threat = _threat_table[target]
				highest_target = target

	return highest_target

## Get threat amount for target
func get_threat(target) -> int:
	return _threat_table.get(target, 0)

## Get all threat targets
func get_all_threat_targets() -> Array:
	return _threat_table.keys()

## Set target
func set_target(new_target) -> void:
	if _current_target != new_target:
		var old = _current_target
		_current_target = new_target
		target_changed.emit(old, new_target)

func _set_target(new_target) -> void:
	if _current_target != new_target:
		var old = _current_target
		_current_target = new_target
		target_changed.emit(old, new_target)

func _update_target() -> void:
	# While taunted, the tank keeps the enemy locked.
	if _taunt_source != null and is_instance_valid(_taunt_source):
		if _current_target != _taunt_source:
			_set_target(_taunt_source)
		return
	var new_target = get_highest_threat_target()
	_set_target(new_target)

## Enter combat state
func _enter_combat(first_target) -> void:
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
	_taunt_source = null
	_set_target(null)
	out_of_combat.emit()

## Decay threat over time (when out of combat)
func _decay_threat(delta: float) -> void:
	var decay_amount := int(threat_decay_rate * delta)
	if decay_amount <= 0:
		return

	var to_remove: Array = []
	for target in _threat_table:
		if is_instance_valid(target):
			_threat_table[target] = maxi(0, _threat_table[target] - decay_amount)
			if _threat_table[target] <= 0:
				to_remove.append(target)
		else:
			to_remove.append(target)

	for target in to_remove:
		_threat_table.erase(target)

	# Update target if current has 0 threat
	if _current_target and not _threat_table.has(_current_target):
		_update_target()

## Transfer threat to another source (on death, etc.)
func transfer_threat_to(source) -> void:
	if not threat_transfer_on_death:
		return

	# Give all current threat to the new source
	for target in _threat_table:
		if is_instance_valid(target):
			var threat: int = _threat_table[target]
			# aggro_component is a property (Node), not a method.
			if "aggro_component" in target and target.aggro_component != null:
				target.aggro_component.add_threat(source, threat)

## Check if entity is in aggro range
func is_in_aggro_range(position: Vector3, target_position: Vector3) -> bool:
	if road_respect and road_clear_supplier.is_valid():
		if float(road_clear_supplier.call(target_position)) < 0.5:
			return false	 # the cartway is safe passage: no hunt
	return position.distance_to(target_position) <= aggro_range

## Handle target death
func on_target_death(target) -> void:
	_threat_table.erase(target)

	if _current_target == target:
		_update_target()

## Get threat info for debugging
func get_threat_info() -> Dictionary:
	var info: Dictionary = {
		"in_combat": _is_in_combat,
		"current_target": _current_target.name if _current_target else null,
		"taunted": is_taunted(),
		"threats": []
	}

	for target in _threat_table:
		if is_instance_valid(target):
			info["threats"].append({
				"target": target.name,
				"threat": _threat_table[target]
			})

	return info
