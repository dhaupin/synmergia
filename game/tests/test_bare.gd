extends SceneTree
func _init() -> void:
	# In --script mode, are autoloads bare globals?
	print("GameLog exists?:", "GameLog" in self)
	quit(0)
