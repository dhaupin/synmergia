## Ported from vant axolotl lib/brain.js
## ScopeHierarchy Resource: declared scope tree (nodes + validation).
## ScopeNode lives in scope_node.gd (standalone) because inner-class
## Resources cannot round-trip through ResourceSaver/ResourceLoader.
extends Resource

const ScopeNodeClass = preload("res://core/frame/srv/scope_node.gd")

@export var nodes: Array[ScopeNode] = []

func _validate() -> Array[String]:
	var errors: Array[String] = []
	var name_set := {}
	var root_count := 0

	for node in nodes:
		errors.append_array(ScopeNodeClass._validate_node(node))

		if node.name in name_set:
			errors.append("Duplicate scope name: '%s'" % node.name)
		name_set[node.name] = true

		if node.parent_name == "":
			root_count += 1

	if root_count != 1:
		errors.append("Hierarchy must have exactly one root (parent_name == ''), found %d" % root_count)

	for node in nodes:
		if node.parent_name != "" and not name_set.has(node.parent_name):
			errors.append("Scope '%s' references missing parent '%s'" % [node.name, node.parent_name])

	# Cycle detection: walk children from every declared root. A node
	# visited twice within one traversal means the hierarchy loops.
	# (Iterative, since GDScript does not allow nested func declarations.)
	for node in nodes:
		if node.parent_name != "":
			continue
		var visited := {}
		var queue: Array = [node.name]
		while not queue.is_empty():
			var current: String = queue.pop_back()
			if visited.has(current):
				errors.append("Cycle detected in hierarchy starting at '%s'" % node.name)
				break
			visited[current] = true
			for child in nodes:
				if child.parent_name == current:
					queue.append(child.name)

	return errors

func _get_environment_full_path(base_dir: String, node: ScopeNode) -> String:
	return base_dir.path_join(node.environment_path)

func _check_environment_paths(base_dir: String) -> Array[String]:
	var errors: Array[String] = []
	for node in nodes:
		var full_path: String = _get_environment_full_path(base_dir, node)
		if not ResourceLoader.exists(full_path):
			errors.append("Environment file not found for scope '%s': '%s'" % [node.name, full_path])
	return errors
