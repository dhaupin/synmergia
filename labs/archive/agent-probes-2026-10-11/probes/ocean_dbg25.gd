extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	var script = load("res://core/services/ocean_service.gd")
	var txt = script.source_code
	var i = txt.find("func sample_depth")
	print("SAMPLE_START_OK=", i > 0)
	print(txt.substr(i, 400))
	quit(0)
