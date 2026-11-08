## Enemy -- basic enemy entity with health and simple AI
extends "res://core/entities/entity.gd"

class_name Enemy
const LootTable = preload("res://core/schemas/loot_table.gd")
const HealthComponent = preload("res://core/components/health_component.gd")
const AggroComponent = preload("res://core/components/aggro_component.gd")
const KillRewards = preload("res://core/services/kill_rewards.gd")
const EnemyData = preload("res://core/schemas/enemy_data.gd")
const FloatingName = preload("res://entities/floating_name.gd")

## Mirror of the Entity damage event with explicit damage_type, consumed
## by the HUD bridge (world_playable) and CombatSystem listeners.
signal damage_dealt(source, target, amount: int, damage_type: String, is_crit: bool)
# enemy_data lives on base Entity (entity.gd) so bosses/elites carry it too.

@export var starting_health: int = 30
@export var starting_level: int = 1
@export var loot_table_id: String = ""

## Set true by spawn pipelines (SpawnService.spawn_enemy_direct,
## HordeEventService._produce_mob) AFTER pre-configuring level/stats/
## health on the node. When set, _ready's _load_from_data() skips the
## template reload that would otherwise clobber those values (a level-7
## /spawn enemy came out as the template's level 1). Plain .new() spawns
## leave it false and keep the default template-driven behavior.
var spawn_data_applied: bool = false

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

## Movement Design System: cached MovementProfile (resolved lazily in
## _movement_profile(); null until first speed query after boot).
var _movement_profile_cache: MovementProfile = null

## AnimationPlayer on the mounted .glb model (null when the enemy has
## no model_path or it carries no animations).
var _model_anim: AnimationPlayer = null

## Hitbox Profile System: cached profile (resolved lazily; null until
## first _apply_hitbox_profile after boot).
var _hitbox_profile_cache: HitboxProfile = null


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

	# Skinned .glb models mount here (wolf was the first; the box
	# placeholders stay for everything else until models exist).
	_mount_model()
	# Hitbox Profile System: apply the data-driven collision shape and
	# the matching model scale AFTER _mount_model so the visual and the
	# collider always agree (both read the same EnemyData.scale).
	_apply_hitbox_profile()
	_apply_model_scale()

	# Threat table: enemies track who generates threat (damage, heals,
	# taunts) and EnemyAI reads it for in-combat target switching.
	# Training dummies skip it: no threat can exist without a brain,
	# and a dummy threat table would pollute kill-credit fallbacks.
	if aggro_component == null and not is_training_dummy():
		aggro_component = AggroComponent.new()
		add_child(aggro_component)

	# Fighters carry the combat effect stack (aura mirror + GCD/casting
	# component); training dummies only need the aura tracker.
	_ensure_effect_stack(not is_training_dummy())

	# Nameplate law: every enemy gets a floating name plate. Kind is
	# read from the template's enemy class (elite/boss scale up), and
	# world bosses (metadata WORLD_BOSS) get the big plate from
	# SpawnService; ensure() is create-or-update so double-wiring is
	# harmless.
	var plate_kind := "enemy"
	var plate_cfg := {}
	if enemy_data != null and "enemy_type" in enemy_data:
		var etype := int(enemy_data.enemy_type)
		if etype == EnemyData.EnemyType.WORLD_BOSS or etype == EnemyData.EnemyType.RAID_BOSS:
			plate_kind = "boss"
			plate_cfg = {"big": true}
		elif etype == EnemyData.EnemyType.BOSS:
			plate_kind = "boss"
		elif etype == EnemyData.EnemyType.CHAMPION or etype == EnemyData.EnemyType.ELITE:
			plate_kind = "elite"
	FloatingName.ensure(self, FloatingName.compose_text(display_name, level), plate_kind, plate_cfg)

	GameLog.info("Enemy spawned: %s (lvl %d, %d HP)" % [display_name, level, max_health])


func _load_from_data() -> void:
	if spawn_data_applied:
		# A spawn pipeline pre-applied template data (possibly with a
		# level override and scaled stats): re-loading from the template
		# here would reset that work (e.g. the horde's "Wolf [3]"
		# display suffix and the level itself). Keep everything as-is.
		return
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
			_face_travel(move_direction)
			move_direction = Vector3.ZERO  # consume the steer for this frame
		_update_model_anim(true)
	else:
		_update_model_anim(false)


