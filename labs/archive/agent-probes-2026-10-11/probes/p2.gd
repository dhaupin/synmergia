extends SceneTree
const GLOBE_SCENE := "res://scenes/worlds/globe_island.tscn"
func _init() -> void:
    var packed: PackedScene = load(GLOBE_SCENE)
    var g: Node3D = packed.instantiate()
    root.add_child(g)
    print("children:" + str(g.get_child_count()))
    var nodes := g.get_children()
    for i in range(nodes.size()):
        print("child" + str(i) + ":" + str(nodes[i].name))
    var p: Node = g.get("player")
    print("get_player:" + str(p))
    quit(0)
