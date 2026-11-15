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
	player.entity_id = "ap4_player"
	pm.local_player = player
	root.add_child(player)
	await process_frame
	var enemy = EnemyScript.new()
	var ed = EnemyDataScript.new()
	ed.display_name = "Wolf"
	enemy.enemy_data = ed
	root.add_child(enemy)
	await process_frame
	es.register_entity(enemy, null, "ap4_wolf")
	await process_frame
	tm.set_target("ap4_wolf", "ap4_wolf", "Wolf", enemy.global_position, enemy, 2, {})
	await process_frame
	seed(777)
	player.use_skill(0)
	await process_frame; await process_frame
	print("after cast: enemy hp=", enemy.current_health)
	await create_timer(0.5).timeout
	print("final enemy hp=", enemy.current_health, " dead=", enemy.is_dead)
	quit(0)
