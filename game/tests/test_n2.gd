extends SceneTree
func _init() -> void:
	var s = load("res://core/entities/npc_entity.gd")
	print("npc:", s != null)
	quit(0)
