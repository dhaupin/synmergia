extends SceneTree
func _init() -> void:
	const Entity = preload("res://core/entities/entity.gd")
	var e = Entity.new()
	print("Entity.new() =>", e != null, " type=", e.get_class())
	print("EntityType.PLAYER =", Entity.EntityType.PLAYER)
	quit(0)
