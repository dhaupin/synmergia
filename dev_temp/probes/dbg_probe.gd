extends SceneTree
func _init() -> void:
	var packed: PackedScene = load("res://scenes/worlds/globe_island.tscn")
	print("packed: ", packed)
	if packed == null or not packed.can_instantiate():
		print("FAIL: cannot instantiate")
		quit(1)
	var g: Node3D = packed.instantiate()
	root.add_child(g)
	print("children after instantiate: ", g.get_child_count())
	for i in range(g.get_child_count()):
		var c: Node = g.get_child(i)
		print("  child ", i, ": ", c.name, " type: ", typeof(c))
	var p: Node = g.get("player")
	print("player via get: ", p)
	if p != null:
		print("player script: ", p.get_script())
	quit(0)
