extends SceneTree

func _init() -> void:
	var bases := [
		preload("res://adapters/persistence/persistence_store.gd"),
		preload("res://adapters/cache/cache_store.gd"),
		preload("res://adapters/memory_layer/memory_store.gd"),
	]
	for b in bases:
		print("base -> %s" % [b])
	var subs := [
		preload("res://adapters/persistence/memory_persistence_store.gd"),
		preload("res://adapters/persistence/postgres_store.gd"),
		preload("res://adapters/cache/memory_cache_store.gd"),
		preload("res://adapters/cache/redis_store.gd"),
	]
	for s in subs:
		print("sub -> %s" % [s])
	quit(0)
