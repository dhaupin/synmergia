## PlayerProgress - persistent progression for the local player
## Saves xp/gold/level/position through the adapter layer (DictStore ->
## PersistenceStore) and restores it when the character spawns into the
## world. The authoritative stats live on the player node (duck-typed
## progression surface added to PlayerController); PlayerManager keeps
## its own mirror for the HUD. This service is the durable copy.
##
## Wire-up:
##   - world_playable calls restore_player(player) after registering it
##   - Checkpoints: kill_rewarded (coalesced), respawn_completed,
##     player_controller tree-exit (_exit_tree), and a 30s autosave tick.
##   - Store name "characters" from BackendFactory.STORE_MANIFEST; a
##     missing registry (script mode) falls back to a private DictStore
##     so tests still exercise the real save/load path.
##   - Frame bridge: every checkpoint also mirrors the snapshot into
##     StateSchema-typed state tree nodes (core/frame/bridge/
##     progress_bridge.gd) so the frame's canonical hashing and D027
##     diffing see character progress. Tree failure never blocks the
##     durable adapter-layer save.
extends Node

const DictStore = preload("res://adapters/persistence/dict_store.gd")
const ProgressBridgeScript = preload("res://core/frame/bridge/progress_bridge.gd")

## Character-node id -> last saved snapshot (dedupe + diagnostics).
var _last_saved: Dictionary = {}

## Minimum seconds between kill-driven saves: a pack pull pays out one
## checkpoint, not one per mob.
const KILL_SAVE_COOLDOWN: float = 5.0
var _last_kill_save_ms: int = 0

## Autosave interval while a character is tracked.
const AUTOSAVE_INTERVAL: float = 30.0
var _autosave_accum: float = 0.0

var _store: DictStore = null

## Frame bridge (state tree projection). Lazy: created on first
## checkpoint -- frame primitives are plain objects, nothing to wire
## at boot.
var _bridge = null

const _kv_prefix := "progress:char:"


func _ready() -> void:
	_store = _resolve_store()
	GameLog.info("PlayerProgress: Ready (store=%s)" % ("adapter" if _store != null else "unavailable"))

	if EventHub:
		if EventHub.has_signal("kill_rewarded") and not EventHub.kill_rewarded.is_connected(_on_kill_rewarded):
			EventHub.kill_rewarded.connect(_on_kill_rewarded)
	if RespawnService:
		if RespawnService.has_signal("respawn_completed") \
				and not RespawnService.respawn_completed.is_connected(_on_respawn_completed):
			RespawnService.respawn_completed.connect(_on_respawn_completed)


func _process(delta: float) -> void:
	_autosave_accum += delta
	if _autosave_accum < AUTOSAVE_INTERVAL:
		return
	_autosave_accum = 0.0
	for character_id in _last_saved.keys():
		var player: Node = _find_tracked_player(character_id)
		if player != null:
			save_player(player, "autosave")


## Resolve the shared persistence store through the adapter registry.
## Registry absent (script mode) -> plain DictStore (its own shared
## fallback). Registry present but the name unregistered -> same; a
## memory-backend boot keeps everything in memory either way.
func _resolve_store() -> DictStore:
	if get_tree() != null:
		var reg: Node = get_tree().root.get_node_or_null("AdapterRegistry")
		if reg != null and reg.has_method("get_persistence"):
			var backend = reg.get_persistence("characters")
			if backend != null:
				return _wrap(backend)
	return DictStore.new()


## Wrap a raw PersistenceStore in a DictStore view.
func _wrap(backend) -> DictStore:
	var store := DictStore.new()
	store.set_adapter_registry(null)
	store._store = backend
	return store


## Rebind after a test replaces the registry backend.
func set_store(backend) -> void:
	_store = _wrap(backend)
	# The old bridge holds the old store's data; rebuild the projection
	# from scratch on the new store.
	_bridge = null


## ---------------------------------------------------------------------------
## Save / load
## ---------------------------------------------------------------------------

## Snapshot the player's progression into the store. `reason` is
## diagnostics only (checkpoint kind).
func save_player(player: Node, reason: String = "checkpoint") -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if not ("entity_id" in player) or str(player.entity_id) == "":
		return false
	var character_id := str(player.entity_id)

	var snapshot: Dictionary = {
		"experience": int(player.experience) if "experience" in player else 0,
		"gold": int(player.gold) if "gold" in player else 0,
		"level": int(player.level) if "level" in player else 1,
	}
	if player is Node3D and player.is_inside_tree():
		# is_inside_tree guard: the exit checkpoint fires during scene
		# teardown, when the node is already out of the tree and
		# global_position errors ("!is_inside_tree()").
		var p: Vector3 = player.global_position
		snapshot["position"] = {"x": p.x, "y": p.y, "z": p.z}
	snapshot["saved_at"] = Time.get_unix_time_from_system()
	snapshot["reason"] = reason

	_store.set_kv(_kv_prefix + character_id, snapshot)
	_last_saved[character_id] = snapshot

	# Frame bridge: mirror the snapshot into StateSchema-typed state
	# tree nodes (pure, never throws into the durable path below).
	var bridge = _get_bridge()
	if bridge != null:
		bridge.write_progress(character_id, snapshot)
	return true


## Load a character's saved progression. Returns {} when the character
## has never been saved (fresh character keeps its defaults).
func load_progress(character_id: String) -> Dictionary:
	if character_id == "":
		return {}
	var stored = _store.get_kv(_kv_prefix + character_id)
	if stored is Dictionary and not stored.is_empty():
		return stored
	return {}


