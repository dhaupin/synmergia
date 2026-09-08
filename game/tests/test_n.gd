extends SceneTree
func _init() -> void:
	var s = load("res://core/entities/entity.gd")
	var s2 = load("res://core/entities/npc_entity.gd")
	print("entity:", s != null, "npc:", s2 != null)
	quit(0)
