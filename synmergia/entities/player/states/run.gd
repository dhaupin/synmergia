## Run State - Player is moving
class_name RunState
extends State

var animation_playing: bool = false

func enter(_data: Dictionary = {}) -> void:
	animation_play("run")
	animation_playing = true

func exit() -> void:
	animation_playing = false

func update(_delta: float) -> void:
	var parent := state_machine.get_parent()
	
	# Check for idle (no input)
	if not parent.is_moving() and parent.is_on_floor():
		transition_to("Idle")
	
	# Check for jump
	if Input.is_action_just_pressed("jump") and parent.is_on_floor():
		transition_to("Jump")
	
	# Check for dodge
	if Input.is_action_just_pressed("dodge") and parent.is_on_floor():
		transition_to("Dodge")
	
	# Check for attack
	if Input.is_action_just_pressed("attack"):
		transition_to("Attack")

func physics_update(delta: float) -> void:
	var parent := state_machine.get_parent()
	
	# Get movement direction
	var move_dir := parent.get_movement_direction()
	
	# Calculate speed
	var speed := parent.sprint_speed if parent.is_sprinting else parent.move_speed
	
	# Apply movement
	var target_velocity := move_dir * speed
	parent.velocity.x = lerp(parent.velocity.x, target_velocity.x, 15.0 * delta)
	parent.velocity.z = lerp(parent.velocity.z, target_velocity.z, 15.0 * delta)
	
	# Rotate toward movement direction
	if move_dir.length() > 0.1:
		var target_rotation := atan2(move_dir.x, move_dir.z)
		parent.rotation.y = lerp_angle(parent.rotation.y, target_rotation, 10.0 * delta)

func animation_play(anim_name: String) -> void:
	var parent := state_machine.get_parent()
	if parent.animation_player.has_animation(anim_name):
		parent.animation_player.play(anim_name)
