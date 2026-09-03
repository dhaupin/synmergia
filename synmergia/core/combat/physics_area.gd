## PhysicsArea - 3D sphere-based area detection
## For AoE skills, auras, and radius effects
## Supports line-of-sight blocking and configurable geometry collision
extends Node3D
class_name PhysicsArea
const Entity = preload("res://core/entities/entity.gd")


signal entity_entered(entity: Entity)
signal entity_exited(entity: Entity)
signal area_updated(entities_in_area: Array)

enum Shape {
	SPHERE,           # 3D sphere (default)
	SPHERE_LAYERED    # Sphere with inner/outer layers
}

enum BlockingMode {
	NONE,             # No blocking, detects through everything
	WALLS_ONLY,       # Blocked by collision layer 1 (walls)
	WALLS_AND_FLOORS,# Blocked by collision layers 1-2
	ALL_GEOMETRY      # Blocked by all solid objects
}

@export var shape: Shape = Shape.SPHERE
@export var radius: float = 5.0           # Main radius
@export var inner_radius: float = 0.0     # For layered spheres (no effect zone in center)
@export var height: float = 0.0           # Optional: cylinder height override (0 = infinite/unrestricted)

@export var blocking_mode: BlockingMode = BlockingMode.NONE
@export var source_entity: Entity = null  # Origin of the area
@export var update_interval: float = 0.1  # How often to refresh (0 = every frame)

var _entities_in_area: Array = []
var _collision_shape: CollisionShape3D
var _area: Area3D
var _monitoring: bool = false
var _last_update_time: float = 0.0

func _ready() -> void:
	_setup_area()

func _setup_area() -> void:
	# Create Area3D for detection
	_area = Area3D.new()
	_area.name = "PhysicsAreaDetection"
	add_child(_area)
	
	# Set collision layers/masks based on blocking mode
	_configure_collision()
	
	# Create shape
	_collision_shape = CollisionShape3D.new()
	var shape_instance: Shape3D
	
	if shape == Shape.SPHERE_LAYERED:
		# Use hollow sphere (not natively supported, so use shape layer trick)
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		shape_instance = sphere
	else:
		var sphere := SphereShape3D.new()
		sphere.radius = radius
		shape_instance = sphere
	
	_collision_shape.shape = shape_instance
	_area.add_child(_collision_shape)
	
	# Connect signals
	_area.body_shape_entered.connect(_on_body_shape_entered)
	_area.body_shape_exited.connect(_on_body_shape_exited)

func _configure_collision() -> void:
	# Configure what layers this area monitors
	# Layer 1 = walls, Layer 2 = floors, Layer 3 = entities, etc.
	match blocking_mode:
		BlockingMode.NONE:
			_area.collision_mask = 0b0000001  # Only entities layer
		BlockingMode.WALLS_ONLY:
			_area.collision_mask = 0b0000011  # Entities + walls
		BlockingMode.WALLS_AND_FLOORS:
			_area.collision_mask = 0b0000111  # Entities + walls + floors
		BlockingMode.ALL_GEOMETRY:
			_area.collision_mask = 0b0111111  # All solid geometry

func start_monitoring() -> void:
	_monitoring = true
	_area.monitoring = true
	_refresh_area()

func stop_monitoring() -> void:
	_monitoring = false
	_area.monitoring = false

func _process(delta: float) -> void:
	if not _monitoring:
		return
	
	if update_interval > 0:
		_last_update_time += delta
		if _last_update_time >= update_interval:
			_last_update_time = 0.0
			_refresh_area()
	else:
		_refresh_area()

func _refresh_area() -> void:
	# Remove invalid entities
	var valid_entities: Array = []
	for entity in _entities_in_area:
		if is_instance_valid(entity):
			valid_entities.append(entity)
	_entities_in_area = valid_entities

## SPHERE DETECTION

func get_entities_in_sphere(origin: Vector3, sphere_radius: float, ignore_source: bool = true) -> Array:
	var entities: Array = []
	
	# Use physics sphere query
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = sphere_radius
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.collision_mask = 0b0000001  # Only entities layer
	
	var results := space_state.intersect_shape(query, 50)
	
	for result in results:
		var collider := result["collider"]
		if collider is Entity:
			if ignore_source and collider == source_entity:
				continue
			entities.append(collider)
	
	return entities

