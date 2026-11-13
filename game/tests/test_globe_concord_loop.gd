## test_globe_concord_loop - THE CONCORD LOOP LIVES ON THE GLOBE.
##
## planar-retirement Step 1 (the flagship port). Before this, only the
## planar world_playable created the Ancient Door + Concord Stone, so
## `ActsService` (which scans the "ancient_doors" group) never saw a door
## on the planet the player actually plays -- the whole
## watch-the-sky -> solve-the-day -> the-door-opens-at-dawn loop was dead.
## This receipt proves the loop is live on the globe:
##   1. LAW: VillageProps.build_concord places the Ancient Door + the
##      Concord Stone in METER reach of the spawn plaza, each in its group.
##   2. SCENE: a real globe boot builds the door + stone under world_root,
##      the SkySigns renderer is mounted, and the local body carries the
##      interact resolution.
##   3. FLAGSHIP: ActsService sees the globe door and a door_opened records
##      a chapter; the Concord Stone records a window insight through
##      SignService.
##
## Run: godot --headless --path game --script res://tests/test_globe_concord_loop.gd
extends SceneTree

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
	print("--- GLOBE CONCORD LOOP RECEIPT ---")
	await process_frame

	await _leg_law_build_concord()
	await _leg_globe_scene()
	await _leg_flagship()

	print("=== GLOBE CONCORD LOOP RECEIPT: %d checks, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		print("GLOBE CONCORD LOOP RECEIPT PASSED")
		quit(0)
	else:
		print("GLOBE CONCORD LOOP RECEIPT FAILED")
		quit(1)


## LEG 1 (LAW): VillageProps.build_concord places the two props near the
## spawn plaza and each joins its own group on _ready.
func _leg_law_build_concord() -> void:
	var VP: GDScript = load("res://entities/village_props.gd")
	var root_node := Node3D.new()
	root.add_child(root_node)
	var no_walk := func(_dir: Vector3) -> float: return 0.0
	VP.build_concord(root_node, 100.0, 0.52, no_walk)
	await process_frame
	var door := root_node.get_node_or_null("AncientDoor")
	var stone := root_node.get_node_or_null("ConcordStone")
	_check(door != null, "build_concord places the Ancient Door")
	_check(stone != null, "build_concord places the Concord Stone")
	if door != null:
		_check(door.is_in_group("ancient_doors"), "the globe Ancient Door joins 'ancient_doors'")
		_check(str(door.get("display_name")) == "The First Ancient", "the door carries the authored display name")
		# Meter reach: the door sits ~7 m of arc from spawn, not 240 m.
		var TGen = load("res://scenes/worlds/terrain_gen.gd")
		var spawn: Vector3 = TGen.SPAWN_CENTER
		var d: float = spawn.angle_to(door.position.normalized()) * 100.0
		_check(d < 15.0, "the door is a short walk from spawn (%.1f m arc)" % d)
	if stone != null:
		_check(stone.is_in_group("concord_stones"), "the globe Concord Stone joins 'concord_stones'")
		_check(str(stone.get("display_name")) == "The Haven Stone", "the stone carries the authored display name")
	root_node.queue_free()


## LEG 2 (SCENE): a real globe boot builds the Concord loop under
## world_root, mounts the sky signs, and gives the local body the interact
## resolution.
func _leg_globe_scene() -> void:
	ProjectSettings.set_setting(RADIUS_SETTING, 100.0)
	var packed: PackedScene = load(GLOBE_SCENE)
	if not _check(packed != null and packed.can_instantiate(), "globe scene loads"):
		return
	var globe = packed.instantiate()
	root.add_child(globe)
	# Wait for the boot waves (the Concord loop is one of them).
	var deadline: int = Time.get_ticks_msec() + 60000
	while not globe.has_meta("boot_waves_done_ms") and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(globe.has_meta("boot_waves_done_ms"), "the boot waves finish (the world dresses)")
	# Drain the async mesh lane before reads + quit (the probe law).
	var clipmap = globe.get("clipmap")
	var drain_deadline: int = Time.get_ticks_msec() + 60000
	while clipmap != null and clipmap._mesh_pending() > 0 and Time.get_ticks_msec() < drain_deadline:
		await process_frame
	await process_frame

	var world_root: Node = globe.get("world_root")
	var door: Node3D = world_root.get_node_or_null("AncientDoor")
	var stone: Node3D = world_root.get_node_or_null("ConcordStone")
	_check(door != null, "the globe builds the Ancient Door into the world")
	_check(stone != null, "the globe builds the Concord Stone into the world")
	if door != null:
		_check(door.is_in_group("ancient_doors"), "the globe door is in the 'ancient_doors' group")
	if stone != null:
		_check(stone.is_in_group("concord_stones"), "the globe stone is in the 'concord_stones' group")

	# The SkySigns renderer rides the globe (adopted by the player).
	var player = globe.get("player")
	var sky_signs: Node = null
	if player != null:
		sky_signs = player.get_node_or_null("SkySigns")
	_check(sky_signs != null, "the SkySigns constellation renderer is mounted on the globe")
	if sky_signs != null:
		_check(sky_signs.is_in_group("sky_signs"), "the sky renderer is in the 'sky_signs' group")

	# The local body carries the interact resolution (the planar parity).
	if player != null:
		_check(player.has_method("_try_interact"), "the globe body has the interact dispatch")
		_check(player.has_method("_activate_nearby_ancient_door"), "the globe body resolves the Ancient Door")
		_check(player.has_method("_activate_nearby_concord_stone"), "the globe body resolves the Concord Stone")


## LEG 3 (FLAGSHIP): ActsService sees the globe door; a door_opened
## records a chapter. The Concord Stone records a window insight.
func _leg_flagship() -> void:
	var acts = root.get_node_or_null("ActsService")
	var signs = root.get_node_or_null("SignService")
	if not _check(acts != null and signs != null, "ActsService + SignService are mounted"):
		return
	var globe = _find_globe()
	if globe == null:
		_fail("globe not found for the flagship leg")
		return
	var world_root: Node = globe.get("world_root")
	var door: Node3D = world_root.get_node_or_null("AncientDoor")
	if door == null:
		_fail("no globe door for the flagship leg")
		return

	# ActsService scans the "ancient_doors" group on a timer; run a scan now
	# (idempotent) so the assertion is deterministic.
	acts._scan_doors()
	_check(door.door_opened.is_connected(acts._on_door_opened),
		"ActsService wired the globe door's door_opened")

	# A door open records a chapter. Clear the ledger, unlock the day the
	# door tracks, then open it through its REAL interact path.
	acts._recorded.clear()
	acts._next_fill.clear()
	acts._rebuild_next_fill()
	var day: int = door._resolve_day()
	if day >= 0:
		signs._unlocked_days[day] = true
	var stub := {"entity_id": "concord_receipt_pilot"}
	var result: Dictionary = door.try_interact(stub)
	_check(bool(result.get("ok", false)), "the globe door opens on E (msg: %s)" % str(result.get("message", "")))
	await process_frame
	_check(not acts._recorded.is_empty(),
		"a door_opened on the globe records a Chronicle chapter")

	# The Concord Stone records a window insight through SignService.
	var stone: Node3D = world_root.get_node_or_null("ConcordStone")
	if stone == null:
		_fail("no globe stone for the insight leg")
		return
	var sresult: Dictionary = stone.try_interact(stub)
	_check(bool(sresult.get("ok", false)),
		"the globe Concord Stone records an insight on E (msg: %s)" % str(sresult.get("message", "")))

	# Cleanup: free the globe so the run exits clean.
	globe.queue_free()
	await process_frame


func _find_globe() -> Node:
	for c in root.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("globe_world.gd"):
			return c
	return null
