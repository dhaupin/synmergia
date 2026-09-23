## ProgressBridge - PlayerProgress snapshots -> StateSchema-typed tree nodes.
##
## Frame primitive -- NOT an autoload, NO class_name (game/core/frame rules).
## Pure functions over plain Dictionaries: the game side (PlayerProgress)
## produces snapshots, this module maps them onto the state tree contract
## (labs/prd-state-schema.md) so character progress becomes visible to the
## frame's canonical hashing and D027 diffing.
##
## Node layout (per character):
##   /player/<character_id>/progress      type=health   {current,max}
##   /player/<character_id>/position      type=position {x,y,z} 0.01m grid
##   /player/<character_id>/inventory     type=inventory{items:[gold,...]}
##
## The health node carries progression as (current=experience, max=xp to
## next level): the StateSchema health contract is integer current/max and
## progression IS the character's "health" in the leveling sense. The
## inventory node holds the gold coin entry so currency is diffable.
##
## Consumers (PlayerProgress) call write_progress() on its checkpoint
## cadence; the returned PackedByteArray root hash folds every node, so a
## change to any character value moves the hash and D027 sees the diff.
##
## Validation: every payload is validated against the StateSchema contract
## BEFORE insert (the tree stores what it is given). Off-grid floats are
## quantized to 0.01m here -- the bridge is the engine-side quantization
## point the PRD assumes -- so a raw player position never poisons the tree.
extends RefCounted

const StateSchemaScript = preload("res://data/roots/state_schema.gd")
const StateTreeScript = preload("res://core/frame/kv/state_tree.gd")

## Schema instance shared by every node this bridge writes: node hashes
## fold the schema id, so per-node schema instances would make roots
## incomparable across writes.
var _schema: StateSchemaScript

## Tree this bridge writes into. Injected (a boot-owned tree) or lazily
## owned -- tests pass one in, the game side may own it privately.
var _tree: StateTreeScript
var _owns_tree: bool = false


func _init(tree = null) -> void:
	_schema = StateSchemaScript.new()
	if tree != null and tree is StateTreeScript:
		_tree = tree
	else:
		_tree = StateTreeScript.new()
		_owns_tree = true


func get_tree() -> StateTreeScript:
	return _tree


## ---------------------------------------------------------------------------
## Snapshot -> node payloads (pure; also used by tests)
## ---------------------------------------------------------------------------

## XP needed to reach the next level: must mirror the player surface
## (PlayerProgress.restore_player curve: 1000 base, 1.5x per level).
static func xp_to_next(level: int) -> int:
	var need := 1000
	for _i in range(maxi(0, level - 1)):
		need = int(need * 1.5)
	return need


## Quantize a coordinate onto the 0.01m grid (float only; ints pass).
static func quantize_coordinate(v) -> Variant:
	var t := typeof(v)
	if t == TYPE_INT:
		return v
	if t != TYPE_FLOAT:
		return null
	return roundf(v * 100.0) / 100.0


## Map a PlayerProgress snapshot onto StateSchema payloads.
## Returns {} when the snapshot has no usable progress fields.
static func snapshot_to_payloads(snapshot: Dictionary) -> Dictionary:
	if snapshot.is_empty():
		return {}
	var level: int = int(snapshot.get("level", 1))
	var xp: int = int(snapshot.get("experience", 0))
	var gold: int = int(snapshot.get("gold", 0))

	var out: Dictionary = {}
	if snapshot.has("experience") or snapshot.has("level"):
		out["health"] = {"current": xp, "max": xp_to_next(level)}
	if snapshot.has("position") and snapshot["position"] is Dictionary:
		var pos: Dictionary = snapshot["position"]
		if pos.has("x") and pos.has("y") and pos.has("z"):
			out["position"] = {
				"x": quantize_coordinate(pos["x"]),
				"y": quantize_coordinate(pos["y"]),
				"z": quantize_coordinate(pos["z"]),
			}
	if snapshot.has("gold"):
		out["inventory"] = {"items": [{"id": "gold", "quantity": gold}]}
	return out


## ---------------------------------------------------------------------------
## Tree writes
## ---------------------------------------------------------------------------

## Write every node for one character. Returns the tree root hash after
## the write (PackedByteArray), or empty bytes when nothing was written.
func write_progress(character_id: String, snapshot: Dictionary) -> PackedByteArray:
	var cid := character_id.strip_edges()
	if cid.is_empty() or snapshot.is_empty():
		return PackedByteArray()

	var payloads := snapshot_to_payloads(snapshot)
	if payloads.is_empty():
		return PackedByteArray()

	var base := _character_base(cid)
	if payloads.has("health"):
		_tree.insert_state(base + "progress", cid, "health", payloads["health"])
	if payloads.has("position"):
		_tree.insert_state(base + "position", cid, "position", payloads["position"])
	if payloads.has("inventory"):
		_tree.insert_state(base + "inventory", cid, "inventory", payloads["inventory"])
	return _tree.root_hash()


## Remove every node for one character (character deletion / test reset).
## Returns true when at least one node existed.
func clear_progress(character_id: String) -> bool:
	var cid := character_id.strip_edges()
	if cid.is_empty():
		return false
	var base := _character_base(cid)
	var removed := false
	for leaf in ["progress", "position", "inventory"]:
		if _tree.delete_state(base + leaf):
			removed = true
	return removed


## Read back one node as the raw value Dictionary ({} when absent).
func read_node(character_id: String, leaf: String) -> Dictionary:
	var base := _character_base(character_id.strip_edges())
	var value: Variant = _tree.get_state(base + leaf)
	return value if value is Dictionary else {}


## Read back the typed payloads for a character (diagnostics / tests).
func read_progress(character_id: String) -> Dictionary:
	var out: Dictionary = {}
	for pair in [["progress", "health"], ["position", "position"], ["inventory", "inventory"]]:
		var node := read_node(character_id, pair[0])
		if not node.is_empty():
			out[pair[1]] = node.get("payload", {})
	return out


## Current tree root hash (empty bytes when the tree is empty).
func root_hash() -> PackedByteArray:
	return _tree.root_hash()


static func _character_base(character_id: String) -> String:
	# Character ids are hex-ish generated strings, but guard the path
	# namespace anyway: no slashes in ids.
	var safe := character_id.replace("/", "_")
	return "/player/%s/" % safe
