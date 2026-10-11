extends SceneTree
class FF:
	var character_class: String = ""
	var level: int = 10
	var xp: int = 0
	var stats: Dictionary = {"wisdom": 0}
	func _init(cid: String = "") -> void:
		character_class = cid
	func get_healing_power() -> int:
		return int(stats.get("wisdom", 10)) * 2

func _initialize() -> void:
	var svc = root.get_node_or_null("SignService")
	var ds = root.get_node_or_null("DataService")
	if not ds._loaded: ds.load_all_data()
	if svc.has_method("ensure_initialized"): svc.ensure_initialized()
	# REPLICATE the earlier tests' clock churn:
	for d in [55555]:
		svc._unlocked_days[d] = true
		svc.set_clock_override(d * 86400.0 + 3600.0)
		svc.get_blessed_class_id(d)
		svc._unlocked_days.erase(d)
	var day := 66666
	svc._unlocked_days[day] = true
	svc.set_clock_override(day * 86400.0 + 3600.0)
	var skill = load("res://core/combat/skill.gd").new()
	skill.heal_amount = 100
	print("akkan heal=", skill.calculate_healing(FF.new("akkan_attacker")))
	print("now_day=", svc.day_index_for(svc._now_unix()), " override=", svc._clock_override)
	quit(0)
