extends SceneTree
var _fails := 0
func _check(cond: bool, label: String) -> void:
	if cond: print("PASS: " + label)
	else:
		_fails += 1; printerr("FAIL: " + label)
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var UP = load("res://ui/components/ui_panel.gd")
	var titles := {}
	for n in ["SkillAcademyUI", "ShopUI", "SettingsPanel", "FerryDockUi", "inventory_ui", "TradeUi", "QuestUi"]:
		var p: Control = UP.new()
		p.name = n
		titles[n] = p.call("_display_title")
		p.free()
	for t in titles: print("  " + t + " -> \"" + titles[t] + "\"")
	_check(String(titles["SkillAcademyUI"]) == "Skill Academy", "SkillAcademyUI pays prettified")
	_check(String(titles["ShopUI"]) == "Shop", "ShopUI pays prettified")
	_check(String(titles["SettingsPanel"]) == "Settings", "SettingsPanel pays prettified")
	_check(String(titles["FerryDockUi"]) == "Ferry Dock", "FerryDockUi pays prettified")
	_check(String(titles["inventory_ui"]) == "Inventory", "inventory_ui pays prettified")
	_check(String(titles["TradeUi"]) == "Trade", "TradeUi pays prettified")
	_check(String(titles["QuestUi"]) == "Quest", "QuestUi pays prettified")
	# set_panel_title still wins.
	var q: Control = UP.new()
	q.name = "QuestUi"
	q.set_panel_title("Guild Hall")
	_check(String(q.call("_display_title")) == "Guild Hall", "set_panel_title outranks the fallback")
	q.free()
	print("PANEL TITLES probe: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
