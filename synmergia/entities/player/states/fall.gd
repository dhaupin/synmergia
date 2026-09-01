## Fall State - Player is falling
class_name FallState
extends State

var has_dodged_air: bool = false

func enter(_data: Dictionary = {}) -> void:
	has_dodged_air = true if state_machine.get_parent().is_invincible else false
	animation_play("fall")

func exit() -> void:
	has_dodged_air = false

func update(_delta: float) -> void:
	var parent := state_machine.get_parent()
	
	# Air attack
	if Input.is_action_just_pressed("attack") and parent.is_on_floor() == false:
		transition_to("AirAttack")
	
	# Air dodge (can dodge again in air if not already used)
	if Input.is_action_just_pressed("dodge") and parent.can_air_dodge and not has_dodged_air:
		transition_to("AirDodge")

func physics_update(delta: float) -> void:
	var parent := state_machine.get_parent()
	
	# Air control
	var move_dir: Vector3 = parent.get_movement_direction()
	var air_control := 0.5
	
	if move_dir.length() > 0:
		parent.velocity.x += move_dir.x * parent.move_speed * air_control * delta
		parent.velocity.z += move_dir.z * parent.move_speed * air_control * delta
	
	# Check for landing
	if parent.is_on_floor() and parent.velocity.y <= 0:
		transition_to("Land")

func animation_play(anim_name: String) -> void:
	var parent := state_machine.get_parent()
	if parent.animation_player.has_animation(anim_name):
		parent.animation_player.play(anim_name)
