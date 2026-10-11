extends SceneTree
func _init() -> void:
	var scene: PackedScene = load("res://models/npcs/npc_blacksmith_village.glb")
	var inst := scene.instantiate()
	var ap := _find_ap(inst)
	var anim: Animation = ap.get_animation("walk")
	print("walk length=%.2f" % anim.length)
	for t in anim.get_track_count():
		var kc := anim.track_get_key_count(t)
		var times := []
		for k in kc:
			times.append(snappedf(anim.track_get_key_time(t, k), 0.01))
		print("  track %d path=%s keys=%d times=%s" % [t, anim.track_get_path(t), kc, str(times)])
	inst.free()
	quit(0)
func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := _find_ap(c)
		if a != null:
			return a
	return null
