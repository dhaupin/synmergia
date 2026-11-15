extends SceneTree
func _init() -> void:
	await process_frame
	var svc = root.get_node_or_null("A11yService")
	var panel := PanelContainer.new(); root.add_child(panel)
	var b := Button.new(); b.text = "One"; panel.add_child(b)
	var fired := {"n": 0, "t": 0.0}
	svc.focusables_changed.connect(func(): fired["n"] += 1)
	var t0 := Time.get_ticks_msec()
	for i in range(600):
		await process_frame
		if fired["n"] > 0:
			fired["t"] = (Time.get_ticks_msec() - t0) / 1000.0
			break
	print("fired=", fired["n"], " after_ms=", fired["t"])
	var b2 := Button.new(); b2.text = "Two"; panel.add_child(b2)
	var t1 := Time.get_ticks_msec()
	for i in range(600):
		await process_frame
		if fired["n"] >= 2:
			print("second fired after_ms=", (Time.get_ticks_msec() - t1) / 1000.0)
			break
	quit(0)
