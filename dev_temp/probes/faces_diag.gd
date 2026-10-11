extends SceneTree
func _init() -> void:
	var F = load("res://core/frame/math/icosahedral_faces.gd")
	print("count=", F.face_count())
	for f in range(F.face_count()):
		var fv: PackedInt32Array = F.face_vertices(f)
		print("face ", f, " verts=", fv, " nbrs=", F.neighbors(f))
	quit(0)
