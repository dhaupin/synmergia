extends SceneTree
const KillRewards2 = preload("res://core/services/kill_rewards.gd")
class FakeFighter:
	var character_class: String = ""
	var level: int = 10
	var xp: int = 0
	var stats: Dictionary = {"strength": 20, "agility": 10, "intelligence": 10, "vitality": 10, "wisdom": 0}
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
	var skill = load("res://core/combat/skill.gd").new()
	skill.heal_amount = 100
	var a = FakeFighter.new("synthetic_conduit")
	var b = FakeFighter.new("akkan_attacker")
	print("heal synthetic_conduit=", skill.calculate_healing(a))
	print("heal akkan_attacker=", skill.calculate_healing(b))
	quit(0)
