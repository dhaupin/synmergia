## Ported from vant axolotl lib/cache.js
## Generic content-hash tree substrate.
extends RefCounted

## The FoldedShell (first consumer, the owner's storage mechanism):
## payloads are stored as content-hash cells on the folded shell, so
## identical state blocks pay ONCE no matter how many paths hold them
## (the intersection rebate, prd-industry-labs T3-at-scale). The tree
## keeps only the node record (path, hash, schema); the payload VALUE
## lives in the shell. Plain RefCounted payloads are the common case;
## Resource payloads fall back to inline storage (duplicate() is
## id-entity, not content, for Objects).
const FOLDED_SHELL = preload("res://core/frame/kv/folded_shell.gd")

var _nodes: Dictionary = {}
var _snapshots: Dictionary = {}
var _schema_refs_by_root: Dictionary = {}
var _current_root: PackedByteArray = PackedByteArray()

## Reusable HashingContext to avoid allocation churn.
var _hashing_context: HashingContext = HashingContext.new()

## The shell behind _cells: one store, many claimant paths. Space
## "t3" holds every distinct payload this tree has ever stored; a
## rebased path re-claims its content instead of re-paying.
var _shell: FOLDED_SHELL = null

## Measurement: how many payload stores were ATTEMPTED (a no-dedup
## tree would have paid every one of them). Distinct cells actually
## stored is shell.space_size("t3") -- the difference is the rebate,
## see savings_ratio().
var _stores_attempted: int = 0


func _init() -> void:
	_shell = FOLDED_SHELL.new(256)
	_shell.ensure_space("t3")
	_current_root = _sha256(PackedByteArray())
	_record_snapshot()


## The shell measurement surface (cells, rebate, evictions). Frame
## rule: stress is MEASURED, not feared. read-only shell accessor.
func shell() -> FOLDED_SHELL:
	return _shell


## How much dedup saved at scale: (stores a no-dedup tree would have
## paid) minus (distinct cells actually stored), as a ratio of the
## no-dedup baseline. 0.0 = no duplicates; approaches 1.0 when most
## writes are repeats (the T3-at-scale thesis: N entities sharing K
## distinct states pay K, not N).
func savings_ratio() -> float:
	var distinct := _shell.space_size("t3")
	if _stores_attempted == 0 or distinct == 0:
		return 0.0
	return clampf(1.0 - float(distinct) / float(_stores_attempted), 0.0, 1.0)


## Inserts or replaces a node and returns its 32-byte content hash.
func insert(path: String, value: Variant, schema: Resource) -> PackedByteArray:
	var normalized_path := _normalize_path(path)
	var value_bytes := var_to_bytes(value)
	var schema_id := _schema_id(schema)
	var node_hash := _node_hash(normalized_path, _hash_bytes_for(schema, value, value_bytes), schema_id)

	_record_snapshot()

	var existing = _nodes.get(normalized_path)
	if existing != null and existing.get("hash") == node_hash:
		return node_hash

	var node := {
		"path": normalized_path,
		"hash": node_hash,
		"value_bytes": value_bytes,
		"schema_ref": schema,
		"schema_id": schema_id,
		"cell": _store_value(value, value_bytes)
	}
	_nodes[normalized_path] = node
	_current_root = _root_hash(_nodes)
	_record_snapshot()
	return node_hash


## Batch insert multiple nodes and compute root hash once at the end.
## Returns array of [path, node_hash] for each inserted node.
func insert_batch(entries: Array) -> Array:
	if entries.is_empty():
		return []

	_record_snapshot()

	var results: Array = []
	for entry in entries:
		if not entry is Array or entry.size() < 3:
			push_error("T3.insert_batch: entry must be [path, value, schema]")
			continue
		var path: String = str(entry[0])
		var value: Variant = entry[1]
		var schema: Resource = entry[2]

		var normalized_path := _normalize_path(path)
		var value_bytes := var_to_bytes(value)
		var schema_id := _schema_id(schema)
		var node_hash := _node_hash(normalized_path, _hash_bytes_for(schema, value, value_bytes), schema_id)

		var existing = _nodes.get(normalized_path)
		if existing != null and existing.get("hash") == node_hash:
			results.append([normalized_path, node_hash])
			continue

		var node := {
			"path": normalized_path,
			"hash": node_hash,
			"value_bytes": value_bytes,
			"schema_ref": schema,
			"schema_id": schema_id,
			"cell": _store_value(value, value_bytes)
		}
		_nodes[normalized_path] = node
		results.append([normalized_path, node_hash])

	_current_root = _root_hash(_nodes)
	_record_snapshot()
	return results


