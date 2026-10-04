## Seed chain derivation for recursive seed trees.
## Ported from game/core/frame/prototype/iso_math.py (section 7.2)
## Spec: labs/world-building-arch.md sec 7.2
extends RefCounted

const T3Script = preload("res://core/frame/kv/t3.gd")
const SeedSchemaScript = preload("res://core/frame/schemas/seed_schema.gd")

## Derives a content-hash seed from a scope stack and a path.
## The stack is [player_seed, shard_seed, world_seed] (top to bottom).
## Bottom-up derivation: world folds first, then shard, then player.
## Returns a 32-byte SHA-256 hash.
static func derive_seed(stack: Array[PackedByteArray], path: String) -> PackedByteArray:
	var acc := path.to_utf8_buffer()
	for i in range(stack.size() - 1, -1, -1):
		acc = _sha256(stack[i] + acc)
	# Edge case: an empty stack runs no fold, so acc is still raw path
	# bytes. Always finish with a hash so the output is 32 bytes.
	if stack.is_empty():
		acc = _sha256(acc)
	return acc

## Builds a seed tree by recursively deriving seeds and inserting
## them into a T3 instance with SeedSchema resources.
## world_root structure: {path: {seed_type, visibility_scope, parameters, children: {...}}}
## Returns the root hash of the populated tree.
func build_seed_tree(t3: Variant, stack: Array[PackedByteArray], world_root: Dictionary) -> PackedByteArray:
	if t3 == null:
		t3 = T3Script.new()
	var schema := SeedSchemaScript.new()
	for node_path in world_root.keys():
		var node_spec: Dictionary = world_root[node_path]
		_insert_seed_node(t3, schema, stack, node_path, node_spec)
	return t3.hash_subtree("/")


func _insert_seed_node(t3: Variant, schema: Resource, stack: Array[PackedByteArray], path: String, spec: Dictionary) -> void:
	var seed_type: String = spec.get("seed_type", "locked")
	var visibility_scope: String = spec.get("visibility_scope", "world")
	var parameters: Dictionary = spec.get("parameters", {})
	var seed_path: String = spec.get("path", path)
	var layer_seed := derive_seed(stack, seed_path)
	var value := {
		"seed_type": seed_type,
		"visibility_scope": visibility_scope,
		"path": seed_path,
		"parameters": parameters,
		"derived_seed": layer_seed.hex_encode()
	}
	t3.insert(path, value, schema)
	if spec.has("children"):
		var children: Dictionary = spec["children"]
		for child_key in children.keys():
			var child_spec: Dictionary = children[child_key]
			var child_path: String = "%s/%s" % [path, child_key]
			_insert_seed_node(t3, schema, stack, child_path, child_spec)


## Returns a hex-encoded string representation of a seed hash for logging.
static func seed_hash(seed: PackedByteArray) -> String:
	return seed.hex_encode()


## Rolling chain anchor: folds the authoritative world-tree root hash
## into the chain head, so the seed chain always carries the latest
## re-rooted tree state (Phase 3 of the tick calls this per tick; the
## head is a deterministic function of every root the server has ever
## re-rooted to). Empty hashes are ignored (no fold, head unchanged).
var _chain_head: PackedByteArray = PackedByteArray()

func update_root(root_hash: PackedByteArray) -> PackedByteArray:
	if root_hash.is_empty():
		return _chain_head
	_chain_head = _sha256(_chain_head + root_hash)
	return _chain_head


## The current chain head (all folded roots so far).
func chain_head() -> PackedByteArray:
	return _chain_head


static func _sha256(data: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	if not data.is_empty():
		context.update(data)
	return context.finish()
