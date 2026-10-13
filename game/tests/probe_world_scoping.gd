## One-shot probe: the S16 world-scoping gate.
## 1. spawn_all_offering_npcs must NOT place the Deep Warden in the
##    planar world (the underworld globe spawns him itself).
## 2. zone_deep_root_camp must still be registered (quest/EXPLORE law).
## 3. Planar zone detectors must ignore the subworld zone even when an
##    entity physically sits at its (subworld-frame) center.
## 4. THE TERRAFORM SCOPE PIN (authored-backend scoping): the world
##    DATA declarations scope the heightfield per world -- world_main
##    declares NOTHING (the authored-backends round ended: the play
##    world wants the natural analytic terrain; the penrose lattice
##    backend stays available for any world that asks for it, none
##    does right now) -- and the moon declares NOTHING too (both
##    grounds are the natural analytic law). Strictly structural: the
##    .tres declarations and the registered worlds must agree.
extends SceneTree

var _checks := 0


func _check(label: String, cond: bool) -> bool:
	_checks += 1
	print("  %s %s" % ["PASS" if cond else "FAIL", label])
	return cond


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	var ds = root.get_node_or_null("DataService")
	var zm = root.get_node_or_null("ZoneManager")
	var sp = root.get_node_or_null("SpawnService")
	if ds == null or zm == null or sp == null:
		push_error("FAIL: autoloads missing")
		quit(1)
		return
	if zm._zones.is_empty():
		zm.load_zones()

	# --- Terraform scoping: the DATA declares, per world. The boot
	# resolves the declaration; the pin guards the DATA, which is the
	# single authority (the same .tres the scene read at boot).
	var main_data = load("res://data/worlds/world_main.tres")
	var moon_data = load("res://data/worlds/world_moon.tres")
	var terra_ok := true
	if main_data == null or moon_data == null:
		terra_ok = false
	else:
		if not str(main_data.terrain_backend_id).is_empty():
			terra_ok = false  # the main ground is the natural law now
		if not str(moon_data.terrain_backend_id).is_empty():
			terra_ok = false  # the moon's ground is the natural law
	ok = _check("terraform scope: main and moon both declare nothing (natural law)", terra_ok) and ok

	var zone = zm.get_zone("zone_deep_root_camp")
	ok = _check("zone_deep_root_camp registered", zone != null) and ok
	if zone == null:
		quit(1)
		return
	ok = _check("zone names a subworld (world_id = underworld)", \
		str(zone.world_id) == "underworld") and ok
	ok = _check("zone is excluded from planar law", not zm._zone_is_planar(zone)) and ok

	# The planar NPC placement pass must skip the Warden entirely.
	sp.spawn_all_offering_npcs()
	var es = root.get_node_or_null("EntityService")
	var warden_count := 0
	if es != null:
		for ent in es.get_all_entities():
			if is_instance_valid(ent) and ent.get("npc_data") != null \
					and str(ent.npc_data.id) == "npc_deep_warden":
				warden_count += 1
				print("    planar Warden at ", ent.global_position)
	ok = _check("no planar Deep Warden after spawn_all_offering_npcs", \
		warden_count == 0) and ok

	# Other offering NPCs still spawn planar (the gate is not a nuke).
	var elder_ok := false
	if es != null:
		for ent in es.get_all_entities():
			if is_instance_valid(ent) and ent.get("npc_data") != null \
					and str(ent.npc_data.id) == "npc_village_elder":
				elder_ok = true
	ok = _check("village elder still spawns planar", elder_ok) and ok

	# A body parked exactly at the camp's subworld-frame center must
	# not be claimed by any planar detector or transition. Use a REAL
	# entity (spawn_npc_entity path) so can_enter() type checks hold.
	var warden_data = ds.get_npc("npc_deep_warden")
	var probe = null
	if warden_data != null:
		probe = sp.spawn_npc_entity("zone_deep_root_camp", Vector3(0, 2000, 0), warden_data)
	if probe == null:
		push_error("FAIL: could not spawn probe NPC")
		quit(1)
		return
	# spawn_npc_entity already parents the entity; just place it.
	probe.global_position = Vector3(0, 2000, 0)
	var claims = zm.check_seamless_transition(probe)
	ok = _check("camp center claims nothing planar", claims == null) and ok
	ok = _check("refuses planar transition into the camp", \
		not zm.perform_seamless_transition(probe, zone)) and ok
	probe.queue_free()

	if ok:
		print("PASS: world-scoping gate (%d checks)" % _checks)
		quit(0)
	else:
		push_error("FAIL: world-scoping gate")
		quit(1)