## Returns the stored value at path, or null when the node does not exist.
@warning_ignore("native_method_override")
func get_at(path: StringName) -> Variant:
	var normalized_path := _normalize_path(str(path))
	var node = _nodes.get(normalized_path)
	if node == null:
		return null
	# Cell-resident payload: the value lives in the shell (T3 content
	# is immutable, so a shared cell is always the right value).
	var rec: Variant = _shell.get_value(node.get("cell"))
	if rec is Dictionary and rec.has("inline"):
		return rec["inline"]
	return rec


## Deletes one node and returns whether the node existed.
func delete(path: String) -> bool:
	var normalized_path := _normalize_path(path)
	if not _nodes.has(normalized_path):
		return false

	_record_snapshot()
	_nodes.erase(normalized_path)
	_current_root = _root_hash(_nodes)
	_record_snapshot()
	return true


## Returns the hash of a node's subtree, or the SHA-256 of empty bytes when absent.
func hash_subtree(path: String) -> PackedByteArray:
	var normalized_path := _normalize_path(path)
	if normalized_path == "":
		return _current_root

	var paths: Array = []
	for node_path in _nodes.keys():
		if _is_under(node_path, normalized_path):
			paths.append(node_path)
	if paths.is_empty():
		return _sha256(PackedByteArray())

	paths.sort()
	if paths.size() == 1:
		var node: Dictionary = _nodes[paths[0]]
		return node.get("hash")

	var combined := PackedByteArray()
	for node_path in paths:
		var node: Dictionary = _nodes[node_path]
		combined.append_array(node.get("hash"))
	return _sha256(combined)


## Returns a deterministic array of changed paths between two known root snapshots.
func diff(old_root: PackedByteArray, new_root: PackedByteArray) -> Array:
	if old_root == new_root:
		return []

	var old_nodes_value: Variant = _snapshot_for_root(old_root)
	var new_nodes_value: Variant = _snapshot_for_root(new_root)
	if old_nodes_value == null or new_nodes_value == null:
		return []

	var old_nodes: Dictionary = old_nodes_value
	var new_nodes: Dictionary = new_nodes_value
	var paths: Array = []
	for node_path in old_nodes.keys():
		paths.append(node_path)
	for node_path in new_nodes.keys():
		if not node_path in paths:
			paths.append(node_path)
	paths.sort()

	var changes: Array = []
	for node_path in paths:
		var old_node: Variant = old_nodes.get(node_path)
		var new_node: Variant = new_nodes.get(node_path)
		var old_hash: Variant = null
		var new_hash: Variant = null
		if old_node != null:
			old_hash = old_node.get("hash")
		if new_node != null:
			new_hash = new_node.get("hash")
		if old_hash == new_hash:
			continue

		var value_bytes: Variant = null
		if new_node != null:
			value_bytes = new_node.get("value_bytes")
		changes.append([node_path, old_hash, new_hash, value_bytes])
	return changes


