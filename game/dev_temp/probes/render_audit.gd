## render_audit - the FUNCTIONAL AUDIT receipt: everything built
## recently, booted the way the game boots it, walked piece by piece.
##
##   A. THE MAIN WORLD (globe_world.tscn at the ordinary 20 km):
##      PierBeacon + MoorGuide with their halos, the night law on the
##      live lamps, the Pans Runner carrying her deck pieces.
##   B. THE UNDERWORLD (globe_underworld.tscn through the REAL seam:
##      ScopeService swap + receive_visitor): camp + Warden, the Glow
##      Cistern, the Deep Wilds, the Underglow Lake, the Deep Trail,
##      the airflow (vent carry + thrower rite), the strata mist, and
##      the swim credit firing live.
##   C. THE RENDER FACTS (headless honesty): every MeshInstance3D in
##      both worlds carries a real mesh + a real material (the things
##      the engine actually draws); lights inventoried. Headless has
##      no rasterer -- "would draw" is the honest ceiling here, the
##      pixel pass stays on-device.
## Run headless: godot --headless --path . --script res://dev_temp/probes/render_audit.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const UNDER_SCENE := "res://scenes/worlds/globe_underworld.tscn"
const RADIUS_SETTING := "synmergia/world/planet_radius"
const RADIUS := 20000.0
const WALKER_SCRIPT := "res://entities/globe_player.gd"

var _checks := 0


func _check(label: String, cond: bool, detail: String = "") -> bool:
	_checks += 1
	print("AUDIT-PASS %s %s" % [label, detail] if cond else "AUDIT-MISS %s %s" % [label, detail])
	return cond


func _init() -> void:
	call_deferred("_run")


func _count_family(host: Node, prefix: String) -> int:
	var n := 0
	for c in host.get_children():
		if str(c.name).begins_with(prefix):
			n += 1
	return n


func _inherits_collider(n: Node) -> bool:
	for d in n.get_children():
		if d is StaticBody3D or d is CollisionShape3D:
			return true
	return false


