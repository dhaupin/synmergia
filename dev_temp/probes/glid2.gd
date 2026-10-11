extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var ResourceScan = load("res://core/frame/srv/resource_scan.gd")
	for p in ResourceScan.list_resources("res://data/gliders"):
		var r: Resource = load(p)
		var gn: String = "noscript"
		if r.get_script() != null:
			gn = (r.get_script() as Script).get_global_name()
		print("HIGH: ", p.get_file(), " gn=", gn, " id=", r.get("id"))
	for p in ResourceScan.list_resources("res://data/mounts"):
		var r2: Resource = load(p)
		var gn2: String = "noscript"
		if r2.get_script() != null:
			gn2 = (r2.get_script() as Script).get_global_name()
		print("MID: ", p.get_file(), " gn=", gn2)
	quit(0)
