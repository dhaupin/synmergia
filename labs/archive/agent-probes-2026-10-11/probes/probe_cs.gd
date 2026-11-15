extends SceneTree
func _initialize() -> void:
	change_scene_to_file("res://ui/menus/character_select.tscn")
	var t := Timer.new()
	t.wait_time = 1.5
	t.one_shot = true
	t.timeout.connect(_go)
	root.add_child(t)
	t.start()
func _go() -> void:
	var s := current_scene
	print("scene: ", s)
	var c: Node = s.get_node_or_null("SpeciesContainer")
	print("container children: ", c.get_child_count())
	for ch in c.get_children():
		print("  child: ", ch.name, " class=", ch.get_class(), " script=", ch.get_script().resource_path if ch.get_script() else "none")
	quit(0)
