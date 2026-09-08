extends SceneTree
func _init() -> void:
	for p in ["res://core/events/event_hub.gd","res://core/services/cooldown_service.gd","res://adapters/migrations/migration_runner.gd"]:
		var s = load(p)
		print("LOADED", p, s != null)
	quit(0)
