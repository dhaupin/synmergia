extends SceneTree
func _init() -> void:
	await process_frame
	var EnemyScript = load("res://entities/enemy.gd")
	var EnemyDataScript = load("res://core/schemas/enemy_data.gd")
	var enemy = EnemyScript.new()
	var ed = EnemyDataScript.new()
	ed.display_name = "Wolf"
	enemy.enemy_data = ed
	root.add_child(enemy)
	await process_frame
	print("enemy hp field=", enemy.current_health, " hc.current=", enemy.health_component.current_health, " hc.max=", enemy.health_component.max_health, " max_health=", enemy.max_health)
	print("enemy_data.armor=", ed.armor if "armor" in ed else "?")
	enemy.take_damage(10, null, "physical")
	print("after 10dmg: field=", enemy.current_health, " hc=", enemy.health_component.current_health)
	quit(0)
