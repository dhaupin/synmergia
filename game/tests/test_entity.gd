extends SceneTree
func _init() -> void:
	for p in ["res://core/entities/entity.gd","game/entities/enemy.gd","res://core/entities/npc_entity.gd","res://core/entities/skill_academy_npc.gd"]:
		var s = load(p)
		print("LOADED", p, s != null)
	quit(0)
