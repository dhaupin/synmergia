extends SceneTree
func _init() -> void:
	# In normal boot, are autoloads bare globals?
	print("GameLog exists?:", "GameLog" in self)
	print("EventHub exists?:", "EventHub" in self)
	quit(0)
