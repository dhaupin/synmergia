## PlayerController - Main player character controller
## Free-form combat system (RYL2-style)
class_name PlayerController
extends CharacterBody3D

# Movement
@export var move_speed: float = 5.0
@export var sprint_speed: float = 7.5
@export var air_dodge_force: float = 6.0  # Stronger air dodge
@export var jump_force: float = 10.0
@export var gravity_force: float = 20.0
@export var dodge_force: float = 4.5
@export var dodge_cost: float = 25.0
@export var dodge_cooldown: float = 1.5

# Combat
@export var basic_attack: Skill = null
@export var skillbar: Array[Skill] = []
@export var attack_range: float = 2.5

# State
@export var can_air_dodge: bool = true
var is_invincible: bool = false
var is_attacking: bool = false
var is_sprinting: bool = false
var is_targeting: bool = false
var current_target: Node3D = null

# Components
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var state_machine: StateMachine = $StateMachine
@onready var camera_pivot: Node3D = $CameraPivot

# Multiplayer
var player_id: int = 1
var is_local_player: bool = true

func _ready() -> void:
	# Connect to input
	InputManager.player_input.connect(_on_player_input)
	PlayerManager.set_local_player(self)
	
	# Set collision
	collision_mask = 0b0000111
	collision_layer = 0b0000001
	
	# Initialize basic attack if null
	if basic_attack == null:
		basic_attack = _create_basic_attack()
	
	Logger.info("PlayerController ready")

func _create_basic_attack() -> Skill:
	var skill := Skill.new()
	skill.skill_name = "Strike"
	skill.skill_id = "strike"
	skill.skill_type = Skill.SkillType.MELEE
	skill.damage = 20
	skill.mana_cost = 0
	skill.cast_time = 0.0
	skill.cooldown = 1.0
	skill.animation_duration = 0.4
	skill.range = 2.5
	skill.hitbox_size = 1.5
	skill.allow_movement = true
	skill.allow_jumping = true
	skill.combo_chain = ["heavy_strike"]
	return skill

func _physics_process(delta: float) -> void:
	if not is_local_player:
		return
	
	# QoS: Rate limit movement
	if QoSService.rate_limit(entity_id, "movement"):
		move_and_slide()
	else:
		Logger.debug("PlayerController: Rate limited movement for %s" % entity_id)

func is_moving() -> bool:
	var input := InputManager.get_movement_input()
	return input.length() > 0.1

func get_movement_direction() -> Vector3:
	var input := InputManager.get_movement_input()
	var cam_basis := get_camera_basis()
	
	var forward := -cam_basis.z
	var right := cam_basis.x
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()
	
	var direction := (forward * input.y + right * input.x)
	return direction.normalized() if direction.length() > 0 else Vector3.ZERO

func get_camera_basis() -> Basis:
	if camera_pivot and camera_pivot.get_child_count() > 0:
		var cam = camera_pivot.get_child(0)
		if cam is Camera3D:
			return cam.global_transform.basis
	return Transform3D().basis

func _on_player_input(action: String, pressed: bool) -> void:
	if not is_local_player:
		return
	
	match action:
		"sprint":
			is_sprinting = pressed
		"target_next":
			if pressed:
				cycle_target()

## SKILL SYSTEM

func use_skill(slot: int) -> void:
	if slot < 0 or slot >= skillbar.size():
		return
	
	var skill: Skill = skillbar[slot]
	if skill and skill.can_cast(self):
		# Check if ground targeted
		if skill.is_ground_targeted:
			var ground_pos := _get_ground_target_position(skill.ground_target_range)
			CombatSystem.execute_skill(self, skill, null, ground_pos)
		else:
			CombatSystem.execute_skill(self, skill, current_target)

func _get_ground_target_position(max_range: float) -> Vector3:
	var direction := InputManager.last_direction
	if direction == Vector2.ZERO:
		direction = Vector2(0, -1)  # Default forward
	
	return CombatSystem.get_ground_target_position(self, direction, max_range)

## TARGETING

func cycle_target(previous: bool = false) -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		current_target = null
		is_targeting = false
		return
	
	# Sort by distance
	enemies.sort_custom(func(a, b): 
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
	)
	
	var current_idx := enemies.find(current_target) if current_target in enemies else -1
	var next_idx := (current_idx + 1) % enemies.size() if not previous else (current_idx - 1 + enemies.size()) % enemies.size()
	
	current_target = enemies[next_idx]
	is_targeting = true

func clear_target() -> void:
	current_target = null
	is_targeting = false

## HITBOX & COMBAT

func create_hitbox(skill: Skill, target: Entity = null, ground_pos: Vector3 = Vector3.ZERO) -> void:
	CombatSystem.create_hitbox(self, skill, target, ground_pos)

func show_aoe_indicator(skill: Skill) -> void:
	# Visual indicator for ground-targeted AoE
	# Will be implemented with UI/VFX
	pass

func hide_aoe_indicator() -> void:
	pass

## STATE HELPERS

func get_look_direction() -> Vector3:
	if is_targeting and current_target:
		return (current_target.global_position - global_position).normalized()
	return -camera_pivot.global_transform.basis.z if camera_pivot else Vector3.ZERO

## MULTIPLAYER

@rpc("call_local")
func receive_position(pos: Vector3, rot: float) -> void:
	if is_local_player:
		return
	global_position = global_position.lerp(pos, 0.3)
	rotation.y = rot

@rpc("call_local")
func receive_animation(anim_name: String) -> void:
	if animation_player and animation_player.has_animation(anim_name):
		animation_player.play(anim_name)

func get_network_state() -> Dictionary:
	return {
		"position": global_position,
		"rotation": rotation.y,
		"velocity": velocity,
		"state": state_machine.get_state_name()
	}