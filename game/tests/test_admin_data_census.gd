## Receipt: the admin data census -- the dormant DataService catalog
## accessors reach a real surface.
##
## `get_counts()`, `get_all_currencies()`, `get_all_dwellings()`,
## `get_all_recipes()` and `get_layer_profiles()` were declared but had
## ZERO callers: the loaded catalog could not be inspected at runtime,
## and the four catalogs a gameplay path reaches only BY ID (a currency,
## a dwelling, a recipe, a layer profile) had no enumerable door.
##
## The AdminShell `data` command is that door. This receipt drives the
## REAL shell: every leg resolves through the live DataService, and the
## census total must equal the sum of its own rows (a census that
## disagrees with itself is a lie). An unknown subcommand is refused
## honestly rather than printing an empty table.
##
## Run: godot --headless --path game --script res://tests/test_admin_data_census.gd
extends SceneTree

var _passed: int = 0
var _failed: int = 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("   PASS  %s" % msg)
	else:
		_failed += 1
		print("   FAIL  %s" % msg)


func _finish() -> void:
	print("=== ADMIN DATA CENSUS RECEIPT: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ds = root.get_node_or_null("DataService")
	if ds != null and not ds._loaded and ds.has_method("load_all_data"):
		ds.load_all_data()
	await process_frame

	# --- the shell compiles and carries the new command ---------------
	var ShellScript: GDScript = load("res://core/admin/admin_shell.gd")
	_check(ShellScript != null, "admin_shell.gd loads (no parse errors)")
	if ShellScript == null:
		_finish()
		return
	var shell = ShellScript.new()
	root.add_child(shell)
	await process_frame

	# --- `data` (counts): every row, and the total is honest ----------
	var counts_res = shell.execute("data", "")
	_check(counts_res != null and counts_res.success, "`data` runs and succeeds")
	var out: String = counts_res.output if counts_res != null else ""
	_check(out.contains("Data Census"), "the census header renders")
	_check(out.contains("currencies"), "the census lists currencies")
	_check(out.contains("skills"), "the census lists skills")

	# Recompute the total the way the command does and require a match:
	# a census whose total disagrees with its own rows is a lie.
	var counts: Dictionary = ds.get_counts()
	var recomputed: int = 0
	for k in counts.keys():
		recomputed += int(counts[k])
	_check(recomputed > 0, "the live catalog is non-empty (%d resources)" % recomputed)
	_check(out.contains(str(recomputed)),
		"the printed total equals the recomputed sum (%d)" % recomputed)

	# --- the four formerly-dormant catalogs enumerate -----------------
	for leg in [["currencies", "get_all_currencies", "currency_gold"],
			["dwellings", "get_all_dwellings", ""],
			["recipes", "get_all_recipes", "recipe_iron_ingot"],
			["layers", "get_layer_profiles", "physics_layers_main"]]:
		var sub: String = leg[0]
		var getter: String = leg[1]
		var probe_id: String = leg[2]
		var res = shell.execute("data " + sub, "")
		_check(res != null and res.success, "`data %s` runs and succeeds" % sub)
		var rows = ds.call(getter)
		var n: int = rows.size() if rows is Array else (rows as Dictionary).size()
		_check(res != null and res.output.contains(str(n)),
			"`data %s` reports the live count (%d)" % [sub, n])
		if probe_id != "":
			_check(res != null and res.output.contains(probe_id),
				"`data %s` lists the real id '%s'" % [sub, probe_id])

	# --- an unknown subcommand is refused honestly --------------------
	var bad = shell.execute("data nonsense_sub", "")
	_check(bad != null and not bad.success, "an unknown subcommand is refused (no empty table)")

	shell.queue_free()
	_finish()
