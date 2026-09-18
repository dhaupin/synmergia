## OpenSeedRegistry - Tracks TTL for open instance seeds
##
## For open instance seeds (dungeons, arenas, raids), the seed is held in memory
## on the shard for a TTL duration (default 5 minutes) after the last character logout.
## Reconnecting within the window restores the same instance state.
## After TTL expiry, the instance state is finalized and GC'd.
##
## Spec: labs/prd-open-seed-ttl.md (D032)
extends Node

const InstanceTypeDefinitionScript = preload("res://core/schemas/instance_type_definition.gd")

## Signals
signal seed_registered(character_id: String, instance_type: String)
signal seed_expired(character_id: String, instance_type: String)
signal instance_finalized(character_id: String, snapshot: Dictionary)

const DEFAULT_TTL_MS: int = 300000  # 5 minutes

class RegistryEntry:
	var character_id: String
	var instance_seed: PackedByteArray
	var instance_type: String
	var last_logout_ms: int
	var ttl_ms: int
	var finalized: bool = false
	var state_tree_snapshot: Dictionary = {}

	func _init(p_char_id: String, p_seed: PackedByteArray, p_type: String, p_ttl_ms: int, p_logout_ms: int) -> void:
		character_id = p_char_id
		instance_seed = p_seed
		instance_type = p_type
		ttl_ms = p_ttl_ms
		last_logout_ms = p_logout_ms
		finalized = false
		state_tree_snapshot = {}

## Map of character_id -> RegistryEntry
var _entries: Dictionary = {}

## Cache of loaded instance type definitions: name -> int (ttl_ms)
var _type_ttl_cache: Dictionary = {}

## Custom finalizer callback: Callable(character_id: String, entry: RegistryEntry)
var _finalize_callback: Callable = Callable()

## GC sweep timer (runs every 60 seconds)
var _gc_timer: Timer

## GC sweep interval in seconds
const GC_SWEEP_INTERVAL_SEC: float = 60.0

func _ready() -> void:
	_load_instance_types()
	_start_gc_timer()
	GameLog.info("OpenSeedRegistry: Ready (loaded %d instance type definitions)" % _type_ttl_cache.size())

## Preloads instance type definitions from disk
func _load_instance_types() -> void:
	var dir_path := "res://data/roots/world/instance_types"
	var dir := DirAccess.open(dir_path)
	if not dir:
		GameLog.warn("OpenSeedRegistry: Instance types dir not found: %s" % dir_path)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res_path := dir_path + "/" + file_name
			var res: Resource = load(res_path)
			if res is InstanceTypeDefinitionScript:
				var def := res as InstanceTypeDefinitionScript
				_type_ttl_cache[def.name] = def.default_ttl_ms
		file_name = dir.get_next()
	dir.list_dir_end()

## Starts the periodic GC sweep timer
func _start_gc_timer() -> void:
	_gc_timer = Timer.new()
	_gc_timer.name = "GC_Sweep"
	_gc_timer.wait_time = GC_SWEEP_INTERVAL_SEC
	_gc_timer.autostart = true
	_gc_timer.one_shot = false
	_gc_timer.timeout.connect(_on_gc_timeout)
	add_child(_gc_timer)
	GameLog.info("OpenSeedRegistry: GC sweep timer started (interval: %.1fs)" % GC_SWEEP_INTERVAL_SEC)

## GC sweep timeout callback - runs every 60 seconds
func _on_gc_timeout() -> void:
	var swept := sweep_expired()
	if swept > 0:
		GameLog.info("OpenSeedRegistry: GC sweep finalized %d expired entries" % swept)

## Returns TTL in milliseconds for an instance type
func get_ttl_for_type(instance_type: String) -> int:
	if _type_ttl_cache.has(instance_type):
		return _type_ttl_cache[instance_type]
	return DEFAULT_TTL_MS

## Sets a custom finalize callback
func set_finalize_callback(cb: Callable) -> void:
	_finalize_callback = cb

