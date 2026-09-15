## Ported from vant axolotl lib/brain.js
extends Resource

class_name ScopeHierarchy

class ScopeNode:
	var name: String = ""
	var parent_name: String = ""
	var environment_path: String = ""
	var rules_overrides: Dictionary = {}

	@export var name: String = ""
	@export var parent_name: String = ""
	@export var environment_path: String = ""
	@export var rules_overrides: Dictionary = {}

	@staticmethod
	func _validate_node(node: Dictionary) -> Array[String]:
		var errors = []
		if not node.has("name") or node["name"] == "":
			errors.append("ScopeNode missing or empty 'name'")
		if not node.has("parent_name"):
			errors.append("ScopeNode '%s' missing 'parent_name'" % node.get("name", "unknown"))
		if not node.has("environment_path") or node["environment_path"] == "":
			errors.append("ScopeNode '%s' missing or empty 'environment_path'" % node.get("name", "unknown"))
		if not node.has("rules_overrides"):
			errors.append("ScopeNode '%s' missing 'rules_overrides'" % node.get("name", "unknown"))
		return errors

@export var nodes: Array[ScopeNode] = []

func _validate() -> Array[String]:
	var errors = []
	var name_set = {}
	var root_count = 0

	for node in nodes:
		var node_errors = ScopeNode._validate_node(node)
		errors.append_array(node_errors)

		if node.name in name_set:
			errors.append("Duplicate scope name: '%s'" % node.name)
		name_set[node.name] = true

		if node.parent_name == "":
			root_count += 1
		elif not name_set.has(node.parent_name):
			pass

	if root_count != 1:
		errors.append("Hierarchy must have exactly one root (parent_name == ''), found %d" % root_count)

	for node in nodes:
		if node.parent_name != "" and not name_set.has(node.parent_name):
			errors.append("Scope '%s' references missing parent '%s'" % [node.name, node.parent_name])

	var visited = {}
	var rec_stack = {}

	func _detect_cycle(name: String) -> bool:
		if not visited.has(name):
			visited[name] = true
			rec_stack[name] = true
			for child in nodes:
				if child.parent_name == name:
					if _detect_cycle(child.name):
						return true
			rec_stack.erase(name)
		elif rec_stack.has(name):
			return true
		return false

	for node in nodes:
		if node.parent_name == "":
			if _detect_cycle(node.name):
				errors.append("Cycle detected in hierarchy starting at '%s'" % node.name)
				break

	return errors

func _get_environment_full_path(base_dir: String, node: ScopeNode) -> String:
	return base_dir.path_join(node.environment_path)

func _check_environment_paths(base_dir: String) -> Array[String]:
	var errors = []
	for node in nodes:
		var full_path = _get_environment_full_path(base_dir, node)
		if not ResourceLoader.exists(full_path):
			errors.append("Environment file not found for scope '%s': '%s'" % [node.name, full_path])
	return errors