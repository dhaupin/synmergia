extends SceneTree
func _init() -> void:
    var packed: PackedScene = load("res://scenes/worlds/globe_island.tscn")
    var g: Node3D = packed.instantiate()
    root.add_child(g)
    print("child_count: " + str(g.get_child_count()))
    for i in range(g.get_child_count()):
        print("child" + str(i) + ":" + g.get_child(i).name)
    var p: Node = g.get("player")
    print("get(player):" + str(p))
    quit(0)
