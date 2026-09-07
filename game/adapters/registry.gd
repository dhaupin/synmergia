extends Node

# AdapterRegistry -- the single place services resolve their
# stores by name. Autoloaded as `AdapterRegistry`.
#
# Usage:
#   var store := AdapterRegistry.get_persistence("accounts")
#   var rows := store.query("SELECT * FROM accounts WHERE id = $1", [player_id])
#
#   var cache := AdapterRegistry.get_cache("sessions")
#   cache.set("session:%s" % token, account_id, 86400)
#
#   var mem := AdapterRegistry.get_memory("cooldowns")
#   if mem.exists(player_id):
#       ...
#
# Stores are registered at boot by the backend factory reading
# the env-driven manifest. Services should NEVER `new()` their
# own store -- always go through the registry so backend swaps
# (dev -> prod, prod -> test) Just Work.
#
# See:
#   - prd-db.md sec.5 (architecture)
#   - prd-db.md sec.8 (service-to-store wiring)


const MemoryPersistenceStore = preload("res://adapters/persistence/memory_persistence_store.gd")
const MemoryCacheStore = preload("res://adapters/cache/memory_cache_store.gd")
const PostgresStore = preload("res://adapters/persistence/postgres_store.gd")
const RedisStore = preload("res://adapters/cache/redis_store.gd")


var _persistence: Dictionary = {}  # name -> PersistenceStore
var _cache: Dictionary = {}        # name -> CacheStore
var _memory: Dictionary = {}       # name -> MemoryStore


func _ready() -> void:
	# The backend factory registers defaults at boot. We don't
	# pre-register anything here so tests can control it.
	pass


# --- Registration ---

func register_persistence(name: String, store: PersistenceStore) -> void:
	_persistence[name] = store


func register_cache(name: String, store: CacheStore) -> void:
	_cache[name] = store


func register_memory(name: String, store: MemoryStore) -> void:
	_memory[name] = store


# --- Lookup ---
# Returns null if the name isn't registered. Callers should
# handle null defensively (especially in early boot).

func get_persistence(name: String) -> PersistenceStore:
	return _persistence.get(name, null)


func get_cache(name: String) -> CacheStore:
	return _cache.get(name, null)


func get_memory(name: String) -> MemoryStore:
	return _memory.get(name, null)


# --- Introspection (for tests + dev tooling) ---

func persistence_names() -> Array:
	return _persistence.keys()


func cache_names() -> Array:
	return _cache.keys()


func memory_names() -> Array:
	return _memory.keys()


func is_registered_persistence(name: String) -> bool:
	return _persistence.has(name)


func is_registered_cache(name: String) -> bool:
	return _cache.has(name)


func is_registered_memory(name: String) -> bool:
	return _memory.has(name)


# --- Test helpers (not for production use) ---

func reset_for_tests() -> void:
	_persistence.clear()
	_cache.clear()
	_memory.clear()
