extends SceneTree
func _init() -> void:
	await process_frame
	var svc = root.get_node_or_null("A11yService")
	var pm = root.get_node_or_null("PlayerManager")
	var PlayerScript = load("res://entities/player/player_controller.gd")
	var EnemyScript = load("res://entities/enemy.gd")
	var EnemyDataScript = load("res://core/schemas/enemy_data.gd")
	var es = root.get_node_or_null("EntityService")
	var player = PlayerScript.new()
	player.entity_id = "wp_player"
	if pm: pm.local_player = player
	root.add_child(player)
	await process_frame
	var enemy = EnemyScript.new()
	enemy.enemy_data = EnemyDataScript.new()
	enemy.entity_id = "wp_wolf"
	root.add_child(enemy)
	await process_frame
	if es: es.register_entity(enemy, null, "wp_wolf")
	await process_frame
	print("player=", player, " camera=", svc._camera())
	print("player pos=", player.global_position, " enemy pos=", enemy.global_position, " dist=", player.global_position.distance_to(enemy.global_position))
	var snap: Array = svc.snapshot()
	var world_entries := []
	for e in snap:
		if String(e["path"]).begins_with("world/"):
			world_entries.append(e["action"])
	print("world entries=", world_entries)
	quit(0)
