extends SceneTree
func _init() -> void:
    var packed: PackedScene = load("res://scenes/worlds/globe_island.tscn")
    var g: Node3D = packed.instantiate()
    root.add_child(g)
    await root.get_tree().physics_frame
    await root.get_tree().physics_frame
    for i in range(g.get_child_count()):
        var c: Node = g.get_child(i)
        if c is Node3D:
            for j in range(c.get_child_count()):
                var p: Node = c.get_child(j)
                if p is Node3D:
                    print("patch:" + str(i) + ":" + str(p.name) + " children:" + str(p.get_child_count()))
                    for k in range(p.get_child_count()):
                        var r: Node = p.get_child(k)
                        print("  rock:" + str(k) + ":" + str(r.name) + " type:" + typeof(r))
    quit(0)
