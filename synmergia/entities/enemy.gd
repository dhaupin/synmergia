## Enemy — basic enemy entity with health and simple AI
class_name Enemy
extends Entity

@export var enemy_data: Resource
@export var starting_health: int = 30
@export var starting_level: int = 1
@export var loot_table_id: String = ""

@onready var health_component: HealthComponent = $HealthComponent

var _ai_state: String = "idle"
var _wander_target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0


func _ready() -> void:
	entity_type = EntityType.ENEMY
	relation = Relation.HOSTILE
	controller_type = ControllerType.HOSTILE_AI
	add_to_group("enemies")

	if enemy_data:
		_load_from_data()
	elif starting_health > 0:
		max_health = starting_health
		current_health = starting_health

	if health_component:
		health_component.max_health = max_health
		health_component.current_health = current_health
		health_component.health_depleted.connect(_on_died)

	GameLog.info("Enemy spawned: %s (lvl %d, %d HP)" % [display_name, level, max_health])


func _load_from_data() -> void:
	if "display_name" in enemy_data and enemy_data.display_name:
		display_name = enemy_data.display_name
	if "level" in enemy_data:
		level = int(enemy_data.level)
	if "health" in enemy_data:
		max_health = int(enemy_data.health)
		current_health = max_health


func _physics_process(delta: float) -> void:
	if health_component and health_component._is_dead:
		return
	_ai_update(delta)


func _ai_update(delta: float) -> void:
	match _ai_state:
		"idle":
			_wander_timer += delta
			if _wander_timer > 3.0:
				_wander_timer = 0.0
				_wander_target = global_position + Vector3(
					randf_range(-5, 5), 0, randf_range(-5, 5))
				_ai_state = "wander"
		"wander":
			var dir := (_wander_target - global_position)
			dir.y = 0
			if dir.length() > 0.5:
				dir = dir.normalized()
				global_position += dir * 1.5 * delta
			else:
				_ai_state = "idle"
		"chase":
			pass  # TODO: path toward target


func take_damage(amount: int, source = null) -> int:
	if health_component:
		health_component.current_health -= amount
		health_component.health_changed.emit(
			health_component.current_health,
			health_component.max_health,
			-amount)
		if health_component.current_health <= 0:
			health_component.health_depleted.emit()
			# TODO: loot drop, XP reward
	else:
		current_health -= amount
		health_changed.emit(current_health, max_health, -amount)
		if current_health <= 0:
			died.emit(source)
	return amount


func _on_died() -> void:
	GameLog.info("Enemy died: %s" % display_name)
	_roll_and_drop_loot()
	queue_free()


func _roll_and_drop_loot() -> void:
	if loot_table_id.is_empty():
		return

	var path := "res://data/loot_tables/%s.tres" % loot_table_id
	var table: LootTable = load(path) as LootTable
	if not table:
		return

	var result := table.roll_drop()
	for item in result.items:
		GameLog.info("  loot: %s x%d" % [item.get("item_id", ""), item.get("quantity", 1)])

	for cid in result.currency:
		GameLog.info("  currency: %s %d" % [cid, result.currency[cid]])