## THE STAND LAW (the sideways-vertical wolf bug, world-shape aware):
## the body's up is the local planet radial when a planet frame exists
## (spherical world), else classic Y. Forward is the horizon part of
## the wished direction; every steer re-stands the body so patrol
## reads asWalking on the ground, never tipping or rolling.
func _face_travel(dir: Vector3) -> void:
	if dir.length_squared() < 0.000001:
		return
	var up := Vector3.UP
	var pm: Node = get_node_or_null("/root/PlayerManager")
	var local: Node = pm.local_player if pm != null and is_instance_valid(pm) else null
	var planet_center: Variant = (local.planet_center if local != null and "planet_center" in local else Vector3.ZERO)
	var pc: Vector3 = planet_center if planet_center is Vector3 else Vector3.ZERO
	if pc != Vector3.ZERO:
		var rel: Vector3 = global_position - pc
		if rel.length() > 0.001:
			up = rel.normalized()
	var fwd: Vector3 = dir - up * dir.dot(up)
	if fwd.length_squared() < 0.000001:
		return  # straight up/down wish: no heading to face
	fwd = fwd.normalized()
	# Every other entity class faces -Z; the model root's own PI yaw
	# keeps the authored forward on -Z too.
	global_transform.basis = Basis.looking_at(-fwd, up)
	_update_model_anim(true)


## Mount the skinned .glb from EnemyData.model_path under a ModelRoot
## and hide any scene-level placeholder mesh the author left behind.
## Silence is fine: most enemies still run box placeholders (the
## phantom-path lint keeps model_path empty until the file exists).
func _mount_model() -> void:
	var path := ""
	if enemy_data != null:
		var mp = enemy_data.get("model_path")
		if mp != null:
			path = str(mp)
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		GameLog.warn("Enemy: model_path failed to load: " + path)
		return
	var root := Node3D.new()
	root.name = "ModelRoot"
	add_child(root)
	var inst := packed.instantiate()
	inst.name = path.get_file().get_basename()
	root.add_child(inst)
	# Face travel direction -Z like every other entity.
	root.rotation.y = PI
	_model_anim = _find_anim_player(inst)
	# Hide the author's placeholder box mesh (direct child MeshInstance3D)
	# once a real model is present -- only when it is NOT the model we
	# just mounted.
	for c in get_children():
		if c is MeshInstance3D:
			c.visible = false
	GameLog.info("Enemy: mounted model %s" % path)


## Hitbox Profile System: resolve this creature's HitboxProfile from
## EnemyData.hitbox_profile_id (falls back through
## DataService.get_creature_hitbox_profile, which derives the body plan
## from animation_set; cached).
func _hitbox_profile() -> HitboxProfile:
	if _hitbox_profile_cache != null:
		return _hitbox_profile_cache
	if DataService:
		_hitbox_profile_cache = DataService.get_creature_hitbox_profile(enemy_data)
	if _hitbox_profile_cache == null:
		GameLog.warn("Enemy: no hitbox profile resolved for %s -- keeping scene shape" % display_name)
	return _hitbox_profile_cache


## Apply the HitboxProfile collision shape to this enemy. Prefers the
## scene-authored "Hitbox" CollisionShape3D child (StaticBody3D/Hitbox
## in the playable world); otherwise builds one under a StaticBody3D.
## The profile's height_offset centers the shape on the entity origin
## (feet-on-floor), replacing the hand-placed transforms in .tscn files.
func _apply_hitbox_profile() -> void:
	var profile: HitboxProfile = _hitbox_profile()
	if profile == null:
		return
	var base_scale: float = 1.0
	if enemy_data != null:
		var sc = enemy_data.get("scale")
		if sc != null:
			base_scale = float(sc)
	var shape := profile.build_shape(base_scale)
	var dims := profile.get_dims(base_scale)

	var target: CollisionShape3D = null
	# Scene-authored nodes win so level designers keep node-order control.
	var named_body := get_node_or_null("StaticBody3D")
	if named_body != null:
		var named_shape := named_body.get_node_or_null("Hitbox") as CollisionShape3D
		if named_shape != null:
			target = named_shape
		elif named_body is CollisionShape3D:
			target = named_body
	if target == null:
		var direct := get_node_or_null("Hitbox") as CollisionShape3D
		if direct != null:
			target = direct
	if target == null:
		# Guards (and older scenes) author a bare direct CollisionShape3D.
		var plain := get_node_or_null("CollisionShape3D") as CollisionShape3D
		if plain != null:
			target = plain
	if target == null:
		# No scene-authored shape: create the standard StaticBody3D/Hitbox
		# pair. Deferred add: _ready can run while the tree is mid-setup
		# during scene instantiation (guards in world_playable hit this)
		# and a sync add_child there is rejected. Shape/offset are plain
		# properties, so setting them now still applies when the body lands.
		var body := StaticBody3D.new()
		body.name = "StaticBody3D"
		add_child.call_deferred(body)
		target = CollisionShape3D.new()
		target.name = "Hitbox"
		body.add_child(target)

	target.shape = shape
	target.position = Vector3(0.0, float(dims["offset"]), 0.0)
	GameLog.info("Enemy: hitbox '%s' applied to %s" % [profile.id, display_name])


