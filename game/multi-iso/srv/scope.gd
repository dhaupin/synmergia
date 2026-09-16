## Ported from vant axolotl lib/brain.js
extends RefCounted

class_name Scope

var name: String = ""
var parent: Scope = null
var children: Array[Scope] = []
var rules_overrides: Dictionary = {}
var environment_path: String = ""

func _init(p_name: String, p_parent: Scope, p_environment_path: String, p_rules_overrides: Dictionary) -> void:
	name = p_name
	parent = p_parent
	environment_path = p_environment_path
	rules_overrides = p_rules_overrides.duplicate(true)
	if parent:
		parent.children.append(self)

func walk(callback: Callable) -> void:
	callback.call(self)
	for child in children:
		child.walk(callback)

func find(p_name: String) -> Scope:
	if name == p_name:
		return self
	for child in children:
		var result = child.find(p_name)
		if result:
			return result
	return null

func flip(rule_id: String, resolution: String) -> void:
	rules_overrides[rule_id] = resolution

func get_override(rule_id: String) -> String:
	return rules_overrides.get(rule_id, "")