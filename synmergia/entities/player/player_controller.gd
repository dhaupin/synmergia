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
	
	# Register with TargetingManager
	TargetingManager.register_targetable(
		entity_id,
		"player",
		self,
		name,
		global_position,
		Entity.EntityType.PLAYER
	)
	
	# Set local player for TargetingManager
	TargetingManager.set_local_player(entity_id)
	
	# Connect to InteractionLayer for touch targeting
	_connect_interaction_layer()
	
	GameLogger.info("PlayerController ready")

func _connect_interaction_layer() -> void:
	if InteractionLayer:
		InteractionLayer.tap.connect(_on_interaction_tap)
		InteractionLayer.double_tap.connect(_on_interaction_double_tap)
		InteractionLayer.long_press.connect(_on_interaction_long_press)
		InteractionLayer.action_triggered.connect(_on_interaction_action)

## Handle tap (touch) - target entity
func _on_interaction_tap(position: Vector2) -> void:
	if not is_local_player:
		return
	
	# Only handle taps on right side of screen (for movement)
	var viewport_size := get_viewport_rect().size
	if position.x < viewport_size.x * 0.3:
		return  # Left side is movement joystick
	
	_handle_left_click(position)

## Handle double tap - quick target
func _on_interaction_double_tap(position: Vector2) -> void:
	if not is_local_player:
		return
	
	# Quick target nearest enemy
	_find_and_set_nearest_target()

## Handle long press - context menu
func _on_interaction_long_press(position: Vector2) -> void:
	if not is_local_player:
		return
	
	# Raycast to find target
	var camera := _get_camera()
	if camera:
		var target_info := TargetingManager.raycast_from_touch(position, camera)
		if target_info:
			_show_target_context_menu(target_info)

## Handle action triggers from InteractionLayer
func _on_interaction_action(action_name: String) -> void:
	if not is_local_player:
		return
	
	match action_name:
		"target_next":
			cycle_target()
		"target_prev":
			cycle_target_previous()
		"focus":
			# Focus on current target
			pass
		"target_self":
			_target_self()
		"cancel":
			clear_target()

## Target self
func _target_self() -> void:
	TargetingManager.set_target(
		entity_id,
		"player",
		name,
		global_position,
		self,
		Entity.EntityType.PLAYER
	)
	is_targeting = false  # Self-target doesn't enable targeting mode

## Show target context menu
func _show_target_context_menu(target_info: TargetingManager.TargetInfo) -> void:
	match target_info.entity_type:
		Entity.EntityType.PLAYER:
			_show_player_context_menu(target_info)
		Entity.EntityType.NPC:
			_show_npc_context_menu(target_info)
		Entity.EntityType.LOOT:
			_show_loot_context_menu(target_info)
		Entity.EntityType.TELEPORT:
			_show_gateway_context_menu(target_info)

func _show_npc_context_menu(target_info: TargetingManager.TargetInfo) -> void:
	# Show NPC interaction menu (talk, trade, etc.)
	pass

func _show_loot_context_menu(target_info: TargetingManager.TargetInfo) -> void:
	# Show loot interaction (loot, pass)
	pass

func _show_gateway_context_menu(target_info: TargetingManager.TargetInfo) -> void:
	# Show gateway interaction (enter, cancel)
	pass

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
		GameLogger.debug("PlayerController: Rate limited movement for %s" % entity_id)

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
		"target_previous":
			if pressed:
				cycle_target_previous()

## Cycle to next target (Tab)
func cycle_target() -> void:
	var camera := _get_camera()
	if not camera:
		return
	
	# Raycast in look direction to find targetable
	var look_dir := -camera.global_transform.basis.z
	var target_info := TargetingManager.get_target_in_direction(global_position, look_dir, 50.0)
	
	if target_info:
		TargetingManager.set_target(
			target_info.id,
			target_info.schema_id,
			target_info.display_name,
			target_info.world_position,
			target_info.node,
			target_info.entity_type
		)
		is_targeting = true
	else:
		# Find nearest targetable if raycast didn't hit
		_find_and_set_nearest_target()

