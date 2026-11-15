extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var G = load("res://entities/moon_gate.gd")
	var g = G.new()
	g.set("target_world", "moon")
	g.set("dev_hatch", true)
	root.add_child(g)
	var svc = root.get_node_or_null("SignService")
	var reg = load("res://core/frame/srv/world_registry.gd").new()
	reg.load_worlds()
	var P: float = float(reg.get_world("moon").orbit_period_days)
	var phi: float = float(reg.get_world("moon").orbit_phase_rad)
	var e: float = (-phi / TAU) * P
	while e < svc.sky_epoch_days():
		e += P
	svc.set_clock_override((e + P * 0.5) * 86400.0)
	var w: Dictionary = g.window_status()
	print("SHUT fav=", w["favorability"], " open=", w["open"], " msg=", w["message"])
	print("PROMPT=", g.get_interaction_prompt())
	svc.set_clock_override(-1.0)
	quit(0)
