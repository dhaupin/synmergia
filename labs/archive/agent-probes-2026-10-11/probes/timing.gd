extends SceneTree
func _init() -> void:
    var Ico: GDScript = load("res://core/frame/math/icosahedral.gd").new()
    var Sph: GDScript = load("res://core/frame/math/spherical.gd")
    var t0: float = Time.get_unix_time_from_system()
    var pos: Vector3 = Sph.spherical_to_cartesian(0.0, 0.0, 1.0, 20000.0)
    var cell: int = Ico.position_to_cell(pos, 20000.0)
    var t1: float = Time.get_unix_time_from_system()
    print("position_to_cell at 20km took " + str(t1 - t0) + " second(s)")
    quit(0)