## Cycle to previous target (Shift+Tab)
func cycle_target_previous() -> void:
	TargetingManager.restore_previous()

func _find_and_set_nearest_target() -> void:
	# Get all enemies and find nearest
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return
	
	# Sort by distance
	enemies.sort_custom(func(a, b): 
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
	)
	
	# Target nearest
	var nearest = enemies[0]
	if nearest.has("entity_id"):
		TargetingManager.set_target(
			nearest.entity_id,
			"enemy",
			nearest.get("display_name", "Enemy"),
			nearest.global_position,
			nearest,
			Entity.EntityType.ENEMY
		)
		is_targeting = true

## SKILL SYSTEM

func use_skill(slot: int) -> void:
	if slot < 0 or slot >= skillbar.size():
		return
	
	var skill: Skill = skillbar[slot]
	if skill and skill.can_cast(self):
		# Get target from TargetingManager
		var target: Node = null
		var target_info := TargetingManager.get_current_target()
		if target_info:
			target = target_info.node
		
		# Check if ground targeted
		if skill.is_ground_targeted:
			var ground_pos := _get_ground_target_position(skill.ground_target_range)
			CombatSystem.execute_skill(self, skill, null, ground_pos)
		else:
			CombatSystem.execute_skill(self, skill, target as Entity)

func _get_ground_target_position(max_range: float) -> Vector3:
	var direction := InputManager.last_direction
	if direction == Vector2.ZERO:
		direction = Vector2(0, -1)  # Default forward
	
	return CombatSystem.get_ground_target_position(self, direction, max_range)

## TARGETING

func _unhandled_input(event: InputEvent) -> void:
	if not is_local_player:
		return
	
	# Left click - target entity
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(event.position)
		# Right click - clear target or context menu
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click()
	
	# Escape - clear target
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			clear_target()

func _handle_left_click(screen_pos: Vector2) -> void:
	var camera := _get_camera()
	if not camera:
		return
	
	# Raycast from camera
	var target_info := TargetingManager.raycast_from_camera(screen_pos, camera)
	
	if target_info:
		# Target the entity
		TargetingManager.set_target(
			target_info.id,
			target_info.schema_id,
			target_info.display_name,
			target_info.world_position,
			target_info.node,
			target_info.entity_type
		)
		is_targeting = true
		
		# Show tooltip if applicable
		_show_target_tooltip(target_info)
	else:
		# Clicked on nothing - clear target if not clicking on UI
		if not _is_click_on_ui(screen_pos):
			clear_target()

func _handle_right_click() -> void:
	# Right click while targeting opens context menu or clears target
	if TargetingManager.has_target():
		var target := TargetingManager.get_current_target()
		if target and target.entity_type == Entity.EntityType.PLAYER:
			_show_player_context_menu(target)

func clear_target() -> void:
	TargetingManager.clear_target()
	is_targeting = false
	_hide_target_tooltip()

func _get_camera() -> Camera3D:
	if camera_pivot and camera_pivot.get_child_count() > 0:
		var cam = camera_pivot.get_child(0)
		if cam is Camera3D:
			return cam
	return null

func _is_click_on_ui(screen_pos: Vector2) -> bool:
	var tree := get_tree()
	if not tree:
		return false
	var root := tree.root
	if not root:
		return false
	
	# Check for UI elements at position
	var controls := root.get_nodes_in_group("clickable")
	for control in controls:
		if control is Control:
			var rect := Rect2(control.global_position, control.size)
			if rect.has_point(screen_pos):
				return true
	return false

func _show_target_tooltip(target_info: TargetingManager.TargetInfo) -> void:
	# Emit signal or show tooltip UI
	EventBus.entity_targeted.emit(entity_id, target_info.id, target_info.entity_type)

func _hide_target_tooltip() -> void:
	# Hide tooltip UI
	pass

func _show_player_context_menu(target: TargetingManager.TargetInfo) -> void:
	# Show player interaction context menu
	pass

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