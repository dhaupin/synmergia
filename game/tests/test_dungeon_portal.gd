## test_dungeon_portal.gd - Portal -> dungeon -> horde loop, live.
## Run headless:
##
##   cd game && godot --headless --path . --script res://tests/test_dungeon_portal.gd
##
## Covers the closed loop:
##   1. Authored gateway .tres loads (data/gateways/, guard-cache lesson).
##   2. Dungeon zone carries horde_config_id="vault_seal" (ZoneData).
##   3. DataService.get_horde catalog + resolver agree.
##   4. use_gateway through the REAL WorldService path teleports the
##      player into the dungeon zone.
##   5. Zone entry auto-starts the vault_seal horde (instance-scoped).
##   6. Horde mobs + the entering player pin to /world/instances/dungeon.
##   7. Re-entry does not double-start; plain zones never auto-start.
##
## Exit 0 = all pass.
extends SceneTree

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _run()
	quit(0 if _fail == 0 else 1)

func _run() -> void:
	var horde = root.get_node_or_null("HordeEventService")
	var es = root.get_node_or_null("EntityService")
	var zm = root.get_node_or_null("ZoneManager")
	var pm = root.get_node_or_null("PlayerManager")
	var proj = root.get_node_or_null("WorldStateProjection")
	var ws = root.get_node_or_null("WorldService")
	var ds = root.get_node_or_null("DataService")
	_assert(horde != null, "HordeEventService present")
	_assert(es != null and zm != null and pm != null, "core services present")
	_assert(proj != null and ws != null and ds != null, "projection/world/data present")
	if horde == null or es == null or zm == null or pm == null or proj == null or ws == null or ds == null:
		return _finish()

	# --- 1. Authored gateway .tres -------------------------------------------
	var gateway = load("res://data/gateways/dungeon_forest_depths_entrance.tres")
	_assert(gateway != null, "authored gateway .tres loads")
	if gateway == null:
		return _finish()
	_assert(str(gateway.destination_zone_id) == "zone_dungeon_forest_depths",
			"gateway destination is the dungeon zone")

	# --- 2. Dungeon zone carries the horde trigger ---------------------------
	var dungeon: Resource = ds.get_zone("zone_dungeon_forest_depths")
	_assert(dungeon != null, "dungeon zone in the catalog")
	if dungeon != null:
		_assert("horde_config_id" in dungeon and str(dungeon.horde_config_id) == "vault_seal",
				"dungeon zone declares horde_config_id=vault_seal")

	# --- 3. Catalog + resolver agree ------------------------------------------
	var a = ds.get_horde("vault_seal")
	var b = load("res://core/schemas/horde_data_resolver.gd").load_config("vault_seal")
	_assert(a != null and b != null and a == b, "catalog and resolver return the SAME instance")

	# --- Player ----------------------------------------------------------------
	var PlayerScript = load("res://entities/player/player_controller.gd")
	var player: Node = PlayerScript.new()
	player.display_name = "PortalHero"
	player.entity_id = "portal_char"
	# Dungeon gates at level 10; the hero skips the queue for the test.
	player.level = 12
	root.add_child(player)
	await process_frame
	es.register_entity(player, null, "portal_char")
	pm.set_local_player(player)
	await process_frame

	# --- 4. Gateway walk through the REAL WorldService path -------------------
	# Register the same runtime record world_playable._setup_portal builds.
	var gateway_id: String = ws.register_gateway({
		"display_name": str(gateway.display_name),
		"position": Vector3(27, 0, 0),
		"from_zone": "portal_test_zone",
		"to_zone": str(gateway.destination_zone_id),
		"to_position": gateway.destination_position,
		"required_level": int(gateway.min_level),
		"radius": 5.0,
		"activation_radius": 6.0,
	})
	_assert(gateway_id != "", "gateway record registered")
	# Load zone defs like the production login path does so the dungeon
	# destination resolves (the lazy-load fallback in use_gateway also
	# covers this; loading here keeps the test on the happy path).
	if zm.has_method("load_zones"):
		zm.load_zones()
	# Put the player in the source zone first (entry uses entity_exit_zone).
	# Source zone sits AWAY from the dungeon (dungeon: center 0,0,0 r200)
	# so the seamless detector cannot re-claim a zone-less player back
	# into it mid-teleport.
	var ZoneDataScript = load("res://core/schemas/zone_data.gd")
	var source_zone = ZoneDataScript.new()
	source_zone.id = "portal_test_zone"
	source_zone.zone_center = Vector3(400, 0, 400)
	source_zone.zone_radius = 60.0
	zm.register_zone(source_zone)
	zm.entity_enter_zone(player, source_zone)
	await process_frame

	var dest: Dictionary = ws.use_gateway(gateway_id, player)
	_assert(not dest.is_empty(), "use_gateway teleports the player")
	_assert(str(dest.get("zone_id", "")) == "zone_dungeon_forest_depths",
			"destination zone is the dungeon")
	await process_frame
	await process_frame

	# --- 5. Zone entry auto-started the horde ---------------------------------
	var horde_id: String = horde.active_horde_in_zone("zone_dungeon_forest_depths")
	_assert(horde_id != "", "dungeon entry auto-started the vault_seal horde")
	if horde_id == "":
		return _finish()
	_assert(str(horde._hordes[horde_id]["instance_scope"]) == "dungeon",
			"auto horde is instance-scoped")

	# --- 6. Mobs + player pin to the instance scope ---------------------------
	# Wait for wave 1 to finish spawning (6 slimes at MAX_SPAWNS_PER_FRAME/tick).
	var ok := await _wait_fighting(horde, horde_id, 6, 30000)
	_assert(ok, "wave 1 reaches fighting (6 slimes)")
	proj.flush(true)
	await process_frame
	var mob_ids: Array = horde._hordes[horde_id]["mobs_spawned_ids"]
	var pinned := true
	for eid in mob_ids:
		if str(proj.get_entity_scope_override(str(eid))) != "instance:dungeon":
			pinned = false
	_assert(pinned and mob_ids.size() > 0, "all auto-horde mobs pinned to instance:dungeon")
	_assert(str(proj.get_entity_scope_override("portal_char")) == "instance:dungeon",
			"entering player pinned to the instance scope")
	var snap: Array = proj.snapshot_for_instance("dungeon")
	_assert(not snap.is_empty(), "instance snapshot reads the dungeon subtree")

	# --- 7. Re-entry safety ----------------------------------------------------
	zm.entity_enter_zone(player, dungeon)
	await process_frame
	_assert(horde.active_horde_in_zone("zone_dungeon_forest_depths") == horde_id,
			"re-entry does not double-start")

	horde.stop_horde(horde_id, "portal test done")
	await process_frame
	_assert(str(proj.get_entity_scope_override("portal_char")) == "",
			"sweep releases the player pin")
	await process_frame
	_finish()

func _wait_fighting(horde, horde_id: String, expected_alive: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var st: Dictionary = horde.get_horde_status(horde_id)
		if st.is_empty():
			return false
		if str(st.get("state", "")) == "fighting" and int(st.get("remaining", -1)) == expected_alive:
			return true
	return false

func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)

func _finish() -> void:
	print("---")
	print("test_dungeon_portal: %d passed, %d failed" % [_pass, _fail])
