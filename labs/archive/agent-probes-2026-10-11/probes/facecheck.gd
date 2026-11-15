extends SceneTree
func _initialize() -> void:
	var F = load("res://core/frame/math/icosahedral_faces.gd")
	F._ensure_built()
	var d1: Vector3 = Vector3(1.0, 0.0, 0.0)
	var d2: Vector3 = Vector3(20010.52, -0.998832, -0.097762).normalized()
	print("FACECHECK dot16_1=", d1.dot(F.face_center(16)), " dot18_1=", d1.dot(F.face_center(18)))
	print("FACECHECK dot16_2=", d2.dot(F.face_center(16)), " dot18_2=", d2.dot(F.face_center(18)))
	print("FACECHECK c16=", F.face_center(16), " c18=", F.face_center(18))
	quit(0)
