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
	var texts: Array = []
	for row in chart._moon_rows.get_children():
		texts.append(str(row.text))
	print("MOON_PAGE_ROWS=", texts.size())
	for t in texts:
		print("ROW: ", t)
	quit(0)
