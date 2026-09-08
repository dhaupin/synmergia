extends SceneTree
func _init() -> void:
	# Preload the base first so its class_name registers globally.
	var _ps = preload("res://adapters/persistence/persistence_store.gd")
	var _cs = preload("res://adapters/cache/cache_store.gd")
	var _ms = preload("res://adapters/memory_layer/memory_store.gd")
	print("bases preloaded")
	# Now the subclass should resolve its base.
	var mps = preload("res://adapters/persistence/memory_persistence_store.gd")
	print("memory_persistence_store:", mps)
	quit(0)
