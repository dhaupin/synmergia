extends SceneTree

# Load each adapter file individually and report which ones fail to parse.
const TARGETS := [
	"res://adapters/persistence/persistence_store.gd",
	"res://adapters/cache/cache_store.gd",
	"res://adapters/memory_layer/memory_store.gd",
	"res://adapters/persistence/memory_persistence_store.gd",
	"res://adapters/persistence/postgres_store.gd",
	"res://adapters/cache/memory_cache_store.gd",
	"res://adapters/cache/redis_store.gd",
	"res://adapters/registry.gd",
	"res://adapters/backend_factory.gd",
	"res://core/entities/entity.gd",
]

func _init() -> void:
	print("--- adapter parse check ---")
	for path in TARGETS:
		var script = load(path)
		if script == null:
			print("  [FAIL] %s" % path)
		else:
			print("  [PASS] %s" % path)
	quit(0)
