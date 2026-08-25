## Projectile - Base class for all projectiles (arrows, fireballs, spells)
## Handles movement, collision, and impact effects
class_name Projectile
extends Node3D

signal hit(target: Entity, damage: int)
signal expired()
signal destroyed()

enum ProjectileType {
	ARROW,         # Physical, single target
	FIREBALL,      # Magical, explodes on impact
	MAGIC_BOLT,    # Magic, single target
	HEALING_ORB,   # Healing projectile
	TRAP,          # Ground-targeted, stationary
	AOE_MARKER     # Area effect marker
}

@export var projectile_type: ProjectileType = ProjectileType.ARROW
@export var speed: float = 20.0           # Units per second
@export var max_range: float = 50.0       # Max travel distance
@export var lifetime: float = 10.0        # Max time alive
@export var hitbox_radius: float = 0.5     # Collision radius

# Damage configuration
@export var base_damage: int = 10
@export var damage_type: String = "physical"  # physical, fire, ice, lightning, arcane
@export var penetration: float = 0.0          # Armor ignore percentage

# Owner (who fired this)
var source: Entity = null

# Target tracking
var target: Entity = null
var target_position: Vector3 = Vector3.ZERO
var is_homing: bool = false

# State
var _distance_traveled: float = 0.0
var _time_alive: float = 0.0
var _has_hit: bool = false
var _velocity: Vector3 = Vector3.ZERO

# Visual
@export var vfx_scene: String = ""
@export var sfx_hit: String = ""
@export var sfx_miss: String = ""
var _vfx_instance: Node3D = null

# Area effect (for explosions)
@export var explosion_radius: float = 0.0
@export var explosion_damage_falloff: bool = true

func _ready() -> void:
	add_to_group("projectiles")

func _physics_process(delta: float) -> void:
	if _has_hit:
		return
	
	_time_alive += delta
	
	# Check lifetime expiration
	if _time_alive >= lifetime:
		_expire()
		return
	
	# Update movement
	var movement := _velocity * delta
	var movement_distance := movement.length()
	
	# Homing behavior
	if is_homing and target and is_instance_valid(target):
		var to_target := target.global_position - global_position
		to_target.y = 0  # Keep on same Y plane
		if to_target.length() > 0.1:
			var target_dir := to_target.normalized()
			_velocity = _velocity.lerp(target_dir * speed, 0.1).normalized() * speed
	
	# Apply movement
	var old_pos := global_position
	global_position += movement
	_distance_traveled += movement_distance
	
	# Check range
	if _distance_traveled >= max_range:
		_expire()
		return
	
	# Collision detection
	_check_collision(old_pos, global_position)

## Initialize projectile
func initialize(from: Entity, to: Vector3, skill: Skill = null) -> void:
	source = from
	target_position = to
	
	# Set direction
	var direction := (to - global_position).normalized()
	_velocity = direction * speed
	
	# Apply skill modifiers
	if skill:
		base_damage = skill.damage
		damage_type = skill.damage_type
		speed = skill.projectile_speed if skill.projectile_speed > 0 else speed
		max_range = skill.range
		is_homing = skill.is_homing
		vfx_scene = skill.vfx_projectile
		explosion_radius = skill.area_radius

## Set as homing projectile
func set_homing(target_entity: Entity, homing_strength: float = 0.1) -> void:
	is_homing = true
	target = target_entity

## Check collision with entities
func _check_collision(from: Vector3, to: Vector3) -> void:
	# Raycast or sphere cast from 'from' to 'to'
	var space_state := get_world_3d().direct_space_state
	
	var query := PhysicsRayQueryParameters3D.create(from, to, 0x00000001 | 0x00000002)
	var result := space_state.intersect_ray(query)
	
	if result:
		var collider := result["collider"]
		
		# Check if it's an entity
		if collider is Entity:
			if collider != source:  # Don't hit source
				_on_hit(collider)
		elif collider.has_method("get_entity"):
			var entity: Entity = collider.get_entity()
			if entity and entity != source:
				_on_hit(entity)
		else:
			# Hit environment - check for AOE
			if explosion_radius > 0:
				_explode(result["position"])

