extends SceneTree
func _init() -> void:
	# In normal boot, are autoloads bare globals?
	print("GameLog exists?:", "GameLog" in self)
	print("CooldownService exists?:", "CooldownService" in self)
	print("QoSService exists?:", "QoSService" in self)
	quit(0)
