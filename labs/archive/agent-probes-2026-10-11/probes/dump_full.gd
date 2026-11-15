extends SceneTree
func _init() -> void:
	var scene: PackedScene = load("res://models/npcs/npc_blacksmith_village.glb")
	var inst := scene.instantiate()
	var ap := _find_ap(inst)
	for clip in ["idle", "walk"]:
		var anim: Animation = ap.get_animation(clip)
		print("=== %s: tracks=%d length=%.2f" % [clip, anim.get_track_count(), anim.length])
		for t in anim.get_track_count():
			var path: NodePath = anim.track_get_path(t)
			var kc := anim.track_get_key_count(t)
			var times := PackedFloat32Array()
			for k in mini(kc, 4):
				times.append(anim.track_get_key_time(t, k))
			if kc > 4:
				times.append(anim.track_get_key_time(t, kc - 1))
			print("  [%d] %s keys=%d times=%s" % [t, path, kc, times])
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