## Applies a diff to a known root snapshot and returns the resulting root hash.
func apply_diff(root: PackedByteArray, diff: Array) -> PackedByteArray:
	if diff.is_empty():
		return root

	var base_value: Variant = _snapshot_for_root(root)
	if base_value == null:
		return root

	# apply_diff re-bases nodes from DIFF bytes (which carry no cell
	# keys); shell cells from the base tree are simply re-claimed by
	# the rebased node records below (the rebate re-claims, never
	# re-pays).
	var result: Dictionary = _clone_nodes(base_value)
	for entry_value in diff:
		if not entry_value is Array:
			push_error("T3.apply_diff: diff entry is not an array")
			continue
		var entry: Array = entry_value
		if entry.size() < 4:
			push_error("T3.apply_diff: diff entry is incomplete")
			continue

		var node_path := _normalize_path(str(entry[0]))
		var new_hash: Variant = entry[2]
		if new_hash == null:
			result.erase(node_path)
			continue

		# The diff carries value BYTES (transport format); the rebased
		# node re-claims its content cell through the shell -- the
		# rebate means a content already in the tree is claimed, not
		# re-paid (apply_diff = rebasing pointers, not re-storing).
		var value_bytes: Variant = entry[3]
		var old_node: Variant = base_value.get(node_path)
		if value_bytes == null:
			if old_node != null:
				value_bytes = old_node.get("value_bytes")
			else:
				value_bytes = PackedByteArray()
		var byte_arr: PackedByteArray = value_bytes
		var rebased_value: Variant = bytes_to_var(byte_arr)

		var schema_ref: Resource = _schema_for_root(root, node_path)
		if schema_ref == null and old_node != null:
			schema_ref = old_node.get("schema_ref")
		if schema_ref == null and _nodes.has(node_path):
			schema_ref = _nodes[node_path].get("schema_ref")
		if schema_ref == null:
			schema_ref = Resource.new()

		result[node_path] = {
			"path": node_path,
			"hash": new_hash,
			"value_bytes": byte_arr,
			"schema_ref": schema_ref,
			"schema_id": _schema_id(schema_ref),
			"cell": _store_value(rebased_value, byte_arr)
		}

	_nodes = _clone_nodes(result)
	_current_root = _root_hash(_nodes)
	_record_snapshot()
	return _current_root


## Returns a full snapshot of all nodes under scope_path as diff entries
## with old_hash=null (indicating full state, not differential).
## Used for client resync when hash divergence is detected.
func get_full_scope_snapshot(scope_path: String) -> Array:
	var scope := _normalize_path(scope_path)
	var paths: Array = []
	for node_path in _nodes.keys():
		if _is_under(node_path, scope):
			paths.append(node_path)
	paths.sort()

	var snapshot: Array = []
	for node_path in paths:
		var node: Dictionary = _nodes[node_path]
		var entry := [
			node_path,
			PackedByteArray(),  # old_hash = null (full state marker)
			node.get("hash"),
			node.get("value_bytes"),
		]
		snapshot.append(entry)
	return snapshot


## Store a payload as a content-hash cell on the shell; returns the
## cell hash key. Plain payloads (Dictionary/Array/String/numbers/
## bool -- var_to_bytes is content-identity for them) go through the
## rebate: the same content stored again re-claims the existing cell
## and pays nothing. Resources are stored inline on their own cell
## (their content hash is the NODE hash, not a resource identity).
func _store_value(value: Variant, value_bytes: PackedByteArray) -> String:
	var content_hash := value_bytes.hex_encode()
	if value is Resource:
		_shell.put("t3", 0, content_hash, {"inline": value})
	else:
		_shell.put("t3", 0, content_hash, value)
	_stores_attempted += 1
	return content_hash


## Walks nodes under scope_path in deterministic depth-first pre-order.
func walk(scope_path: String, callback: Callable) -> void:
	var scope := _normalize_path(scope_path)
	var paths: Array = []
	for node_path in _nodes.keys():
		if _is_under(node_path, scope):
			paths.append(node_path)
	paths.sort()

	if not callback.is_valid():
		push_error("T3.walk: callback is invalid")
		return

	for node_path in paths:
		var node: Dictionary = _nodes[node_path]
		var rec: Variant = _shell.get_value(node.get("cell"))
		var value: Variant = rec
		if rec is Dictionary and rec.has("inline"):
			value = rec["inline"]
		if not callback.is_valid():
			push_error("T3.walk: callback became invalid")
			continue
		callback.call(node_path, node.get("hash"), value)


func _normalize_path(path: String) -> String:
	var parts: Array = path.split("/")
	var normalized_parts: Array = []
	for part in parts:
		if part != "":
			normalized_parts.append(part)
	return "/".join(normalized_parts)


func _schema_id(schema: Resource) -> String:
	if schema == null:
		return ""
	# Deterministic schema identity: content hashes must not depend on
	# object instance ids (str(schema) embeds <Resource#-92233...>), or
	# identical trees would hash differently across instances and restarts.
	var script: Variant = schema.get_script()
	if script != null and script.resource_path != "":
		return script.resource_path
	return "native:" + schema.get_class()


