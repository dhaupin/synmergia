extends SceneTree
func _init() -> void:
	var q: Variant = load("res://core/schemas/quest_data.gd").new()
	q.min_level = 4
	var v = q.get("min_level", 1)
	print("DYN_GET_RESULT=", v)
	quit(0)
