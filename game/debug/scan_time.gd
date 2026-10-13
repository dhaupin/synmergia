extends SceneTree
## One-shot timing: cost per call of terrain_height vs _land_mass,
## so the landmass scan grid can be sized to fit inside a bounded run.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var Sph = load("res://core/frame/math/spherical.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var n: int = 4000
	var ga: float = PI * (3.0 - sqrt(5.0))
	var dirs: Array = []
	for i in range(n):
		var y: float = 1.0 - 2.0 * (float(i) + 0.5) / float(n)
		var r: float = sqrt(maxf(0.0, 1.0 - y * y))
		var th: float = ga * float(i)
		dirs.append(Vector3(cos(th) * r, y, sin(th) * r).normalized())
	var t0: int = Time.get_ticks_usec()
	var s: float = 0.0
	for d in dirs:
		s += Gen.terrain_height(d, seed_b)
	var t1: int = Time.get_ticks_usec()
	for d in dirs:
		s += Gen._land_mass(d, Gen._seed_salt(seed_b, "terrain"))
	var t2: int = Time.get_ticks_usec()
	print("terrain_height: %.3f ms/call  _land_mass: %.3f ms/call (s=%.1f)" % [
		float(t1 - t0) / 1000.0 / float(n), float(t2 - t1) / 1000.0 / float(n), s])
	quit(0)
