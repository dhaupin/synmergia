extends SceneTree
var t := 0.0
var frames := 0
func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	var inst = scene.instantiate()
	root.add_child(inst)
	current_scene = inst
func _process(delta: float) -> bool:
	t += delta
	frames += 1
	var cs = current_scene
	if cs != null:
		var p = cs.get_node_or_null("Player")
		if p != null and frames % 30 == 0:
			print("t=%.1f pos=%s zone-check=%s" % [t, p.global_position, p.get("entity_type")])
		# stop condition
		if t > 4.0:
			print("FINAL pos=%s" % str(p.global_position if p else Vector3.ZERO))
			quit(0)
			return true
	return false
