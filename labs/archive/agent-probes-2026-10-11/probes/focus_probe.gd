extends SceneTree
func _init() -> void:
	await process_frame
	var svc = root.get_node_or_null("A11yService")
	var btn := Button.new()
	btn.name = "SoloBtn"
	btn.text = "Solo"
	root.add_child(btn)
	await process_frame
	await process_frame
	btn.grab_focus()
	await process_frame
	print("btn.has_focus: ", btn.has_focus())
	var snap: Array = svc.snapshot()
	for e in snap:
		print("entry focused=", e["focused"], " action=", e["action"])
	print("focus_next ret: ", svc.focus_next())
	await process_frame
	print("after: btn.has_focus=", btn.has_focus(), " owner=", root.gui_get_focus_owner())
	quit(0)
