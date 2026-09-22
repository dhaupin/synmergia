## Idle State - Player is standing still
extends "res://core/state/state_base.gd"
class_name IdleState

var idle_timer: float = 0.0

func enter(_data: Dictionary = {}) -> void:
	animation_play("idle")
	idle_timer = 0.0

func exit() -> void:
	pass

func update(delta: float) -> void:
	idle_timer += delta

	# Check for movement
	if state_machine.get_parent().is_moving():
		transition_to("Run")

	# Check for crouch (touch CRH hold and keyboard C both land here)
	if Input.is_action_just_pressed("crouch") and state_machine.get_parent().is_on_floor():
		transition_to("Crouch")
		return

	# Check for attack (standing attack: basic swings from rest)
	if Input.is_action_just_pressed("attack"):
		transition_to("Attack")
		return

	# Check for jump
	if Input.is_action_just_pressed("jump") and state_machine.get_parent().is_on_floor():
		transition_to("Jump")

func physics_update(_delta: float) -> void:
	# Apply friction when idle
	var parent: PlayerController = state_machine.get_parent()
	if parent.velocity.length() > 0.1:
		parent.velocity.x = lerp(parent.velocity.x, 0.0, 10.0 * _delta)
		parent.velocity.z = lerp(parent.velocity.z, 0.0, 10.0 * _delta)