## Restore saved progression onto a freshly spawned character node.
## Returns true when a snapshot existed and was applied. Position only
## restores when the save is NEWER than the character's session start
## is unknowable, so it always applies: last session's logout point is
## the standard "continue where you left off" semantic. Callers that
## want a fixed entry point (intro sequences) can pass
## restore_position = false.
func restore_player(player: Node, restore_position: bool = true) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if not ("entity_id" in player) or str(player.entity_id) == "":
		return false
	var character_id := str(player.entity_id)
	var progress := load_progress(character_id)
	if progress.is_empty():
		return false

	if progress.has("experience") and "experience" in player:
		player.experience = int(progress["experience"])
	if progress.has("gold") and "gold" in player:
		player.gold = int(progress["gold"])
	if progress.has("level") and "level" in player:
		player.level = int(progress["level"])
		# Keep the level curve consistent with the restored level: XP
		# needed grows 1.5x per level from the 1000 base.
		if "experience_to_next_level" in player:
			player.experience_to_next_level = 1000
			for _i in range(maxi(0, player.level - 1)):
				player.experience_to_next_level = int(player.experience_to_next_level * 1.5)

	if restore_position and progress.has("position") and player is Node3D:
		var pos: Dictionary = progress["position"]
		if pos.has("x") and pos.has("y") and pos.has("z"):
			player.global_position = Vector3(
				float(pos["x"]), float(pos["y"]), float(pos["z"]))

	# Emit the same signals a fresh grant would so HUD bars hydrate.
	if player.has_signal("experience_changed"):
		player.experience_changed.emit(
			int(player.experience), int(player.level))
	if player.has_signal("gold_changed"):
		player.gold_changed.emit(int(player.gold))

	# Mirror into PlayerManager (the HUD reads it). Direct field writes:
	# load_character_data() would clobber name/class/race with defaults.
	if get_tree() != null:
		var pm: Node = get_tree().root.get_node_or_null("PlayerManager")
		if pm != null:
			if "experience" in pm:
				pm.experience = int(progress.get("experience", 0))
			if "gold" in pm:
				pm.gold = int(progress.get("gold", 0))
			if "level" in pm:
				pm.level = int(progress.get("level", 1))
			if "experience_to_next_level" in pm:
				pm.experience_to_next_level = 1000
				for _i in range(maxi(0, int(progress.get("level", 1)) - 1)):
					pm.experience_to_next_level = int(pm.experience_to_next_level * 1.5)
			if pm.has_signal("experience_changed"):
				pm.experience_changed.emit(pm.experience, pm.level)

	_last_saved[character_id] = progress
	GameLog.info("PlayerProgress: restored %s (lvl %d, %d xp, %d gold)" % [
		character_id, int(progress.get("level", 1)),
		int(progress.get("experience", 0)), int(progress.get("gold", 0))])
	return true


## True when this character has a durable snapshot.
func has_progress(character_id: String) -> bool:
	return not load_progress(character_id).is_empty()


## Drop a character's save (delete-character / test reset).
func clear_progress(character_id: String) -> void:
	_store.erase(_kv_prefix + character_id)
	_last_saved.erase(character_id)
	var bridge = _get_bridge()
	if bridge != null:
		bridge.clear_progress(character_id)


## Diagnostics: last snapshot captured for a character ({} if none).
func last_saved_snapshot(character_id: String) -> Dictionary:
	var snap = _last_saved.get(character_id, {})
	return snap.duplicate(true) if snap is Dictionary else {}


## ---------------------------------------------------------------------------
## Checkpoint hooks
## ---------------------------------------------------------------------------

## Any credited kill by the local player is a checkpoint candidate;
## coalesced so a pack pull writes once.
func _on_kill_rewarded(entity, killer, _rewards: Dictionary) -> void:
	if killer == null or not is_instance_valid(killer):
		return
	if not ("entity_id" in killer):
		return
	var now := Time.get_ticks_msec()
	if now - _last_kill_save_ms < int(KILL_SAVE_COOLDOWN * 1000.0):
		_pending_kill_saver(killer)
		return
	_last_kill_save_ms = now
	save_player(killer, "kill")


## A kill checkpoint was skipped by the cooldown; schedule one save at
## the end of the window instead of dropping the progress silently.
func _pending_kill_saver(killer: Node) -> void:
	var timer := get_tree().create_timer(KILL_SAVE_COOLDOWN)
	timer.timeout.connect(func():
		if killer != null and is_instance_valid(killer) \
				and "entity_id" in killer:
			save_player(killer, "kill_coalesced"))


## Coming back to life is a natural anchor point (and the position the
## player will actually resume from).
func _on_respawn_completed(player, _position: Vector3) -> void:
	save_player(player, "respawn")


## ---------------------------------------------------------------------------
## Helpers
## ---------------------------------------------------------------------------

## The autosave tick looks players up by id; the world scene registers
## them with EntityService, so resolve through it (with a scene-walk
## fallback for tests that never registered).
func _find_tracked_player(character_id: String) -> Node:
	if EntityService and EntityService.has_method("get_entity"):
		var found = EntityService.get_entity(character_id)
		if found != null and is_instance_valid(found):
			return found
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("players")


## Direct set for tests that need to simulate a stale save.
func _debug_set_raw(character_id: String, snapshot: Dictionary) -> void:
	_store.set_kv(_kv_prefix + character_id, snapshot)


## ---------------------------------------------------------------------------
## Frame bridge (PlayerProgress -> StateSchema state tree)
## ---------------------------------------------------------------------------

## Diagnostics/test access to the bridge projection.
func state_tree_bridge():
	return _get_bridge()


func _get_bridge():
	if _bridge == null:
		_bridge = ProgressBridgeScript.new()
	return _bridge
