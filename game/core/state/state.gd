## State - Base state class for the state machine
##
## DEPRECATED: Use StateSchema with type "behavior_state" in T3 state tree instead.
## See game/data/roots/state_schema.gd for the canonical behavior state schema.
## Valid states: "idle", "move", "attack", "interact" with payload {current_state: String, ai_tick_state: int}
## Migration: Replace node-based FSM with StateSchema entries in the content-hash state tree.
## The T3 state tree provides persistence, replication, and content-addressable history.
extends Node
class_name State

const StateMachine = preload("res://core/state/state_machine.gd")
var state_machine: StateMachine

func enter(_data: Dictionary = {}) -> void:
	pass

func exit() -> void:
	pass

func update(_delta: float) -> void:
	pass

func physics_update(_delta: float) -> void:
	pass


## Helper: route a transition through the owning state machine.
## Subclasses call this unqualified; it forwards to state_machine.
func transition_to(state_name: String, data: Dictionary = {}) -> void:
	if state_machine:
		state_machine.transition_to(state_name, data)


## Helper: play an animation on the parent's AnimationPlayer if present.
## If the parent has no AnimationPlayer, the call is a no-op.
func animation_play(anim_name: String) -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var anim: Object = parent.get("animation_player")
	if anim == null:
		anim = parent.get_node_or_null("AnimationPlayer")
	if anim and anim.has_method("has_animation") and anim.has_method("play"):
		if anim.has_animation(anim_name):
			anim.play(anim_name)

## MIGRATION GUIDE: Legacy FSM -> StateSchema (behavior_state)
##
## OLD (node-based FSM):
##   - extends State
##   - StateMachine node with child State nodes
##   - transition_to() calls for state changes
##   - State stored in scene tree, not persisted
##
## NEW (StateSchema in T3 state tree):
##   - Use StateSchema resource with type = "behavior_state"
##   - Payload: {"current_state": "idle"|"move"|"attack"|"interact", "ai_tick_state": int}
##   - Entity behavior state stored in FrameService state tree
##   - Access via FrameService.get_state(entity_id, "behavior_state")
##   - Update via FrameService.set_state(entity_id, StateSchema, payload)
##   - Persists across sessions, replicates to clients, content-hash history
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
## Do NOT write new code using extends State or StateMachine.
## This file is kept for existing player controller states only.
