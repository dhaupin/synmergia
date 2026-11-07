## test_globe_gates_guards - PLANAR-RETIREMENT STEP 3 LIVES ON THE GLOBE.
##
## world_playable was the only scene that wired the transit gates, the
## town watch, the dungeon portal, and the housing plot; the planet the
## player actually boots (globe_world) had NONE of them. This receipt
## proves the port, system by system:
##   1. GATES: the Moon Gate + the Ascent stand under world_root, joined
##      to "moon_gates", each named with a real target world and reading
##      the dev-hatch law (state 2).
##   2. GUARDS: the town watch is created from GuardData, carries a live
##      GuardAI brain, registers with EntityService, and is posted (a
##      REAL non-zero post -- the return-to-post law needs it).
##   3. PORTAL: the dungeon gateway is registered with WorldService and
##      targetable as TELEPORT (the walk-up Enter path resolves it).
##   4. HOUSING: the demo plot is registered with DwellingService.
##   5. INTERACT: the globe body's E dispatch binds the village ankh
##      through the real bind_player path (and resolves a nearby gate).
##
## The S16 transit itself (conjure + scope swap) is probe_multiworld's
## scope; this receipt stops at "the gate is real and reachable".
##
## Run: godot --headless --path game --script res://tests/test_globe_gates_guards.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING: String = "synmergia/world/planet_radius"
const TELEPORT_TYPE: int = 32  # Entity.EntityType.TELEPORT

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
	print("--- GLOBE GATES/GUARDS/PORTAL/HOUSING RECEIPT ---")
	await process_frame

	await _leg_boot()
	await _leg_gates()
	await _leg_guards()
	await _leg_portal()
	await _leg_housing()
	await _leg_interact()

	print("=== GLOBE GATES RECEIPT: %d checks, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		print("GLOBE GATES RECEIPT PASSED")
		quit(0)
	else:
		print("GLOBE GATES RECEIPT FAILED")
		quit(1)


## Boot the globe and drain the boot waves (the world dresses).
func _leg_boot() -> void:
	ProjectSettings.set_setting(RADIUS_SETTING, 100.0)
	var packed: PackedScene = load(GLOBE_SCENE)
	if not _check(packed != null and packed.can_instantiate(), "globe scene loads"):
		return
	var globe = packed.instantiate()
	root.add_child(globe)
	var deadline: int = Time.get_ticks_msec() + 60000
	while not globe.has_meta("boot_waves_done_ms") and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(globe.has_meta("boot_waves_done_ms"), "the boot waves finish (the world dresses)")
	var streamer = globe.get("streamer")
	var drain_deadline: int = Time.get_ticks_msec() + 60000
	while streamer != null and streamer._mesh_pending() > 0 and Time.get_ticks_msec() < drain_deadline:
		await process_frame
	await process_frame


## LEG 1: the transit gates stand and read the dev-hatch law.
func _leg_gates() -> void:
	var globe := _find_globe()
	if globe == null:
		_fail("no globe for the gate leg")
		return
	var gates := get_nodes_in_group("moon_gates")
	var by_name := {}
	for g in gates:
		by_name[str(g.name)] = g
	_check(by_name.has("MoonGate"), "the Moon Gate stands on the globe")
	_check(by_name.has("AscentGate"), "the Ascent stands on the globe")
	if by_name.has("MoonGate"):
		var mg = by_name["MoonGate"]
		_check(str(mg.get("target_world")) == "moon", "the Moon Gate names the pale stone")
		_check(int(mg._law_state()) == 2, "the Moon Gate reads the dev-hatch law (state 2)")
		_check(str(mg.get_interaction_prompt()).begins_with("[E]"), "the Moon Gate speaks a prompt")
	if by_name.has("AscentGate"):
		var ag = by_name["AscentGate"]
		_check(str(ag.get("target_world")) == "underworld", "the Ascent names the Deep Root")
		_check(int(ag._law_state()) == 2, "the Ascent reads the dev-hatch law (state 2)")


## LEG 2: the town watch is live, registered, brained, and posted.
func _leg_guards() -> void:
	var globe := _find_globe()
	if globe == null:
		_fail("no globe for the guard leg")
		return
	var es = root.get_node_or_null("EntityService")
	var tm = root.get_node_or_null("TargetingManager")
	var world_root: Node = globe.get("world_root")
	var guards: Array = []
	for child in world_root.get_children():
		if child.get("guard_data") != null:
			guards.append(child)
	_check(guards.size() == 4, "the town watch stands on the globe (%d guards)" % guards.size())
	var with_ai := 0
	var registered := 0
	var posted := 0
	for g in guards:
		if g.get("_guard_ai") != null:
			with_ai += 1
		var gid: String = str(g.entity_id)
		if es != null and gid != "" and es.get_entity(gid) != null:
			registered += 1
		var data = g.get("guard_data")
		if data != null and "post_position" in data \
				and (data.post_position as Vector3).length() > 0.5:
			posted += 1
	_check(with_ai == 4, "each guard carries a live GuardAI brain (%d)" % with_ai)
	_check(registered == 4, "each guard is registered with EntityService (%d)" % registered)
	_check(posted == 4, "each guard is posted at a REAL post (the return-to-post law) (%d)" % posted)
	if tm != null and not guards.is_empty():
		var gid: String = str(guards[0].entity_id)
		_check(not tm.get_targetable(gid).is_empty(), "the guard is registered as targetable")


## LEG 3: the dungeon portal is registered + targetable as TELEPORT.
func _leg_portal() -> void:
	var ws = root.get_node_or_null("WorldService")
	var tm = root.get_node_or_null("TargetingManager")
	if ws == null:
		_fail("no WorldService for the portal leg")
		return
	var found = null
	for gw in ws.get_zone_gateways("zone_village_center"):
		if str(gw.to_zone_id) == "zone_dungeon_forest_depths":
			found = gw
			break
	if not _check(found != null, "the dungeon gateway is registered with WorldService"):
		return
	if tm != null:
		var t = tm.get_targetable(str(found.id))
		_check(not t.is_empty(), "the portal is registered as targetable")
		if not t.is_empty():
			_check(int(t.get("entity_type", 0)) == TELEPORT_TYPE, "the portal targets as TELEPORT")


## LEG 4: the demo housing plot is registered.
func _leg_housing() -> void:
	var dw = root.get_node_or_null("DwellingService")
	if dw == null:
		_fail("no DwellingService for the housing leg")
		return
	var plot: Dictionary = dw.get_plot("plot_haven_1") if dw.has_method("get_plot") else {}
	if not _check(not plot.is_empty(), "the demo plot is registered with DwellingService"):
		return
	_check(str(plot.get("zone_id", "")) == "zone_village_center", "the plot rides the village zone")
	_check(int(plot.get("price", 0)) > 0, "the plot carries a purchase price")


## LEG 5: the globe body's E dispatch binds the village ankh + resolves a
## nearby gate. (The gate's transit itself is probe_multiworld's scope.)
func _leg_interact() -> void:
	var globe := _find_globe()
	if globe == null:
		_fail("no globe for the interact leg")
		return
	var player = globe.get("player")
	if not _check(player != null, "the globe has a local player body"):
		return
	_check(player.has_method("_try_interact"), "the globe body has the interact dispatch")
	_check(player.has_method("_activate_nearby_ankh"), "the ankh leg is wired")
	_check(player.has_method("_activate_nearby_moon_gate"), "the moon-gate leg is wired")
	# The village ankh: stand on it and press E through the real dispatch.
	var ankh = null
	for n in get_nodes_in_group("ankhs"):
		if str(n.name) == "VillageAnkh":
			ankh = n
			break
	if ankh == null:
		_fail("the VillageAnkh stands in the world")
		return
	player.global_position = (ankh as Node3D).global_position
	player._try_interact()
	_check(str(player.get("respawn_ankh_id")) != "", "pressing E binds the respawn point at the ankh")
	# The gate resolves by proximity (the dispatch's gate leg).
	player.global_position = (get_nodes_in_group("moon_gates")[0] as Node3D).global_position
	var resolved = player._nearest_in_group("moon_gates")
	_check(resolved != null, "the gate leg resolves a gate under the player")
	await _leg_loot_pickup(player)
	globe.queue_free()
	await process_frame


## LEG 6: the E dispatch picks up a real ground drop (Step 2 made the
## wildlife drop loot; the pickup leg is what closes the loop).
func _leg_loot_pickup(player) -> void:
	var gls = root.get_node_or_null("GroundLootService")
	if gls == null or not gls.has_method("create_drop"):
		_fail("no GroundLootService for the loot leg")
		return
	var ds = root.get_node_or_null("DataService")
	if ds == null:
		_fail("no DataService for the loot leg")
		return
	gls.clear_all()
	var drop_pos: Vector3 = (player as Node3D).global_position
	var drop_id: String = gls.create_drop(drop_pos, [{"item_id": "res_iron_ore", "quantity": 2}], {"source": "receipt"})
	_check(drop_id != "", "a ground drop lands under the player")
	player._try_interact()
	_check(gls.get_drop_count() == 0, "pressing E picks the drop up (the loot leg is wired)")
	var bag = player.get("inventory_component")
	if bag != null and bag.has_method("find_item"):
		_check(bag.find_item("res_iron_ore") >= 0, "the ore landed in the bag")


func _find_globe() -> Node:
	for c in root.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("globe_world.gd"):
			return c
	return null
