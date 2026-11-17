extends SceneTree

# test_parse_check - THE WHOLE-TREE STRUCTURAL PARSE GUARD.
#
# Run: godot --headless --path game --script res://tests/test_parse_check.gd
#
# WHY THIS EXISTS (the PR #117 lesson): a subclass that redeclares a member
# its parent already declares -- GlobeWorldPlayer.var _inventory_bag vs
# PlayerBase.func _inventory_bag -- is a HARD parse error. The world scene
# then cannot load at all, so the browser build never reaches the world. The
# trap: load() still returns a NON-NULL script for a file that failed to
# parse, so a spot check of "!= null" passes and the break sails through CI.
#
# THE HONEST SIGNAL: Script.reload() re-parses the SOURCE without
# instantiating. It returns OK (0) for a clean file, ERR_PARSE_ERROR (43) for
# a structural defect (duplicate member, syntax error, bad type), and a
# DIFFERENT non-OK code for a file that merely names an autoload -- in
# --script mode autoloads are absent, so ~133 clean files return 36, not 43.
# The discriminator is therefore the specific code 43, NOT "any non-OK".
# (Script.can_instantiate() is unusable: every autoload-referencing file
# reports false in script mode, so it cannot separate the two cases.)
#
# This walks every .gd under res:// and fails on any file whose reload() is
# ERR_PARSE_ERROR, except the documented baseline below.

const BASELINE := [
	# Pre-existing dead legacy: a Godot-3-style file with several top-level
	# `class_name` declarations plus a self-preload. ZERO live references
	# (verified: no preload/load/extends/new names it). Needs a real refactor
	# or removal, tracked in labs/prd-verification-gates.md -- not papered
	# over here; a NEW structural break still fails this guard.
	"res://core/combat/healing.gd",
]

const SKIP_DIRS := ["res://.godot"]

var _ok := 0
var _fail := 0
var _baselined := 0
var _failed_paths: Array = []

func _init() -> void:
	print("--- STRUCTURAL PARSE GUARD (every .gd under res://) ---")
	_walk("res://")
	print("--- RESULTS: %d compiled, %d baselined, %d BROKEN ---" % [_ok, _baselined, _fail])
	if _fail > 0:
		for p in _failed_paths:
			print("  [BROKEN] %s" % p)
	quit(0 if _fail == 0 else 1)

func _skip(path: String) -> bool:
	for d in SKIP_DIRS:
		if path.begins_with(d):
			return true
	return false

func _walk(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path + name if dir_path == "res://" else dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with(".") and not _skip(full):
				_walk(full)
		elif name.ends_with(".gd"):
			_check(full)
		name = dir.get_next()
	dir.list_dir_end()

func _check(path: String) -> void:
	var script = load(path)
	if script == null:
		print("  [FAIL] %s : load() returned null" % path)
		_fail += 1
		_failed_paths.append(path)
		return
	var err: int = script.reload()
	# 43 = ERR_PARSE_ERROR = a real structural defect. Other non-OK codes
	# (e.g. 36 = a missing identifier, which in --script mode is just an
	# autoload that isn't mounted) are expected and must NOT fail.
	if err == ERR_PARSE_ERROR:
		if path in BASELINE:
			_baselined += 1
			return
		print("  [FAIL] %s : reload() = %d (ERR_PARSE_ERROR)" % [path, err])
		_fail += 1
		_failed_paths.append(path)
		return
	_ok += 1
