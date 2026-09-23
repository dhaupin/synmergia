## Entity - Base class for all game entities
## Characters, NPCs, enemies all inherit from this
extends Node3D
class_name Entity

signal health_changed(current: int, maximum: int)
signal mana_changed(current: int, maximum: int)
signal stamina_changed(current: float, maximum: float)
signal died(killer)  # Entity type omitted to avoid circular reference during parsing
signal stat_changed(stat: String, value: int)
signal state_changed(new_state: String)

enum EntityType {
	NONE = 0,
	PLAYER = 1,
	ENEMY = 2,
	NPC = 4,
	DESTRUCTIBLE = 8,
	OBJECT = 16,
	TELEPORT = 32,
	LOOT = 64,
	ALL = 0xFFFFFFFF
}

enum Relation {
	NEUTRAL,
	FRIENDLY,
	HOSTILE
}

enum ControllerType {
	HUMAN,      # Real human player
	AGENT,      # AI agent
	NPC,        # Scripted NPC
	HOSTILE_AI  # Enemy AI
}

@export var entity_id: String = ""
# Per-entity seed (world-building.md sec. 18.8 Phase 0 item).
# Assigned deterministically by EntityService at registration from
# (frame_seed, entity_id); empty until then. Derivation uses the
# canonical seed chain in seed_chain.gd.
@export var seed: String = ""
@export var display_name: String = "Entity"
@export var level: int = 1
@export var entity_type: EntityType = EntityType.NPC
@export var relation: Relation = Relation.NEUTRAL

# AI steering contract: the EnemyAI child writes the desired movement
# vector each frame; concrete entities (Enemy) apply it in their
# _physics_process. Zero vector = stand still.
var move_direction: Vector3 = Vector3.ZERO

# Runtime threat hooks. The AggroComponent (when present) reads these
# via add_damage_threat/record_heal_threat; kept on the base class so
# combat code can treat every entity uniformly.
# NOTE: `relation` (NEUTRAL/FRIENDLY/HOSTILE) is the allegiance field;
# there is no separate `faction` property on Entity.

# Controller type - for fairness system (HUMAN and AGENT are equals)
@export var controller_type: ControllerType = ControllerType.NPC
@export var connector_id: String = ""  # Which connector controls this (for agents)

# Stats stored as dictionary
var stats: Dictionary = {
	"strength": 10,
	"agility": 10,
	"intelligence": 10,
	"vitality": 10,
	"endurance": 10,
	"wisdom": 10,
	"damage_multiplier": 1.0,
	"defense_multiplier": 1.0,
	"armor_multiplier": 1.0,
	"movement_speed_multiplier": 1.0
}

# Resources
var max_health: int = 100
var current_health: int = 100
var max_mana: int = 100
var current_mana: int = 100
var max_stamina: float = 100.0
var current_stamina: float = 100.0

# Status effects (using Array to avoid circular dependency with StatusEffect)
var status_effects: Array = []
var is_dead: bool = false

# Team (for friendly fire)
var team_id: int = 0

# Respawn state
var respawn_point: Vector3 = Vector3.ZERO  # Last bound position
var respawn_ankh_id: String = ""           # Bound ankh ID
var pending_respawn: bool = false         # Waiting to respawn

# Faction
var faction_id: String = ""

## Enemy template for combat-relevant Entities (Enemy mobs, and bosses
## spawned as bare Entities). Carrying it on the base class lets the
## kill-reward, loot and state-projection paths treat bosses and elites
## exactly like regular enemies (duck-typed "enemy_data" in entity).
@export var enemy_data: Resource

## Allegiance alias used by EntityService.is_enemy and combat code
## ("entity.faction == Entity.Relation.HOSTILE"). Kept as a getter/setter
## pair over `relation` so the two fields can never disagree.
var faction: int:
	get:
		return relation
	set(value):
		relation = value

# Species (using untyped var to avoid circular dependency with Species schema)
var species_id: String = ""
var species = null

# CharacterData reference for player entities (for allocated stats)
var character_data = null  # Untyped to avoid circular dependency with CharacterData schema

func _ready() -> void:
	_calculate_max_resources()
	current_health = max_health
	current_mana = max_mana
	health_changed.emit(current_health, max_health)

func _calculate_max_resources() -> void:
	max_health = 100 + (get_stat("vitality") * 10)
	max_mana = 100 + (get_stat("intelligence") * 8)
	max_stamina = 100.0 + (get_stat("endurance") * 5)

## STATS

## Get stat value including allocated stats from CharacterData
func get_stat(stat_name: String) -> int:
	var base: int = stats.get(stat_name, 0)

	# Add allocated stats from CharacterData if available
	if character_data != null:
		base += character_data.get_allocated_points(stat_name)

	return base

## Called when allocated stats change (e.g., from UI)
func on_stats_changed() -> void:
	_calculate_max_resources()
	# Emit health/mana changed to update UI
	health_changed.emit(current_health, max_health)
	mana_changed.emit(current_mana, max_mana)
	stamina_changed.emit(current_stamina, max_stamina)

func set_stat(stat_name: String, value: int) -> void:
	stats[stat_name] = value
	stat_changed.emit(stat_name, value)
	if stat_name == "vitality":
		_calculate_max_resources()

func add_stat(stat_name: String, amount: int) -> void:
	set_stat(stat_name, get_stat(stat_name) + amount)

## SPECIES