## Scale the mounted model by EnemyData.scale so the visual matches the
## (clamped) hitbox scale. Box placeholders keep their authored size.
func _apply_model_scale() -> void:
	if enemy_data == null:
		return
	var sc = enemy_data.get("scale")
	if sc == null or is_equal_approx(float(sc), 1.0):
		return
	var model_root := get_node_or_null("ModelRoot") as Node3D
	if model_root == null:
		return
	var profile: HitboxProfile = _hitbox_profile()
	var s: float = profile.clamp_scale(float(sc)) if profile != null else clampf(float(sc), 0.25, 4.0)
	model_root.scale = Vector3(s, s, s)


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_anim_player(c)
		if f != null:
			return f
	return null


## Swap walk/idle clips with movement state. The .glb's AnimationPlayer
## targets an absolute root (like /rig_wolf/Skeleton3D); repoint it
## relative to the model root so instancing under any parent resolves.
func _update_model_anim(moving: bool) -> void:
	if _model_anim == null or not is_instance_valid(_model_anim):
		return
	if _model_anim.root_node.is_absolute():
		_model_anim.root_node = _model_anim.get_parent().get_path()
	var wanted := "walk" if moving else "idle"
	if _model_anim.current_animation != wanted and _model_anim.has_animation(wanted):
		_model_anim.play(wanted)


func _current_speed() -> float:
	# EnemyData.move_speed stays the per-enemy override (tuned per mob);
	# the movement profile multiplies on top so global feel changes
	# (slide speed, gravity, sprint) land everywhere from one .tres.
	var base: float = 2.0
	if enemy_data and "move_speed" in enemy_data:
		base = float(enemy_data.move_speed)
	var profile: MovementProfile = _movement_profile()
	if profile == null:
		return base
	# Map enemy move_speed onto the profile's run band proportionally.
	return base * (profile.run_speed / 7.5)


## Resolve this enemy's movement profile from EnemyData.movement_profile_id
## (falls back to the standard humanoid profile; cached).
func _movement_profile() -> MovementProfile:
	if _movement_profile_cache != null:
		return _movement_profile_cache
	var profile_id: String = "movement_standard"
	if enemy_data != null:
		# 4.7.2: Resource.get(key, default) lost its default arg -- null-check
		# instead of passing "" as a second argument (parse error).
		var requested = enemy_data.get("movement_profile_id")
		if requested != null and not str(requested).is_empty():
			profile_id = str(requested)
	if DataService:
		_movement_profile_cache = DataService.get_movement_profile(profile_id)
	return _movement_profile_cache


