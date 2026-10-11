extends SceneTree
func _init() -> void:
	await process_frame
	var svc = root.get_node_or_null("A11yService")
	print("svc=", svc, " processing=", svc.is_processing() if svc else "?", " mode=", svc.process_mode if svc else "?")
	svc.set_process(true)
	var b := Button.new(); b.text = "Probe"; root.add_child(b)
	await create_timer(0.8).timeout
	print("dirty=", svc._dirty, " deb=", svc._debounce, " sig_empty=", svc._last_sig == "")
	quit(0)
