extends SceneTree
func _init() -> void:
	await process_frame
	var pm = root.get_node_or_null("PlayerManager")
	var es = root.get_node_or_null("EntityService")
	var tm = root.get_node_or_null("TargetingManager")
	var PlayerScript = load("res://entities/player/player_controller.gd")
	var EnemyScript = load("res://entities/enemy.gd")
	var EnemyDataScript = load("res://core/schemas/enemy_data.gd")
	var player = PlayerScript.new()
	player.entity_id = "ap3_player"
	pm.local_player = player
	root.add_child(player)
	await process_frame
	var enemy = EnemyScript.new()
	var ed = EnemyDataScript.new()
	ed.display_name = "Wolf"
	enemy.enemy_data = ed
	root.add_child(enemy)
	await process_frame
	es.register_entity(enemy, null, "ap3_wolf")
	await process_frame
	tm.set_target("ap3_wolf", "ap3_wolf", "Wolf", enemy.global_position, enemy, 2, {})
	await process_frame
	var skill = player.skillbar[0]
	print("skill_type=", skill.skill_type, " is_hitbox=", skill.skill_type in [skill.SkillType.MELEE, skill.SkillType.RANGED, skill.SkillType.GROUND_TARGETED, skill.SkillType.TARGETED_AOE])
	print("CombatSystem registered player: ", root.get_node_or_null("CombatSystem")._entities.has(player.entity_id) if root.get_node_or_null("CombatSystem") else "?")
	var cs = root.get_node_or_null("CombatSystem")
	if cs:
		print("wolf registered: ", cs._entities.has("ap3_wolf"), " all keys=", cs._entities.keys().slice(0, 6))
	seed(12345)
	player.use_skill(0)
	await process_frame; await process_frame
	print("after cast: gcd=", player.combat_component.gcd_remaining if player.combat_component else "?", " enemy hp=", enemy.current_health)
	await create_timer(0.4).timeout
	print("enemy hp=", enemy.current_health)
	quit(0)
