extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var A = load("res://ui/components/sky_almanac_ui.gd")
	var chart = A.new()
	root.add_child(chart)
	await process_frame
	await process_frame
	chart.refresh()
	chart.refresh()
	var names: Array = []
	for row in chart._moon_rows.get_children():
		names.append(row.get_instance_id())
	var seen: Dictionary = {}
	var dupes: int = 0
	for id in names:
		if seen.has(id):
			dupes += 1
		seen[id] = true
	print("UNIQUE_ROWS=", seen.size(), " DUPLICATES=", dupes)
	quit(0)
