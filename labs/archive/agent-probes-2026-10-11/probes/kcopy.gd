extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var r = load("res://data/gliders/zz_probe_copy.tres")
	if r != null:
		print("HIGH copy id=", r.get("id"), " gn=", ((r.get_script() as Script).get_global_name() if r.get_script() != null else "noscript"))
	else:
		print("HIGH copy failed to load")
	quit(0)
