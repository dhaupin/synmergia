extends SceneTree
func _init() -> void:
	await process_frame
	var svc = root.get_node_or_null("A11yService")
	var b := Button.new(); b.text = "Solo"; root.add_child(b)
	# wait through the debounce with generous headroom
	for i in range(300):
		await process_frame
	print("dirty=", svc._dirty, " deb=", svc._debounce, " sig_empty=", svc._last_sig == "")
	quit(0)
