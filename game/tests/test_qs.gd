extends SceneTree
const QoSService = preload("res://core/autoload/qos_service.gd")
func _init() -> void:
	# Does the const preload resolve to the autoload singleton at runtime?
	print("QoSService is Node?:", QoSService is Node)
	print("QoSService has rate_limit?:", QoSService.has_method("rate_limit"))
	var ok = QoSService.rate_limit("test", "test")
	print("rate_limit returned:", ok)
	quit(0)
