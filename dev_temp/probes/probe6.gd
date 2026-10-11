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
	var skill = load("res://core/combat/skill.gd").new()
	skill.heal_amount = 100
	# Full replication: combatmath test's exact day + heal test's day
	var d1 := 55555
	svc._unlocked_days[d1] = true
	svc.set_clock_override(d1 * 86400.0 + 3600.0)
	var b1: String = svc.get_blessed_class_id(d1)
	var other1 := ""
	for cid in svc._playable_class_ids():
		if cid != b1:
			other1 = cid
			break
	print("d1 blessed=", b1, " other=", other1)
	svc._unlocked_days.erase(d1)
	# heal test:
	var day := 66666
	svc._unlocked_days[day] = true
	svc.set_clock_override(day * 86400.0 + 3600.0)
	var b2: String = svc.get_blessed_class_id(day)
	print("d2 blessed=", b2)
	print("heal(other1)=", skill.calculate_healing(FF.new(other1)))
	print("is_blessed(other1)=", svc.is_class_blessed(other1))
	quit(0)
