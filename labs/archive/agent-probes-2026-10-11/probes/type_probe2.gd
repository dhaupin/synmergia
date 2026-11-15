extends SceneTree
func _init() -> void:
	var q: Variant = {"id": "x"}
	_typed(q)
	print("AFTER_CALL")
	quit(0)
func _typed(qid: String) -> void:
	print("TYPED_GOT=", qid)
