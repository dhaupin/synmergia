## StatusEffect - Buffs and debuffs
## Can be stacked, have durations, and modify entity stats/behaviors
class_name StatusEffect
extends Resource

signal effect_expired
signal stack_changed(new_stacks: int)

enum EffectType {
	BUFF,
	DEBUFF,
	NEUTRAL
}

enum StackBehavior {
	NONE,
	REFRESH,
	ADD,
	REPLACE
}

@export var effect_name: String = "Effect"
@export var effect_type: EffectType = EffectType.NEUTRAL
@export var duration: float = 0.0  # 0 = instant/permanent
@export var max_stacks: int = 1
@export var stack_behavior: StackBehavior = StackBehavior.NONE

var current_stacks: int = 1
var remaining_duration: float = 0.0
var source_entity: Entity = null
var target_entity: Entity = null
var is_active: bool = false

var _timer: Timer

func _init() -> void:
	remaining_duration = duration

func apply(target: Entity) -> void:
	if is_active:
		_handle_stacking()
		return
	
	target_entity = target
	is_active = true
	
	if duration > 0:
		_timer = Timer.new()
		_timer.one_shot = true
		_timer.timeout.connect(_on_duration_expired)
		target.add_child(_timer)
		_timer.start(duration)
		remaining_duration = duration
	
	_apply_effect()
	stack_changed.emit(current_stacks)

func remove(target: Entity) -> void:
	if not is_active:
		return
	
	_revert_effect()
	
	if _timer:
		_timer.stop()
		_timer.queue_free()
		_timer = null
	
	is_active = false
	target_entity = null

func _handle_stacking() -> void:
	match stack_behavior:
		StackBehavior.REFRESH:
			remaining_duration = duration
			if _timer:
				_timer.start(duration)
		StackBehavior.ADD:
			current_stacks = min(max_stacks, current_stacks + 1)
			stack_changed.emit(current_stacks)
		StackBehavior.REPLACE:
			_revert_effect()
			current_stacks = 1
			_apply_effect()

func _on_duration_expired() -> void:
	_expire()
	effect_expired.emit()

func _expire() -> void:
	if target_entity and is_active:
		remove(target_entity)

func is_expired() -> bool:
	return remaining_duration <= 0 and duration > 0

func _apply_effect() -> void:
	# Override in subclasses
	pass

func _revert_effect() -> void:
	# Override in subclasses
	pass

func get_stacks() -> int:
	return current_stacks

func get_remaining_duration() -> float:
	return remaining_duration if is_active else 0.0

func is_permanent() -> bool:
	return duration == 0.0
