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
	if player == null or slime == null:
		print("PROBE: missing player/slime")
		quit(1); return
	var ai = slime.get("_ai")
	print("PROBE: ai=%s" % [ai])
	if ai != null:
		print("PROBE: _memory_agent_path='%s'" % ai._memory_agent_path)
		var tree = ai._get_memory_tree()
		print("PROBE: memory_tree=%s" % [tree])
		var before: int = ai._known_threats.size()
		slime.take_damage(5, player)
		print("PROBE: threats before=%d after=%d" % [before, ai._known_threats.size()])
		print("PROBE: threats=%s" % [ai._known_threats])
		if tree != null:
			var paths: Array = tree.list_by_kind(ai._memory_agent_path, "event")
			print("PROBE: event paths under agent: %d" % paths.size())
			var inserted = tree.insert_memory(ai._memory_agent_path + "/events/probe_test", "event", {"player_id": "x", "time": 1.0}, 1.0)
			print("PROBE: direct insert size=%s" % [inserted.size()])
			print("PROBE: paths after direct insert=%d" % tree.list_by_kind(ai._memory_agent_path, "event").size())
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
