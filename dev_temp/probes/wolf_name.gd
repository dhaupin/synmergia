extends SceneTree
func _init() -> void:
	await process_frame
	var EnemyScript = load("res://entities/enemy.gd")
	var EnemyDataScript = load("res://core/schemas/enemy_data.gd")
	var enemy = EnemyScript.new()
	var ed = EnemyDataScript.new()
	print("ed.display_name before assign: '", ed.display_name, "'")
	enemy.enemy_data = ed
	root.add_child(enemy)
	await process_frame
	print("enemy.display_name after add: '", enemy.display_name, "'")
	quit(0)
