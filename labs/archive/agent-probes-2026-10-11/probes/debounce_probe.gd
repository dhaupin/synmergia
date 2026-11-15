extends SceneTree
func _init() -> void:
	await process_frame
	var svc = root.get_node_or_null("A11yService")
	var panel := PanelContainer.new()
	root.add_child(panel)
	var b := Button.new(); b.text = "One"; panel.add_child(b)
	var fired := {"n": 0}
	svc.focusables_changed.connect(func(): fired["n"] += 1)
	await create_timer(1.0).timeout
	print("after first settle: fired=", fired["n"], " dirty=", svc._dirty, " lastsig_empty=", svc._last_sig == "")
	var b2 := Button.new(); b2.text = "Two"; panel.add_child(b2)
	await create_timer(1.0).timeout
	print("after second add: fired=", fired["n"], " dirty=", svc._dirty, " sig=", svc._last_sig.left(40))
	quit(0)
