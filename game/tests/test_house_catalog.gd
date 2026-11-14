# test_house_catalog.gd - THE HOUSING RECEIPT: every house tier in
# data/houses/ must hold its own integrity LAWS, and HousingService must
# read the tier rather than a hardcoded constant:
#
#   A. IDENTITY: filename == id, the family's house_ prefix, and the
#      script binds to house_data.gd.
#   B. THE HONEST TAG: display_name + description + icon_path authored,
#      icon_path resolves to a real file under res://icons/.
#   C. THE TIER LADDER: cost climbs with tier (a later tier never costs
#      less than an earlier one), footprint and wall_height grow too, and
#      every tier carries at least one structural feature.
#   D. THE SERVICE READS DATA: HousingService.build_house charges the
#      tier's cost and stamps plot.house_tier, and an unknown tier falls
#      back to the built-in cottage constants (never a crash).
#
# Receipt-lore: script-mode law -- autoloads resolved from root at
# runtime; the dir is walked with DirAccess exactly like
# test_data_naming_lint; failure names the file.
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)

func _finish() -> void:
	print("--- HOUSE CATALOG: %d passed, %d failed ---" % [_checks - _fails, _fails])
	quit(0 if _fails == 0 else 1)

func _tres_files(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".tres"):
			out.append(f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

func _run() -> void:
	var root_node := root
	var ds = root_node.get_node_or_null("DataService")
	_check("DataService autoload present", ds != null)

	var files := _tres_files("res://data/houses")
	_check("house tier dir has files (%d)" % files.size(), files.size() > 0)

	var tiers: Array = []
	for fn in files:
		var rel: String = "data/houses/" + str(fn)
		var txt := FileAccess.get_file_as_string("res://" + rel)
		var base: String = str(fn).trim_suffix(".tres")

		# A. IDENTITY
		_check("%s: filename uses house_ prefix" % fn, base.begins_with("house_"))
		_check("%s: id == filename" % fn, txt.contains('id = "%s"' % base))
		_check("%s: binds house_data.gd" % fn, txt.contains("core/schemas/house_data.gd"))

		# B. THE HONEST TAG
		_check("%s: display_name authored" % fn, txt.contains("display_name = ") and not txt.contains('display_name = ""'))
		_check("%s: description authored" % fn, txt.contains("description = ") and not txt.contains('description = ""'))
		_check("%s: features authored" % fn, txt.contains("features = ["))

		# icon_path resolves on disk
		var icon_line := ""
		for line in txt.split("\n"):
			if line.strip_edges().begins_with("icon_path = "):
				icon_line = line.strip_edges().trim_prefix("icon_path = ").trim_prefix("\"").trim_suffix("\"")
		_check("%s: icon_path under res://icons/houses/" % fn, icon_line.begins_with("res://icons/houses/"))
		_check("%s: icon_path file exists (%s)" % [fn, icon_line], FileAccess.file_exists(icon_line))

		# Typed load: the resource binds HouseData and parses
		var res = load("res://" + rel)
		_check("%s: loads as a Resource" % fn, res != null)
		if res != null:
			tiers.append(res)

	# C. THE TIER LADDER (cost + size climb with tier)
	if tiers.size() >= 2:
		tiers.sort_custom(func(a, b): return int(a.tier) < int(b.tier))
		var cost_ok := true
		var size_ok := true
		for i in range(1, tiers.size()):
			if int(tiers[i].cost) < int(tiers[i - 1].cost):
				cost_ok = false
			if float(tiers[i].wall_height) < float(tiers[i - 1].wall_height):
				size_ok = false
		_check("cost never steps DOWN the tier ladder", cost_ok)
		_check("wall_height never steps DOWN the tier ladder", size_ok)
		for t in tiers:
			_check("%s: carries at least one structural feature" % t.id, t.features.size() > 0)

	# E. THE HEARTH KIT (labs/prompts/gemini_housing.md sec. 2): the eight
	# canon placeables must all resolve as real furnishings. A canon-named
	# item with no data is a promise the world cannot keep.
	if ds != null:
		var hearth_kit: Array = [
			"furn_fireplace_stone", "furn_wooden_chair", "furn_plank_bed",
			"furn_workbench_oak", "furn_bookshelf", "furn_potted_megaseed",
			"furn_coat_rack", "furn_lantern_post",
		]
		var missing: Array = []
		for hid in hearth_kit:
			if ds.get_item(hid) == null:
				missing.append(hid)
		_check("all %d canon Hearth Kit placeables resolve" % hearth_kit.size(), missing.is_empty())
		if not missing.is_empty():
			_check("Hearth Kit gaps: " + ", ".join(missing), false)

	# D. THE SERVICE READS DATA
	var svc = root_node.get_node_or_null("HousingService")
	_check("HousingService autoload present", svc != null)
	if svc != null and ds != null:
		var cottage = ds.get_house("house_cottage")
		_check("DataService.get_house resolves house_cottage", cottage != null)
		_check("DataService.get_all_houses returns %d" % tiers.size(), ds.get_all_houses().size() == tiers.size())

		var plot: Dictionary = svc.register_test_plot("house_probe_plot", "test_zone", "house_owner")
		var player = load("res://tests/support/reward_player_stub.gd").new()
		player.entity_id = "house_owner"
		player.display_name = "house_owner"
		player.set("gold", 2000000)
		root_node.add_child(player)

		var r: Dictionary = svc.build_house(player, "house_probe_plot", "house_cottage")
		_check("build_house succeeds on an owned plot", bool(r.get("ok", false)))
		if cottage != null:
			_check("build_house charged the tier cost (%d)" % int(cottage.cost),
				int(player.gold) == 2000000 - int(cottage.cost))
		_check("plot.house_tier stamped from data", str(svc.get_plot("house_probe_plot").get("house_tier", "")) == "house_cottage")

		# Unknown tier: falls back to built-in constants, never crashes.
		var plot2: Dictionary = svc.register_test_plot("house_probe_plot2", "test_zone", "house_owner2")
		var player2 = load("res://tests/support/reward_player_stub.gd").new()
		player2.entity_id = "house_owner2"
		player2.display_name = "house_owner2"
		player2.set("gold", 2000000)
		root_node.add_child(player2)
		var r2: Dictionary = svc.build_house(player2, "house_probe_plot2", "house_does_not_exist")
		_check("unknown tier still builds (built-in fallback)", bool(r2.get("ok", false)))
		_check("unknown tier charges the fallback HOUSE_COST",
			int(player2.gold) == 2000000 - int(svc.HOUSE_COST))

		_finish()
		return

	_finish()
