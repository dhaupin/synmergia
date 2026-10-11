extends SceneTree
func _init() -> void:
	var g = load("res://scenes/worlds/terrain_gen.gd")
	var Faces = load("res://core/frame/math/icosahedral_faces.gd")
	var seed_b: PackedByteArray = g.world_seed_bytes()
	for f in range(20):
		var center: Vector3 = Faces.face_center(f)
		var verts: PackedInt32Array = Faces.face_vertices(f)
		var v: Vector3 = Icosahedral.VERTICES[verts[0]].normalized()
		var prev: float = 0.0
		var maxd: float = 0.0
		var maxi: int = 0
		for i in range(41):
			var t: float = float(i) / 40.0
			var dir: Vector3 = (center * (1.0 - t) + v * t).normalized()
			var h: float = g.rock_top_height(dir, seed_b, f, 100.0)
			if i > 0 and abs(h - prev) > maxd:
				maxd = abs(h - prev); maxi = i
			prev = h
		print("face %d maxdelta %.3f at step %d" % [f, maxd, maxi])
	quit(0)
