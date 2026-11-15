extends SceneTree
func _initialize() -> void:
	var ds = root.get_node_or_null("DataService")
	var svc = root.get_node_or_null("SignService")
	if not ds._loaded: ds.load_all_data()
	if svc.has_method("ensure_initialized"): svc.ensure_initialized()
	var world: PackedScene = load("res://scenes/world_playable.tscn")
	var inst := world.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame
	var door = inst.get_node_or_null("AncientDoor")
	var day: int = door._resolve_day()
	var now_day: int = svc.day_index_for(float(Time.get_unix_time_from_system()))
	print("door resolves day=", day, " now=", now_day, " offset=", door.for_day_offset)
	print("unlocked(day)=", svc.is_ancient_unlocked(day))
	for w in svc.WINDOWS_PER_DAY:
		svc.force_reveal_window(now_day, w)
	print("after reveal: unlocked(tomorrow)=", svc.is_ancient_unlocked(now_day + 1))
	await process_frame
	await process_frame
	print("door._is_open=", door._is_open, " _last_known=", door._last_known_unlocked)
	quit(0)
