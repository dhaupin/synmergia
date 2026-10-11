extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var fs = root.get_node_or_null("FerryService")
	fs.ensure_loaded()
	var v = fs.get_ferry("veh_sundered_barque")
	print("barque_found=", v != null)
	if v != null:
		print("per_day=", int(v.ferries_per_day), " first=", float(v.first_departure_hour), " cross=", float(v.crossing_hours))
		fs._clock_override = 100.0 + 5.5 / 24.0
		var st = fs.route_status("veh_sundered_barque")
		print("status=", str(st.get("status","?")))
		print("dep=", str(st.get("dep",{})))
		fs._clock_override = -1.0
	quit(0)
