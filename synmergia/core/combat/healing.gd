## Healing - Health, mana, stamina restoration system
## Instant heals, regen over time, and resource replenishment
extends Node

const __RegenerationOverTime__ = preload("res://core/combat/healing.gd")
## Simple instant heal (call directly or from effects)
static func heal_instant(target: Entity, amount: int) -> int:
	if target.is_dead:
		return 0
	
	var overheal := 0
	target.current_health += amount
	
	if target.current_health > target.max_health:
		overheal = target.current_health - target.max_health
		target.current_health = target.max_health
	
	target.health_changed.emit(target.current_health, target.max_health)
	return amount - overheal  # Return actual healed amount

## Instant mana restore
static func restore_mana_instant(target: Entity, amount: int) -> int:
	if target.is_dead:
		return 0
	
	var overrestore := 0
	target.current_mana += amount
	
	if target.current_mana > target.max_mana:
		overrestore = target.current_mana - target.max_mana
		target.current_mana = target.max_mana
	
	target.health_changed.emit(target.current_health, target.max_health)  # Reuse signal or add mana_changed
	return amount - overrestore

## Instant stamina restore
static func restore_stamina_instant(target: Entity, amount: float) -> float:
	if target.is_dead:
		return 0.0
	
	var overrestore := 0.0
	target.current_stamina += amount
	
	if target.current_stamina > target.max_stamina:
		overrestore = target.current_stamina - target.max_stamina
		target.current_stamina = target.max_stamina
	
	return amount - overrestore

## RegenerationOverTime - Tick-based resource regen
class_name RegenerationOverTime
extends Node

signal regen_tick(entity: Entity, amount: int, resource: String)
signal regen_complete(entity: Entity)

enum Resource {
	HEALTH,
	MANA,
	STAMINA
}

@export var resource_type: Resource = Resource.HEALTH
@export var tick_amount: int = 10       # Amount restored per tick
@export var tick_interval: float = 1.0   # Seconds between ticks
@export var total_ticks: int = 10       # 0 = infinite
@export var delay_first_tick: bool = true  # Wait tick_interval before first tick

var _target: Entity
var _current_ticks: int = 0
var _timer: Timer
var _is_active: bool = false

func _init() -> void:
	pass

func start(target: Entity) -> void:
	if _is_active:
		return
	
	_target = target
	_current_ticks = 0
	_is_active = true
	
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.wait_time = tick_interval
	
	if delay_first_tick:
		_timer.timeout.connect(_on_delayed_tick)
	else:
		_timer.timeout.connect(_on_tick)
	
	_target.add_child(_timer)
	
	var initial_wait := 0.0 if not delay_first_tick else tick_interval
	_timer.start(initial_wait if initial_wait > 0 else tick_interval)

func stop() -> void:
	_is_active = false
	if _timer:
		_timer.stop()
		_timer.queue_free()
		_timer = null
	_target = null

func _on_delayed_tick() -> void:
	_timer.timeout.disconnect(_on_delayed_tick)
	_timer.timeout.connect(_on_tick)
	_on_tick()

func _on_tick() -> void:
	if not _is_active or not _target or not is_instance_valid(_target):
		stop()
		return
	
	_current_ticks += 1
	
	match resource_type:
		Resource.HEALTH:
			if _target.is_dead:
				stop()
				return
			var healed := _apply_healing(_target, tick_amount)
			regen_tick.emit(_target, healed, "health")
		
		Resource.MANA:
			var restored := _apply_mana_restore(_target, tick_amount)
			regen_tick.emit(_target, restored, "mana")
		
		Resource.STAMINA:
			var restored := _apply_stamina_restore(_target, float(tick_amount))
			regen_tick.emit(_target, restored, "stamina")
	
	# Check if regen is complete
	if total_ticks > 0 and _current_ticks >= total_ticks:
		regen_complete.emit(_target)
		stop()

