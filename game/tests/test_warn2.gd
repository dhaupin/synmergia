extends SceneTree
func _init() -> void:
	for k in ["script/warnings/infer_variant","script/warnings/untyped_assignment","script/warnings/unsafe_property_access","script/warnings/unsafe_method_access","script/warnings/unsafe_cast","script/warnings/unsafe_call_argument","script/warnings/unsafe_self_use"]:
		ProjectSettings.set(k, 0)
	var s = load("res://core/services/combat_math.gd")
	print("OK", s != null)
	quit(0)
