extends SceneTree
func _init() -> void:
	const RespawnService = preload("res://core/services/respawn_service.gd")
	const EntityService = preload("res://core/services/entity_service.gd")
	const Entity = preload("res://core/entities/entity.gd")
	const SkillSchema = preload("res://core/schemas/skill.gd")
	var s = load("res://core/schemas/skill.gd")
	print("skill:", s != null)
	quit(0)