func _apply_healing(entity: Entity, amount: int) -> int:
	entity.current_health = min(entity.max_health, entity.current_health + amount)
	entity.health_changed.emit(entity.current_health, entity.max_health)
	return amount

func _apply_mana_restore(entity: Entity, amount: int) -> int:
	entity.current_mana = min(entity.max_mana, entity.current_mana + amount)
	return amount

func _apply_stamina_restore(entity: Entity, amount: float) -> float:
	entity.current_stamina = min(entity.max_stamina, entity.current_stamina + amount)
	return amount

## HoT - Health over time buff
class_name HoT
extends StatusEffect

@export var tick_amount: int = 5
@export var tick_interval: float = 1.0
@export var total_ticks: int = 10
@export var delay_first_tick: bool = true

var _regen: RegenerationOverTime

func _init() -> void:
	effect_type = EffectType.BUFF
	duration = tick_interval * total_ticks if not delay_first_tick else tick_interval * total_ticks + tick_interval

func apply(target: Entity) -> void:
	super.apply(target)
	
	_regen = RegenerationOverTime.new()
	_regen.resource_type = RegenerationOverTime.Resource.HEALTH
	_regen.tick_amount = tick_amount
	_regen.tick_interval = tick_interval
	_regen.total_ticks = total_ticks
	_regen.delay_first_tick = delay_first_tick
	_regen.regen_complete.connect(_on_regen_complete)
	_regen.start(target)

func remove(target: Entity) -> void:
	if _regen:
		_regen.stop()
		_regen.queue_free()
		_regen = null
	super.remove(target)

func _on_regen_complete(entity: Entity) -> void:
	effect_expired.emit()

## MoT - Mana over time buff
class_name MoT
extends StatusEffect

@export var tick_amount: int = 5
@export var tick_interval: float = 1.0
@export var total_ticks: int = 10
@export var delay_first_tick: bool = true

var _regen: RegenerationOverTime

func _init() -> void:
	effect_type = EffectType.BUFF
	duration = tick_interval * total_ticks if not delay_first_tick else tick_interval * total_ticks + tick_interval

func apply(target: Entity) -> void:
	super.apply(target)
	
	_regen = RegenerationOverTime.new()
	_regen.resource_type = RegenerationOverTime.Resource.MANA
	_regen.tick_amount = tick_amount
	_regen.tick_interval = tick_interval
	_regen.total_ticks = total_ticks
	_regen.delay_first_tick = delay_first_tick
	_regen.regen_complete.connect(_on_regen_complete)
	_regen.start(target)

func remove(target: Entity) -> void:
	if _regen:
		_regen.stop()
		_regen.queue_free()
		_regen = null
	super.remove(target)

func _on_regen_complete(entity: Entity) -> void:
	effect_expired.emit()

## SoT - Stamina over time buff
class_name SoT
extends StatusEffect

@export var tick_amount: int = 5
@export var tick_interval: float = 1.0
@export var total_ticks: int = 10
@export var delay_first_tick: bool = true

var _regen: RegenerationOverTime

func _init() -> void:
	effect_type = EffectType.BUFF
	duration = tick_interval * total_ticks if not delay_first_tick else tick_interval * total_ticks + tick_interval

func apply(target: Entity) -> void:
	super.apply(target)
	
	_regen = RegenerationOverTime.new()
	_regen.resource_type = RegenerationOverTime.Resource.STAMINA
	_regen.tick_amount = tick_amount
	_regen.tick_interval = tick_interval
	_regen.total_ticks = total_ticks
	_regen.delay_first_tick = delay_first_tick
	_regen.regen_complete.connect(_on_regen_complete)
	_regen.start(target)

func remove(target: Entity) -> void:
	if _regen:
		_regen.stop()
		_regen.queue_free()
		_regen = null
	super.remove(target)

func _on_regen_complete(entity: Entity) -> void:
	effect_expired.emit()
