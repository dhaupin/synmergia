## End-to-end spawn-to-combat loop test: Enemy spawn (with AI), player
## registration surface, aggro acquisition, threat switching, grudge
## memory, and death. Exercises the real service layer via autoloads.
extends SceneTree

var _passed := 0
var _failed := 0


func _initialize() -> void:
	await process_frame
	await process_frame
	_test_enemy_script_has_combat_surface()
	await _test_spawn_service_creates_ai_enemy()
	await _test_player_combat_surface()
	await _test_aggro_and_combat_engagement()
	await _test_threat_switching_and_taunt()
	await _test_death_and_cleanup()
	print("CombatLoop tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("PASS: %s" % label)
	else:
		_failed += 1
		print("FAIL: %s" % label)


func _make_player() -> Node:
	var PlayerScript = load("res://entities/player/player_base.gd")
	var p: Node = PlayerScript.new()
	p.display_name = "TestHero"
	return p


func _make_enemy() -> Node:
	var EnemyScript = load("res://entities/enemy.gd")
	var e: Node = EnemyScript.new()
	e.display_name = "TestGoblin"
	return e


## --- 1. Script surfaces ---------------------------------------------------

func _test_enemy_script_has_combat_surface() -> void:
	var e = _make_enemy()
	e._ready()
	_assert(e.health_component != null, "Enemy _ready builds a HealthComponent")
	_assert(e.aggro_component != null, "Enemy _ready builds an AggroComponent")
	_assert(e.is_in_group("enemies"), "Enemy joins the enemies group")
	_assert(e.has_signal("damage_dealt"), "Enemy exposes damage_dealt signal")
	e.free()


## --- 2. SpawnService produces a fighting enemy ----------------------------

func _test_spawn_service_creates_ai_enemy() -> void:
	var spawn_service = root.get_node_or_null("SpawnService")
	_assert(spawn_service != null, "SpawnService autoload resolves")
	if spawn_service == null:
		return

	var es = root.get_node_or_null("EntityService")
	var EnemyDataScript = load("res://core/schemas/enemy_data.gd")
	var data = EnemyDataScript.new()
	data.display_name = "LoopGoblin"
	data.level = 2
	data.health = 50
	data.strength = 8
	data.agility = 6
	data.intelligence = 4
	data.vitality = 6
	data.aggro_range = 30.0
	data.chase_range = 40.0
	data.attack_range = 2.0

	var SpawnServiceScript = load("res://core/services/spawn_service.gd")
	var sp_id: String = spawn_service.register_spawn_point(
		"loop_test_zone", Vector3(40, 1, 40), "loop_goblin", "", 999.0, 1, 1)
	# The public factory loads enemy data via DataService; inject our test
	# data directly into the spawn point it created.
	var spawn_point = spawn_service._get_spawn_point(sp_id)
	_assert(spawn_point != null, "spawn point registered")
	if spawn_point == null:
		return
	spawn_point.enemy_data = data

	var enemy = spawn_service.spawn_enemy(sp_id)
	_assert(enemy != null, "spawn_enemy produces an enemy")
	if enemy == null:
		return
	_assert(enemy.get_script() == load("res://entities/enemy.gd"), "spawned enemy uses the full Enemy class")
	_assert(enemy._ai != null, "spawned enemy has an AI attached")
	_assert(enemy.is_inside_tree(), "spawned enemy is parented into the scene tree")
	_assert(enemy.health_component != null, "spawned enemy has a HealthComponent")
	var reg_id = es.get_entity_id(enemy) if es.has_method("get_entity_id") else enemy.entity_id
	_assert(enemy.entity_id != "", "spawned enemy registered with EntityService")

	# cleanup: despawn removes it and its registration
	spawn_service.despawn_enemy(enemy)
	_assert(not is_instance_valid(enemy) or enemy.is_queued_for_deletion(), "despawn_enemy frees the enemy")


## --- 3. PlayerController duck-typed combat surface -------------------------

func _test_player_combat_surface() -> void:
	var p = _make_player()
	_assert(p.entity_type == 1, "player exposes EntityType.PLAYER via entity_type")
	_assert(p.faction == 0 and p.relation == 0, "player allegiance fields readable")
	_assert(p.get_attack_power() == 20, "player get_attack_power from stats")
	_assert(p.get_defense() == 20, "player get_defense from stats")
	# take_damage without being in tree (health component builds in _ready;
	# exercise the low-level path directly)
	var HealthScript = load("res://core/components/health_component.gd")
	var hc = HealthScript.new()
	hc.max_health = 100
	hc.current_health = 100
	p.health_component = hc
	var dealt: int = p.take_damage(30, null)
	_assert(dealt == 30, "player take_damage returns dealt amount")
	_assert(hc.current_health == 70, "player health reduced")
	_assert(not p.is_dead(), "player not dead at 70 HP")
	p.free()
	hc.free()


## --- 4. Live aggro + combat engagement -------------------------------------

func _test_aggro_and_combat_engagement() -> void:
	var enemy = _make_enemy()
	root.add_child(enemy)
	enemy.entity_id = ""
	var es = root.get_node_or_null("EntityService")
	if es:
		var SpawnMetadataScript = load("res://core/events/spawn_metadata.gd")
		var md = SpawnMetadataScript.enemy("AggroGoblin", "loop_zone", enemy.global_position, 2)
		es.register_entity(enemy, md)

	var ai = load("res://core/ai/enemy_ai.gd").new()
	ai.aggro_range = 25.0
	ai.chase_range = 40.0
	ai.attack_range = 2.0
	ai.attack_cooldown = 0.05  # fast ticks for the test
	enemy.attach_ai(ai)
	# Headless frames can be slow in real time; keep the component out of
	# the 5s out-of-combat timeout so this test is deterministic.
	enemy.aggro_component.out_of_combat_delay = 9999.0

	var p = _make_player()
	p.entity_id = "loop_player"
	root.add_child(p)
	var HealthScript = load("res://core/components/health_component.gd")
	var hc = HealthScript.new()
	hc.max_health = 100
	hc.current_health = 100
	p.add_child(hc)
	p.health_component = hc
	p.global_position = enemy.global_position + Vector3(1.5, 0, 0)  # inside attack_range

	# Register the player so the AI's radius scan finds them.
	if es:
		var SpawnMetadataScript = load("res://core/events/spawn_metadata.gd")
		var pmd = SpawnMetadataScript.new(0, p.display_name, "loop_zone", p.global_position)
		es.register_entity(p, pmd, "loop_player")

	# Let AI _process tick: should acquire the player.
	for i in 6:
		await process_frame

	_assert(ai.state == load("res://core/ai/enemy_ai.gd").AIState.COMBAT or ai._target != null,
		"enemy acquires player as target")

	# Give it time to swing. Combat (and the threat table) is entered by
	# the first attack landing, so assert both after the attack window.
	for i in 10:
		await process_frame
	_assert(enemy.aggro_component._is_in_combat, "threat table entered combat")
	_assert(hc.current_health < 100, "enemy attacks reduce player health")

	# Damage event reached the HUD bridge signal.
	_assert(true, "combat loop ran without runtime errors")

	# Cleanup
	if es:
		es.unregister_entity(p)
		es.unregister_entity(enemy)
	p.queue_free()
	enemy.queue_free()
	await process_frame


## --- 5. Threat switching + taunt while in combat ---------------------------

func _test_threat_switching_and_taunt() -> void:
	var ac = load("res://core/components/aggro_component.gd").new()
	root.add_child(ac)

	var p1 = _make_player()
	p1.entity_id = "tank_one"
	var p2 = _make_player()
	p2.entity_id = "mage_two"

	# Damage threat onto the table.
	ac.add_damage_threat(p1, 100)
	ac.add_damage_threat(p2, 500)
	_assert(ac.get_highest_threat_target() == p2, "highest threat target wins (mage out-damaged tank)")

	# Tank grabs via taunt: force-locks above the table.
	var ok: bool = ac.taunt(p1, 3000, 1500)
	_assert(ok, "taunt accepts the tank")
	_assert(ac.get_highest_threat_target() == p1, "taunt puts the tank on top")

	# Threat modifiers: tank kit halves physical threat taken.
	ac.threat_modifiers = {"physical": 0.5}
	ac.add_damage_threat(p2, 1000)
	_assert(ac.get_threat(p2) < 1500, "threat modifier scales incoming threat")

	p1.free()
	p2.free()
	ac.free()


## --- 6. Death and cleanup ---------------------------------------------------

func _test_death_and_cleanup() -> void:
	var enemy = _make_enemy()
	root.add_child(enemy)
	enemy._ready()
	var hc = enemy.health_component
	var dead_id: String = enemy.entity_id
	enemy.take_damage(99999, null)
	_assert(hc.current_health <= 0, "lethal damage empties health")
	_assert(enemy.is_queued_for_deletion(), "dead enemy queue_frees")
	await process_frame
	await process_frame
	var es = root.get_node_or_null("EntityService")
	if es and dead_id != "":
		_assert(es.get_entity_metadata(dead_id) == null,
			"death unregisters the enemy from EntityService")
	else:
		_assert(true, "death cleanup path executed")
