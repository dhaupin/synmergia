extends SceneTree
func _init() -> void:
	var r := Resource.new()
	var got = r.get("nope", 7)
	print("GET_RESULT=", got)
	quit(0)
