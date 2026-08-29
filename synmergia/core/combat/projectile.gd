## Projectile - Base class for all projectiles (arrows, fireballs, spells)
## Handles movement, collision, and impact effects
## Works for PLAYERS, ENEMIES, NPCs - any Entity can fire projectiles
class_name Projectile
extends Node3D

signal hit(target: SynmergiaEntity, damage: int)
signal expired()
signal destroyed()
signal trajectory_changed(old_dir: Vector3, new_dir: Vector3)

enum ProjectileType {
	ARROW,
	FIREBALL,
	MAGIC_BOLT,
	HEALING_ORB,
	HEAVY_SHOT,
	TRAP,
	AOE_MARKER,
	BEAM,
	RICOCHET,
	CHAIN,
	ORB,
	GUIDED_MISSILE
}

enum ProjectileOwner {
	PLAYER_ONLY,
	ENEMY_ONLY,
	ALL
}

@export var projectile_type: ProjectileType = ProjectileType.ARROW
@export var allowed_owners: ProjectileOwner = ProjectileOwner.ALL
@export var speed: float = 20.0
@export var max_range: float = 50.0
@export var lifetime: float = 10.0
@export var hitbox_radius: float = 0.5

@export var base_damage: int = 10
@export var damage_type: String = "physical"
@export var penetration: float = 0.0
@export var bonus_damage_vs_players: float = 0.0
@export var bonus_damage_vs_enemies: float = 0.0

var source: SynmergiaEntity = null
var _source_is_player: bool = false
var target: SynmergiaEntity = null
var target_position: Vector3 = Vector3.ZERO
var is_homing: bool = false

var _distance_traveled: float = 0.0
var _time_alive: float = 0.0
var _has_hit: bool = false
var _velocity: Vector3 = Vector3.ZERO

@export var pierce_count: int = 0
var _pierce_remaining: int = 0
var _hit_entities: Array = []

@export var ricochet_count: int = 0
@export var chain_count: int = 0
@export var chain_range: float = 10.0
var _ricochet_remaining: int = 0
var _chain_targets: Array = []

@export var vfx_scene: String = ""
@export var sfx_hit: String = ""
@export var sfx_miss: String = ""
var _vfx_instance: Node3D = null

@export var explosion_radius: float = 0.0
@export var explosion_damage_falloff: bool = true

@export var is_beam: bool = false
@export var beam_duration: float = 0.5

@export var is_trap: bool = false
@export var trap_duration: float = 30.0
@export var trap_trigger_radius: float = 2.0
var _trap_triggered: bool = false
var _trap_timer: float = 0.0

func _ready() -> void:
	add_to_group("projectiles")
	_pierce_remaining = pierce_count
	_ricochet_remaining = ricochet_count

func _physics_process(delta: float) -> void:
	if is_trap and not _trap_triggered:
		_trap_timer += delta
		if _trap_timer >= trap_duration:
			_expire()
		return
	
	if _has_hit:
		return
	
	_time_alive += delta
	
	if _time_alive >= lifetime:
		_expire()
		return
	
	var movement := _velocity * delta
	var movement_distance := movement.length()
	
	if is_homing and target and is_instance_valid(target):
		var to_target := target.global_position - global_position
		to_target.y = 0
		if to_target.length() > 0.1:
			var target_dir := to_target.normalized()
			var old_dir := _velocity.normalized()
			_velocity = _velocity.lerp(target_dir * speed, 0.1).normalized() * speed
			if old_dir.dot(_velocity.normalized()) < 0.99:
				trajectory_changed.emit(old_dir, _velocity.normalized())
	
	var old_pos := global_position
	global_position += movement
	_distance_traveled += movement_distance
	
	if _distance_traveled >= max_range:
		_expire()
		return
	
	_check_collision(old_pos, global_position)

func initialize(from: SynmergiaEntity, to: Vector3, skill: Skill = null) -> void:
	source = from
	target_position = to
	
	_source_is_player = (from.controller_type == SynmergiaEntity.ControllerType.HUMAN or 
						 from.controller_type == SynmergiaEntity.ControllerType.AGENT)
	
	var direction := (to - global_position).normalized()
	_velocity = direction * speed
	
	if skill:
		base_damage = skill.damage
		damage_type = skill.damage_type
		speed = skill.projectile_speed if skill.projectile_speed > 0 else speed
		max_range = skill.range
		is_homing = skill.is_homing
		vfx_scene = skill.vfx_projectile
		explosion_radius = skill.area_radius
		pierce_count = skill.pierce_count
		_pierce_remaining = pierce_count

func set_homing(target_entity: SynmergiaEntity, homing_strength: float = 0.1) -> void:
	is_homing = true
	target = target_entity

