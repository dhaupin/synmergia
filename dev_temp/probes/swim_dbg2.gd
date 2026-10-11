extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var SS = load("res://core/frame/srv/swim_state.gd")
	var s = SS.new()
	var dt := 1.0 / 60.0
	# Keep going past 2700: how long until drowning accrues?
	for i in range(600):
		s.tick(dt, 20.0, 50.0, 60.0)
	for i in range(2110):
		s.tick(dt, 20.0, 50.0, 60.0)
	print("breath=", s.breath, " drowning=", s.drowning_s, " state=", s.state)
	quit(0)
