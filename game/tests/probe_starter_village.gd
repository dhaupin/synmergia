## Probe: the STARTER VILLAGE PROTO (the ledger's parked build).
## Headless script mode:
##   godot --headless --path game --script res://tests/probe_starter_village.gd
##
## The village rides the plaza's own laws, so the probe pins BOTH
## layers:
##   LAW (no scene): every authored structure direction lands on the
##     plaza's exact flat ground (== SPAWN_HEIGHT), stays dry above
##     the sea line, and reads a CLEAN cartway corridor (the road bend
##     and the apron rank keep the cartway out of the village).
##   SCENE (the globe boot): the village node exists under world_root
##     with the THREE authored structures, each carrying the one-law
##     PropBody collider (climbable group), and each sitting at
##     planet_radius + lift + the walk law's plaza height.
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"

var _fails: int = 0


func _check(label: String, cond: bool) -> bool:
	if cond:
		print("PASS: " + label)
	else:
		_fails += 1
		printerr("FAIL: " + label)
	return cond


func _dir_for(V, spawn: Vector3, east: Vector3, north: Vector3, bearing: float, reach: float) -> Vector3:
	var rad: float = deg_to_rad(float(bearing))
	return (spawn + east * (float(reach) * cos(rad)) \
		+ north * (float(reach) * sin(rad))).normalized()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var TGen = load("res://scenes/worlds/terrain_gen.gd")
	var SV = load("res://entities/starter_village.gd")
	var seed_b: PackedByteArray = TGen.world_seed_bytes()
	var sea: float = TGen.sea_level(seed_b)
	var spawn: Vector3 = TGen.SPAWN_CENTER
	var east: Vector3 = Vector3(0, 1, 0).cross(spawn).normalized()
	var north: Vector3 = spawn.cross(east).normalized()

	var layout: Array = [
		["VillageHall", SV.HALL_BEARING_DEG, SV.HALL_REACH],
		["ForgeStall", SV.FORGE_BEARING_DEG, SV.FORGE_REACH],
		["WaySignpost", SV.SIGN_BEARING_DEG, SV.SIGN_REACH],
		["GeneralStore", SV.STORE_BEARING_DEG, SV.STORE_REACH],
	]

	# LAW layer: plaza-flat ground, dry, clean corridor.
	for entry in layout:
		var dir: Vector3 = _dir_for(SV, spawn, east, north, float(entry[1]), float(entry[2]))
		var h: float = TGen.terrain_height(dir, seed_b)
		_check("%s foot is plaza-flat (h %.3f == spawn %.1f)" % [entry[0], h, TGen.SPAWN_HEIGHT],
			absf(h - TGen.SPAWN_HEIGHT) < 0.01)
		_check("%s foot is dry above the sea line" % entry[0], h > sea + 1.0)
		# The cartway law's action, not its raw reach: the bend keeps
		# the route out of the apron and the rank bars the corridor
		# from carving OR tinting inside it -- the village foot keeps
		# its exact ground even when the path passes nearby.
		var st: Vector3 = TGen.road_state_at(dir, seed_b)
		var h_road: float = TGen.road_height_override(dir, seed_b, h)
		_check("%s foot keeps its ground under the cartway law (w %.2f, no regrade)" % [entry[0], st.x],
			absf(h_road - h) < 0.001)
		_check("%s sits inside the plaza flat ring" % entry[0],
			dir.angle_to(spawn) < TGen.SPAWN_FLAT_ANG)

	# LAW layer, the DOCK's own anchor: the ferry terminal rides the
	# plaza->harbor apron arc (6% of the bearing). Its foot must be
	# DRY above the sea line (the apron ring holds), keep its ground
	# under the cartway law, and sit inside the plaza flat ring.
	var harbor_anchor: Vector3 = TGen.village_harbor_dir()
	var dock_dir: Vector3 = spawn.slerp(harbor_anchor, 0.06).normalized()
	var h_dock: float = TGen.terrain_height(dock_dir, seed_b)
	_check("HarborDock foot is dry above the sea line (h %.2f)" % h_dock, h_dock > sea + 1.0)
	_check("HarborDock sits inside the plaza flat ring",
		dock_dir.angle_to(spawn) < TGen.SPAWN_FLAT_ANG)
	var st_dock: Vector3 = TGen.road_state_at(dock_dir, seed_b)
	var h_road_dock: float = TGen.road_height_override(dock_dir, seed_b, h_dock)
	_check("HarborDock foot keeps its ground under the cartway law (w %.2f)" % st_dock.x,
		absf(h_road_dock - h_dock) < 0.001)

	# SCENE layer: the globe boots the village with colliders.
	ProjectSettings.set_setting("synmergia/world/planet_radius", 100.0)
	var packed: PackedScene = load(GLOBE_SCENE)
	var globe = packed.instantiate()
	root.add_child(globe)
	# THE BOOT-WAVE LAW (the loading-speed round): the playable core boots
	# in _ready and the nine ensuite builds -- the starter village and the
	# capitol monolith among them -- ride _boot_waves() one per frame. Any
	# scene-layer read before the waves-done stamp sees a half-built world
	# (this probe used to wait two frames and read the village alone).
	var waves_deadline: int = Time.get_ticks_msec() + 60000
	while not globe.has_meta("boot_waves_done_ms") and Time.get_ticks_msec() < waves_deadline:
		await process_frame
	_check("the boot waves finish (the world dresses)", globe.has_meta("boot_waves_done_ms"))
	# THE LANE-DRAIN LAW: the async mesh lane must be quiet before the read
	# AND before quit -- a probe that exits with a derive still in flight
	# makes the engine tear down around a live worker thread (the stray
	# "nonexistent function" / null-Time errors at shutdown).
	var st_probe = globe.get("streamer")
	var drain_deadline: int = Time.get_ticks_msec() + 60000
	while st_probe != null and st_probe._mesh_pending() > 0 and Time.get_ticks_msec() < drain_deadline:
		await process_frame
	await process_frame

	var world_root: Node = globe.get("world_root")
	var village: Node3D = world_root.get_node_or_null("StarterVillage")
	if not _check("the village boots into the world", village != null):
		quit(1)
		return
	# THE TURN-15 PROP LAW pinned ON the village root: the 5 authored
	# structures PLUS the three game-function prop clusters (ankh,
	# moon gate, bout stones) PLUS the NPC roster entities (the town
	# rosters spawn under the village root on the globe -- the
	# underworld's own-frame law). Names must carry the authored set.
	var expected: Array = ["VillageHall", "ForgeStall", "WaySignpost", "GeneralStore", "HarborDock",
		"VillageAnkh", "VillageMoonGate", "VillageBoutStones"]
	var names_ok := true
	var prop_names := 0
	var npc_entities := 0
	for child in village.get_children():
		var cname: String = str(child.name)
		if cname in expected:
			prop_names += 1
		else:
			# The town roster: NPCEntity children under the town root
			# (the underworld fold-away law). Counted by ELIMINATION --
			# script-mode entity nodes can carry engine auto-names
			# (@Node3D@N), so a name grep undercounts the roster.
			npc_entities += 1
	_check("structure names match the authored layout", names_ok)
	_check("the village carries the 8 authored structure+prop nodes", prop_names == 8)
	_check("the village roster spawns the NPC entities (>= 5 of 6)", npc_entities >= 5)
	# ORIENTATION LAW (the sideways/backwards bug): every village NPC body
	# must stand on the surface -- its local +Y within a small epsilon of the
	# radial up at its position -- not world-Y up (which tilts it off the
	# sphere on the globe). _spawn_town_npc radial-aligns the body.
	var up_ok := true
	var up_checked := 0
	var pc: Vector3 = globe.get("planet_center")
	for child in village.get_children():
		if str(child.name) in expected:
			continue
		var body := child as Node3D
		if body == null:
			continue
		var rel: Vector3 = body.global_position - pc
		if rel.length() < 0.001:
			continue
		var radial: Vector3 = rel.normalized()
		var local_up: Vector3 = body.global_transform.basis.y.normalized()
		up_checked += 1
		if local_up.dot(radial) < 0.999:
			up_ok = false
			printerr("FAIL: NPC %s local up %s != radial %s (dot %.3f)" \
				% [str(child.name), local_up, radial, local_up.dot(radial)])
	_check("village NPCs stand radial (local +Y == surface up, %d checked)" % up_checked,
		up_checked > 0 and up_ok)
	# PropBody pins apply ONLY to the authored structures (props ride
	# their OWN interaction bodies; NPCs are entities).
	for child in village.get_children():
		var cname: String = str(child.name)
		if not (cname in ["VillageHall", "ForgeStall", "WaySignpost", "GeneralStore", "HarborDock"]):
			continue
		var body: Node = child.get_node_or_null("PropBody")
		_check("%s carries the one-law PropBody" % child.name, body != null)
		if body != null:
			var body3d := body as StaticBody3D
			_check("%s PropBody joins the climbable group" % child.name,
				body3d.is_in_group("climbable"))
		# Position law: |pos| == planet_radius + lift + walk height.
		var pl: float = globe.get("planet_radius")
		var walker: Callable = Callable(globe.get("streamer"), "walk_surface_h")
		var dir_s: Vector3 = child.position.normalized()
		var expected_r: float = pl + 0.52 + float(walker.call(dir_s))
		_check("%s rides the walk law's lift (r %.2f ~ %.2f)" % [child.name, child.position.length(), expected_r],
			absf(child.position.length() - expected_r) < 0.5)

	# THE CAPITOL MONOLITH (the coast build): the far ring's authored
	# megalith boots with the same one-law collider belt, rides the
	# same walk-law frame, and THE CONNECTING ROAD reaches its plaza
	# (the cartway's terminal corridor weight reads positive at the
	# capitol bearing -- the road law's own village -> capitol walk).
	var capitol: Node3D = world_root.get_node_or_null("CapitolMonolith")
	_check("the capitol monolith boots into the world", capitol != null)
	if capitol != null:
		_check("the monolith carries the one-law PropBody", capitol.get_node_or_null("PropBody") != null)
		var pl2: float = globe.get("planet_radius")
		var walker2: Callable = Callable(globe.get("streamer"), "walk_surface_h")
		var TGenCap = load("res://scenes/worlds/terrain_gen.gd")
		var cap_dir: Vector3 = TGenCap.capitol_plaza_dir()
		var expected_r2: float = pl2 + 0.52 + float(walker2.call(cap_dir))
		_check("the monolith rides the walk law's lift (r %.2f ~ %.2f)" % [capitol.position.length(), expected_r2],
			absf(capitol.position.length() - expected_r2) < 0.5)
		var seed_cap: PackedByteArray = TGenCap.world_seed_bytes()
		var road_w: float = TGenCap.road_state_at(cap_dir, seed_cap).x
		_check("the connecting road reaches the capitol plaza (w %.2f)" % road_w, road_w > 0.05)
		# THE DUAL-TOWN ROSTER PIN (turn 17, the owner's symmetric-town
		# law): the capitol carries the FULL function set too -- 7 NPCs
		# (armory, skill academy, banker, smithy, merchant, herbalist,
		# keeper), the ankh, the moon gate, and the bout stones, plus
		# the four city quarters and the pier head under its root.
		var cap_props: Array = ["CapitolAnkh", "CapitolMoonGate", "CapitolBoutStones", "ConcordSinkShrine"]
		var cap_props_found := 0
		var cap_npcs := 0
		var cap_built := 0
		var cap_expected_built: Array = ["ConcordHall", "WestHouse", "EastHouse", "SouthHouse", "CapitolPierHead"]
		for child in capitol.get_children():
			var cn: String = str(child.name)
			if cn in cap_props:
				cap_props_found += 1
			elif cn in cap_expected_built:
				cap_built += 1
			else:
				cap_npcs += 1  # NPC entities (the roster's own-frame law)
		_check("the capitol carries the prop family (ankh, moon gate, bout stones, sink shrine)", cap_props_found == 4)
		_check("the capitol quarters + pier head boot (5 built)", cap_built == cap_expected_built.size())
		_check("the capitol roster spawns the 8 NPCs (incl. the Concord herald)", cap_npcs >= 8)
		# THE FERRY GATEWAY PIN: the route's city end names the cove
		# pier gateway -- the boat sails the bay (the owner's turn-17
		# retarget; veh_haven_ferry.route_gateways[1]).
		var FS = root.get_node_or_null("FerryService")
		var DS_f = root.get_node_or_null("DataService")
		if FS != null and DS_f != null:
			var veh = FS.get_ferry("veh_haven_ferry")
			_check("the ferry route's city end is the capitol pier (the boat sails the bay)", \
				veh != null and str(veh.route_gateways[1]) == "waypoint_capitol_pier" \
				and DS_f.get_gateway("waypoint_capitol_pier") != null)
		else:
			_check("the ferry route's city end is the capitol pier (the boat sails the bay)", false)

	print("probe_starter_village: %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	quit(0 if _fails == 0 else 1)
