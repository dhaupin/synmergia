## AirAttack State - Mid-air attack with damage bonus
extends State

const State = preload("res://core/state/state.gd")
class_name AirAttackState

var attack_timer: float = 0.0
var has_hit: bool = false
var is_ground_target: bool = false

func enter(_data: Dictionary = {}) -> void:
	attack_timer = 0.35
	has_hit = false
	
	animation_play("air_attack")

func exit() -> void:
	has_hit = false

func update(delta: float) -> void:
	attack_timer -= delta
	
	var parent := state_machine.get_parent()
	
	# Allow air dodge during attack
	if Input.is_action_just_pressed("dodge"):
		transition_to("AirDodge")

func physics_process(delta: float) -> void:
	var parent := state_machine.get_parent()
	
	# Continue falling during attack
	if parent.velocity.y > -5:
		parent.velocity.y = lerp(parent.velocity.y, -10.0, delta * 5)
	
	# Check for landing
	if parent.is_on_floor() and attack_timer <= 0:
		transition_to("Land")
	
	# Hit detection at peak of attack
	if not has_hit and attack_timer <= 0.2:
		has_hit = true
		execute_air_attack()

func execute_air_attack() -> void:
	var parent := state_machine.get_parent()
	
	# Create hitbox in front of player
	var forward := -parent.global_transform.basis.z
	var hit_position := parent.global_position + forward * 1.5
	
	# Find enemies in range
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy is Entity and enemy.global_position.distance_to(hit_position) < 2.0:
			if enemy.is_alive():
				# Air attacks deal bonus damage
				var damage := int(parent.get_attack_power() * 1.3)  # 30% bonus damage
				enemy.take_damage(damage, parent)

func animation_play(anim_name: String) -> void:
	var parent := state_machine.get_parent()
	if parent.animation_player.has_animation(anim_name):
		parent.animation_player.play(anim_name)
