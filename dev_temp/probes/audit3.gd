extends SceneTree

const PANELS := [
	"res://ui/components/quest_ui.gd",
	"res://ui/components/title_ui.gd",
	"res://ui/social/faction_ui.gd",
	"res://ui/components/bank_ui.gd",
	"res://ui/components/character_panel.gd",
	"res://ui/social/achievement_ui.gd",
	"res://ui/components/action_bar.gd",
	"res://ui/components/quick_access_bar.gd",
	"res://ui/components/loading_ui.gd",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var failed := 0
	for path in PANELS:
		var script = load(path)
		if script == null:
			print("FAIL(load) ", path)
			failed += 1
			continue
		var panel = script.new()
		root.add_child(panel)
		await process_frame
		await process_frame
		var p = panel.get_node_or_null("Panel")
		var main = null
		if p:
			main = p.get_node_or_null("Main")
		var kids: int = p.get_child_count() if p else 0
		if p == null or main == null or kids < 2:
			print("FAIL ", path, " panel=", p != null, " main=", main != null, " kids=", kids)
			failed += 1
		else:
			print("OK   ", path.get_file(), " kids=", kids)
		panel.queue_free()
		await process_frame
	print("SUMMARY: ", PANELS.size() - failed, "/", PANELS.size(), " panels alive")
	quit(0 if failed == 0 else 1)
