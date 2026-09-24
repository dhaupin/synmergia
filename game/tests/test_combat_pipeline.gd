## Combat pipeline end-to-end: registration -> hitbox -> damage -> death.
## Run: godot --headless --path . --script res://tests/test_combat_pipeline.gd
## Covers the "hitboxes swept an empty registry" regression: EntityService
## now mirrors registrations into CombatSystem, and HitboxData carries
## String entity ids.
extends SceneTree

const EntityScript = null  # resolved at runtime; see _load_scripts()
var SkillScript: GDScript = null

var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		printerr("FAIL  ", label)
		_fails += 1

func _run() -> void:
	root.get_node_or_null("GameLog")
	await process_frame

	# entity.gd/skill.gd reference the EventHub autoload at compile time; a
	# parse-time preload in --script mode poisons the cached script (compile
	# fails before autoloads exist, then .new() vanishes mid-test). Runtime
	# load() after boot is the repo's de-flake pattern.
	var entity_script: GDScript = load("res://core/entities/entity.gd")
	SkillScript = load("res://core/combat/skill.gd")
	if entity_script == null or not entity_script.can_instantiate() or SkillScript == null or not SkillScript.can_instantiate():
		printerr("FAIL  entity/skill failed to compile after boot (EventHub ordering regression)")
		quit(1)
		return

	var es = root.get_node_or_null("EntityService")
	var cs = root.get_node_or_null("CombatSystem")
	_check(es != null, "EntityService autoload present")
	_check(cs != null, "CombatSystem autoload present")

	# --- Build a caster and a target enemy, register like production does
	# (world_playable.gd calls es.register_entity explicitly) ---
	var caster = entity_script.new()
	caster.display_name = "CombatTester"
	caster.entity_type = entity_script.EntityType.PLAYER
	root.add_child(caster)
	await process_frame

	var enemy = load("res://entities/enemy.gd").new()
	enemy.display_name = "TrainingDummy"
	enemy.starting_health = 50
	root.add_child(enemy)
	await process_frame

	var caster_id: String = es.register_entity(caster)
	var enemy_id: String = es.register_entity(enemy)
	_check(caster_id != "", "caster registered with EntityService")
	_check(enemy_id != "", "enemy registered with EntityService")

	# --- Registration mirrors into the combat registry ---
	_check(caster.entity_id != "", "caster got an entity_id from EntityService")
	_check(enemy.entity_id != "", "enemy got an entity_id from EntityService")
	_check(cs.registered_entities.has(caster.entity_id),
		"caster mirrored into CombatSystem registry")
	_check(cs.registered_entities.has(enemy.entity_id),
		"enemy mirrored into CombatSystem registry")

	# --- Basic attack skill ---
	# Untyped for the same EventHub-ordering reason as _run()'s guard.
	var skill = SkillScript.new()
	skill.skill_name = "TestStrike"
	skill.skill_id = "test_strike"
	skill.damage = 10
	skill.mana_cost = 0
	skill.cast_time = 0.0
	skill.animation_duration = 0.1
	skill.range = 3.0
	skill.hitbox_size = 2.0
	skill.allow_movement = true

	# Position the dummy inside the hitbox radius, in front of the caster.
	caster.global_position = Vector3(0, 0, 0)
	enemy.global_position = Vector3(0, 0, -1.0)

	var hp_before: int = enemy.health_component.current_health
	_check(hp_before > 0, "enemy starts alive (hp=%d)" % hp_before)

	# --- Create the hitbox exactly like the attack state does ---
	cs.create_hitbox(caster, skill, null, Vector3.ZERO)
	_check(cs.active_hitboxes.size() == 1, "hitbox created")

	# Wait past hitbox duration; _physics_process sweeps it.
	for i in range(30):
		await physics_frame
		if cs.active_hitboxes.is_empty():
			break

	_check(cs.active_hitboxes.is_empty(), "hitbox expired after sweep")
	var hp_after: int = enemy.health_component.current_health
	_check(hp_after < hp_before,
		"enemy took damage via hitbox sweep (%d -> %d)" % [hp_before, hp_after])

	# --- Self-hit guard: the caster's own hp is untouched ---
	var caster_hp: int = caster.current_health
	_check(caster_hp == caster.max_health,
		"caster not hit by own hitbox (hp=%d)" % caster_hp)

	# --- Kill the enemy outright; died must fire ---
	var died_fired := [false]
	enemy.died.connect(func(_k): died_fired[0] = true)
	enemy.take_damage(99999, caster)
	# Capture deadness BEFORE awaiting: _on_died queue_free()d the enemy,
	# so any access after the next frame would hit a freed instance.
	var enemy_dead_before_free: bool = not enemy.is_alive()
	await process_frame
	_check(died_fired[0], "enemy died signal fired on lethal damage")
	_check(enemy_dead_before_free, "enemy reports dead")

	# --- Death cleanup: enemy._on_died already unregistered it from
	# EntityService (which mirrors into CombatSystem) and queue_free()d it.
	# Touching the freed instance here used to segfault the engine.
	await process_frame
	_check(not is_instance_valid(enemy) or not enemy.is_alive(),
		"dead enemy freed or inert (no zombie corpse)")
	_check(not cs.registered_entities.has(enemy_id),
		"death auto-unregistered enemy from combat registry")

	# --- Mirror-guard: direct register_entity still works ---
	var solo = entity_script.new()
	root.add_child(solo)
	await process_frame
	var solo_id: String = es.register_entity(solo)
	_check(solo_id != "" and cs.registered_entities.has(solo_id),
		"second entity registration mirrors into combat registry")
	es.unregister_entity(solo, "test_cleanup")
	_check(not cs.registered_entities.has(solo.entity_id),
		"second entity register/unregister roundtrip clean")

	print("SUMMARY: %d checks, %d failed" % [16, _fails])
	if _fails == 0:
		print("ALL TESTS PASSED")
	quit(0 if _fails == 0 else 1)
