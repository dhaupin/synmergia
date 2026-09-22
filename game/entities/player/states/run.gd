## Run State - Player is moving
extends "res://core/state/state_base.gd"
class_name RunState

const AIR_CONTROL := 0.3  # matches jump.gd's in-air steering

var animation_playing: bool = false

func enter(_data: Dictionary = {}) -> void:
	animation_play("run")
	animation_playing = true

func exit() -> void:
	animation_playing = false

func update(_delta: float) -> void:
	var parent: PlayerController = state_machine.get_parent()

	# Ran off a ledge: hand control to Fall so gravity and the landing
	# states take over. Without this guard Run held the player in
	# mid-air forever (its dodge/jump/crouch branches are all
	# floor-gated) after stepping off the playable floor's edge.
	if not parent.is_on_floor():
		transition_to("Fall")
		return

	# Check for idle (no input)
	if not parent.is_moving():
		transition_to("Idle")
		return

	# Crouch on the ground -> crouch-walk
	if Input.is_action_just_pressed("crouch") and parent.is_on_floor():
		transition_to("Crouch")
		return

	# Check for jump
	if Input.is_action_just_pressed("jump") and parent.is_on_floor():
		transition_to("Jump")
		return

	# COD-style slide: sprinting + dodge input throws the player into
	# a crouched slide that carries the sprint momentum.
	if Input.is_action_just_pressed("dodge") and parent.is_on_floor():
		if parent.is_sprinting:
			transition_to("Slide")
		else:
			transition_to("Dodge")
		return

	# Check for attack
	if Input.is_action_just_pressed("attack"):
		transition_to("Attack")
		return

func physics_update(delta: float) -> void:
	var parent: PlayerController = state_machine.get_parent()

	# Airborne continuation (stepped off a ledge): mild air control
	# instead of the ground-speed lerp, mirroring the Jump state.
	if not parent.is_on_floor():
		var air_dir: Vector3 = parent.get_movement_direction()
		if air_dir.length() > 0:
			parent.velocity.x += air_dir.x * parent.move_speed * AIR_CONTROL * delta
			parent.velocity.z += air_dir.z * parent.move_speed * AIR_CONTROL * delta
		return

	# Get movement direction
	var move_dir: Vector3 = parent.get_movement_direction()

	# Calculate speed (crouch handled by its own state)
	var speed: float = parent.sprint_speed if parent.is_sprinting else parent.move_speed

	# Apply movement
	var target_velocity: Vector3 = move_dir * speed
	parent.velocity.x = lerp(parent.velocity.x, target_velocity.x, 15.0 * delta)
	parent.velocity.z = lerp(parent.velocity.z, target_velocity.z, 15.0 * delta)

	# Rotate toward movement direction
	if move_dir.length() > 0.1:
		var target_rotation := atan2(move_dir.x, move_dir.z)
		parent.rotation.y = lerp_angle(parent.rotation.y, target_rotation, 10.0 * delta)

func animation_play(anim_name: String) -> void:
	var parent: PlayerController = state_machine.get_parent()
	if parent.animation_player.has_animation(anim_name):
		parent.animation_player.play(anim_name)
