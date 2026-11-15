extends SceneTree
func _initialize() -> void:
	var svc = root.get_node_or_null("SignService")
	var ds = root.get_node_or_null("DataService")
	if not ds._loaded: ds.load_all_data()
	if svc.has_method("ensure_initialized"): svc.ensure_initialized()
	var day := 66666
	svc._unlocked_days[day] = true
	svc.set_clock_override(day * 86400.0 + 3600.0)
	var skill_script = load("res://core/combat/skill.gd")
	var skill = skill_script.new()
	skill.heal_amount = 100
	var f = RefCounted.new()
	f.set_meta("x", 1)
	# duck-typed fighter inline
	var fighter = load("res://tests/test_daily_class_blessing.gd").FakeFighter.new("akkan_attacker")
	fighter.stats["wisdom"] = 0
	print("heal=", skill.calculate_healing(fighter))
	print("blessed?(akkan_attacker)=", svc.is_class_blessed("akkan_attacker"))
	print("blessed_day=", svc.day_index_for(svc._now_unix()))
	quit(0)
