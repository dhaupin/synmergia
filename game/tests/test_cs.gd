extends SceneTree
func _init() -> void:
	const Entity = preload("res://core/entities/entity.gd")
	const SkillSchema = preload("res://core/schemas/skill.gd")
	var s = load("res://core/combat/skill.gd")
	print("combat/skill:", s != null)
	quit(0)