## The bytes a node's CONTENT HASH is derived from. When the payload is a
## Dictionary and the schema provides a canonical encoder
## (_to_canonical_bytes -- the whole point of the kv schema classes), the
## canonical form is hashed, so key order and encoding choices cannot fork
## otherwise-identical facts. Otherwise it falls back to the raw
## var_to_bytes serialization. NOTE: value_bytes (the TRANSPORT form that
## diff entries carry and apply_diff decodes) stays var_to_bytes --
## hashing and serialization are different jobs.
func _hash_bytes_for(schema: Resource, value: Variant, value_bytes: PackedByteArray) -> PackedByteArray:
	if value is Dictionary and schema != null and schema.has_method("_to_canonical_bytes"):
		var encoded: Variant = schema.call("_to_canonical_bytes", value)
		if encoded is PackedByteArray:
			return encoded
	return value_bytes


func _node_hash(path: String, value_bytes: PackedByteArray, schema_id: String) -> PackedByteArray:
	var path_bytes := path.to_utf8_buffer()
	var schema_bytes := schema_id.to_utf8_buffer()
	var canonical := PackedByteArray()
	_append_u32(canonical, path_bytes.size())
	canonical.append_array(path_bytes)
	_append_u32(canonical, value_bytes.size())
	canonical.append_array(value_bytes)
	_append_u32(canonical, schema_bytes.size())
	canonical.append_array(schema_bytes)
	return _sha256(canonical)


## Reuses _hashing_context to compute SHA-256 without allocation.
func _sha256(data: PackedByteArray) -> PackedByteArray:
	if _hashing_context.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	if not data.is_empty():
		_hashing_context.update(data)
	return _hashing_context.finish()


func _append_u32(target: PackedByteArray, value: int) -> void:
	for i in range(4):
		target.append((value >> (i * 8)) & 255)


func _root_hash(nodes: Dictionary) -> PackedByteArray:
	var paths: Array = nodes.keys()
	paths.sort()
	var combined := PackedByteArray()
	combined.resize(paths.size() * 32)
	var offset: int = 0
	for node_path in paths:
		var node: Dictionary = nodes[node_path]
		var hash_bytes: PackedByteArray = node.get("hash")
		for i in range(32):
			combined[offset + i] = hash_bytes[i]
		offset += 32
	return _sha256(combined)


func _subtree_paths(scope: String) -> Array:
	var paths: Array = []
	for node_path in _nodes.keys():
		if _is_under(node_path, scope):
			paths.append(node_path)
	paths.sort()
	return paths


func _is_under(node_path: String, scope: String) -> bool:
	if scope == "":
		return true
	return node_path == scope or node_path.begins_with(scope + "/")


func _record_snapshot() -> void:
	var root_key := _root_key(_current_root)
	_snapshots[root_key] = _clone_nodes(_nodes)

	var root_schemas: Dictionary = {}
	if _schema_refs_by_root.has(root_key):
		root_schemas = _schema_refs_by_root[root_key]
	for node_path in _nodes.keys():
		var node: Dictionary = _nodes[node_path]
		root_schemas[node_path] = node.get("schema_ref")
	_schema_refs_by_root[root_key] = root_schemas


func _snapshot_for_root(root: PackedByteArray) -> Variant:
	var root_key := _root_key(root)
	if _snapshots.has(root_key):
		return _snapshots[root_key]
	if root == _current_root:
		return _clone_nodes(_nodes)
	return null


func _schema_for_root(root: PackedByteArray, node_path: String) -> Resource:
	var root_key := _root_key(root)
	if not _schema_refs_by_root.has(root_key):
		return null
	var root_schemas: Dictionary = _schema_refs_by_root[root_key]
	if not root_schemas.has(node_path):
		return null
	return root_schemas[node_path]


func _clone_nodes(nodes: Dictionary) -> Dictionary:
	var clone: Dictionary = {}
	for node_path in nodes.keys():
		clone[node_path] = nodes[node_path].duplicate()
	return clone


func _root_key(root: PackedByteArray) -> String:
	return root.hex_encode()


## Clears all internal state: nodes, snapshots, schema refs, and the
## shell's tree space ("t3" -- release_space orphans only the cells
## this tree uniquely claimed; shared content survives, which is the
## intersection-aware removal law).
## Call this before dropping the last reference to allow GC.
func clear() -> void:
	_nodes.clear()
	_snapshots.clear()
	_schema_refs_by_root.clear()
	_shell.release_space("t3")
	_stores_attempted = 0
	_current_root = _sha256(PackedByteArray())
	_record_snapshot()