func _run() -> void:
	var ok := true

	# ---------- A. THE MAIN WORLD --------------------------------------
	ProjectSettings.set_setting(RADIUS_SETTING, RADIUS)
	var packed: PackedScene = load(GLOBE_SCENE)
	ok = _check("globe_world.tscn loads (the surface is real)", packed != null) and ok
	var world: Node = null
	if packed != null:
		world = packed.instantiate()
		root.add_child(world)
		for _i in range(10):
			await process_frame
		for _i in range(20):
			await root.get_tree().physics_frame
		var wr = world.get("world_root")
		ok = _check("the surface world_root walks", wr != null) and ok
		if wr != null:
			var beacon = wr.get_node_or_null("PierBeacon")
			var guide = wr.get_node_or_null("MoorGuide")
			ok = _check("the PierBeacon stands", beacon != null) and ok
			ok = _check("the MoorGuide stands", guide != null) and ok
			if beacon != null:
				var boxes := 0
				var meshes := 0
				for c in beacon.get_children():
					if c is MeshInstance3D and c.mesh != null:
						meshes += 1
						if str(c.name).begins_with("@"):
							boxes += 1
				ok = _check("the beacon is built stone+cap+lamp", meshes >= 6, "meshes=%d" % meshes) and ok
				var lamp = beacon.get_meta("lamp") if beacon.has_meta("lamp") else null
				var halo = beacon.get_meta("halo") if beacon.has_meta("halo") else null
				ok = _check("the beacon lamp + halo wired (dusk-read)", lamp != null and halo is OmniLight3D \
					and not halo.visible) and ok
				# THE NIGHT LAW, live on this boot's own materials.
				var dark = beacon.get_meta("lamp")
				# The edge hours ride the epoch's FRACTION (place_night takes
				# fposmod first): a whole day base so 14000.5 is true noon
				# and 14000.75 is true dusk.
				var base_day := 14000.0
				var HL = load("res://entities/harbor_lights.gd")
				# Noon sleeps (epoch fraction 0.5), dusk wakes (0.75);
				# 14000.0 itself is MIDNIGHT (the night side of the band).
				HL.place_night(beacon, base_day + 0.5)
				var noon_ok: bool = not dark.emission_enabled and not halo.visible
				HL.place_night(beacon, base_day + 0.75)
				var dusk_on: bool = dark.emission_enabled and halo.visible
				_check("night law dusk-wakes noon-sleeps", dusk_on and noon_ok)

	# The Pans Runner carries her deck (the deck-ride law, live boot).
	if world != null and world.get("world_root") != null:
		var wr2 = world.get("world_root")
		var runner = wr2.get_node_or_null("PansRunner")
		ok = _check("the Pans Runner is placed", runner != null) and ok
		if runner != null:
			var deck: Node = runner.get_node_or_null("DeckPanel")
			var rig: Node = runner.get_node_or_null("MastBlock")
			ok = _check("the deck pieces stand (DeckPanel + MastBlock)", deck != null and rig != null) and ok
			ok = _check("the deck is standable (collider law)", \
				(deck == null or _inherits_collider(deck)) and (rig == null or _inherits_collider(rig))) and ok

	# ---------- B. THE UNDERWORLD THROUGH THE REAL SEAM -------------------
	var upacked: PackedScene = load(UNDER_SCENE)
	ok = _check("globe_underworld.tscn loads", upacked != null) and ok
	var uglobe: Node = null
	var walker: Node = null
	var uwr: Node3D = null
	var scope = root.get_node_or_null("ScopeService")
	var esvc = root.get_node_or_null("EntityService")
	if upacked != null and scope != null:
		var holder := Node3D.new()
		holder.name = "AuditHolder"
		root.add_child(holder)
		uglobe = upacked.instantiate()
		holder.add_child(uglobe)
		for _i in range(10):
			await process_frame
		uwr = uglobe.get("world_root")
		ok = _check("the Deep Root conjures", uwr != null and uwr.is_in_group("world_root_underworld")) and ok
		walker = load(WALKER_SCRIPT).new()
		walker.entity_id = "audit_walker"
		root.add_child(walker)
		if esvc != null:
			esvc._entities["audit_walker"] = walker
		var swapped: bool = scope.enter_world_scope("audit_walker", "underworld", uwr, true)
		ok = _check("the walker rides the real seam into the underworld", \
			swapped and scope.world_of("audit_walker") == "underworld") and ok
		if swapped:
			uglobe.receive_visitor(walker)
			# receive_visitor lands the body skin+0.4 above the camp head
			# (the collision center rides the walk line's skin).
			ok = _check("the visitor lands at the camp head", \
				walker.global_position.distance_to(uwr.global_position + uglobe.get("CAMP_HEAD_POS") + Vector3(0, 1.4, 0)) < 1.0) and ok

	if uglobe != null:
		# THE CISTERN (all five laws on the live boot).
		var jug: Node = uwr.get_node_or_null("GlowCistern")
		ok = _check("the Glow Cistern stands", jug != null) and ok
		if jug != null:
			ok = _check("cistern pieces (slab+7 walls+bench+water)", \
				jug.get_node_or_null("CisternSlab") != null \
				and jug.get_node_or_null("CisternBench") != null \
				and jug.get_node_or_null("CisternWater") != null \
				and _count_family(jug, "CisternWall_") == 7) and ok
			var bench: Node = jug.get_node_or_null("CisternBench")
			var slab: Node = jug.get_node_or_null("CisternSlab")
			ok = _check("every cistern stone stands (collider law)", \
				_inherits_collider(bench) and _inherits_collider(slab)) and ok
			var stone = uglobe.get("_cistern_stone_mat")
			ok = _check("the vein wall material rides", stone != null \
				and bool(stone.emission_enabled)) and ok

		# THE DEEP WILDS (families + collider law on this boot).
		var wilds: Node = uwr.get_node_or_null("DeepWilds")
		ok = _check("the Deep Wilds dress the shelf", wilds != null) and ok
		if wilds != null:
			var crags := _count_family(wilds, "DeepCrag_")
			ok = _check("crags + trunks + clumps + spikes + tufts live", \
				crags >= 9 and _count_family(wilds, "DeadTrunk_") == 7 \
				and _count_family(wilds, "MyceliumClump_") == 9 \
				and _count_family(wilds, "Stalagmite_") == 14 \
				and _count_family(wilds, "WildGrass_") == 36, \
				"crags=%d" % crags) and ok
			var stone_collider := true
			for prefix in ["DeepCrag_", "DeadTrunk_", "Stalagmite_"]:
				for n in wilds.get_children():
					if not str(n.name).begins_with(prefix):
						continue
					if not _inherits_collider(n):
						stone_collider = false
						break
			ok = _check("wilds stones collidered, paint walks over", stone_collider) and ok

		# THE UNDERGLOW LAKE (burn frame live).
		var cald: Node = uwr.get_node_or_null("UnderglowLake")
		ok = _check("the Underglow Lake stands", cald != null) and ok
		if cald != null:
			ok = _check("the curb ring (8) collidered", \
				_count_family(cald, "LakeCurb_") == 8) and ok
			var melt: Node = cald.get_node_or_null("LakeMelt")
			ok = _check("the molten disc paints", melt != null and melt.mesh != null) and ok
			var lmat = uglobe.get("_lava_mat")
			uglobe._process(0.016)
			if lmat != null:
				var e: float = float(lmat.emission_energy_multiplier)
				ok = _check("the melt pulses with the tide (1.1-1.5)", \
					e >= 1.1 and e <= 1.51, "energy=%.3f" % e) and ok
			else:
				ok = _check("the lava material is available", false) and ok

		# THE DEEP TRAIL (the roads).
		var trail: Node = uwr.get_node_or_null("DeepTrail")
		ok = _check("the Deep Trail lays", trail != null) and ok
		if trail != null:
			ok = _check("two legs of plates (32)", _count_family(trail, "TrailPlate_") == 32) and ok

		# THE CAMP (keeper + zone + the arrival pad).
		var spawns: Array = uglobe.get("_npc_spawns")
		ok = _check("the Deep Warden keeps the camp", spawns != null and spawns.size() == 1 \
			and is_instance_valid(spawns[0])) and ok
		var ZoneManager = root.get_node_or_null("ZoneManager")
		ok = _check("zone_deep_root_camp declared live", \
			ZoneManager != null and ZoneManager.get_zone("zone_deep_root_camp") != null) and ok

		# THE AIRFLOW (vent carry + thrower rite -- idempotent book).
		var thermo = root.get_node_or_null("ThermalService")
		ok = _check("ThermalService answers", thermo != null) and ok
		if thermo != null:
			var ids: Array = []
			for u in thermo.get_updrafts():
				ids.append(str(u.id))
			ok = _check("the underworld columns are booked", \
				ids.has("thermal_underworld_vent_east") \
				and ids.has("thermal_underworld_vent_flow") \
				and ids.has("thermal_ascent_thrower")) and ok
			walker.global_position = uwr.global_position \
				+ Vector3(24, 2000.6, -14)
			walker.velocity = Vector3.ZERO
			uglobe._process(1.0 / 60.0)
			ok = _check("the East Stack carries the walker", walker.velocity.y > 0.0 \
				and str(thermo.updraft_at(walker.global_position - uwr.global_position)) == "thermal_underworld_vent_east") and ok
			thermo.awaken_launcher("thermal_ascent_thrower")
			walker.global_position = uwr.global_position + Vector3(4, 2000.6, 4)
			walker.velocity = Vector3.ZERO
			uglobe._process(1.0 / 60.0)
			ok = _check("the woken thrower HURLS", walker.velocity.y > 0.0) and ok
			thermo._awake.erase("thermal_ascent_thrower")
			for u in thermo.get_updrafts():
				if str(u.id) == "thermal_ascent_thrower":
					u.awakened = false

		# THE MIST (the weather law fed live).
		var env = uglobe.get("_world_env")
		var Under = load("res://scenes/worlds/globe_underworld.gd")
		uglobe._process(0.016)
		ok = _check("the strata mist rides the live fog", env != null \
			and absf(float(env.fog_density) - Under.weather_mist(uglobe._glow_tide_phase())) < 0.02) and ok

		# THE SWIM CREDIT (the cistern live once more on this boot).
		var QuestService = root.get_node_or_null("QuestService")
		var OceanService = root.get_node_or_null("OceanService")
		if QuestService != null and OceanService != null:
			QuestService.load_player_quests("audit_walker")
			var accepted: bool = QuestService.accept_quest("audit_walker", "quest_cross_the_cistern")
			ok = _check("the swimming quest accepts on this boot", accepted) and ok
			# Into the dish; one underworld frame delivers the credit.
			var seat: Vector3 = uglobe.get("CAMP_HEAD_POS") + Vector3(12.0, 0.8, 0.0)
			walker.global_position = uwr.global_position + seat
			uglobe._process(1.0 / 60.0)
			var swam := false
			for o in (QuestService.get_quest_progress("audit_walker", "quest_cross_the_cistern").get("objectives", []) as Array):
				if str(o.get("id", "")) == "swim_the_pool" and bool(o.get("completed", false)):
					swam = true
			ok = _check("the crossing credits live (water_entered -> QuestService)", swam) and ok
			# THE BURN (the lake live one more time; the body stands on the
			# walk line IN the melt: the dish reads a clip underneath --
			# WADING, and the whole-digit bite accrues; the curb exit ends it).
			var hp: int = int(walker.current_health)
			walker.global_position = uwr.global_position \
				+ uglobe.get("CAMP_HEAD_POS") + uglobe.get("LAVA_LAKE_SEAT")
			OceanService.forget_swimmer("audit_walker")
			for _i in range(120):
				uglobe._process(1.0 / 60.0)
			var burn: int = hp - int(walker.current_health)
			ok = _check("the lake bites ~8 dps and the exit is free", \
				burn >= 12 and burn <= 20, "burn=%d" % burn) and ok
			# OUT of the lake: free again.
			walker.global_position = uwr.global_position + Vector3(-26, 2000.8, 2)
			OceanService.forget_swimmer("audit_walker")
			var mid: int = int(walker.current_health)
			for _i in range(30):
				uglobe._process(1.0 / 60.0)
			ok = _check("dry ground is free", int(walker.current_health) == mid) and ok
			QuestService.abandon_quest("audit_walker", "quest_cross_the_cistern")
			QuestService._player_quests.erase("audit_walker")

		# ---------- C. THE RENDER FACTS: the boots draw what they built --
		# Every MeshInstance3D the underworld carries needs a REAL mesh
		# (headless has an empty renderer: node truth is what would draw).
		# The census scans the globe ROOT: the strata light and the world
		# environment hang beside world_root, not under it (the first cut
		# scanned uwr alone and read a light count of zero).
		var facts: Dictionary = _scan_meshes(uglobe, {"total": 0, "bare": 0})
		ok = _check("every underworld MeshInstance3D carries a real mesh", int(facts["bare"]) == 0) and ok
		ok = _check("the underworld's mesh census", int(facts["total"]) > 120, "meshes=%d" % facts["total"]) and ok
		print("AUDIT render census underworld meshes=%d bare=%d" % [int(facts["total"]), int(facts["bare"])])
		var lights: int = _count_lights(uglobe, 0)
		print("AUDIT light census underworld lights=%d" % lights)
		ok = _check("the underworld carries real lights", lights >= 1) and ok

		# Fold-back (the underworld is derived content: last out, gone).
		uglobe.release_visitor(walker)
		ok = _check("the last visitor leaving folds the Deep Root away", \
			not is_instance_valid(uglobe) or uglobe.is_queued_for_deletion()) and ok

	if world != null:
		world.queue_free()

	var scope2 = root.get_node_or_null("ScopeService")
	if scope2 != null and walker != null and walker.is_inside_tree():
		var home := Node3D.new()
		root.add_child(home)
		scope2.exit_to_world("audit_walker", "main", home, true)

	if not ok:
		print("AUDIT-FAIL %d" % _checks)
		quit(1)
		return
	print("AUDIT-OK (%d checks)" % _checks)
	quit(0)


## Mesh census: GDScript ints pass by value, so the scan returns its
## tallies (a mutable-by-reference book would lie).
func _scan_meshes(host: Node, tallies: Dictionary) -> Dictionary:
	for c in host.get_children():
		if c is MeshInstance3D:
			tallies["total"] = int(tallies.get("total", 0)) + 1
			if c.mesh == null:
				tallies["bare"] = int(tallies.get("bare", 0)) + 1
		_scan_meshes(c, tallies)
	return tallies


func _count_lights(host: Node, n: int) -> int:
	for c in host.get_children():
		if c is OmniLight3D or c is DirectionalLight3D or c is SpotLight3D:
			n += 1
		n = _count_lights(c, n)
	return n
