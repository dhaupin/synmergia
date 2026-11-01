## PlayerManager - Manages local player state
## Handles player stats, resources, and character data
extends Node

const BlacksmithUI = preload("res://ui/components/blacksmith_ui.gd")
const SkillAcademyUI = preload("res://ui/components/skill_academy_ui.gd")

signal health_changed(current: int, maximum: int)
signal mana_changed(current: int, maximum: int)
signal stamina_changed(current: float, maximum: float)
signal experience_changed(current: int, level: int)
signal level_up(new_level: int)
signal died
signal stats_changed(stats: Dictionary)

var local_player: Node = null

# Character stats
var character_name: String = "Player"
var character_class: String = "Warrior"
var character_race: String = "Human"
var level: int = 1
var experience: int = 0
var experience_to_next_level: int = 1000

# Resources
var max_health: int = 100
var current_health: int = 100
var max_mana: int = 100
var current_mana: int = 100
var max_stamina: float = 100.0
var current_stamina: float = 100.0

# Base stats
var base_stats: Dictionary = {
	"strength": 10,
	"agility": 10,
	"intelligence": 10,
	"vitality": 10,
	"endurance": 10,
	"wisdom": 10
}

# Gold/currency
var gold: int = 0

func _ready() -> void:
	GameLog.info("PlayerManager initialized")

func set_local_player(player: Node) -> void:
	local_player = player
	# A null clear (logout, probe teardown) is a legal slot state:
	# the duck-typed reads must not touch a missing node.
	character_name = player.display_name if (player != null and is_instance_valid(player) and "display_name" in player) else "Player"
	_update_resource_signals()

## Resolve the local player's entity id by duck-typing the bound player
## node (same pattern as TitleService.get_local_player_id). Returns ""
## when no player is bound or the node carries no entity_id.
func get_local_player_id() -> String:
	if local_player != null and is_instance_valid(local_player) and "entity_id" in local_player:
		return str(local_player.get("entity_id"))
	return ""

func _update_resource_signals() -> void:
	health_changed.emit(current_health, max_health)
	mana_changed.emit(current_mana, max_mana)
	stamina_changed.emit(current_stamina, max_stamina)

## STATS

func get_stat(stat_name: String) -> int:
	return base_stats.get(stat_name, 0)

func set_stat(stat_name: String, value: int) -> void:
	base_stats[stat_name] = value
	stats_changed.emit(base_stats)
	_recalculate_derived_stats()

func add_stat(stat_name: String, amount: int) -> void:
	base_stats[stat_name] = base_stats.get(stat_name, 0) + amount
	stats_changed.emit(base_stats)
	_recalculate_derived_stats()

func _recalculate_derived_stats() -> void:
	# Recalculate max health based on vitality
	var vitality_stat := get_stat("vitality")
	var new_max_health := 100 + (vitality_stat * 10)
	if new_max_health != max_health:
		var health_ratio := float(current_health) / max_health if max_health > 0 else 1.0
		max_health = new_max_health
		current_health = int(health_ratio * max_health)
		health_changed.emit(current_health, max_health)

	# Recalculate max mana based on intelligence
	var intelligence_stat := get_stat("intelligence")
	var new_max_mana := 100 + (intelligence_stat * 8)
	if new_max_mana != max_mana:
		var mana_ratio := float(current_mana) / max_mana if max_mana > 0 else 1.0
		max_mana = new_max_mana
		current_mana = int(mana_ratio * max_mana)
		mana_changed.emit(current_mana, max_mana)

## HEALTH

func take_damage(amount: int) -> void:
	var final_damage: int = max(1, amount - get_defense())
	current_health = max(0, current_health - final_damage)
	health_changed.emit(current_health, max_health)

	if current_health <= 0:
		die()

func heal(amount: int) -> void:
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

func get_defense() -> int:
	return get_stat("vitality") * 2

## MANA

func use_mana(amount: int) -> bool:
	if current_mana >= amount:
		current_mana -= amount
		mana_changed.emit(current_mana, max_mana)
		return true
	return false

func restore_mana(amount: int) -> void:
	current_mana = min(max_mana, current_mana + amount)
	mana_changed.emit(current_mana, max_mana)

## STAMINA

func use_stamina(amount: float) -> bool:
	if current_stamina >= amount:
		current_stamina -= amount
		stamina_changed.emit(current_stamina, max_stamina)
		return true
	return false

func restore_stamina(amount: float) -> void:
	current_stamina = min(max_stamina, current_stamina + amount)
	stamina_changed.emit(current_stamina, max_stamina)

func _process(_delta: float) -> void:
	# Regenerate stamina out of combat
	if current_stamina < max_stamina:
		var regen_amount := 5.0 * _delta
		current_stamina = min(max_stamina, current_stamina + regen_amount)
		stamina_changed.emit(current_stamina, max_stamina)

## EXPERIENCE & LEVELING

func add_experience(amount: int) -> void:
	experience += amount
	experience_changed.emit(experience, level)

	while experience >= experience_to_next_level:
		level_up_function()

func level_up_function() -> void:
	experience -= experience_to_next_level
	level += 1

	# Increase XP requirement
	experience_to_next_level = int(experience_to_next_level * 1.5)

	# Stat increases
	add_stat("strength", 1)
	add_stat("agility", 1)
	add_stat("intelligence", 1)
	add_stat("vitality", 1)
	add_stat("endurance", 1)
	add_stat("wisdom", 1)

	# Full restore on level up
	current_health = max_health
	current_mana = max_mana
	health_changed.emit(current_health, max_health)
	mana_changed.emit(current_mana, max_mana)

	level_up.emit(level)
	GameLog.info("Level up! Now level %d" % level)

## DEATH

func die() -> void:
	GameLog.info("Player died!")
	died.emit()

func resurrect(health_percent: float = 0.5) -> void:
	current_health = int(max_health * health_percent)
	current_mana = int(max_mana * health_percent)
	health_changed.emit(current_health, max_health)
	mana_changed.emit(current_mana, max_mana)

## GOLD

func add_gold(amount: int) -> void:
	gold += amount

func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		return true
	return false

func get_gold() -> int:
	return gold

## SERIALIZATION

func get_character_data() -> Dictionary:
	return {
		"name": character_name,
		"class": character_class,
		"race": character_race,
		"level": level,
		"experience": experience,
		"gold": gold,
		"stats": base_stats,
		"health": current_health,
		"mana": current_mana
	}

func load_character_data(data: Dictionary) -> void:
	character_name = data.get("name", "Player")
	character_class = data.get("class", "Warrior")
	character_race = data.get("race", "Human")
	level = data.get("level", 1)
	experience = data.get("experience", 0)
	gold = data.get("gold", 0)
	base_stats = data.get("stats", base_stats)

	# Set resources after stats are loaded
	_recalculate_derived_stats()
	current_health = data.get("health", max_health)
	current_mana = data.get("mana", max_mana)

## Open the blacksmith UI for a player (called by NPCEntity dispatch).
func open_blacksmith_ui(_player_id: String, _npc_data) -> void:
	if local_player and local_player.has_method("_open_blacksmith_ui"):
		local_player._open_blacksmith_ui()

## Open the skill academy UI for a player (called by NPCEntity dispatch).
func open_skill_academy_ui(_player_id: String, _npc_data) -> void:
	if local_player and local_player.has_method("_open_skill_academy_ui"):
		local_player._open_skill_academy_ui()

## Get the local player node.
func get_local_player() -> Node:
	return local_player
