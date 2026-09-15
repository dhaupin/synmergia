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

const T3Script = preload("res://labs/multi-iso/kv/t3.gd")
const StateTreeScript = preload("res://labs/multi-iso/kv/state_tree.gd")
const SeedChainScript = preload("res://labs/multi-iso/kv/seed_chain.gd")

signal frame_entered(player_id: String, frame_id: String, frame_seed: PackedByteArray)
signal frame_exited(player_id: String, frame_id: String)

class FrameEnv:
	var frame_id: String
	var frame_seed: PackedByteArray
	var seed_tree: T3Script
	var state_tree: StateTreeScript
	var entered_at: int

	_func _init(fid: String, fseed: PackedByteArray) -> void:
		frame_id = fid
		frame_seed = fseed
		seed_tree = T3Script.new()
		state_tree = StateTreeScript.new()
		entered_at = Time.get_unix_time_from_system()

var _player_frames: Dictionary = {}   # player_id -> Array[FrameEnv]

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
	
	var frame_seed = Crypto.random_bytes(32)
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
	
	env.seed_tree = null
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
	
	if not hasattr(self, "_player_state_trees"):
		_player_state_trees = {}
	if not _player_state_trees.has(player_id):
		_player_state_trees[player_id] = StateTreeScript.new()
	return _player_state_trees[player_id]

## Sets a custom state tree for the player (for testing/restore).
func set_state_tree(player_id: String, tree: StateTreeScript) -> void:
	if not hasattr(self, "_player_state_trees"):
		_player_state_trees = {}
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