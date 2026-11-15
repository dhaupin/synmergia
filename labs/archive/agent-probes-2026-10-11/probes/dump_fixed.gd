extends SceneTree
func _init() -> void:
	var scene: PackedScene = load("res://models/npcs/npc_blacksmith_village.glb")
	var inst := scene.instantiate()
	var ap := _find_ap(inst)
	for clip in ["idle", "walk"]:
		var anim: Animation = ap.get_animation(clip)
		print("=== %s: tracks=%d length=%.2f" % [clip, anim.get_track_count(), anim.length])
		var t := 2  # thigh_l
		for k in anim.track_get_key_count(t):
			var kt: float = anim.track_get_key_time(t, k)
			var q: Quaternion = anim.rotation_track_interpolate(t, kt)
			print("  thigh_l k%d t=%.3f q=%s" % [k, kt, q])
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
