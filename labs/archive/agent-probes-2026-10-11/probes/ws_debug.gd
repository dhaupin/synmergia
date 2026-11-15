extends SceneTree
func _initialize() -> void:
	await process_frame
	var WS = load("res://core/frame/srv/world_state.gd")
	var ws = WS.new()
	var k: String = ws.set_world_state("underworld", "gate/abyss_seal", {"state": "opened", "by": "q"}, "player_1", 100.5)
	print("KEY: ", k)
	var got: Dictionary = ws._ensure_tree().get_state("world/w/underworld/state/gate/abyss_seal")
	print("RAW: ", got)
	print("READ: ", ws.get_world_state("underworld", "gate/abyss_seal"))
	print("KEYS: ", ws.world_state_keys("underworld"))
	quit(0)
