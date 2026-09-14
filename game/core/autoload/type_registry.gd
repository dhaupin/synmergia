## TypeRegistry - Registers all custom types for cross-reference resolution
extends Node

# Module-level preloads. These run when this script's MODULE loads,
# which is BEFORE _ready() on any autoload -- and because RegisterTypes
# is autoload #3 (after AdapterRegistry and BackendFactory), its module
# loads before every other autoload's module too. That is what makes
# bare `Entity`, `PersistenceStore`, `CacheStore`, `MemoryStore`
# resolvable as type annotations in scripts that load later.
#
# Without these, the class_name only registers when the script is
# actually instantiated, which is too late for `var x: Entity` /
# `extends Entity` in files that parse before this autoload _ready().
#
# Scope: base classes and Entity only. Concrete services/UI are NOT
# preloaded here -- they have their own dependency chains and pulling
# them in at module-load time created circular preload failures. They
# are loaded lazily by the code that needs them.
const Entity = preload("res://core/entities/entity.gd")
const StatusEffect = preload("res://core/entities/status_effect.gd")
const PersistenceStore = preload("res://adapters/persistence/persistence_store.gd")
const CacheStore = preload("res://adapters/cache/cache_store.gd")
const MemoryStore = preload("res://adapters/memory_layer/memory_store.gd")
const DictStore = preload("res://adapters/persistence/dict_store.gd")
const Item = preload("res://core/schemas/item.gd")

func _ready() -> void:
	# No-op at runtime. The actual registration is the module-level
	# preloads above, which run at parse time. The old body called
	# GameLog.debug(...) bare, which is a forward reference under
	# --script mode (GameLog is autoload #15, this is #12, and
	# autoloads are not bare globals there). GDScript resolves
	# identifiers in function bodies at compile time, so that bare
	# reference cascaded into "Identifier not found" for every file
	# depending on this autoload. The call was cosmetic; removed.
	pass