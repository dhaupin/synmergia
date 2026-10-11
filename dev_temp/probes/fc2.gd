extends SceneTree
func _initialize() -> void:
	var F = load("res://core/frame/math/icosahedral_faces.gd")
	F._ensure_built()
	var svc_ang: float = deg_to_rad(360.0) / 20000.0
	print("FC2 tile-edges-scale=", svc_ang)
	quit(0)
