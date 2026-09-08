extends SceneTree
func _init() -> void:
	var s = preload("res://adapters/persistence/memory_persistence_store.gd")
	print("loaded:", s)
	quit(0)
