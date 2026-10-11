extends SceneTree
var armed := false
func _init() -> void:
	call_deferred("_go")
func _go() -> void:
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	var inst = scene.instantiate()
	root.add_child(inst)
	current_scene = inst
	await process_frame
	await process_frame
	var p = inst.get_node_or_null("Player")
	if p == null:
		print("NO PLAYER")
		quit(1)
		return
	print("start pos: ", p.global_position)
	armed = true
	var t := 0.0
	while t < 12.0:
		await process_frame
		t += 1.0/60.0
		if p.global_position.y > 100.0:
			print("TRIPPED t=%.2f pos=%s" % [t, p.global_position])
			quit(0)
			return
	print("never moved; final ", p.global_position)
	quit(0)
