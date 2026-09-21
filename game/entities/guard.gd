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
var _guard_downed := false      # True between 0 HP and the post respawn.
var _guard_respawn_timer: SceneTreeTimer = null


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


## ---------------------------------------------------------------------------
## LAWFUL DURABILITY: downed at 0 HP, reform at the post. Lawful guards
## (town watch, house guards) are not loot/XP pinatas and never truly
## die: no loot roll, no kill XP (KillRewards also zeroes them), no
## despawn. Non-lawful guards (arena/event) use the normal death path.
## ---------------------------------------------------------------------------

func is_lawful_guard() -> bool:
	if guard_data == null:
		return true  # null data defaults to the durable guard behavior
	if "is_lawful" in guard_data:
		return bool(guard_data.is_lawful)
	return true


func respawn_delay() -> float:
	if guard_data != null and "respawn_delay" in guard_data:
		return float(guard_data.respawn_delay)
	return 30.0


## Downed guards are out of play: no steering, no attacks, no AI ticks.
## Standing guards regenerate out of combat (1%/s of max, small
## tick-friendly floor) so watch patrols are fresh for real offenders.
func _physics_process(delta: float) -> void:
	if _guard_downed:
		return
	super._physics_process(delta)
	_regen_if_out_of_combat(delta)


func _regen_if_out_of_combat(delta: float) -> void:
	if health_component == null or health_component.current_health >= health_component.max_health:
		return
	# In combat = AI has a live target or the threat table is non-empty.
	var in_combat := false
	if _guard_ai != null and "_target" in _guard_ai and _guard_ai._target != null \
			and is_instance_valid(_guard_ai._target):
		in_combat = true
	if not in_combat and "aggro_component" in self and aggro_component != null \
			and "_threat_table" in aggro_component and not aggro_component._threat_table.is_empty():
		in_combat = true
	if in_combat:
		return
	var amount := maxf(1.0, float(max_health) * 0.01) * delta
	health_component.current_health = mini(int(ceil(amount)) + health_component.current_health, health_component.max_health)
	health_component.health_changed.emit(health_component.current_health, health_component.max_health, int(ceil(amount)))


func take_damage(amount: int, source = null) -> int:
	if _guard_downed:
		return 0  # downed guards are out of play until they reform
	var applied := super.take_damage(amount, source)
	if is_lawful_guard() and health_component != null \
			and health_component.current_health <= 0 and not _guard_downed:
		_become_downed()
	return applied


## Switch to the DOWNED state: alive-but-out-of-play, respawn scheduled.
func _become_downed() -> void:
	_guard_downed = true
	if health_component != null:
		health_component._is_dead = false
		health_component.current_health = 0
		health_component.health_changed.emit(0, health_component.max_health, 0)
	# The Enemy._ready wired health_depleted -> _on_died; with _is_dead
	# reset BEFORE the depleted emit fires (take_damage emits it when HP
	# crosses 0), _on_died's lawful branch intercepts it there too.
	_schedule_post_respawn()
	GameLog.info("Guard downed: %s (reforms at post in %.0fs)" % [display_name, respawn_delay()])


## Reform at the post after respawn_delay: full health, grudges kept
## (a downed guard does not forget who downed them).
func _schedule_post_respawn() -> void:
	var timer := get_tree().create_timer(respawn_delay())
	_guard_respawn_timer = timer
	timer.timeout.connect(_respawn_at_post)


func _respawn_at_post() -> void:
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_guard_downed = false
	if guard_data != null:
		position = guard_data.post_position
	if health_component != null:
		health_component.current_health = health_component.max_health
		current_health = health_component.max_health
		health_component.health_changed.emit(current_health, health_component.max_health, 0)
	if _guard_ai != null and _guard_ai.has_method("reset_combat"):
		_guard_ai.reset_combat()
	GameLog.info("Guard reformed at post: %s" % display_name)


## Kill credit: guard deaths broadcast so the watch knows one of theirs
## fell (future: bounty/notoriety escalation).
func _on_died() -> void:
	# Lawful guards go DOWNED at 0 HP instead (see take_damage); the
	# normal death path (loot, XP, despawn) never runs for them.
	if is_lawful_guard():
		if not _guard_downed:
			_become_downed()
		return
	if _guard_ai != null and guard_data != null and str(guard_data.watch_group) != "":
		GameLog.info("Guard %s of watch '%s' has fallen" % [display_name, guard_data.watch_group])
	super._on_died()
