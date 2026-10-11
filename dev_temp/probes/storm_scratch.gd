extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var SB = load("res://ui/components/storm_bar.gd")
	var hud := CanvasLayer.new()
	hud.name = "HudLayer"
	root.add_child(hud)
	var bar = SB.new()
	bar.name = "StormBar"
	hud.add_child(bar)
	await process_frame
	var svc = root.get_node_or_null("ArenaRoomService")
	print("svc=", svc)
	var fake_room = {"zone_data": null}
	print("bar resolvable=", svc._storm_bar() == bar)
	svc._on_room_bout_started({"mode": 2, "storm_phases": [{},{},{},{},{}]}, "chip", fake_room)
	print("visible=", bar.visible, " armed=", bar._armed, " iid=", bar.active_instance_id())
	quit(0)