func _check_collision(from: Vector3, to: Vector3) -> void:
	if is_trap and not _trap_triggered:
		_check_trap_activation()
		return
	
	if is_beam:
		return
	
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 0x00000001 | 0x00000002)
	var result := space_state.intersect_ray(query)
	
	if result:
		var collider := result["collider"]
		
		if collider is Entity:
			if collider != source and not _hit_entities.has(collider):
				_on_hit(collider)
		elif collider.has_method("get_entity"):
			var entity: SynmergiaEntity = collider.get_entity()
			if entity and entity != source and not _hit_entities.has(entity):
				_on_hit(entity)
		else:
			if explosion_radius > 0:
				_explode(result["position"])

func _check_trap_activation() -> void:
	var nearby := EntityService.get_entities_in_radius(global_position, trap_trigger_radius)
	
	for entity in nearby:
		if entity == source:
			continue
		
		if _is_hostile(entity):
			_trigger_trap(entity)
			return

func _trigger_trap(trigger_entity: SynmergiaEntity) -> void:
	_trap_triggered = true
	
	if explosion_radius > 0:
		_explode(global_position)
	else:
		_on_hit(trigger_entity)
	
	_expire()

func _is_hostile(target: SynmergiaEntity) -> bool:
	if source == null:
		return true
	
	if _source_is_player:
		return target.entity_type == SynmergiaEntity.EntityType.ENEMY
	else:
		return target.entity_type == SynmergiaEntity.EntityType.PLAYER

func _on_hit(target: SynmergiaEntity) -> void:
	if _has_hit and _pierce_remaining <= 0:
		return
	
	_hit_entities.append(target)
	var damage := _calculate_damage(target)
	
	if target.health_component:
		target.health_component.take_damage(damage, source, damage_type)
	
	hit.emit(target, damage)
	EventHub.projectile_hit.emit(self, target, damage)
	
	if _ricochet_remaining > 0 and ricochet_count > 0:
		_ricochet(target)
		return
	
	if _chain_targets.size() < chain_count:
		_chain_to_next(target)
		return
	
	if explosion_radius > 0:
		_explode(global_position)
	elif _pierce_remaining > 0:
		_pierce_remaining -= 1
		return
	
	_destroy()

func _ricochet(from_target: SynmergiaEntity) -> void:
	var nearby := EntityService.get_entities_in_radius(from_target.global_position, chain_range)
	var next_target: SynmergiaEntity = null
	var min_dist := INF
	
	for entity in nearby:
		if entity != source and not _hit_entities.has(entity) and _is_hostile(entity):
			var dist: float = entity.global_position.distance_to(from_target.global_position)
			if dist < min_dist:
				min_dist = dist
				next_target = entity
	
	if next_target:
		_ricochet_remaining -= 1
		var old_dir := _velocity.normalized()
		_velocity = (next_target.global_position - global_position).normalized() * speed
		trajectory_changed.emit(old_dir, _velocity.normalized())
		target = next_target
	else:
		_expire()

func _chain_to_next(from_target: SynmergiaEntity) -> void:
	var nearby := EntityService.get_entities_in_radius(from_target.global_position, chain_range)
	var next_target: SynmergiaEntity = null
	var min_dist := INF
	
	for entity in nearby:
		if entity != source and not _hit_entities.has(entity) and _is_hostile(entity):
			var dist: float = entity.global_position.distance_to(from_target.global_position)
			if dist < min_dist:
				min_dist = dist
				next_target = entity
	
	if next_target:
		_chain_targets.append(next_target)
		var chain_damage := int(base_damage * 0.5)
		if next_target.health_component:
			next_target.health_component.take_damage(chain_damage, source, damage_type)
		EventHub.projectile_hit.emit(self, next_target, chain_damage)
		
		if _chain_targets.size() < chain_count:
			_chain_to_next(next_target)

func _calculate_damage(target: SynmergiaEntity) -> int:
	var damage := base_damage
	
	if _source_is_player:
		damage = int(damage * (1.0 + bonus_damage_vs_enemies))
	else:
		damage = int(damage * (1.0 + bonus_damage_vs_players))
	
	if penetration > 0 and target.stats.has("armor"):
		var reduction := target.stats["armor"] * penetration
		damage = int(damage * (1.0 - reduction))
	
	return max(1, damage)

