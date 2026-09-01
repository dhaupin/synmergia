## Jump State - Player is airborne
class_name JumpState
extends State

var has_jumped: bool = false

func enter(_data: Dictionary = {}) -> void:
	has_jumped = false
	animation_play("jump")

func exit() -> void:
	has_jumped = false

func update(_delta: float) -> void:
	var parent := state_machine.get_parent()
	
	# Jump initiation
	if not has_jumped and parent.velocity.y > 0:
		has_jumped = true
	
	# Check for air dodge
	if Input.is_action_just_pressed("dodge") and parent.can_air_dodge:
		transition_to("AirDodge")
	
	# Check for air attack
	if Input.is_action_just_pressed("attack") and has_jumped:
		transition_to("AirAttack")
	
	# Check for landing
	if parent.is_on_floor():
		transition_to("Land")

func physics_update(delta: float) -> void:
	var parent := state_machine.get_parent()
	
	# Allow some air control
	var move_dir: Vector3 = parent.get_movement_direction()
	var air_control := 0.3  # 30% control in air
	
	if move_dir.length() > 0:
		parent.velocity.x += move_dir.x * parent.move_speed * air_control * delta
		parent.velocity.z += move_dir.z * parent.move_speed * air_control * delta
	
	# Keep forward momentum from jump
	# Gravity is handled by parent

func animation_play(anim_name: String) -> void:
	var parent := state_machine.get_parent()
	if parent.animation_player.has_animation(anim_name):
		parent.animation_player.play(anim_name)
