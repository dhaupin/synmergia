## Regenerates data/roots/world/scope_hierarchy.tres with the standalone
## ScopeNode class and verifies the save/load roundtrip. (Diagnostic tool.)
extends SceneTree

const ScopeHierarchy = preload("res://core/frame/srv/scope_hierarchy.gd")
const ScopeNode = preload("res://core/frame/srv/scope_node.gd")

func _init() -> void:
	var hierarchy := ScopeHierarchy.new()
	var specs := [
		["world", "", "world/environment.tres"],
		["shard", "world", "../shard/environment.tres"],
		["instance", "shard", "../instance/environment.tres"],
		["player", "instance", "../player/environment.tres"],
	]
	var nodes: Array[ScopeNode] = []
	for spec in specs:
		var node := ScopeNode.new()
		node.name = spec[0]
		node.parent_name = spec[1]
		node.environment_path = spec[2]
		node.rules_overrides = {}
		nodes.append(node)
	hierarchy.nodes = nodes

	var path := "res://data/roots/world/scope_hierarchy.tres"
	var save_err := ResourceSaver.save(hierarchy, path)
	print("save err: ", save_err)

	var loaded: Resource = ResourceLoader.load(path)
	var ok := loaded != null
	var lnodes = loaded.get("nodes") if ok else []
	print("loaded nodes: ", lnodes.size() if lnodes is Array else -1)
	if lnodes is Array:
		for i in range(lnodes.size()):
			var n = lnodes[i]
			var has_script := n != null and n.get_script() != null
			print("  node[%d] script=%s name=%s parent=%s" % [i, has_script, n.get("name"), n.get("parent_name")])
			if not has_script:
				ok = false
	quit(0 if ok else 1)
