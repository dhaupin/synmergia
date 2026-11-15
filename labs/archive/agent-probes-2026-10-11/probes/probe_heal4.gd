extends SceneTree
class FF:
	var character_class: String = ""
	var level: int = 10
	var xp: int = 0
	var stats: Dictionary = {"strength": 20, "wisdom": 0}
	func _init(cid: String = "") -> void:
		character_class = cid
	func get_healing_power() -> int:
		return int(stats.get("wisdom", 10)) * 2

func _initialize() -> void:
	var svc = root.get_node_or_null("SignService")
	var ds = root.get_node_or_null("DataService")
	if not ds._loaded: ds.load_all_data()
	if svc.has_method("ensure_initialized"): svc.ensure_initialized()
	var day := 66666
	svc._unlocked_days[day] = true
	svc.set_clock_override(day * 86400.0 + 3600.0)
	var named: String = svc.get_blessed_class_id(day)
	var other := ""
	for cid in svc._playable_class_ids():
		if cid != named:
			other = cid
			break
	print("named=", named, " other=", other)
	var skill = load("res://core/combat/skill.gd").new()
	skill.heal_amount = 100
	print("heal(named)=", skill.calculate_healing(FF.new(named)))
	print("heal(other)=", skill.calculate_healing(FF.new(other)))
	quit(0)