## Registers an open instance seed for a character
func register(character_id: String, instance_seed: PackedByteArray, instance_type: String = "dungeon", custom_ttl_ms: int = -1) -> void:
	var ttl := custom_ttl_ms if custom_ttl_ms > 0 else get_ttl_for_type(instance_type)
	var now := int(Time.get_unix_time_from_system() * 1000.0)
	var entry := RegistryEntry.new(character_id, instance_seed, instance_type, ttl, now)
	_entries[character_id] = entry
	seed_registered.emit(character_id, instance_type)
	GameLog.info("OpenSeedRegistry: Registered %s for character %s (TTL: %d ms)" % [instance_type, character_id, ttl])

## Updates the last logout timestamp for a character (starts the TTL clock)
func touch_logout(character_id: String, logout_time_ms: int = -1) -> void:
	if not _entries.has(character_id):
		return
	var entry: RegistryEntry = _entries[character_id]
	var now := logout_time_ms if logout_time_ms >= 0 else int(Time.get_unix_time_from_system() * 1000.0)
	entry.last_logout_ms = now

## Looks up active instance seed for a character.
## If found and within TTL window, returns the PackedByteArray seed.
## If expired, calls finalize(), removes entry, and returns empty PackedByteArray.
func lookup(character_id: String, current_time_ms: int = -1) -> PackedByteArray:
	if not _entries.has(character_id):
		return PackedByteArray()
	var entry: RegistryEntry = _entries[character_id]
	var now := current_time_ms if current_time_ms >= 0 else int(Time.get_unix_time_from_system() * 1000.0)
	var elapsed := now - entry.last_logout_ms
	if elapsed < entry.ttl_ms:
		return entry.instance_seed
	# Expired! Finalize and invalidate
	seed_expired.emit(character_id, entry.instance_type)
	finalize(character_id)
	_entries.erase(character_id)
	return PackedByteArray()

## Removes entry without finalizing
func invalidate(character_id: String) -> void:
	if _entries.has(character_id):
		_entries.erase(character_id)

## Finalizes instance state for an expired or terminated instance.
## Idempotent: safe to call multiple times.
func finalize(character_id: String) -> bool:
	if not _entries.has(character_id):
		return false
	var entry: RegistryEntry = _entries[character_id]
	if entry.finalized:
		return false
	entry.finalized = true
	var snapshot := {
		"character_id": character_id,
		"instance_type": entry.instance_type,
		"instance_seed": entry.instance_seed.hex_encode(),
		"finalized_at_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"state": entry.state_tree_snapshot,
	}
	if _finalize_callback.is_valid():
		_finalize_callback.call(character_id, snapshot)
	instance_finalized.emit(character_id, snapshot)
	GameLog.info("OpenSeedRegistry: Finalized instance for character %s" % character_id)
	return true

## Attaches state snapshot before finalization
func set_state_snapshot(character_id: String, state_dict: Dictionary) -> void:
	if _entries.has(character_id):
		var entry: RegistryEntry = _entries[character_id]
		entry.state_tree_snapshot = state_dict

## Gets entry inspection dictionary
func get_entry(character_id: String) -> Dictionary:
	if not _entries.has(character_id):
		return {}
	var entry: RegistryEntry = _entries[character_id]
	return {
		"character_id": entry.character_id,
		"instance_seed": entry.instance_seed,
		"instance_type": entry.instance_type,
		"last_logout_ms": entry.last_logout_ms,
		"ttl_ms": entry.ttl_ms,
		"finalized": entry.finalized,
	}

## Sweeps and finalizes all expired entries
func sweep_expired(current_time_ms: int = -1) -> int:
	var now := current_time_ms if current_time_ms >= 0 else int(Time.get_unix_time_from_system() * 1000.0)
	var expired_keys: Array[String] = []
	for cid in _entries.keys():
		var entry: RegistryEntry = _entries[cid]
		if (now - entry.last_logout_ms) >= entry.ttl_ms:
			expired_keys.append(cid)
	for cid in expired_keys:
		finalize(cid)
		_entries.erase(cid)
	return expired_keys.size()

## Clears all entries (useful in testing)
func clear() -> void:
	_entries.clear()

## Stops the GC sweep timer
func stop_gc_timer() -> void:
	if _gc_timer and is_instance_valid(_gc_timer):
		_gc_timer.stop()
		_gc_timer.queue_free()
		_gc_timer = null
		GameLog.info("OpenSeedRegistry: GC sweep timer stopped")

func _exit_tree() -> void:
	stop_gc_timer()
