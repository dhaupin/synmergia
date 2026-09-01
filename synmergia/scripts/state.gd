## State - Base state class for the state machine
class_name State
extends Node

const StateMachine = preload("res://scripts/state_machine.gd")
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
