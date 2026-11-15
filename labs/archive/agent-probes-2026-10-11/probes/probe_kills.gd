extends SceneTree
func _initialize() -> void:
	await process_frame
	var horde = root.get_node_or_null("HordeEventService")
	var es = root.get_node_or_null("EntityService")
	var pm = root.get_node_or_null("PlayerManager")
	var PlayerScript = load("res://entities/player/player_controller.gd")
	var player: Node = PlayerScript.new()
	player.display_name = "Probe"
	player.entity_id = "probe_char"
	root.add_child(player)
	await process_frame
	es.register_entity(player, null, "probe_char")
	pm.set_local_player(player)
	await process_frame
	var captured := []
	horde.horde_rewards_distributed.connect(func(hid, report): captured.append(report))
	var horde_id: String = horde.start_horde("pz", {"template_id": "slime", "waves": 1, "mobs_per_wave": 2, "inter_wave_delay": 0.0, "boss_template_id": "slime", "reward_gold": 100, "reward_xp": 50})
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var st: Dictionary = horde.get_horde_status(horde_id)
		if str(st.get("state","")) == "fighting" and int(st.get("remaining",-1)) == 2:
			break
	var mob_ids: Array = horde._hordes[horde_id]["mobs_spawned_ids"]
	for eid in mob_ids:
		var mob = es.get_entity(str(eid))
		if mob != null and is_instance_valid(mob):
			mob.take_damage(99999, player)
	deadline = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var st: Dictionary = horde.get_horde_status(horde_id)
		if str(st.get("state","")) == "boss" and str(st.get("boss_id","")) != "":
			break
	var boss = es.get_entity(str(horde.get_horde_status(horde_id).get("boss_id","")))
	if boss != null and is_instance_valid(boss):
		boss.take_damage(99999, player)
	deadline = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if horde._hordes.is_empty():
			break
	print("PROBE report: ", captured)
	quit(0)
