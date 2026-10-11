extends SceneTree
func _init() -> void:
	var scene: PackedScene = load("res://models/npcs/npc_blacksmith_village.glb")
	var inst := scene.instantiate()
	var ap := _find_ap(inst)
	var anim: Animation = ap.get_animation("walk")
	print("walk len=%.2f" % anim.length)
	for t in anim.get_track_count():
		var kc := anim.track_get_key_count(t)
		var samples := []
		for frac in [0.0, 0.25, 0.5, 0.75]:
			var tt: float = anim.length * frac
			if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				var q: Quaternion = anim.rotation_track_interpolate(t, tt)
				samples.append("t%.2f:(%.2f,%.2f,%.2f,%.2f)" % [tt, q.w, q.x, q.y, q.z])
		print("  [%d] %s keys=%d %s" % [t, anim.track_get_path(t), kc, " ".join(samples)])
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
