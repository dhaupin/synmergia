## StateMachineBase - Clean state machine implementation (no class_name to avoid autoload conflicts)
## Replaces the deprecated StateMachine class. Used by player controller.
extends Node

signal state_changed(from: String, to: String)
signal state_entered(state_name: String)
signal state_exited(state_name: String)

@export var initial_state: Node
@export var animateSprite: bool = true

var current_state: Node
var states: Dictionary = {}

func _ready() -> void:
	for child in get_children():
		if child is Node and child.has_method("enter"):
			states[child.name] = child
			child.state_machine = self

	if current_state == null:
		# Scene-declared initial state wins; otherwise prefer Idle, then
		# the first registered state. Scenes that predate initial_state
		# (world_playable's StateMachine had none) used to sit with
		# current_state == null: update()/physics_update() no-oped and
		# the player never responded to input.
		if states.has("Idle"):
			current_state = states["Idle"]
		elif not states.is_empty():
			current_state = states.values()[0]
	if current_state:
		current_state.enter()

func _process(delta: float) -> void:
	if current_state and current_state.has_method("update"):
		current_state.update(delta)

func _physics_process(delta: float) -> void:
	if current_state and current_state.has_method("physics_update"):
		current_state.physics_update(delta)

func transition_to(state_name: String, data: Dictionary = {}) -> void:
	if not states.has(state_name):
		GameLog.warn("State '%s' not found in StateMachine" % state_name)
		return

	var new_state: Node = states[state_name]

	if new_state == current_state:
		return

	var old_name: String = current_state.name if current_state else "None"
	var new_name: String = new_state.name

	if current_state and current_state.has_method("exit"):
		current_state.exit()
	current_state = new_state
	if current_state and current_state.has_method("enter"):
		current_state.enter(data)

	state_changed.emit(old_name, new_name)
	state_entered.emit(new_name)

func get_state_name() -> String:
	return current_state.name if current_state else ""

func has_state(state_name: String) -> bool:
	return states.has(state_name)

func get_current_state() -> Node:
	return current_state