func _explode(position: Vector3) -> void:
	if explosion_radius <= 0:
		return
	
	if vfx_scene != "":
		_spawn_vfx(position)
	
	if sfx_hit != "":
		_spawn_sfx(position)
	
	var nearby := EntityService.get_entities_in_radius(position, explosion_radius)
	
	for entity in nearby:
		if entity == source:
			continue
		
		var distance: float = position.distance_to(entity.global_position)
		var falloff := 1.0
		if explosion_damage_falloff:
			falloff = 1.0 - (distance / explosion_radius) * 0.5
		
		var damage := int(base_damage * falloff)
		
		if entity.health_component:
			entity.health_component.take_damage(damage, source, damage_type)
		
		EventHub.area_damage.emit(source, entity, damage, damage_type)
	
	EventHub.explosion_occurred.emit(position, explosion_radius, source)

func _expire() -> void:
	if _has_hit:
		return
	
	if sfx_miss != "":
		_spawn_sfx(global_position)
	
	expired.emit()
	EventHub.projectile_expired.emit(self)
	_destroy()

func _destroy() -> void:
	if _vfx_instance:
		_vfx_instance.queue_free()
	destroyed.emit()
	queue_free()

func _spawn_vfx(position: Vector3) -> void:
	if vfx_scene == "":
		return
	
	var scene := load(vfx_scene)
	if scene:
		_vfx_instance = scene.instantiate()
		_vfx_instance.global_position = position
		get_tree().root.add_child(_vfx_instance)

func _spawn_sfx(position: Vector3) -> void:
	pass

static func create_arrow(from: SynmergiaEntity, to: Vector3, damage: int) -> Projectile:
	var p := Projectile.new()
	p.projectile_type = ProjectileType.ARROW
	p.base_damage = damage
	p.speed = 30.0
	p.damage_type = "physical"
	p.allowed_owners = ProjectileOwner.ALL
	return p

static func create_fireball(from: SynmergiaEntity, to: Vector3, damage: int, radius: float) -> Projectile:
	var p := Projectile.new()
	p.projectile_type = ProjectileType.FIREBALL
	p.base_damage = damage
	p.speed = 15.0
	p.damage_type = "fire"
	p.explosion_radius = radius
	p.explosion_damage_falloff = true
	p.allowed_owners = ProjectileOwner.ALL
	return p

static func create_magic_bolt(from: SynmergiaEntity, to: Vector3, damage: int) -> Projectile:
	var p := Projectile.new()
	p.projectile_type = ProjectileType.MAGIC_BOLT
	p.base_damage = damage
	p.speed = 25.0
	p.damage_type = "arcane"
	p.allowed_owners = ProjectileOwner.ALL
	return p

static func create_heavy_shot(from: SynmergiaEntity, to: Vector3, damage: int) -> Projectile:
	var p := Projectile.new()
	p.projectile_type = ProjectileType.HEAVY_SHOT
	p.base_damage = damage
	p.speed = 10.0
	p.damage_type = "physical"
	p.allowed_owners = ProjectileOwner.ENEMY_ONLY
	return p

static func create_healing_orb(from: SynmergiaEntity, to: Vector3, heal_amount: int) -> Projectile:
	var p := Projectile.new()
	p.projectile_type = ProjectileType.HEALING_ORB
	p.base_damage = -heal_amount
	p.speed = 12.0
	p.damage_type = "holy"
	p.is_homing = true
	p.allowed_owners = ProjectileOwner.ALL
	return p

static func create_trap(from: SynmergiaEntity, position: Vector3, radius: float) -> Projectile:
	var p := Projectile.new()
	p.projectile_type = ProjectileType.TRAP
	p.is_trap = true
	p.global_position = position
	p.explosion_radius = radius
	p.allowed_owners = ProjectileOwner.ALL
	return p

static func create_chain_lightning(from: SynmergiaEntity, target: SynmergiaEntity, damage: int, chains: int) -> Projectile:
	var p := Projectile.new()
	p.projectile_type = ProjectileType.CHAIN
	p.base_damage = damage
	p.speed = 40.0
	p.damage_type = "lightning"
	p.chain_count = chains
	p.chain_range = 15.0
	p.allowed_owners = ProjectileOwner.ALL
	return p

static func create_ricochet(from: SynmergiaEntity, to: Vector3, damage: int, bounces: int) -> Projectile:
	var p := Projectile.new()
	p.projectile_type = ProjectileType.RICOCHET
	p.base_damage = damage
	p.speed = 25.0
	p.damage_type = "physical"
	p.ricochet_count = bounces
	p.chain_range = 20.0
	p.allowed_owners = ProjectileOwner.ALL
	return p

static func create_beam(from: SynmergiaEntity, to: Vector3, damage: int, duration: float) -> Projectile:
	var p := Projectile.new()
	p.projectile_type = ProjectileType.BEAM
	p.base_damage = damage
	p.is_beam = true
	p.beam_duration = duration
	p.global_position = from.global_position
	p.target_position = to
	p.allowed_owners = ProjectileOwner.ALL
	return p
