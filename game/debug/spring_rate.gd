extends SceneTree
## Forensics: replicate the law's per-spring rng stream exactly and
## print EVERY try's gate verdicts (land / base), sum legals per
## spring; then diff against river_springs itself — so the starvation
## point is read from the actual stream, not from inference.

func _init() -> void:
	print("forensics: loaded")
	call_deferred("_run")

func _run() -> void:
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var sea: float = Gen.sea_level(seed_b)
	var world_legal: int = 0
	for i in range(24):
		var acc: int = Gen._seed_salt(seed_b, "hydro_springs")
		acc = (acc * 131 + i) % 9007199254740991
		var rng := RandomNumberGenerator.new()
		rng.seed = acc
		var legal_here := 0
		var drained_here := 0
		var first_legal := ""
		for t in range(64):
			var d3: Vector3 = Vector3(rng.randf() * 2.0 - 1.0, rng.randf() * 2.0 - 1.0, rng.randf() * 2.0 - 1.0)
			if d3.length() < 0.001:
				continue
			d3 = d3.normalized()
			var lb: float = Gen._land_mass(d3, Gen._seed_salt(seed_b, "terrain"))
			var hb: float = Gen._terrain_height_base(d3, seed_b)
			var ok: bool = lb >= 0.3 and hb > sea
			if ok:
				legal_here += 1
				world_legal += 1
				if first_legal == "":
					first_legal = str(d3)
			if ok:
				# the drained criterion exactly as the law reads it
				var hint2: Vector3 = Vector3(0, 1, 0) if absf(d3.dot(Vector3(0, 1, 0))) < 0.9 else Vector3(1, 0, 0)
				var sa2: Vector3 = d3.cross(hint2).normalized()
				var sb2: Vector3 = d3.cross(sa2).normalized()
				for kk in range(8):
					var ang2: float = TAU * float(kk) / 8.0
					var tan2: Vector3 = sa2 * cos(ang2) + sb2 * sin(ang2)
					var ax2: Vector3 = tan2.cross(d3)
					if ax2.length() <= 1e-9:
						ax2 = sa2
					var cd: Vector3 = d3.rotated(ax2.normalized(), Gen.Hydro.RIVER_STEP_ANG).normalized()
					if Gen._terrain_height_base(cd, seed_b) < hb - 0.1:
						drained_here += 1
						break
		print("spring %2d: legals_in_64=%d drained=%d first=%s" % [i, legal_here, drained_here, first_legal])
	print("WORLD_LEGAL_ACROSS_STREAM=%d (law's river_springs says %d)" % [
		world_legal, Gen.river_springs(seed_b).size()])
	quit(0)
