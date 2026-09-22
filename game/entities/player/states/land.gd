## Land State - Brief landing recovery
extends "res://core/state/state_base.gd"

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

func update(_delta: float) -> void:
	# Input buffering: a press during the landing recovery must not be
	# swallowed by the 0.15 s timer (previously the just_pressed edge
	# expired before Idle/Run could see it, dropping taps entirely).
	# Reacting immediately cancels the recovery, which matches the
	# responsive COD-style feel.
	if Input.is_action_just_pressed("jump"):
		transition_to("Jump")
		return
	if Input.is_action_just_pressed("attack"):
		transition_to("Attack")
		return
	if Input.is_action_just_pressed("dodge"):
		transition_to("Dodge")
		return
	if Input.is_action_just_pressed("crouch"):
		transition_to("Crouch")
		return

	elapsed += _delta

	if elapsed >= DURATION:
		transition_to("Idle")

func physics_update(_delta: float) -> void:
	var parent: PlayerController = state_machine.get_parent()

	# Quick friction on landing
	parent.velocity.x = lerp(parent.velocity.x, 0.0, 20.0 * _delta)
	parent.velocity.z = lerp(parent.velocity.z, 0.0, 20.0 * _delta)

func animation_play(anim_name: String) -> void:
	var parent: PlayerController = state_machine.get_parent()
	if parent.animation_player.has_animation(anim_name):
		parent.animation_player.play(anim_name)
