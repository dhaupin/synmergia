extends SceneTree

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	current_scene = inst

var _frames := 0
func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 90:
		_run()
	return false

func _run() -> void:
	var player := _find(func(n): return str(n.get_script().resource_path).contains("player_controller") if n.get_script() else false)
	var slime := _find(func(n): return str(n.name) == "SlimeA")
	var ai = slime.get("_ai")
	ai.set_physics_process(false)
	slime.take_damage(5, player)
	var es = root.get_node_or_null("EntityService")
	var nearby: Array = es.get_entities_in_radius(slime.global_position, 8.0, Entity.EntityType.PLAYER)
	print("P4: nearby players=%d" % nearby.size())
	for t in nearby:
		print("P4:   target='%s' valid=%s dead=%s grudge=%s in_sanctuary=%s is_enemy=%s" % [
			t.entity_id, ai._is_valid_target(t),
			t.health_component.is_dead() if t.get("health_component") else "?",
			float(ai._known_threats.get(t.entity_id, 0.0)),
			ai._is_target_in_spawn_sanctuary(t),
			root.get_node_or_null("EntityService").is_enemy(slime, t)])
	var res = ai._check_for_targets()
	print("P4: _check_for_targets -> %s (is player: %s)" % [res, res == player])
	quit(0)

func _find(pred: Callable) -> Node:
	var stack: Array = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n != root and pred.call(n):
			return n
		for c in n.get_children():
			stack.push_back(c)
	return null
