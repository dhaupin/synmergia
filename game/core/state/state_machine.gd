## StateMachine - Generic state machine for game entities
## Handles state transitions and calls enter/exit/update
##
## DEPRECATED: Use StateSchema with type "behavior_state" in T3 state tree instead.
## See game/data/roots/state_schema.gd for the canonical behavior state schema.
## Valid states: "idle", "move", "attack", "interact" with payload {current_state: String, ai_tick_state: int}
## Migration: Replace node-based FSM with StateSchema entries in the content-hash state tree.
## The T3 state tree provides persistence, replication, and content-addressable history.
extends Node
class_name StateMachine

const State = preload("res://core/state/state.gd")

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

## MIGRATION GUIDE: Legacy FSM -> StateSchema (behavior_state)
##
## OLD (node-based FSM):
##   - StateMachine node with child State nodes (idle, move, attack, etc.)
##   - _ready() discovers child states via get_children()
##   - transition_to(state_name, data) for state changes
##   - Signals: state_changed, state_entered, state_exited
##   - State stored in scene tree, not persisted across sessions
##   - PlayerController uses $StateMachine node reference
##
## NEW (StateSchema in T3 state tree):
##   - Use StateSchema resource with type = "behavior_state"
##   - Payload: {"current_state": "idle"|"move"|"attack"|"interact", "ai_tick_state": int}
##   - Entity behavior state stored in FrameService state tree (T3 content-hash tree)
##   - Access via FrameService.get_state(entity_id, "behavior_state")
##   - Update via FrameService.set_state(entity_id, StateSchema, payload)
##   - Persists across sessions, replicates to clients, content-hash history
##   - Frame primitives in game/core/frame/ (no autoload, no GameManager dep)
##
## Example payload:
##   {
##     "type": "behavior_state",
##     "entity_id": "player_123",
##     "payload": {
##       "current_state": "move",
##       "ai_tick_state": 42
##     }
##   }
##
## Integration with FrameService:
##   var frame_svc := FrameService
##   var state_schema := preload("res://data/roots/state_schema.gd").new()
##   state_schema.type = "behavior_state"
##   var payload = {"current_state": "idle", "ai_tick_state": 0}
##   frame_svc.set_state(entity_id, state_schema, payload)
##
## Do NOT write new code using StateMachine or extends State.
## This file is kept for existing player controller only (game/entities/player/player_controller.gd).
## New entity behavior should use StateSchema.behavior_state in the T3 state tree.
