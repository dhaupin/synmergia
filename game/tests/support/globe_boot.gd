## Shared globe-boot helper for live tests/probes (planar-retirement Step 5).
##
## The planar world_playable scene is retired; every live test boots the
## GLOBE (the open world) instead. This wraps the boot contract the globe
## receipts already use so the ports stay uniform:
##
##   var boot = load("res://tests/support/globe_boot.gd")
##   var globe = await boot.boot(self)          # self is the SceneTree
##   var player = boot.player(globe)
##   var world_root = boot.world_root(globe)
##   ...
##   await boot.teardown(globe)
##
## No class_name: tests load() it at runtime (script mode has no autoloads,
## and a parse-time class reference would fail the same way game scripts do).
extends RefCounted

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING: String = "synmergia/world/planet_radius"
const BOOT_TIMEOUT_MS := 90000

## Instantiate the globe under `tree.root` and wait for the boot waves +
## the async mesh lane to settle. Returns the scene node (or null).
static func boot(tree: SceneTree, radius: float = 100.0) -> Node:
	ProjectSettings.set_setting(RADIUS_SETTING, radius)
	var packed: PackedScene = load(GLOBE_SCENE)
	if packed == null or not packed.can_instantiate():
		push_error("globe_boot: %s failed to load" % GLOBE_SCENE)
		return null
	var globe := packed.instantiate()
	tree.root.add_child(globe)
	var deadline: int = Time.get_ticks_msec() + BOOT_TIMEOUT_MS
	while not globe.has_meta("boot_waves_done_ms") and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	await drain(globe, tree)
	return globe


## Wait for the async terrain mesh lane to finish before touching the world.
static func drain(globe: Node, tree: SceneTree) -> void:
	if globe == null or not is_instance_valid(globe):
		return
	var clipmap = globe.get("clipmap")
	var deadline: int = Time.get_ticks_msec() + BOOT_TIMEOUT_MS
	while clipmap != null and clipmap.has_method("mesh_pending") \
			and clipmap.mesh_pending() > 0 and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	await tree.process_frame


## The local player body (the globe anchors it on the scene node).
static func player(globe: Node) -> Node:
	if globe == null or not is_instance_valid(globe):
		return null
	return globe.get("player")


## The world_root the content builder parents placed props under.
static func world_root(globe: Node) -> Node:
	if globe == null or not is_instance_valid(globe):
		return null
	return globe.get("world_root")


## Drain the mesh lane, then free the scene cleanly.
static func teardown(globe: Node, tree: SceneTree) -> void:
	if globe == null or not is_instance_valid(globe):
		return
	await drain(globe, tree)
	globe.free()
