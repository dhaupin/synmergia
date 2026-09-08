extends SceneTree
func _init() -> void:
	const Entity = preload("res://core/entities/entity.gd")
	var s = load("res://core/autoload/type_registry.gd")
	print("type_registry:", s != null)
	quit(0)
