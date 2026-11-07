## Tests for the world shape resolver (S2 knob). PLANAR-RETIREMENT STEP 5:
## GameManager no longer branches on the shape -- the open world is the
## globe, always -- so the resolver is now the SHAPE PARAMETER the instance
## contract reads (arena/duel/dungeon stay planar). The resolver behavior
## (default, flip, casing, garbage fallback) is still load-bearing and
## pinned here; the project default stays spherical. Loads by path
## (GuardData lesson).
extends SceneTree

const SETTINGS_KEY: String = "synmergia/world/shape"


func _init() -> void:
	var ok := true
	if not _test_project_default_spherical():
		push_error("FAIL: project_default_spherical")
		ok = false
	if not _test_default_planar():
		push_error("FAIL: default_planar")
		ok = false
	if not _test_spherical_flip():
		push_error("FAIL: spherical_flip")
		ok = false
	if not _test_garbage_falls_back():
		push_error("FAIL: garbage_falls_back")
		ok = false
	if not _test_no_game_manager_branch():
		push_error("FAIL: no_game_manager_branch")
		ok = false
	quit(0 if ok else 1)


## STEP 5: the world branch is gone -- GameManager must always load the
## globe scene and must no longer read world_playable.tscn.
func _test_no_game_manager_branch() -> bool:
	var src := FileAccess.get_file_as_string("res://core/autoload/game_manager.gd")
	assert(not src.contains("world_playable.tscn"), "GameManager still references world_playable.tscn")
	assert(src.contains("res://scenes/worlds/globe_world.tscn"), "GameManager no longer loads the globe")
	return true


func _resolver() -> GDScript:
	return load("res://core/frame/math/world_shape.gd")


## The shipped project default is SPHERICAL (the globe is live).
## This test documents it: flipping the project setting back to
## planar must be a conscious decision that updates this test.
func _test_project_default_spherical() -> bool:
	# Must run before any set_setting call clobbers the loaded value.
	var raw: String = str(ProjectSettings.get_setting(SETTINGS_KEY, "planar"))
	assert(raw == "spherical")
	return true


func _test_default_planar() -> bool:
	ProjectSettings.set_setting(SETTINGS_KEY, "")
	var W = _resolver()
	assert(not W.is_spherical())
	return true


func _test_spherical_flip() -> bool:
	ProjectSettings.set_setting(SETTINGS_KEY, "spherical")
	var W = _resolver()
	assert(W.is_spherical())
	return true


func _test_garbage_falls_back() -> bool:
	ProjectSettings.set_setting(SETTINGS_KEY, "banana")
	var W = _resolver()
	assert(not W.is_spherical())
	# Spherical in any casing still counts.
	ProjectSettings.set_setting(SETTINGS_KEY, "SPHERICAL")
	assert(W.is_spherical())
	ProjectSettings.set_setting(SETTINGS_KEY, "")
	return true
