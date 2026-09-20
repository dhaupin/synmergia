## ScopeNode -- one node of a scope hierarchy (standalone Resource).
##
## Extracted from scope_hierarchy.gd's inner class: Godot 4.x cannot
## serialize inner-class Resources (ResourceSaver writes an empty GDScript
## placeholder and the properties are lost on load). A standalone script
## with a real resource path round-trips correctly and makes typed
## Array[ScopeNode] assignments work across scripts.
## Spec: labs/world-building-arch.md sec. 5 (scope hierarchy).
extends Resource
class_name ScopeNode

@export var name: String = ""
@export var parent_name: String = ""
@export var environment_path: String = ""
@export var rules_overrides: Dictionary = {}

static func _validate_node(node: ScopeNode) -> Array[String]:
	var errors: Array[String] = []
	if node.name == "":
		errors.append("ScopeNode missing or empty 'name'")
	if node.environment_path == "":
		errors.append("ScopeNode '%s' missing or empty 'environment_path'" % node.name)
	return errors
