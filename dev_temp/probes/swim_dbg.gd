extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var SS = load("res://core/frame/srv/swim_state.gd")
	var s = SS.new()
	var dt := 1.0 / 60.0
	# 600 + 2100 = 2700 ticks = 45 s. breath should hit 0 at 45 s... but
	# the first 600 ticks: 10 s SUBMERGED. Then 2100 more = 35 s: total 45 s.
	# breath = 45 - 45 = 0. But floating point: 2700 * (1/60) accumulates.
	for i in range(600):
		s.tick(dt, 20.0, 50.0, 60.0)
	print("after600 breath=", s.breath)
	for i in range(2100):
		s.tick(dt, 20.0, 50.0, 60.0)
	print("after2700 breath=", s.breath, " state=", s.state, " drowning=", s.drowning_s)
	# The tame pool check: depth 23, squeeze_line 14, max_depth 24 -> SQUEEZE band!
	# pressure_per_meter=0 -> pressure accrues PRESSURE_BASE_DPS * delta anyway!
	# My bug: SQUEEZE accrues BASE even with 0 per-meter. The pool's
	# pressure_per_meter=0 means NO tax: base DPS should be scaled BY
	# the volume, not added. Check design: "pressure damage ramps,
	# scaled by pressure_per_meter" -> base is part of the volume's rate.
	quit(0)
