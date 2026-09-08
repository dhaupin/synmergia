extends SceneTree
func _init() -> void:
	# In normal boot, are autoloads bare globals?
	print("CooldownService exists?:", "CooldownService" in self)
	print("QoSService exists?:", "QoSService" in self)
	print("GameLog exists?:", "GameLog" in self)
	quit(0)
