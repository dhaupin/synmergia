## StateMachine - Generic state machine for game entities
## Handles state transitions and calls enter/exit/update
class_name StateMachine
extends Node

signal state_changed(from: String, to: String)
signal state_entered(state_name: String)
signal state_exited(state_name: String)

@export var initial_state: State
@export var animateSprite: bool = true

var current_state: State
var states: Dictionary = {}

func _ready() -> void:
	for child in get_children():
		if child is State:
			states[child.name] = child
			child.state_machine = self
	
	if initial_state:
		current_state = initial_state
		current_state.enter()

func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)

func transition_to(state_name: String, data: Dictionary = {}) -> void:
	if not states.has(state_name):
		GameLog.warn("State '%s' not found in StateMachine" % state_name)
		return
	
	var new_state: State = states[state_name]
	
	if new_state == current_state:
		return
	
	var old_name: String = current_state.name if current_state else "None"
	var new_name: String = new_state.name
	
	current_state.exit()
	current_state = new_state
	current_state.enter(data)
	
	state_changed.emit(old_name, new_name)
	state_entered.emit(new_name)

func get_state_name() -> String:
	return current_state.name if current_state else ""

func has_state(state_name: String) -> bool:
	return states.has(state_name)

func get_current_state() -> State:
	return current_state

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not get_parent() is StateMachine:
		warnings.append("State should be child of StateMachine")
	return warnings
