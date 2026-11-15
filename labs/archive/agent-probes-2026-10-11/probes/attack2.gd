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
	player.entity_id = "ap2_player"
	pm.local_player = player
	root.add_child(player)
	await process_frame
	var enemy = EnemyScript.new()
	var ed = EnemyDataScript.new()
	ed.display_name = "Wolf"
	enemy.enemy_data = ed
	root.add_child(enemy)
	await process_frame
	es.register_entity(enemy, null, "ap2_wolf")
	await process_frame
	var eid: String = "ap2_wolf"
	tm.set_target(eid, eid, "Wolf", enemy.global_position, enemy, 2, {})
	await process_frame
	var tgt = tm.get_current_target()
	print("target set: ", tgt != null and tgt.id != "", " node matches: ", tgt != null and tgt.node == enemy)
	var skill = player.skillbar[0] if player.skillbar.size() > 0 else null
	print("skill=", skill, " can_cast=", skill.can_cast(player) if skill else false)
	seed(42)
	player.use_skill(0)
	await create_timer(0.5).timeout
	print("enemy hp=", enemy.current_health, "/", enemy.max_health, " dead=", enemy.is_dead)
	quit(0)
