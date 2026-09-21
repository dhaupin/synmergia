## Guard - NPC/enemy hybrid entity.
##
## To every player EXCEPT offenders, a Guard behaves like an NPCEntity:
## FRIENDLY relation, interactable, shows an NPC minimap marker. To a
## player on the watchlist, the SAME node is hostile and attacks.
##
## Why relation stays FRIENDLY globally: EntityService.is_enemy() reads
## the global relation, and flipping it would make every system (aggro
## scans, party checks, minimap, dialog) treat the guard as an enemy for
## everyone. Instead, hostility lives in the GuardAI watchlist -- the
## guard "sees" specific players as enemies without the world changing.
##
## The combat surface is inherited from Enemy (take_damage routes into
## the threat table and the AI), so fighting a guard works exactly like
## fighting any enemy: it fights back, remembers, and other guards join.
extends "res://entities/enemy.gd"

const GuardData = preload("res://core/schemas/guard_data.gd")
const GuardAI = preload("res://core/ai/guard_ai.gd")

var guard_data = null   # GuardData
var _guard_ai = null    # GuardAI child (also reachable via _ai on Enemy)


func _ready() -> void:
	# Enemy._ready sets relation = HOSTILE and entity_type = ENEMY; a
	# guard's world-facing identity is the NPC face, so overwrite after.
	super._ready()
	entity_type = EntityType.NPC
	relation = Relation.FRIENDLY


## Attach a GuardAI configured from this guard's GuardData.
func attach_guard_ai(data = null) -> void:
	if data != null:
		guard_data = data
	var ai = GuardAI.new()
	ai.name = "GuardAI"
	attach_ai(ai)
	_guard_ai = ai
	if guard_data != null:
		ai.setup(guard_data)
		_apply_guard_data()


## Enemy reads its stats from EnemyData; guards carry GuardData instead,
## so mirror the shared combat fields onto the entity surface. Called
## after _ready, so the health component is updated in place.
func _apply_guard_data() -> void:
	if "level" in guard_data:
		level = int(guard_data.level)
	if "health" in guard_data and int(guard_data.health) > 0:
		max_health = int(guard_data.health)
		current_health = max_health
	if health_component != null:
		health_component.max_health = max_health
		health_component.current_health = current_health
	if "attack_power" in guard_data and int(guard_data.attack_power) > 0:
		stats["strength"] = max(1, int(guard_data.attack_power) / 2)


## Guard-flavored report_offense passthrough (null-safe).
func report_offense(player_id: String, trigger: int, source_desc: String = "") -> void:
	if _guard_ai != null:
		_guard_ai.report_offense(player_id, trigger, source_desc)


## Interact: offenders get attacked on approach, everyone else gets the
## friendly NPC dialog path (base Entity interaction handles menus).
func get_interaction_prompt() -> String:
	return "Talk"


## Kill credit: guard deaths broadcast so the watch knows one of theirs
## fell (future: bounty/notoriety escalation).
func _on_died() -> void:
	if _guard_ai != null and guard_data != null and str(guard_data.watch_group) != "":
		GameLog.info("Guard %s of watch '%s' has fallen" % [display_name, guard_data.watch_group])
	super._on_died()
