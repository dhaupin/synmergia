extends SceneTree
## LOS probe: pure geometry, no terrain reads. Verifies the exact
## segment-clears-sphere test against hand-computed cases (pairing
## law ~ sqrt(2R h1) + sqrt(2R h2)) so the vista scan verdict is code
## truth, not a formula bug.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var R: float = 20000.0
	# eye 64 m over the sphere, on +x.
	var eye: Vector3 = Vector3(R + 64.0, 0.0, 0.0)
	# target top at height H above the sphere along +x rotated by theta.
	var _tests: Array = [
		# [theta(rad), H_above_sphere, expect_human(1 visible / 0 not)]
		[0.26, 362.0, 1.0],
		[0.26, 100.0, 0.0],
		[0.07, 2.0, 1.0],
		[0.30, 800.0, 1.0],
		[0.10, 10.0, 0.0],
	]
	for t in _tests:
		var th: float = t[0]
		var d: Vector3 = Vector3(cos(th), sin(th), 0.0)  # lat 0 row
		var tgt: Vector3 = (R + t[1]) * d
		var vis: bool = _segment_clears_sphere(eye, tgt, R)
		var pair: float = sqrt(2.0 * R * 64.0) + sqrt(2.0 * R * t[1])
		print("theta=%.2f H=%.0f exact=%s pairing=%.0f m (angles agree=%s)" % [
			th, t[1], ("VIS" if vis else "no"), pair,
			(("same" if vis == (pair > th * R) else "DISAGREE"))])
	quit(0)

func _segment_clears_sphere(a: Vector3, b: Vector3, R: float) -> bool:
	var ab: Vector3 = b - a
	var denom: float = ab.dot(ab)
	if denom < 1e-9:
		return a.length() > R
	var t_star: float = clampf(-a.dot(ab) / denom, 0.0, 1.0)
	var closest: Vector3 = a + ab * t_star
	return closest.length() > R
