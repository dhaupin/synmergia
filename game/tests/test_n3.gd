extends SceneTree
func _init() -> void:
	const Entity = preload("res://core/entities/entity.gd")
	var s = load("res://core/entities/npc_entity.gd")
	print("npc:", s != null)
	quit(0)
