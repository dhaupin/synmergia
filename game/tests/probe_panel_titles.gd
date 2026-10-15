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

	# ---- The NPC-panel distance law pins (the walking-away close) ----
	# One generous canonical radius every NPC-attached panel shares:
	# tap-targets reach well past melee, so a tight default closed
	# panels the frame after opening. The academy rides the same law
	# (its old hardcoded 8m is retired), and the player's own skill/
	# stats management panel has NO leash (works everywhere).
	_check(float(UP.DEFAULT_MAX_INTERACT_DISTANCE) == 12.0, "the canonical close radius is 12m (tap-and-browse safe)")
	var up: Control = UP.new()
	_check(float(up.get("_max_interact_distance")) == 12.0, "fresh panels ride the canonical radius")
	_check(bool(up.call("is_within_interact_distance", Vector3.ZERO, Vector3(11, 0, 0))), "11m reads inside the close law")
	_check(not bool(up.call("is_within_interact_distance", Vector3.ZERO, Vector3(13, 0, 0))), "13m reads outside the close law (real walk-aways close)")
	up.free()
	var SAC = load("res://ui/components/skill_academy_ui.gd")
	var acad: Control = SAC.new()
	_check(float(acad.get("_max_interact_distance")) == 12.0, "the skill academy rides the canonical radius")
	acad.free()
	var sac_src := FileAccess.get_file_as_string("res://ui/components/skill_academy_ui.gd")
	_check(sac_src.contains("_max_interact_distance"), "the academy close law routes through the panel radius var")
	_check(not sac_src.contains("> 8.0"), "the hardcoded 8m academy radius is retired")
	var cs_src := FileAccess.get_file_as_string("res://ui/menus/character_stats_ui.gd")
	_check(not cs_src.contains("check_interact_distance"), "the player management panel has no NPC leash (works everywhere)")
	print("PANEL TITLES probe: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
