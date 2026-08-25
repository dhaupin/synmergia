## PlayerController - Main player character controller
## Handles movement, combat, and input for the player character
class_name PlayerController
extends CharacterBody3D

@export var move_speed: float = 5.0
@export var sprint_speed: float = 7.5
@export var jump_force: float = 10.0
@export var gravity_force: float = 20.0
@export var dodge_force: float = 4.0
@export var dodge_cost: float = 25.0
@export var dodge_cooldown: float = 1.5
@export var attack_range: float = 2.5

@export var ground_acceleration: float = 20.0
@export var air_acceleration: float = 5.0
@export var ground_friction: float = 10.0

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var state_machine: StateMachine = $StateMachine
@onready var camera_pivot: Node3D = $CameraPivot
@onready var attack_hitbox: Area3D = $AttackHitbox

var target: Node3D = null
var can_dodge: bool = true
var is_sprinting: bool = false
var is_attacking: bool = false
var is_targeting: bool = false

# Movement state
var input_direction: Vector3 = Vector3.ZERO
var target_velocity: Vector3 = Vector3.ZERO

# For multiplayer
var player_id: int = 1
var is_local_player: bool = true

func _ready() -> void:
	# Connect to input manager
	InputManager.player_input.connect(_on_player_input)
	PlayerManager.set_local_player(self)
	
	# Set collision
	collision_mask = 0b0000111  # World layers
	collision_layer = 0b0000001  # Player layer
	
	Logger.info("PlayerController ready")

func _physics_process(delta: float) -> void:
	if not is_local_player:
		return
	
	# Get input
	input_direction = _get_movement_input()
	
	# Apply movement
	_apply_movement(delta)
	
	# Move
	move_and_slide()

func _get_movement_input() -> Vector3:
	var input := InputManager.get_movement_input()
	
	# Convert screen input to world direction relative to camera
	var cam_basis := get_camera_basis()
	var forward := -cam_basis.z
	var right := cam_basis.x
	
	# Remove Y component and normalize
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

func _apply_movement(delta: float) -> void:
	var speed := sprint_speed if is_sprinting else move_speed
	
	# Calculate target velocity
	target_velocity.x = input_direction.x * speed
	target_velocity.z = input_direction.z * speed
	
	# Smooth acceleration/deceleration
	var acceleration := ground_acceleration if is_on_floor() else air_acceleration
	
	velocity.x = lerp(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = lerp(velocity.z, target_velocity.z, acceleration * delta)
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity_force * delta

func _on_player_input(action: String, pressed: bool) -> void:
	if not is_local_player:
		return
	
	match action:
		"jump":
			if pressed and is_on_floor():
				_jump()
		"sprint":
			is_sprinting = pressed
		"dodge":
			if pressed:
				_dodge()
		"attack":
			if pressed and not is_attacking:
				_attack()
		"target_next":
			if pressed:
				cycle_target()

func _jump() -> void:
	velocity.y = jump_force
	animation_player.play("jump") if animation_player.has_animation("jump") else null

func _dodge() -> void:
	if not can_dodge or not is_on_floor():
		return
	
	if not PlayerManager.use_stamina(dodge_cost):
		return
	
	can_dodge = false
	
	# Dodge in movement direction or forward if stationary
	var dodge_dir := input_direction
	if dodge_dir == Vector3.ZERO:
		dodge_dir = -global_transform.basis.z
	
	dodge_dir.y = 0
	dodge_dir = dodge_dir.normalized()
	
	velocity = dodge_dir * dodge_force
	velocity.y = jump_force * 0.5
	
	state_machine.transition_to("Dodge")
	
	await get_tree().create_timer(dodge_cooldown).timeout
	can_dodge = true

func _attack() -> void:
	if is_attacking:
		return
	
	is_attacking = true
	state_machine.transition_to("Attack")
	
	# Animation handled by state
	
	await get_tree().create_timer(0.5).timeout
	is_attacking = false

func cycle_target(previous: bool = false) -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		target = null
		return
	
	# Sort by distance
	enemies.sort_custom(func(a, b): 
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
	)
	
	var current_idx := enemies.find(target) if target in enemies else -1
	var next_idx := (current_idx + 1) % enemies.size() if not previous else (current_idx - 1 + enemies.size()) % enemies.size()
	
	target = enemies[next_idx]
	is_targeting = true

func clear_target() -> void:
	target = null
	is_targeting = false

func get_look_direction() -> Vector3:
	if is_targeting and target:
		return (target.global_position - global_position).normalized()
	return -camera_pivot.global_transform.basis.z if camera_pivot else Vector3.ZERO

## Multiplayer replication

@rpc("call_local")
func receive_position(pos: Vector3, rot: float) -> void:
	if is_local_player:
		return
	# Smooth interpolation for other players
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
