## Ported from vant axolotl lib/cache.js
## Generic content-hash tree substrate.
extends RefCounted

var _nodes: Dictionary = {}
var _snapshots: Dictionary = {}
var _schema_refs_by_root: Dictionary = {}
var _current_root: PackedByteArray = PackedByteArray()


func _init() -> void:
	_current_root = _sha256(PackedByteArray())
	_record_snapshot()


## Inserts or replaces a node and returns its 32-byte content hash.
func insert(path: String, value: Variant, schema: Resource) -> PackedByteArray:
	var normalized_path := _normalize_path(path)
	var value_bytes := var_to_bytes(value)
	var schema_id := _schema_id(schema)
	var node_hash := _node_hash(normalized_path, value_bytes, schema_id)

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
		"value": value
	}
	_nodes[normalized_path] = node
	_current_root = _root_hash(_nodes)
	_record_snapshot()
	return node_hash


## Returns the stored value at path, or null when the node does not exist.
@warning_ignore("native_method_override")
func get_at(path: StringName) -> Variant:
	var normalized_path := _normalize_path(str(path))
	var node = _nodes.get(normalized_path)
	if node == null:
		return null
	if node.has("value"):
		return node.get("value")
	return bytes_to_var(node.get("value_bytes"))


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

		var value_bytes: Variant = entry[3]
		var old_node: Variant = base_value.get(node_path)
		if value_bytes == null:
			if old_node != null:
				value_bytes = old_node.get("value_bytes")
			else:
				value_bytes = PackedByteArray()

		var schema_ref: Resource = _schema_for_root(root, node_path)
		if schema_ref == null and old_node != null:
			schema_ref = old_node.get("schema_ref")
		if schema_ref == null and _nodes.has(node_path):
			schema_ref = _nodes[node_path].get("schema_ref")
		if schema_ref == null:
			schema_ref = Resource.new()

		var value: Variant = bytes_to_var(value_bytes)
		result[node_path] = {
			"path": node_path,
			"hash": new_hash,
			"value_bytes": value_bytes,
			"schema_ref": schema_ref,
			"schema_id": _schema_id(schema_ref),
			"value": value
		}

	_nodes = _clone_nodes(result)
	_current_root = _root_hash(_nodes)
	_record_snapshot()
	return _current_root


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
		var value: Variant = node.get("value")
		if not node.has("value"):
			value = bytes_to_var(node.get("value_bytes"))
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
	var resource_path := schema.resource_path
	if resource_path != "":
		return resource_path
	return str(schema)


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


func _sha256(data: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	if not data.is_empty():
		context.update(data)
	return context.finish()


func _append_u32(target: PackedByteArray, value: int) -> void:
	for i in range(4):
		target.append((value >> (i * 8)) & 255)


func _root_hash(nodes: Dictionary) -> PackedByteArray:
	var paths: Array = nodes.keys()
	paths.sort()
	var combined := PackedByteArray()
	for node_path in paths:
		var node: Dictionary = nodes[node_path]
		combined.append_array(node.get("hash"))
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


## Clears all internal state: nodes, snapshots, and schema refs.
## Call this before dropping the last reference to allow GC.
func clear() -> void:
	_nodes.clear()
	_snapshots.clear()
	_schema_refs_by_root.clear()
	_current_root = _sha256(PackedByteArray())
	_record_snapshot()
