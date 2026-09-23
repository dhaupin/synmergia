## Enemy -- basic enemy entity with health and simple AI
extends "res://core/entities/entity.gd"

class_name Enemy
const LootTable = preload("res://core/schemas/loot_table.gd")
const HealthComponent = preload("res://core/components/health_component.gd")
const AggroComponent = preload("res://core/components/aggro_component.gd")
const KillRewards = preload("res://core/services/kill_rewards.gd")

## Mirror of the Entity damage event with explicit damage_type, consumed
## by the HUD bridge (world_playable) and CombatSystem listeners.
signal damage_dealt(source, target, amount: int, damage_type: String)


@export var enemy_data: Resource
@export var starting_health: int = 30
@export var starting_level: int = 1
@export var loot_table_id: String = ""

## The health component is looked up at runtime (via _resolve_health)
## rather than via @onready. The @onready form used to fail in 4.7 with a
## "Parent path vanished" warning when the enemy was instantiated
## together with its HealthComponent in the same scene, because the
## child subtree isn't fully resolved at the moment the parent's
## @onready block runs. The deferred lookup runs from _ready after
## the node is fully in the tree.
var health_component: HealthComponent = null
var aggro_component: AggroComponent = null
var _ai = null  # EnemyAI child, if attached (set via attach_ai)

var _wander_target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0

## Last combatant that damaged this enemy (killer-of-record fallback).
## Set in take_damage; cleared when no valid source. Used by the
## XP/kill-reward hook when no explicit killer reaches _on_died.
var _last_damager: Node = null


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

	_resolve_health()
	if health_component == null:
		# Runtime-spawned enemies (no scene HealthComponent child) get one here.
		health_component = HealthComponent.new()
		add_child(health_component)
	if health_component:
		health_component.max_health = max_health
		health_component.current_health = current_health
		health_component.health_depleted.connect(_on_died)

	# Threat table: enemies track who generates threat (damage, heals,
	# taunts) and EnemyAI reads it for in-combat target switching.
	if aggro_component == null:
		aggro_component = AggroComponent.new()
		add_child(aggro_component)

	GameLog.info("Enemy spawned: %s (lvl %d, %d HP)" % [display_name, level, max_health])


func _load_from_data() -> void:
	if "display_name" in enemy_data and enemy_data.display_name:
		display_name = enemy_data.display_name
	if "level" in enemy_data:
		level = int(enemy_data.level)
	if "health" in enemy_data:
		max_health = int(enemy_data.health)
		current_health = max_health


## Walks the local subtree to find a HealthComponent. The scene attaches
## a child node literally named "HealthComponent" in world_playable.tscn;
## enemies spawned at runtime (e.g. via SpawnService) may use any name, so
## we also fall back to a type-based search.
func _resolve_health() -> void:
	if health_component:
		return
	var named: Node = get_node_or_null("HealthComponent")
	if named and named is HealthComponent:
		health_component = named
		return
	# Type-based fallback: walk children.
	for child in get_children():
		if child is HealthComponent:
			health_component = child
			return


func _physics_process(delta: float) -> void:
	if health_component and health_component._is_dead:
		return

	# EnemyAI (when attached) steers via move_direction; also apply
	# basic separation-free movement for a wandering feel.
	if _ai != null:
		if move_direction.length_squared() > 0.001:
			var speed: float = _current_speed()
			global_position += move_direction * speed * delta
			move_direction = Vector3.ZERO  # consume the steer for this frame


func _current_speed() -> float:
	if enemy_data and "move_speed" in enemy_data:
		return float(enemy_data.move_speed)
	return 2.0


