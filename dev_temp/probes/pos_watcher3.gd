extends SceneTree
var armed := true
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
	if p != null and armed:
		armed = false
		_watch(p)
	return false
func _watch(p) -> void:
	var last: Vector3 = p.global_position
	print("BOOT pos: ", last)
	var t: float = 0.0
	while t < 3.0:
		await process_frame
		t += 1.0 / 60.0
		if absf(p.global_position.y - last.y) > 50.0:
			print("MOVED t=%.2f: %s -> %s" % [t, last, p.global_position])
			quit(0)
			return
		last = p.global_position
	print("STABLE: %s" % str(last))
	quit(0)
