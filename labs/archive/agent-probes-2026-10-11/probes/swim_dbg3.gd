extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var SS = load("res://core/frame/srv/swim_state.gd")
	# Pool at -29 (1 m above rock): pool squeeze_line = max(24-10, ?) = 14.
	# 23 m deep >= 14 -> SQUEEZE! The pool's squeeze band EXISTS
	# (14..24) but has per_meter=0 -- so base DPS accrues. My "tame"
	# claim needs the volume to ALSO zero the base... or the base DPS
	# is part of the tax which the volume scales entirely.
	var s = SS.new()
	var dt := 1.0/60.0
	for i in range(600):
		s.tick(dt, 23.0, 14.0, 24.0, 0.0, 0.0)
	print("pool floor state=", s.state, " pressure=", s.pressure)
	# CRUSH check: shelf 61 m: squeeze_line = 50, max 60. 61 >= 60 CRUSH.
	var svc2 = svc
	svc2.forget_swimmer("crushed")
	var r = svc2.tick_swimmer("crushed", Vector3(3000, -61.0, 0), 1.0/60.0)
	print("crush state=", r["state"], " depth=", r["depth"])
	print("CRUSH=", SS.State.CRUSH, " SQ=", SS.State.SQUEEZE)
	quit(0)
