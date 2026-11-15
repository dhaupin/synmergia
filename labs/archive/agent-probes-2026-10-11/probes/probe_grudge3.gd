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
	print("P3: entity_id='%s' ai_path='%s'" % [slime.entity_id, ai._memory_agent_path])
	ai.set_physics_process(false)
	print("P3: threats before=%s" % [ai._known_threats])
	var ret = slime.take_damage(5, player)
	print("P3: take_damage returned %s, slime hp=%d" % [ret, slime.health_component.current_health])
	print("P3: threats after take_damage=%s" % [ai._known_threats])
	var tree = ai._get_memory_tree()
	if tree != null:
		var paths: Array = tree.list_by_kind(ai._memory_agent_path, "event")
		print("P3: event paths=%d" % paths.size())
		for p in paths:
			var m: Dictionary = tree.get_memory(str(p))
			print("P3:   %s -> %s w=%s" % [p, m.get("content", {}).get("action", "?"), m.get("weight", "?")])
	print("P3: recheck=_check_for_targets==player: %s" % (ai._check_for_targets() == player))
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
