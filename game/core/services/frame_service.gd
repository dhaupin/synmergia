## FrameService - Server-authoritative frame seed and state management
##
## A "frame" is a transient, scoped environment (dream, tutorial, jail).
## The server generates the frame_seed on entry, sends it to the client
## for visual determinism. The frame's state tree is empty on creation.
## Persistent state (XP, items) goes to the player's state tree, not
## the frame tree. The frame env is GC'd at frame exit.
##
## Spec: labs/prd-frame-authority.md
extends Node

const T3Script = preload("res://core/frame/kv/t3.gd")
const StateTreeScript = preload("res://core/frame/kv/state_tree.gd")
const SeedChainScript = preload("res://core/frame/kv/seed_chain.gd")

signal frame_entered(player_id: String, frame_id: String, frame_seed: PackedByteArray)
signal frame_exited(player_id: String, frame_id: String)

## Emitted whenever the shared world state tree's root hash changes.
## Client resync keys off this: compare the hash you last synced
## against world_root_hash() and request a scope snapshot on mismatch.
signal world_state_changed(root_hash: PackedByteArray)

class FrameEnv:
	var frame_id: String
	var frame_seed: PackedByteArray
	var seed_tree: T3Script
	var state_tree: StateTreeScript
	var entered_at: int

	func _init(fid: String, fseed: PackedByteArray) -> void:
		frame_id = fid
		frame_seed = fseed
		seed_tree = T3Script.new()
		state_tree = StateTreeScript.new()
		entered_at = Time.get_unix_time_from_system()

var _player_frames: Dictionary = {}   # player_id -> Array[FrameEnv]
var _player_state_trees: Dictionary = {}  # player_id -> StateTreeScript

## Shared world state tree (outside any frame): the canonical runtime
## projection of character + world entity state. The frame bridges
## write into it (core/frame/bridge/*); every mutation announces the
## new root hash via world_state_changed so resync can key off it.
var _world_state_tree: StateTreeScript = null
var _world_root_hash: PackedByteArray = PackedByteArray()

func _ready() -> void:
	GameLog.info("FrameService: Ready")

## Enters a frame for the given player.
## Generates a new frame_seed, initializes empty seed_tree and state_tree.
## Returns true on success, false if player already in a frame.
func enter_frame(player_id: String, frame_id: String) -> bool:
	if _player_frames.has(player_id):
		var stack: Array = _player_frames[player_id]
		if stack.size() > 0:
			GameLog.warn("FrameService: %s already in frame %s" % [player_id, stack[-1].frame_id])
			return false

	var crypto := Crypto.new()
	var frame_seed = crypto.generate_random_bytes(32)
	var env = FrameEnv.new(frame_id, frame_seed)

	if not _player_frames.has(player_id):
		_player_frames[player_id] = []
	_player_frames[player_id].append(env)

	GameLog.info("FrameService: %s entered frame %s" % [player_id, frame_id])
	frame_entered.emit(player_id, frame_id, frame_seed)
	return true

## Exits the current frame for the given player.
## Pops the scope, GCs the frame env, emits frame_exited signal.
## Returns true on success, false if player not in a frame.
func exit_frame(player_id: String) -> bool:
	if not _player_frames.has(player_id):
		return false
	var stack: Array = _player_frames[player_id]
	if stack.is_empty():
		return false

	var env: FrameEnv = stack.pop_back()
	var frame_id = env.frame_id

	if env.seed_tree != null:
		env.seed_tree.clear()
		env.seed_tree = null
	if env.state_tree != null:
		env.state_tree.clear()
		env.state_tree = null

	if stack.is_empty():
		_player_frames.erase(player_id)

	GameLog.info("FrameService: %s exited frame %s" % [player_id, frame_id])
	frame_exited.emit(player_id, frame_id)
	return true

## Returns the current frame_seed for the player, or empty if not in frame.
func get_frame_seed(player_id: String) -> PackedByteArray:
	if not _player_frames.has(player_id):
		return PackedByteArray()
	var stack: Array = _player_frames[player_id]
	if stack.is_empty():
		return PackedByteArray()
	return stack[-1].frame_seed

## Returns the current frame's seed tree, or null if not in frame.
func get_seed_tree(player_id: String) -> Variant:
	if not _player_frames.has(player_id):
		return null
	var stack: Array = _player_frames[player_id]
	if stack.is_empty():
		return null
	return stack[-1].seed_tree

## Returns the current frame's state tree, or null if not in frame.
func get_state_tree(player_id: String) -> Variant:
	if not _player_frames.has(player_id):
		return null
	var stack: Array = _player_frames[player_id]
	if stack.is_empty():
		return null
	return stack[-1].state_tree

## Returns the player's persistent state tree (outside any frame).
## Creates it on first access.
func get_player_state_tree(player_id: String) -> StateTreeScript:
	if not _player_frames.has(player_id):
		_player_frames[player_id] = []
	var stack: Array = _player_frames[player_id]

	if not _player_state_trees.has(player_id):
		_player_state_trees[player_id] = StateTreeScript.new()
	return _player_state_trees[player_id]

## Sets a custom state tree for the player (for testing/restore).
func set_state_tree(player_id: String, tree: StateTreeScript) -> void:
	if not _player_state_trees.has(player_id):
		_player_state_trees[player_id] = StateTreeScript.new()
	_player_state_trees[player_id] = tree

## Returns true if the player is currently in a frame.
func in_frame(player_id: String) -> bool:
	if not _player_frames.has(player_id):
		return false
	return not _player_frames[player_id].is_empty()

## Returns the current frame_id for the player, or empty string if not in frame.
func get_current_frame_id(player_id: String) -> String:
	if not _player_frames.has(player_id):
		return ""
	var stack: Array = _player_frames[player_id]
	if stack.is_empty():
		return ""
	return stack[-1].frame_id


## ---------------------------------------------------------------------------
## Shared world state tree
## ---------------------------------------------------------------------------

## The canonical world state tree (outside any frame). Created lazily;
## every writer writes through touch_world_tree() so the root hash and
## the change signal stay authoritative in ONE place.
func get_world_state_tree() -> StateTreeScript:
	if _world_state_tree == null:
		_world_state_tree = StateTreeScript.new()
	return _world_state_tree

## Announce a mutation: recompute the root hash, emit world_state_changed.
## Writers call this AFTER their inserts (hash_subtree("/") reflects the
## current tree). Safe to call multiple times for one batch.
func touch_world_tree() -> void:
	var tree := get_world_state_tree()
	var hash: PackedByteArray = tree.root_hash()
	if hash != _world_root_hash:
		_world_root_hash = hash
		world_state_changed.emit(hash)

## Last announced root hash of the shared world tree (empty when no
## state has been written yet).
func world_root_hash() -> PackedByteArray:
	return _world_root_hash
