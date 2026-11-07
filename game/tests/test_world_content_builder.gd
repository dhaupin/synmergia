## test_world_content_builder - PLANAR-RETIREMENT STEP 4 (the declared
## content law).
##
## The two-worlds drift happened because each scene hand-wrote its own
## `_setup_*` list. WorldContentBuilder flips that: a world DECLARES an
## ordered manifest and registers one builder per family; the builder
## runs the manifest in order and reports any declared family left
## without a builder LOUD. This receipt proves:
##   1. the builder runs families in DECLARED order (not registration
##      order),
##   2. a declared family with no builder is reported in
##      missing_builders() and fails build_all(),
##   3. a builder returning false is reported as failed,
##   4. re-registering a family REPLACES it (the swap law),
##   5. the GLOBE declares its manifest and every declared family is
##      backed by a builder (the "globe is missing X" gate, live).
##
## Run: godot --headless --path game --script res://tests/test_world_content_builder.gd
extends SceneTree

const BUILDER_PATH := "res://core/world/world_content_builder.gd"
const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING: String = "synmergia/world/planet_radius"

var _passed := 0
var _failed := 0


func _ok(msg: String) -> void:
	_passed += 1
	print("   PASS  %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	print("   FAIL  %s" % msg)


func _check(cond: bool, msg: String) -> bool:
	if cond:
		_ok(msg)
	else:
		_fail(msg)
	return cond


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- WORLD CONTENT BUILDER RECEIPT ---")
	await process_frame
	_leg_order()
	_leg_gap_gate()
	_leg_refusal()
	_leg_swap_law()
	await _leg_globe_manifest()
	print("=== WORLD CONTENT BUILDER RECEIPT: %d checks, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		print("WORLD CONTENT BUILDER RECEIPT PASSED")
		quit(0)
	else:
		print("WORLD CONTENT BUILDER RECEIPT FAILED")
		quit(1)


## The builder runs families in the DECLARED order, regardless of the
## order the builders were registered.
func _leg_order() -> void:
	var b = load(BUILDER_PATH).new()
	b.declare(["third", "first", "second"])
	var ran: Array = []
	b.add_family("first", func() -> void: ran.append("first"))
	b.add_family("second", func() -> void: ran.append("second"))
	b.add_family("third", func() -> void: ran.append("third"))
	var complete: bool = b.build_all()
	_check(complete, "build_all reports complete when every family has a builder")
	_check(str(ran) == str(["third", "first", "second"]), "families run in DECLARED order (%s)" % str(ran))
	_check(b.built_families().size() == 3, "three families recorded as built")


## A declared family with no builder is the "missing X" gap -- reported
## by missing_builders() and failing build_all().
func _leg_gap_gate() -> void:
	var b = load(BUILDER_PATH).new()
	b.declare(["present", "absent"])
	b.add_family("present", func() -> void: pass)
	var complete: bool = b.build_all()
	_check(not complete, "build_all fails when a declared family has no builder")
	_check(b.missing_builders() == ["absent"], "the gap is named in missing_builders (%s)" % str(b.missing_builders()))


## A builder that refuses (returns false) is reported as failed, not
## mistaken for a built family.
func _leg_refusal() -> void:
	var b = load(BUILDER_PATH).new()
	b.declare(["refuser"])
	b.add_family("refuser", func() -> bool: return false)
	var complete: bool = b.build_all()
	_check(not complete, "build_all fails when a builder refuses (returns false)")
	_check(b.failed_families() == ["refuser"], "the refusal is named in failed_families (%s)" % str(b.failed_families()))
	_check(b.built_families().is_empty(), "a refused family is NOT counted as built")


## Re-registering a family replaces its builder (the swap law).
func _leg_swap_law() -> void:
	var b = load(BUILDER_PATH).new()
	b.declare(["fam"])
	var which: Array = []
	b.add_family("fam", func() -> void: which.append("old"))
	b.add_family("fam", func() -> void: which.append("new"))
	b.build_all()
	_check(which == ["new"], "re-registering a family replaces the builder (%s)" % str(which))


## The live gate: the globe declares a manifest and EVERY declared
## family is backed by a builder (the drift can never ship silently).
func _leg_globe_manifest() -> void:
	ProjectSettings.set_setting(RADIUS_SETTING, 100.0)
	var packed: PackedScene = load(GLOBE_SCENE)
	if not _check(packed != null and packed.can_instantiate(), "globe scene loads"):
		return
	var globe = packed.instantiate()
	root.add_child(globe)
	var deadline: int = Time.get_ticks_msec() + 60000
	while not globe.has_meta("boot_waves_done_ms") and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(globe.has_meta("boot_waves_done_ms"), "the boot waves finish through the builder")
	# Drain the terrain streamer before teardown (freeing mid-stream is
	# the same teardown crash the gates receipt guards against).
	var streamer = globe.get("streamer")
	var drain_deadline: int = Time.get_ticks_msec() + 60000
	while streamer != null and streamer._mesh_pending() > 0 and Time.get_ticks_msec() < drain_deadline:
		await process_frame
	var declared: Array = globe.CONTENT_MANIFEST
	_check(declared.size() > 0, "the globe declares a content manifest (%d families)" % declared.size())
	var b = globe.get("content_builder")
	if not _check(b != null, "the globe built its content through a WorldContentBuilder"):
		globe.queue_free()
		return
	_check(b.missing_builders().is_empty(), "every declared family is backed by a builder (no gap)")
	_check(b.built_families().size() == declared.size(), "every declared family ran (%d/%d)" % [b.built_families().size(), declared.size()])
	globe.queue_free()
	await process_frame
