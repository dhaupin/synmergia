extends SceneTree

## Probe: load the generated blacksmith glb and verify it brought
## mesh + skeleton + the two animation clips. Exit 0 = all present.

func _init() -> void:
	var ok := true
	var scene: PackedScene = load("res://models/npcs/npc_blacksmith_village.glb")
	if scene == null:
		push_error("FAIL: glb did not load")
		quit(1)
		return
	print("[OK] glb loads (%s)" % scene.get_class())
	var inst := scene.instantiate()
	print("[OK] root type: %s name: %s children: %d" % [inst.get_class(), inst.name, inst.get_child_count()])
	var found := _scan(inst)
	print("[OK] node types: %s" % str(found["types"].keys()))
	print("[OK] meshes=%d skeleton=%s anims=%s" % [found["meshes"], "yes" if found["skeleton"] != null else "no", str(found["anims"])])
	if int(found["meshes"]) == 0:
		push_error("FAIL: no meshes")
		ok = false
	if found["skeleton"] == null:
		push_error("FAIL: no Skeleton3D")
		ok = false
	if not (found["anims"] as Array).has("idle"):
		push_error("FAIL: missing idle clip (got %s)" % str(found["anims"]))
		ok = false
	if not (found["anims"] as Array).has("walk"):
		push_error("FAIL: missing walk clip (got %s)" % str(found["anims"]))
		ok = false
	inst.free()
	print("--- BLACKSMITH MODEL PROBE: ok=%s ---" % str(ok))
	quit(0 if ok else 1)

## GDScript passes ints/objects by value, so the scan RETURNS its
## findings instead of mutating in-out params.
func _scan(node: Node) -> Dictionary:
	var out := {"meshes": 0, "skeleton": null, "anims": [], "types": {}}
	out["types"][node.get_class()] = true
	if node is MeshInstance3D:
		out["meshes"] = int(out["meshes"]) + 1
	if node is Skeleton3D and out["skeleton"] == null:
		out["skeleton"] = node
	if node is AnimationPlayer:
		for a in (node as AnimationPlayer).get_animation_list():
			out["anims"].append(a)
	for c in node.get_children():
		var sub := _scan(c)
		out["meshes"] = int(out["meshes"]) + int(sub["meshes"])
		if out["skeleton"] == null:
			out["skeleton"] = sub["skeleton"]
		out["anims"].append_array(sub["anims"])
		for t in (sub["types"] as Dictionary).keys():
			out["types"][t] = true
	return out
