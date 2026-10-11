extends SceneTree
func _init() -> void:
	_typed({"id": "x"})
	print("AFTER_CALL")
	quit(0)
func _typed(qid: String) -> void:
	print("TYPED_GOT=", qid)
