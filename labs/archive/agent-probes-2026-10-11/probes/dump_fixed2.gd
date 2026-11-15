extends SceneTree
func _init() -> void:
	var scene: PackedScene = load("res://models/npcs/npc_blacksmith_village.glb")
	var inst := scene.instantiate()
	var ap := _find_ap(inst)
	var anim: Animation = ap.get_animation("walk")
	print("=== walk length=%.2f" % anim.length)
	# find thigh_l track
	for t in anim.get_track_count():
		var path := anim.track_get_path(t)
		if not String(path).contains("thigh_l"):
			continue
		print("track %d: %s keys=%d" % [t, path, anim.track_get_key_count(t)])
		for k in anim.track_get_key_count(t):
			var kt: float = anim.track_get_key_time(t, k)
			var q: Quaternion = anim.rotation_track_interpolate(t, kt)
			print("  k%d t=%.3f q=%s" % [k, kt, q])
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
