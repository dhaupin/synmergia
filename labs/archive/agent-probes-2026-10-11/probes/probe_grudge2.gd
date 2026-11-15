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
	print("PROBE2: player is Entity: %s" % (player is Entity))
	print("PROBE2: player is Node: %s, has entity_id: %s, id='%s'" % [player is Node, "entity_id" in player, player.entity_id])
	print("PROBE2: player entity_type=%s (PLAYER=%d)" % [player.entity_type, Entity.EntityType.PLAYER])
	var is_combatant: bool = player is Entity or (player is Node and "entity_id" in player)
	print("PROBE2: is_combatant=%s" % is_combatant)
	ai.on_damaged(player)
	print("PROBE2: after direct on_damaged: threats=%s" % [ai._known_threats])
	print("PROBE2: aggro_component=%s" % [slime.get("aggro_component")])
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
