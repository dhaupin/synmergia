extends SceneTree
func _init() -> void:
	call_deferred("_go")
func _go() -> void:
	await process_frame
	var es = root.get_node_or_null("EntityService")
	print("EntityService: ", es)
	var s = load("res://core/entities/entity.gd")
	print("script: ", s, " can_inst=", s.can_instantiate())
	var a = s.new()
	print("a: ", a)
	print("a.get_script(): ", a.get_script() if a != null else "null")
	if a != null and a.get_script() != null:
		print("same: ", a.get_script() == s, " a.path=", a.get_script().resource_path)
	a.free()
	quit(0)