func apply_species(new_species) -> void:
	if new_species == null:
		return

	species = new_species
	species_id = new_species.id

	# Apply stat modifiers
	for stat in new_species.stat_modifiers:
		var modifier := new_species.stat_modifiers[stat] as int
		stats[stat] = stats.get(stat, 10) + modifier

	# Apply resource modifiers
	max_health = int(max_health * new_species.health_modifier)
	max_mana = int(max_mana * new_species.mana_modifier)
	max_stamina = max_stamina * new_species.stamina_modifier

	# Apply movement speed modifier
	stats["movement_speed_multiplier"] = new_species.speed_modifier

	_calculate_max_resources()

	# GameLog.debug("Entity: Applied species %s to %s" % [species_id, display_name])

## HEALTH

func take_damage(amount: int, source = null) -> int:
	if is_dead:
		return 0

	var damage := _calculate_damage_received(amount)
	current_health = max(0, current_health - damage)
	health_changed.emit(current_health, max_health)

	if current_health <= 0:
		die(source)

	return damage

func heal(amount: int) -> void:
	if is_dead:
		return
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

func heal_percentage(percent: float) -> void:
	heal(int(max_health * percent))

func is_alive() -> bool:
	return not is_dead and current_health > 0

func _calculate_damage_received(amount: int) -> int:
	var defense: float = get_defense()
	var reduction: float = float(defense) / (defense + 100.0)
	return int(amount * (1.0 - reduction))

## MANA

func use_mana(amount: int) -> bool:
	if current_mana >= amount:
		current_mana -= amount
		return true
	return false

func restore_mana(amount: int) -> void:
	current_mana = min(max_mana, current_mana + amount)

## STAMINA

func use_stamina(amount: float) -> bool:
	if current_stamina >= amount:
		current_stamina -= amount
		return true
	return false

func restore_stamina(amount: float) -> void:
	current_stamina = min(max_stamina, current_stamina + amount)

## DEFENSE & OFFENSE

func get_defense() -> int:
	return stats.vitality * 2

func get_magic_resistance() -> int:
	return stats.wisdom * 2

func get_attack_power() -> int:
	# Physical damage: STR-based
	return get_stat("strength") * 2

func get_spell_power() -> int:
	# Magical damage: INT-based
	return get_stat("intelligence") * 2

func get_healing_power() -> int:
	# Healing power: WIS-based
	return get_stat("wisdom") * 2

func get_attack_speed() -> float:
	return 1.0 + (get_stat("agility") * 0.01)

func get_crit_chance() -> float:
	return 0.05 + (get_stat("agility") * 0.003)

func get_crit_multiplier() -> float:
	return 1.5

func get_armor() -> int:
	# Physical mitigation: VIT-based
	return get_stat("vitality")

func get_spell_resist() -> int:
	# Magic mitigation: WIS-based
	return get_stat("wisdom")

## STATUS EFFECTS

func apply_status_effect(effect) -> void:
	if effect.is_expired():
		return
	status_effects.append(effect)
	effect.apply(self)
	effect.effect_expired.connect(_on_status_effect_expired)

func _on_status_effect_expired(effect) -> void:
	status_effects.erase(effect)

func remove_status_effect(effect) -> void:
	if status_effects.has(effect):
		effect.remove(self)
		status_effects.erase(effect)

func has_status_effect(effect_type: String) -> bool:
	for effect in status_effects:
		if effect.effect_type == effect_type:
			return true
	return false

func clear_all_status_effects() -> void:
	for effect in status_effects:
		effect.remove(self)
	status_effects.clear()

## DEATH

func die(killer = null) -> void:
	if is_dead:
		return
	is_dead = true
	clear_all_status_effects()
	died.emit(killer)

func resurrect(health_percent: float = 0.5) -> void:
	is_dead = false
	current_health = int(max_health * health_percent)
	current_mana = int(max_mana * health_percent)
	health_changed.emit(current_health, max_health)

## UTILITY

func is_in_range(target, range: float) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return global_position.distance_to(target.global_position) <= range

func can_attack(target) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if is_dead or target.is_dead:
		return false
	if team_id != 0 and team_id == target.team_id:
		return false  # Same team, no friendly fire
	return true

## SERIALIZATION

func get_entity_data() -> Dictionary:
	return {
		"entity_id": entity_id,
		"display_name": display_name,
		"level": level,
		"stats": stats,
		"health": current_health,
		"mana": current_mana,
		"faction_id": faction_id,
		"species_id": species_id,
		"position": {
			"x": global_position.x,
			"y": global_position.y,
			"z": global_position.z
		},
		"rotation": rotation.y
	}

func load_entity_data(data: Dictionary) -> void:
	entity_id = data.get("entity_id", entity_id)
	display_name = data.get("display_name", display_name)
	level = data.get("level", level)
	stats = data.get("stats", stats)
	faction_id = data.get("faction_id", faction_id)
	species_id = data.get("species_id", species_id)
	_calculate_max_resources()
	current_health = data.get("health", max_health)
	current_mana = data.get("mana", max_mana)
	var pos_data = data.get("position", {})
	if not pos_data.is_empty():
		global_position = Vector3(pos_data.get("x", 0), pos_data.get("y", 0), pos_data.get("z", 0))
	rotation.y = data.get("rotation", 0)

## Get display name with titles (if player entity)
func get_full_display_name() -> String:
	if entity_type != EntityType.PLAYER:
		return display_name
	# Resolve autoload via SceneTree root to avoid parse-time dependency.
	# The bare name `TitleService` would be a parse error in --script mode
	# where autoloads are not pre-loaded.
	var root := get_tree().root if is_inside_tree() else null
	if root == null:
		return display_name
	var title_service := root.get_node_or_null("TitleService")
	if title_service and title_service.has_method("get_display_name"):
		return title_service.get_display_name(entity_id, display_name)
	return display_name
