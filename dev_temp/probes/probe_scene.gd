extends SceneTree

## Probe: the blacksmith NPC scene embeds the skinned glb and the
## entity's _play_model_idle() path can find and play "idle".

func _init() -> void:
	var scene: PackedScene = load("res://scenes/npcs/blacksmith_village.tscn")
	if scene == null:
		push_error("FAIL: npc scene did not load")
		quit(1)
		return
	var inst := scene.instantiate()
	root.add_child(inst)
	await process_frame
	var ap := inst.get_node_or_null("ModelRoot/AnimationPlayer") as AnimationPlayer
	var skel := _find_skel(inst)
	var ok := true
	if ap == null:
		push_error("FAIL: no ModelRoot/AnimationPlayer")
		ok = false
	elif not ap.has_animation("idle"):
		push_error("FAIL: no idle clip")
		ok = false
	elif ap.is_playing() and ap.current_animation == "idle":
		print("[OK] idle playing on scene instance")
	else:
		print("[WARN] idle not auto-playing (ap.playing=%s current=%s)" % [ap.is_playing(), ap.current_animation])
	print("[OK] skeleton present: %s" % (skel != null))
	inst.free()
	print("--- SCENE MODEL PROBE: ok=%s ---" % str(ok))
	quit(0 if ok else 1)

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skel(c)
		if s != null:
			return s
	return null
