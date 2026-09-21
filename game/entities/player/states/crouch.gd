## Crouch State - Low-profile stance. Walks at crouch_speed, disables
## sprint. Exits to Idle when the crouch input is released, or to
## Run when the player moves without holding crouch (tap-to-uncrouch
## on mobile: standing up while moving resumes the normal gait).
extends "res://core/state/state_base.gd"
class_name CrouchState

func enter(_data: Dictionary = {}) -> void:
	var parent: PlayerController = state_machine.get_parent()
	parent.is_crouching = true
	parent.is_sprinting = false
	animation_play("crouch")

func exit() -> void:
	var parent: PlayerController = state_machine.get_parent()
	parent.is_crouching = false

func update(_delta: float) -> void:
	var parent: PlayerController = state_machine.get_parent()

	# Release crouch input -> stand up (idle if not moving).
	if not Input.is_action_pressed("crouch") and not Input.is_action_pressed("dodge"):
		if parent.is_moving():
			transition_to("Run")
		else:
			transition_to("Idle")
		return

	# Jump while crouched stands up into the jump.
	if Input.is_action_just_pressed("jump") and parent.is_on_floor():
		transition_to("Jump")
		return

	if Input.is_action_just_pressed("attack"):
		transition_to("Attack")
		return

func physics_update(delta: float) -> void:
	var parent: PlayerController = state_machine.get_parent()
	if not parent.is_on_floor():
		transition_to("Fall")
		return

	var move_dir: Vector3 = parent.get_movement_direction()

	# Slow crouch-walk.
	parent.velocity.x = lerp(parent.velocity.x, move_dir.x * parent.crouch_speed, 12.0 * delta)
	parent.velocity.z = lerp(parent.velocity.z, move_dir.z * parent.crouch_speed, 12.0 * delta)

	# Rotate toward movement direction.
	if move_dir.length() > 0.1:
		var target_rotation := atan2(move_dir.x, move_dir.z)
		parent.rotation.y = lerp_angle(parent.rotation.y, target_rotation, 8.0 * delta)