func take_damage(amount: int, source = null, damage_type: String = "physical", is_crit: bool = false) -> int:
	# Killer-of-record FIRST: any valid in-tree combatant counts (duck-typed,
	# so the player body qualifies). The death chain below (die() ->
	# _on_died -> KillRewards.award_kill(self, _last_damager)) runs
	# synchronously inside health_component.die(), so this must be set
	# before the lethal branch or one-shot kills credit the PREVIOUS
	# attacker (or nobody). Found by the horde rewards test: a one-shot
	# slime kill paid the stale damager.
	if _is_valid_damager(source):
		_last_damager = source
	# EnemyData armor/resist mitigation by school: physical hits face
	# armor, magical hits face resistance. Training dummy carries 25/40
	# specifically so players can SEE their mitigation on it. Other
	# schools (true/pure) bypass. min 1 so chip damage always lands.
	var applied := amount
	if enemy_data != null and "armor" in enemy_data:
		var defense: float = float(enemy_data.resistance) \
				if (damage_type == "magical" or damage_type == "magic") \
				else float(enemy_data.armor)
		if defense > 0.0:
			var reduction: float = defense / (defense + 100.0)
			applied = maxi(1, int(float(amount) * (1.0 - reduction)))
	if health_component:
		# No _is_dead poke here: health_component.die() owns the dead flag
		# and early-returns when it is already set -- setting it first used
		# to make the proper death flow a silent no-op.
		health_component.current_health = maxi(0, health_component.current_health - applied)
		# Mirror onto the base Entity field: CombatSystem damage checks,
		# HUD binds and a11y/probe reads all use current_health -- the
		# old unmirrored field reported a full-health enemy after every
		# hit (R37: the a11y world-bridge probe found it).
		current_health = health_component.current_health
		health_changed.emit(
			health_component.current_health,
			health_component.max_health,
			-applied)
		if health_component.current_health <= 0:
			# Proper death flow: die() sets the component's _is_dead/_killer,
			# creates the corpse, emits health_depleted (-> _on_died: loot,
			# kill rewards, unregister) and EventHub.entity_died. Poking
			# _is_dead directly (the old code) skipped all of that.
			# Mirror death onto the base Entity fields BEFORE die(): the
			# whole die chain runs synchronously and is_alive() -- used by
			# CombatSystem hitbox sweeps and kill-credit checks -- must tell
			# the truth inside it, not just after it returns. Entity.die's
			# own convention is set-then-emit; the mirror now matches.
			is_dead = true
			current_health = 0
			health_component.die(source)
	else:
		current_health -= applied
		health_changed.emit(current_health, max_health)
		if current_health <= 0:
			# Entity.die sets is_dead, clears status effects, emits died.
			die(source)

	# HUD feed: the Enemy path bypasses health_component.take_damage (it
	# pokes the component directly), so the combat event is emitted here.
	# Crit flag rides along for DamageNumbers/log/toast styling.
	damage_dealt.emit(source, self, applied, damage_type, is_crit)
	EventHub.damage_dealt.emit(source, self, applied, damage_type, is_crit)

	# Threat: damage on this enemy builds the attacker's position on the
	# threat table (drives in-combat target switching in EnemyAI).
	# Duck-typed: the player body (CharacterBody3D, not an Entity subclass)
	# is the live player, and its attacks must build threat and grudges.
	var is_combatant: bool = source is Entity or (source is Node and "entity_id" in source)
	if aggro_component and is_combatant:
		aggro_component.add_damage_threat(source, amount)

	# Grudge memory + engagement: let the AI remember and fight back.
	if _ai and is_combatant:
		_ai.on_damaged(source)

	return amount

## A valid damager: live in-tree Node with a combatant id. Deliberately
## duck-typed so the player body (not an Entity subclass) qualifies.
func _is_valid_damager(node) -> bool:
	if node == null or not (node is Node):
		return false
	if not is_instance_valid(node) or not node.is_inside_tree():
		return false
	return "entity_id" in node or "player_id" in node

## Attach an EnemyAI brain and hook engagement callbacks.
## Training dummies refuse a brain: they never aggro, chase, or retaliate
## no matter which spawn pipeline attaches one (scene, SpawnService,
## horde waves, respawn cycle). Central gate keeps all five sites honest.
func attach_ai(ai) -> void:
	if is_training_dummy():
		return
	_ai = ai
	add_child(ai)


## True when the template marks this entity as a training dummy:
## take_damage is welcome, but no retaliation, no threat, no loot,
## no XP/gold. Duck-typed field check so test doubles stay safe.
func is_training_dummy() -> bool:
	return enemy_data != null and "is_dummy" in enemy_data \
			and bool(enemy_data.is_dummy)


func _on_died() -> void:
	GameLog.info("Enemy died: %s" % display_name)
	# Dummies pay nothing: no loot roll, no kill rewards. Death still
	# runs the normal unregister/free chain so respawn cycles rebuild them.
	if not is_training_dummy():
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
	# Node-level loot_table_id wins; fall back to the enemy_data schema
	# so scene-placed enemies (world_playable copies AI ranges but not
	# every data field) and any spawn path that only sets enemy_data
	# still roll their table.
	var table_id := loot_table_id
	if table_id.is_empty() and enemy_data != null:
		table_id = str(enemy_data.loot_table_id)
	if table_id.is_empty():
		return

	var path := "res://data/loot_tables/%s.tres" % table_id
	var table: LootTable = load(path) as LootTable
	if not table:
		GameLog.warn("Enemy: loot table not found for id '%s' (dropping base loot only)" % table_id)
		return

	var result := table.roll_drop()
	for item in result.items:
		GameLog.info("  loot: %s x%d" % [item.get("item_id", ""), item.get("quantity", 1)])

	for cid in result.currency:
		GameLog.info("  currency: %s %d" % [cid, result.currency[cid]])

	# Spawn a real ground drop at the corpse. GroundLootService resolves
	# the {item_id, quantity} dicts into Item instances. The gate matches
	# create_drop's own emptiness law (items OR currency): gating on items
	# alone silently threw away currency-only rolls -- with the shipped wolf
	# table ~46% of kills roll no item while 90% roll gold, so nearly half of
	# all kill loot (the coin) never reached the ground. Kill credit rides
	# along too so LootRulesService can apply party delegation rules.
	if GroundLootService and (not result.items.is_empty() or not result.currency.is_empty()):
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