## LINE OF SIGHT

## Check if there's clear line of sight between two points
## Returns true if unobstructed, false if blocked
func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	if blocking_mode == BlockingMode.NONE:
		return true
	
	var space_state := get_world_3d().direct_space_state
	
	var query := PhysicsRayQueryParameters3D.create(from, to)
	
	match blocking_mode:
		BlockingMode.WALLS_ONLY:
			query.collision_mask = 0b0000010  # Just walls
		BlockingMode.WALLS_AND_FLOORS:
			query.collision_mask = 0b0000110  # Walls + floors
		BlockingMode.ALL_GEOMETRY:
			query.collision_mask = 0b0111111  # All solid
	
	var result := space_state.intersect_ray(query)
	
	# If no hit, line of sight is clear
	return result.is_empty()

## Get all entities in sphere that have line of sight from origin
func get_entities_with_los(origin: Vector3, sphere_radius: float) -> Array:
	var all_entities := get_entities_in_sphere(origin, sphere_radius)
	var los_entities: Array = []
	
	for entity in all_entities:
		# Check LOS to entity's center
		var target_pos := entity.global_position
		# Offset slightly above ground for better LOS
		target_pos.y += 1.0
		
		if has_line_of_sight(origin, target_pos):
			los_entities.append(entity)
	
	return los_entities

## Check if a specific point is visible from origin (within radius)
func is_point_visible(origin: Vector3, point: Vector3, max_distance: float = -1.0) -> bool:
	if max_distance > 0 and origin.distance_to(point) > max_distance:
		return false
	return has_line_of_sight(origin, point)

## Get all blocking intersections between two points
func get_blocking_objects(from: Vector3, to: Vector3) -> Array[Dictionary]:
	var space_state := get_world_3d().direct_space_state
	var blockers: Array[Dictionary] = []
	
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b1111110  # All geometry except entities
	
	var result := space_state.intersect_ray(query)
	
	# This only returns one hit, need to iterate for multiple blockers
	# For now, simplified single-hit version
	if not result.is_empty():
		blockers.append(result)
	
	return blockers

## Check if entity is within effective range considering geometry
func is_in_range_and_visible(origin: Vector3, target: Entity, max_range: float) -> bool:
	if not is_instance_valid(target):
		return false
	
	var distance: float = origin.distance_to(target.global_position)
	if distance > max_range:
		return false
	
	# Check line of sight
	return has_line_of_sight(origin + Vector3(0, 1.5, 0), target.global_position + Vector3(0, 1.0, 0))

## ENTITY DETECTION

func _on_body_shape_entered(body_rid: RID, body: Node3D, body_shape_index: int, local_shape_index: int) -> void:
	if body is Entity:
		if not _entities_in_area.has(body):
			_entities_in_area.append(body)
			entity_entered.emit(body)
			area_updated.emit(_entities_in_area)

func _on_body_shape_exited(body_rid: RID, body: Node3D, body_shape_index: int, local_shape_index: int) -> void:
	if body is Entity:
		_entities_in_area.erase(body)
		entity_exited.emit(body)
		area_updated.emit(_entities_in_area)

func get_entities() -> Array:
	return _entities_in_area.duplicate()

func get_entity_count() -> int:
	return _entities_in_area.size()

func has_entity(entity: Entity) -> bool:
	return _entities_in_area.has(entity)

func clear() -> void:
	_entities_in_area.clear()
	area_updated.emit(_entities_in_area)

## CONFIGURATION

func set_radius(new_radius: float) -> void:
	radius = new_radius
	if _collision_shape and _collision_shape.shape is SphereShape3D:
		(_collision_shape.shape as SphereShape3D).radius = radius

func set_blocking_mode(mode: BlockingMode) -> void:
	blocking_mode = mode
	_configure_collision()

func cleanup() -> void:
	stop_monitoring()
	if is_instance_valid(_area):
		_area.queue_free()
	queue_free()
