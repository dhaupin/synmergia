extends SceneTree
const EventHub = preload("res://core/events/event_hub.gd")
func _init() -> void:
	print("typeof EventHub:", typeof(EventHub))
	print("EventHub class:", EventHub.get_class() if EventHub.has_method("get_class") else "no method")
	print("has player_died?:", EventHub.has_signal("player_died") if EventHub.has_method("has_signal") else "no method")
	quit(0)
