## Attack State - Free-form combat (RYL2-style)
## Player can move, jump, and use skills during combat
extends Node

const StateBase = preload("res://core/state/state_base.gd")
class_name AttackState
const Skill = preload("res://core/combat/skill.gd")


const BASE_ATTACK_DURATION: float = 0.4

var current_skill: Skill = null
var attack_timer: float = 0.0
var is_attacking: bool = false
var can_move_during_attack: bool = true  # Free-form combat allows movement
var can_jump_during_attack: bool = true
var has_initiated: bool = false

signal attack_initiated(skill: Skill)
signal attack_hit(target: Node3D, damage: int)
signal attack_finished()

func enter(_data: Dictionary = {}) -> void:
	var parent := state_machine.get_parent()

	# Check if a skill was passed
	if _data.has("skill"):
		current_skill = _data["skill"]
	else:
		# Use basic attack
		current_skill = parent.basic_attack

	if current_skill:
		_setup_skill(current_skill)
	else:
		_setup_basic_attack()

	has_initiated = false
	is_attacking = false

func _setup_skill(skill: Skill) -> void:
	attack_timer = skill.cast_time if skill.is_ground_targeted else skill.animation_duration
	can_move_during_attack = skill.allow_movement
	can_jump_during_attack = skill.allow_movement
	is_attacking = false

func _setup_basic_attack() -> void:
	attack_timer = BASE_ATTACK_DURATION
	can_move_during_attack = true  # RYL2-style: always can move
	can_jump_during_attack = true
	is_attacking = false

func exit() -> void:
	var parent := state_machine.get_parent()
	parent.is_attacking = false
	current_skill = null
	is_attacking = false
	has_initiated = false

func update(delta: float) -> void:
	attack_timer -= delta

	var parent := state_machine.get_parent()

	# Handle attack initiation
	if not has_initiated and attack_timer <= get_attack_start_time():
		_initiate_attack()

	# Check for cancel window (movement can interrupt in cancel window)
	if attack_timer <= 0:
		_finish_attack()

func _physics_process(delta: float) -> void:
	var parent := state_machine.get_parent()

	# Allow movement during attack if permitted
	if can_move_during_attack:
		_handle_movement_during_attack(delta)

	# Allow jumping during attack if permitted
	if can_jump_during_attack and Input.is_action_just_pressed("jump"):
		transition_to("Jump")

	# Allow dodging during attack
	if Input.is_action_just_pressed("dodge"):
		transition_to("Dodge")

func _handle_movement_during_attack(_delta: float) -> void:
	var parent := state_machine.get_parent()
	var move_dir := parent.get_movement_direction()

	if move_dir.length() > 0.1:
		# Slow movement during attack (70% speed)
		var speed := parent.move_speed * 0.7
		parent.velocity.x = lerp(parent.velocity.x, move_dir.x * speed, 8.0 * _delta)
		parent.velocity.z = lerp(parent.velocity.z, move_dir.z * speed, 8.0 * _delta)

func _initiate_attack() -> void:
	if has_initiated:
		return
	has_initiated = true
	is_attacking = true

	var parent := state_machine.get_parent()
	parent.is_attacking = true

	# Play attack animation
	animation_play(get_attack_animation_name())

	# Emit signal
	attack_initiated.emit(current_skill)

	# If ground-targeted skill, handle targeting
	if current_skill and current_skill.is_ground_targeted:
		_execute_ground_targeted_skill()
	else:
		# Execute immediate attack
		_execute_immediate_attack()

func _execute_immediate_attack() -> void:
	var parent := state_machine.get_parent()

	# Create hitbox
	if current_skill and current_skill.hitbox_size > 0:
		parent.create_hitbox(current_skill)

func _execute_ground_targeted_skill() -> void:
	# Ground-targeted AoE skill - player chooses location
	var parent := state_machine.get_parent()

	# Lock movement during cast (but can still rotate)
	can_move_during_attack = false
	can_jump_during_attack = false

	# Show AoE indicator
	parent.show_aoe_indicator(current_skill)

func get_attack_start_time() -> float:
	if current_skill:
		return current_skill.animation_duration * 0.7  # Hit at 70% through animation
	return BASE_ATTACK_DURATION * 0.5  # Basic attack hits at 50%

func get_attack_animation_name() -> String:
	if current_skill:
		return "attack_" + current_skill.animation_name
	return "attack"

func _finish_attack() -> void:
	var parent := state_machine.get_parent()

	# Clean up
	if current_skill and current_skill.is_ground_targeted:
		parent.hide_aoe_indicator()

	attack_finished.emit()

	# Return to movement state
	if parent.is_on_floor():
		if parent.is_moving():
			transition_to("Run")
		else:
			transition_to("Idle")
	else:
		transition_to("Fall")

func animation_play(anim_name: String) -> void:
	var parent := state_machine.get_parent()
	if parent.animation_player.has_animation(anim_name):
		parent.animation_player.play(anim_name)