## Handle hit
func _on_hit(target: Entity) -> void:
	if _has_hit:
		return
	_has_hit = true
	
	# Calculate damage
	var damage := _calculate_damage(target)
	
	# Apply damage
	if target.health_component:
		target.health_component.take_damage(damage, source, damage_type)
	
	# Emit signals
	hit.emit(target, damage)
	EventBus.projectile_hit.emit(self, target, damage)
	
	# Check for AOE
	if explosion_radius > 0:
		_explode(global_position)
	
	_destroy()

## Calculate final damage
func _calculate_damage(target: Entity) -> int:
	var damage := base_damage
	
	# Apply penetration (ignore armor/resistance)
	if penetration > 0 and target.stats.has("armor"):
		var reduction := target.stats["armor"] * penetration
		damage = int(damage * (1.0 - reduction))
	
	# Type effectiveness (future: elemental multipliers)
	# ...
	
	return max(1, damage)

## Explosion effect
func _explode(position: Vector3) -> void:
	if explosion_radius <= 0:
		return
	
	# Visual effect
	if vfx_scene != "":
		_spawn_vfx(position)
	
	# Audio effect
	if sfx_hit != "":
		_spawn_sfx(position)
	
	# Damage all entities in radius
	var nearby := EntityService.get_entities_in_radius(position, explosion_radius)
	
	for entity in nearby:
		if entity == source:
			continue
		
		# Distance-based damage falloff
		var distance := position.distance_to(entity.global_position)
		var falloff := 1.0
		if explosion_damage_falloff:
			falloff = 1.0 - (distance / explosion_radius) * 0.5  # Min 50% damage at edge
		
		var damage := int(base_damage * falloff)
		
		if entity.health_component:
			entity.health_component.take_damage(damage, source, damage_type)
		
		EventBus.area_damage.emit(source, entity, damage, damage_type)
	
	EventBus.explosion_occurred.emit(position, explosion_radius, source)

## Expire (max range or lifetime)
func _expire() -> void:
	if _has_hit:
		return
	
	# Visual miss effect
	if sfx_miss != "":
		_spawn_sfx(global_position)
	
	expired.emit()
	EventBus.projectile_expired.emit(self)
	_destroy()

## Cleanup
func _destroy() -> void:
	if _vfx_instance:
		_vfx_instance.queue_free()
	destroyed.emit()
	queue_free()

## Spawn VFX
func _spawn_vfx(position: Vector3) -> void:
	if vfx_scene == "":
		return
	
	var scene := load(vfx_scene)
	if scene:
		_vfx_instance = scene.instantiate()
		_vfx_instance.global_position = position
		get_tree().root.add_child(_vfx_instance)

## Spawn SFX
func _spawn_sfx(position: Vector3) -> void:
	# AudioManager.play(sfx_miss, position)  # Placeholder
	pass

## Static factory methods
static func create_arrow(from: Entity, to: Vector3, damage: int) -> Projectile:
	var p := Projectile.new()
	p.projectile_type = ProjectileType.ARROW
	p.base_damage = damage
	p.speed = 30.0
	p.damage_type = "physical"
	return p

static func create_fireball(from: Entity, to: Vector3, damage: int, radius: float) -> Projectile:
	var p := Projectile.new()
	p.projectile_type = ProjectileType.FIREBALL
	p.base_damage = damage
	p.speed = 15.0
	p.damage_type = "fire"
	p.explosion_radius = radius
	p.explosion_damage_falloff = true
	return p

static func create_magic_bolt(from: Entity, to: Vector3, damage: int) -> Projectile:
	var p := Projectile.new()
	p.projectile_type = ProjectileType.MAGIC_BOLT
	p.base_damage = damage
	p.speed = 25.0
	p.damage_type = "arcane"
	return p
