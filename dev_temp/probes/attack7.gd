extends SceneTree
func _init() -> void:
	await process_frame
	var pm = root.get_node_or_null("PlayerManager")
	var es = root.get_node_or_null("EntityService")
	var tm = root.get_node_or_null("TargetingManager")
	var cs = root.get_node_or_null("CombatSystem")
	var PlayerScript = load("res://entities/player/player_controller.gd")
	var EnemyScript = load("res://entities/enemy.gd")
	var EnemyDataScript = load("res://core/schemas/enemy_data.gd")
	var player = PlayerScript.new()
	player.entity_id = "ap7_player"
	pm.local_player = player
	root.add_child(player)
	var enemy = EnemyScript.new()
	var ed = EnemyDataScript.new()
	ed.display_name = "Wolf"
	enemy.enemy_data = ed
	root.add_child(enemy)
	await process_frame
	es.register_entity(enemy, null, "ap7_wolf")
	cs.register_entity(player)
	cs.register_entity(enemy)
	await process_frame
	tm.set_target("ap7_wolf", "ap7_wolf", "Wolf", enemy.global_position, enemy, 2, {})
	await process_frame
	# Direct damage sanity: does take_damage even move the number?
	enemy.take_damage(10, player, "physical")
	print("after take_damage(10): hp=", enemy.current_health)
	quit(0)
