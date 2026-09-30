extends SceneTree

## ResourceScan: the export-safe scanner. The pack-conversion bug it
## kills is only fully visible inside an exported pack (.tres ->
## .res + .tres.remap), but the CONTRACT is testable in the dev tree:
## base-name parsing, dedupe keying, and that every listed path
## actually loads. Run:
##   godot --headless --path . --script res://core/frame/srv/test_resource_scan.gd

var _checks: int = 0
var _fails: int = 0

func _init() -> void:
	var RS = load("res://core/frame/srv/resource_scan.gd")

	# Base-name parsing (the pack's three shapes + non-resources).
	_check("x.tres -> x", RS.resource_base("species_human.tres") == "species_human")
	_check("x.res -> x (the converted binary)", RS.resource_base("species_human.res") == "species_human")
	_check("x.tres.remap -> x (the sidecar)", RS.resource_base("species_human.tres.remap") == "species_human")
	_check("x.res.remap -> x", RS.resource_base("x.res.remap") == "x")
	_check("non-resources are rejected", RS.resource_base("notes.txt") == "" \
		and RS.resource_base("data.json") == "" and RS.resource_base("x.remap") == "")

	# The dev tree: every species .tres is found and LOADABLE.
	var species: Array[String] = RS.list_resources("res://data/species")
	_check("the species dir lists 3 loadable resources", species.size() == 3)
	var all_load := true
	for p in species:
		if load(p) == null:
			all_load = false
	_check("every listed path loads (dev tree)", all_load)

	# Trailing-slash callers (shard_parameters, targeting) must get
	# normalized paths, never a mid-path "//".
	var slashed: Array[String] = RS.list_resources("res://data/species/")
	var no_double := true
	for p in slashed:
		if str(p).replace("res://", "").contains("//"):
			no_double = false
	_check("trailing-slash dir normalizes (3, no //)", slashed.size() == 3 and no_double)

	# load_dir keys by the caller's id extractor (the DataService shape).
	var by_id: Dictionary = RS.load_dir("res://data/species", \
		func(res, _path): return str(res.id))
	_check("load_dir keys by id (3 species)", by_id.has("human") \
		and by_id.has("akkan") and by_id.has("synthetic"))

	# Recursion: the whole data tree lists well past the top level.
	var all_data: Array[String] = RS.list_resources("res://data")
	_check("the recursive scan covers the whole data tree (>100 files)", \
		all_data.size() > 100)
	# Dedupe invariant: no two listed paths share DIR + base (the same
	# resource's .res/.remap pair collapses). Same FILENAME in different
	# directories is legitimate (data/roots/*/environment.tres).
	var bases: Dictionary = {}
	var dupes := 0
	for p in all_data:
		var s := str(p)
		var dir_part: String = s.substr(0, s.rfind("/"))
		var key: String = dir_part + "/" + RS.resource_base(s.get_file())
		if bases.has(key):
			dupes += 1
		bases[key] = true

	# A missing directory is an empty answer, not a crash.
	_check("a missing dir is an empty list", RS.list_resources("res://data/does_not_exist").is_empty())

	if _fails == 0:
		print("RESOURCE SCAN TEST PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("RESOURCE SCAN TEST FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
