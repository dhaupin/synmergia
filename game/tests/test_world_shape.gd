## Tests for the world shape resolver (S2 knob; the full menu->world
## flow now branches on it, so the default and the spherical flip are
## both load-bearing). Loads by path (GuardData lesson).
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
	quit(0 if ok else 1)


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
