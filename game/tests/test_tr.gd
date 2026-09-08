extends SceneTree
func _init() -> void:
	# Simulate normal boot: pre-resolve the autoloads type_registry needs.
	const GameLog = preload("res://core/autoload/logger.gd")
	const Entity = preload("res://core/entities/entity.gd")
	const RespawnService = preload("res://core/services/respawn_service.gd")
	const StatusEffect = preload("res://core/entities/status_effect.gd")
	var s = load("res://core/autoload/type_registry.gd")
	print("type_registry:", s != null)
	quit(0)
