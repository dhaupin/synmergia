## Land State - Brief landing recovery
extends Node

const StateBase = preload("res://core/state/state_base.gd")
class_name LandState

const DURATION: float = 0.15

var elapsed: float = 0.0

func enter(_data: Dictionary = {}) -> void:
	elapsed = 0.0
	animation_play("land")

	# Reduce fall velocity
	var parent: PlayerController = state_machine.get_parent()
	parent.velocity.y = 0

func exit() -> void:
	pass

func update(delta: float) -> void:
	elapsed += delta

	if elapsed >= DURATION:
		transition_to("Idle")

func physics_update(_delta: float) -> void:
	var parent: PlayerController = state_machine.get_parent()

	# Quick friction on landing
	parent.velocity.x = lerp(parent.velocity.x, 0, 20.0 * _delta)
	parent.velocity.z = lerp(parent.velocity.z, 0, 20.0 * _delta)

func animation_play(anim_name: String) -> void:
	var parent: PlayerController = state_machine.get_parent()
	if parent.animation_player.has_animation(anim_name):
		parent.animation_player.play(anim_name)
