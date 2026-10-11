extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var fs = root.get_node_or_null("FerryService")
	fs.ensure_loaded()
	fs._clock_override = 100.0 + 4.92 / 24.0
	var st = fs.route_status("veh_sundered_barque")
	print("status=", str(st.get("status","?")))
	print("dep=", str(st.get("dep",{})))
	fs._clock_override = -1.0
	quit(0)
