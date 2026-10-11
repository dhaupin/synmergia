extends SceneTree
func _init() -> void:
	var scene: PackedScene = load("res://scenes/npcs/blacksmith_village.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	await process_frame
	_dump(inst, 0)
	inst.free()
	quit(0)
func _dump(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var cls := ""
	if n is AnimationPlayer:
		cls = " [AnimationPlayer]"
	if n is Skeleton3D:
		cls = " [Skeleton3D]"
	print("%s%s (%s)%s" % [pad, n.name, n.get_class(), cls])
	for c in n.get_children():
		_dump(c, depth + 1)
