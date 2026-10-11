extends SceneTree
func _init() -> void:
	var scene: PackedScene = load("res://../tmp/import_test/cube_merged.glb")
	print("loaded: ", scene != null)
	quit(0)
