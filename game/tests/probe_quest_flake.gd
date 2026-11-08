## probe_quest_flake.gd - one-shot diagnostic for the quests-panel flake.
## Boots the same round-6 journey, then at 6.1s inspects:
##   - the NPC the battery would pick for the quest offering
##   - what _npc_data_for_target / _npc_quest_ids_for_target resolve
##   - the MenuManager instance identity + open_panels after opening
extends SceneTree

var _t := 0.0
var _schedule: Array = []

func _initialize() -> void:
	print("=== QUEST FLAKE PROBE ===")
	change_scene_to_file("res://ui/menus/main_menu.tscn")
	ProjectSettings.set_setting("synmergia/world/shape", "planar")
	_schedule = [
		[1.0, _hop], [1.9, _hop], [2.8, _hop], [3.7, _hop],
		[4.4, _auto_select], [4.7, _auto_play],
		[6.1, _inspect],
	]

func _hop() -> void:
	if current_scene == null:
		return
	var start_btn: Button = current_scene.get_node_or_null("MenuButtons/StartButton")
	if start_btn and not start_btn.disabled:
		start_btn.pressed.emit()
		return
	if current_scene.name == "Login":
		var guest: Button = current_scene.get_node_or_null("Center/Panel/Form/Buttons/GuestButton")
		if guest and not guest.disabled:
			guest.pressed.emit()
			return
	if current_scene.name == "Lobby":
		var create: Button = current_scene.get_node_or_null("Center/Panel/VBox/Buttons/CreateButton")
		if create and not create.disabled:
			create.pressed.emit()

func _auto_select() -> void:
	if current_scene and current_scene.name == "CharacterSelect" and current_scene.has_method("_auto_select"):
		current_scene.call("_auto_select")

func _auto_play() -> void:
	if current_scene and current_scene.has_method("_auto_play"):
		current_scene.call("_auto_play")

func _inspect() -> void:
	var world := current_scene
	print("scene=", world.name if world else "null")
	var found: Array = []
	if world:
		for npc in world.get_tree().get_nodes_in_group("offering_npcs"):
			if not is_instance_valid(npc) or not ("npc_data" in npc) or npc.npc_data == null:
				continue
			if npc.npc_data.has_method("has_offering") and npc.npc_data.has_offering("quest"):
				found.append(npc)
	print("quest npcs=", found.size())
	if found.is_empty():
		quit(1)
		return
	var npc: Node = found[0]
	print("chosen npc entity_id=", npc.entity_id, " data id=", npc.npc_data.id)
	var es := root.get_node_or_null("EntityService")
	if es and es.has_method("get_entity"):
		print("entity_svc lookup: ", es.get_entity(str(npc.entity_id)))
	var world_player := _player()
	if world_player == null:
		print("player=null")
		quit(1)
		return
	print("player= ", world_player.entity_id if "entity_id" in world_player else world_player.name)
	var data = world_player.call("_npc_data_for_target", str(npc.entity_id))
	print("npc_data_for_target => ", data)
	if data != null:
		print("quest ids => ", world_player.call("_npc_quest_ids_for_target", str(npc.entity_id)))
	var mm := root.get_node_or_null("MenuManager")
	print("mm@root=", mm)
	var hud := world.get_node_or_null("HudLayer") if world else null
	var mm_hud: Node = hud.get_node_or_null("MenuManager") if hud else null
	print("mm@hud=", mm_hud, " static_instance=", mm_hud.get("instance") if mm_hud else "?")
	world_player.call("_open_npc_quests", str(npc.entity_id))
	await process_frame
	await process_frame
	if mm_hud:
		print("hud open_panels=", mm_hud.get("_open_panels"))
	if root.get_node_or_null("MenuManager") != null:
		print("root open_panels=", root.get_node_or_null("MenuManager").get("_open_panels"))
	quit(0)

func _player() -> Node:
	var es := root.get_node_or_null("EntityService")
	if es and es.has_method("get_all_entities"):
		for e in es.get_all_entities():
			if is_instance_valid(e) and "is_local_player" in e and e.is_local_player:
				return e
	if current_scene == null:
		return null
	return current_scene.get_node_or_null("Player") if current_scene.get_node_or_null("Player") else current_scene.get("player")

func _process(delta: float) -> bool:
	_t += delta
	while not _schedule.is_empty() and _t >= float(_schedule[0][0]):
		var step: Array = _schedule.pop_front()
		(step[1] as Callable).call()
	return false
