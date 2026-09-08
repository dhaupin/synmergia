extends SceneTree
func _init() -> void:
	var keys = []
	for k in ProjectSettings.get_property_list():
		var n = k.get("name","")
		if "infer_variant" in n or "untyped_assignment" in n or "variant" in n:
			keys.append(n + "=" + str(ProjectSettings.get(n)))
	print("KEYS:", keys)
	quit(0)
