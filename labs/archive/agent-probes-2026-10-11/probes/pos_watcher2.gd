extends SceneTree
func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	var inst = scene.instantiate()
	root.add_child(inst)
	current_scene = inst
func _process(_delta: float) -> bool:
	var cs = current_scene
	if cs == null:
		return false
	var p = cs.get_node_or_null("Player")
	if p != null and p.has_method("get_position_history"):
		print("HIST: ", p.get_position_history())
		quit(0)
		return true
	return false
