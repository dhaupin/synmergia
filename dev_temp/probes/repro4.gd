extends SceneTree
var t := 0.0
func _init() -> void:
	call_deferred("_boot")
func _boot() -> void:
	var Spy: GDScript = load("res://tests/spy_node.gd")
	var spy: Node = Spy.new()
	spy.name = "InputSpy"
	root.add_child(spy)
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	var inst = scene.instantiate()
	root.add_child(inst)
	current_scene = inst
	var seen := false
	while t < 6.0:
		await process_frame
		t += 1.0/60.0
		var zm = root.get_node_or_null("ZoneManager")
		var p = current_scene.get_node_or_null("Player")
		if p == null or zm == null:
			continue
		if not seen and str(zm.get_entity_zone_id(p)) == "zone_deep_root_camp":
			seen = true
			print("POISONED at t=%.2f pos=%s" % [t, p.global_position])
			quit(0)
			return
	print("clean: ", current_scene.get_node_or_null("Player").global_position)
	quit(0)
