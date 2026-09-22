## probe_npc_registry.gd - dump entity registry state after boot.
extends SceneTree

var _t := 0.0
var _done := false

func _initialize() -> void:
	change_scene_to_file("res://ui/menus/main_menu.tscn")

var _steps := {
	1.0: false,
	2.0: false,
	2.6: false,
}

func _process(delta: float) -> bool:
	_t += delta
	# Journey: play -> select -> play (same as test_interaction_pipeline).
	if _t >= 1.0 and not _steps[1.0]:
		_steps[1.0] = true
		var btn: Button = current_scene.get_node_or_null("MenuButtons/PlayButton")
		if btn and not btn.disabled:
			btn.pressed.emit()
	if _t >= 2.0 and not _steps[2.0]:
		_steps[2.0] = true
		if current_scene and current_scene.name == "CharacterSelect" and current_scene.has_method("_auto_select"):
			current_scene._auto_select()
	if _t >= 2.6 and not _steps[2.6]:
		_steps[2.6] = true
		if current_scene and current_scene.has_method("_auto_play"):
			current_scene._auto_play()
	if _t < 6.0 or _done:
		return false
	_done = true
	var es := root.get_node_or_null("EntityService")
	if es == null:
		print("PROBE: no EntityService")
		quit(1)
		return false
	var all: Array = es.get_all_entities()
	print("PROBE: get_all_entities() count = ", all.size())
	for e in all:
		var valid := is_instance_valid(e)
		var etype := str(e.get("entity_type")) if valid and "entity_type" in e else "n/a"
		var ename := str(e.display_name) if valid and "display_name" in e else "n/a"
		var eid := str(e.entity_id) if valid and "entity_id" in e else "n/a"
		var has_npcdata: bool = valid and "npc_data" in e and e.npc_data != null
		var inside_tree: bool = valid and e.is_inside_tree()
		print("PROBE entity: id=%s name=%s type=%s npc_data=%s in_tree=%s valid=%s" % [eid, ename, etype, str(has_npcdata), str(inside_tree), str(valid)])
	var npcs: Array = es.get_all_npcs() if es.has_method("get_all_npcs") else []
	print("PROBE: get_all_npcs() count = ", npcs.size())
	# Where does the scene tree hold NPCs?
	var world := current_scene
	if world:
		print("PROBE: current_scene = ", world.name)
		for group_name in ["npcs", "entities"]:
			print("PROBE group '%s': %d nodes" % [group_name, world.get_tree().get_nodes_in_group(group_name).size()])
	quit(0)
	return false
