extends SceneTree
func _init() -> void:
	await process_frame
	var pm = root.get_node_or_null("PlayerManager")
	var es = root.get_node_or_null("EntityService")
	var PlayerScript = load("res://entities/player/player_controller.gd")
	var EnemyScript = load("res://entities/enemy.gd")
	var EnemyDataScript = load("res://core/schemas/enemy_data.gd")
	var player = PlayerScript.new()
	player.entity_id = "ap_player"
	pm.local_player = player
	root.add_child(player)
	await process_frame
	var enemy = EnemyScript.new()
	var ed = EnemyDataScript.new()
	ed.display_name = "Wolf"
	enemy.enemy_data = ed
	root.add_child(enemy)
	await process_frame
	es.register_entity(enemy, null, "ap_wolf")
	await process_frame
	print("player has use_skill=", player.has_method("use_skill"), " cc=", player.combat_component)
	if player.combat_component != null:
		print("cc methods: find_first_ready_skill=", player.combat_component.has_method("find_first_ready_skill"), " skillbar=", "skillbar" in player)
	print("player.skillbar size=", player.skillbar.size() if "skillbar" in player else "?")
	for i in range(player.skillbar.size() if "skillbar" in player else 0):
		print("  slot ", i, ": ", player.skillbar[i])
	seed(37)
	player.use_skill(0)
	await create_timer(0.4).timeout
	print("enemy hp=", enemy.current_health, "/", enemy.max_health)
	quit(0)
