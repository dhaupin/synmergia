## test_level_curve.gd - THE PROGRESSION RATIO LAW'S RECEIPT.
##
## Verifies the one-file curve law (game/core/progression/level_curve.gd):
## the shipped 1.5^n tutorial band stays byte-equal (quest reward
## authoring assumes it), the post-band breathing ratio is anchored and
## monotonic, the cap is the single authority (DEFAULT_CAP with sane
## LEVEL_CAP env override), and BOTH data-level drift rails hold:
##  * the engine consults the curve (player_manager source law), and
##  * no zone/quest/gateway .tres re-bakes an absolute content ceiling
##    (the exact drift that made the world "end" at level 30).
## Run: cd game && godot --headless --path . --script res://tests/test_level_curve.gd
extends SceneTree

const CurveScript := preload("res://core/progression/level_curve.gd")

var _fails := 0
var _passes := 0

func _ok(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("PASS: ", label)
	else:
		_fails += 1
		push_error("FAIL: %s" % label)

func _init() -> void:
	# ---- THE SHIPPED BAND IS BYTE-EQUAL --------------------------------
	_ok(CurveScript.level_cost(1) == 1000, "cost(1) keeps the seed 1000")
	_ok(CurveScript.level_cost(2) == 1500, "cost(2) keeps the 1.5 law")
	var band_top: int = int(float(1000) * pow(1.5, 9))
	_ok(CurveScript.level_cost(10) == band_top, "cost(10) is the shipped band top (%d)" % band_top)

	# ---- THE BREATHING BAND --------------------------------------------
	_ok(CurveScript.level_cost(11) == int(float(band_top) * pow(1.03, 1)),
		"cost(11) anchors at band top x ratio")
	_ok(CurveScript.level_cost(12) == int(float(band_top) * pow(1.03, 2)),
		"cost(12) compounds the ratio, not the old 1.5")
	var monotonic := true
	var prev := CurveScript.level_cost(1)
	for l in range(2, 121):
		var c := CurveScript.level_cost(l)
		if c < prev:
			monotonic = false
		prev = c
	_ok(monotonic, "curve is monotonic through level 120 (curve survives a future 100+ cap)")

	# ---- THE CAP LAW ----------------------------------------------------
	OS.set_environment("LEVEL_CAP", "")
	_ok(CurveScript.max_level() == 60, "clean env -> DEFAULT_CAP 60")
	OS.set_environment("LEVEL_CAP", "90")
	_ok(CurveScript.max_level() == 90, "sane env override -> 90")
	OS.set_environment("LEVEL_CAP", "junk")
	_ok(CurveScript.max_level() == 60, "junk env -> falls back to 60, never boot failure")
	OS.set_environment("LEVEL_CAP", "1")
	_ok(CurveScript.max_level() == 60, "absurd env (1) -> falls back to 60")
	OS.set_environment("LEVEL_CAP", "")

	# ---- INCOME CALIBRATION (informational + sanity window) -------------
	var total60: int = CurveScript.cumulative_cost_to(60)
	print("INFO: cumulative XP 1..60 = %d (curve total; seasonal packs author the income)" % total60)
	_ok(total60 < CurveScript.cumulative_cost_to(10) * 60,
		"post-band soft band keeps 60 within reach (total not 1.5^n exploded)")

	# ---- ENGINE-CONSULTS-CURVE LAW (text receipt, naming-lint precedent)
	var pm_src := FileAccess.open("res://core/autoload/player_manager.gd", FileAccess.READ).get_as_text()
	_ok(pm_src.contains("preload(\"res://core/progression/level_curve.gd\")"),
		"player_manager preloads the curve law")
	_ok(pm_src.contains("level < LevelCurve.max_level()"),
		"the add_experience loop is cap-guarded by the curve")
	_ok(pm_src.contains("LevelCurve.level_cost(level + 1)"),
		"the next level's cost comes from the curve, not a compounding drift")

	# ---- NO RE-BAKED CONTENT CEILING (data law) ------------------------
	# Tutorial gates are allowed as authored (5/8/10/12 = the walk order);
	# everything else rides the ride-forever sentinels (quest 100 ->
	# the data default; zone 999; gateway 100). Anything in between is
	# the level-30 mistake again: a content ceiling the cap raise would
	# have to remember to sweep.
	var allowed_gates := {"5": true, "8": true, "10": true, "12": true}
	var sweep_ok := true
	for base in ["res://data/zones", "res://data/quests", "res://data/gateways"]:
		var dir := DirAccess.open(base)
		if dir == null:
			continue
		for f in dir.get_files():
			if not f.ends_with(".tres"):
				continue
			var txt := FileAccess.open(base + "/" + f, FileAccess.READ).get_as_text()
			var idx := 0
			while true:
				idx = txt.find("max_level = ", idx)
				if idx < 0:
					break
				var raw := txt.substr(idx + "max_level = ".length(), 4).strip_edges()
				var val := raw.substr(0, raw.find("\n"))
				idx += 1
				if val == "999" or val == "100":
					continue
				if base.contains("quests") and allowed_gates.has(val):
					continue
				push_error("FAIL: re-baked content ceiling in %s: max_level = %s" % [f, val])
				sweep_ok = false
	_ok(sweep_ok, "zones/quests/gateways carry no absolute content ceiling (cap raises touch the curve, not 1000 tres)")

	print("--- LEVEL CURVE: %d passed, %d failed ---" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)
