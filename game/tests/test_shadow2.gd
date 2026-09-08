extends SceneTree
const EventHub = preload("res://core/events/event_hub.gd")
func _init() -> void:
	# Does the const preload resolve to the autoload singleton at runtime?
	print("EventHub is Node?:", EventHub is Node)
	print("EventHub has player_died signal?:", EventHub.has_signal("player_died"))
	quit(0)
