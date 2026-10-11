extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ok := true
	for path in [
		"res://data/roots/world/environment.tres",
		"res://data/roots/shard/environment.tres",
		"res://data/roots/instance/environment.tres",
		"res://data/roots/player/environment.tres",
	]:
		var res = ResourceLoader.load(path)
		if res == null:
			printerr("FAIL: ", path, " failed to load")
			ok = false
		else:
			print("PASS: ", path, " -> ", res.get_class())
	print("RESULT: ", "ALL PARSE OK" if ok else "BROKEN")
	quit(0 if ok else 1)