func take_damage(amount: int, source = null) -> int:
	if health_component:
		# No _is_dead poke here: health_component.die() owns the dead flag
		# and early-returns when it is already set -- setting it first used
		# to make the proper death flow a silent no-op.
		health_component.current_health -= amount
		health_component.health_changed.emit(
			health_component.current_health,
			health_component.max_health,
			-amount)
		if health_component.current_health <= 0:
			# Proper death flow: die() sets the component's _is_dead/_killer,
			# creates the corpse, emits health_depleted (-> _on_died: loot,
			# kill rewards, unregister) and EventHub.entity_died. Poking
			# _is_dead directly (the old code) skipped all of that.
			health_component.die(source)
			# Mirror death onto the base Entity fields so is_alive() -- used
			# by CombatSystem hitbox sweeps and kill-credit checks -- tells
			# the truth instead of reporting a dead enemy as alive.
			is_dead = true
			current_health = 0
	else:
		current_health -= amount
		health_changed.emit(current_health, max_health)
		if current_health <= 0:
			# Entity.die sets is_dead, clears status effects, emits died.
			die(source)

	# HUD feed: mirror the player-side damage event so CombatLog and
	# DamageNumbers see enemy->player and player->enemy hits alike.
	damage_dealt.emit(source, self, amount, "physical")
	EventHub.damage_dealt.emit(source, self, amount, "physical")

	# Threat: damage on this enemy builds the attacker's position on the
	# threat table (drives in-combat target switching in EnemyAI).
	# Duck-typed: PlayerController (CharacterBody3D, not an Entity subclass)
	# is the live player, and its attacks must build threat and grudges.
	var is_combatant: bool = source is Entity or (source is Node and "entity_id" in source)
	if aggro_component and is_combatant:
		aggro_component.add_damage_threat(source, amount)

	# Grudge memory + engagement: let the AI remember and fight back.
	if _ai and is_combatant:
		_ai.on_damaged(source)

	# Killer-of-record: any valid in-tree combatant counts (duck-typed,
	# so PlayerController qualifies). Used for kill credit when no
	# explicit killer is threaded through the death flow.
	if _is_valid_damager(source):
		_last_damager = source

	return amount

## A valid damager: live in-tree Node with a combatant id. Deliberately
## duck-typed so PlayerController (not an Entity subclass) qualifies.
func _is_valid_damager(node) -> bool:
	if node == null or not (node is Node):
		return false
	if not is_instance_valid(node) or not node.is_inside_tree():
		return false
	return "entity_id" in node or "player_id" in node

## Attach an EnemyAI brain and hook engagement callbacks.
func attach_ai(ai) -> void:
	_ai = ai
	add_child(ai)


func _on_died() -> void:
	GameLog.info("Enemy died: %s" % display_name)
	_roll_and_drop_loot()
	# XP/kill-reward hook: pays the killer (or top threat holder) via
	# the duck-typed progression surface and broadcasts kill_rewarded.
	KillRewards.award_kill(self, _last_damager)
	# Unify with base Entity death semantics so combat systems
	# (CombatSystem death hooks, threat cleanup) see one signal.
	died.emit(null)
	despawned_from_world()
	queue_free()

## Called before queue_free: allow services to clean up references.
func despawned_from_world() -> void:
	var ml = Engine.get_main_loop()
	if ml == null or not ml is SceneTree:
		return
	var es = (ml as SceneTree).root.get_node_or_null("EntityService")
	if es and entity_id != "" and es.has_method("unregister_entity"):
		es.unregister_entity(self)


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

	# Spawn a real ground drop at the corpse. GroundLootService resolves
	# the {item_id, quantity} dicts into Item instances; an empty roll
	# (nothing dropped) creates no drop. Currency rides along and is
	# paid via the duck-typed add_gold on pickup. Kill credit rides
	# along too so LootRulesService can apply party delegation rules.
	if GroundLootService and not result.items.is_empty():
		var drop_pos := global_position + Vector3(0.0, -0.5, 0.0)
		var options := {
			"source": "enemy",
			"currency": result.currency,
			"despawn_seconds": GroundLootService.DEFAULT_DESPAWN_SECONDS,
		}
		if LootRulesService != null and LootRulesService.has_method("build_enemy_drop_options"):
			options = LootRulesService.build_enemy_drop_options(_loot_credit_player_id(), options)
		GroundLootService.create_drop(drop_pos, result.items, options)


## Loot-credit resolution: same order as the XP/kill-reward hook (direct
## killer first, then threat-table owner) so party loot rules apply to
## exactly the player the kill was credited to.
func _loot_credit_player_id() -> String:
	if _last_damager != null and is_instance_valid(_last_damager) \
			and "entity_id" in _last_damager and not ("loot_table_id" in _last_damager):
		return str(_last_damager.entity_id)
	if "aggro_component" in self and aggro_component != null \
			and aggro_component.has_method("get_highest_threat_target"):
		var owner = aggro_component.get_highest_threat_target()
		if owner != null and is_instance_valid(owner) and "entity_id" in owner \
				and not ("loot_table_id" in owner):
			return str(owner.entity_id)
	return ""
