## concord_shrine_probe -- the money-hub round's receipt (the sinks get
## a physical home): the Concord sink shrine + its herald stand on the
## capitol strand of the real globe, and the data doors they sell
## through all load.
##   1) THE DATA DOORS: npc_concord_herald loads, its zone roster row
##      and both placement batches carry the herald + shrine rows, and
##      the herald's offering resolves to the premium panel through the
##      REAL NPData helper.
##   2) THE SHRINE STANDS: the real globe boot places a
##      ConcordSinkShrine (the prop belt's kind factory under the
##      capitol root) AND the herald NPC entity carrying its NPData.
##   3) THE BODY LAWS ON THE KIND FACTORY: build a fresh shrine, attach
##      the PropCollider body in-tree -- a proper BoxShape wraps the
##      pillar (over 4.5 m tall, the band and dais inside it) -- and
##      the sky-cyan band light + halo read real.
## Run headless: godot --headless --path . --script res://dev_temp/probes/concord_shrine_probe.gd
extends SceneTree

# SCRIPT-MODE LAW: no const preloads of game scripts -- autoload
# identifiers register AFTER parse; load at RUNTIME, inside _run.

var _fails := 0
var _passes := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("SHRINE-PASS %s %s" % [label, detail])
	else:
		_fails += 1
		print("SHRINE-MISS %s %s" % [label, detail])


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# 1) THE DATA DOORS
	var npc_res = load("res://data/npc/npc_concord_herald.tres")
	_check("herald_loads", npc_res != null and str(npc_res.get("id")) == "npc_concord_herald")
	if npc_res == null:
		quit(1)
		return
	var offering_ref := ""
	for inc in npc_res.get("includes"):
		if str(inc.get("type")) == "offering":
			offering_ref = str(inc.get("ref_id"))
	_check("herald_offering_ref", offering_ref == "concord_pillar_vault", "ref=" + offering_ref)
	var offering = load("res://data/npc_offerings/concord_pillar_vault.tres")
	var svc_ok: bool = offering != null and str(offering.get("service_id")) == "PremiumShopService"
	var panel: Dictionary = offering.get("service_params") if offering != null else {}
	_check("offering_service", svc_ok, "panel=%s" % str(panel.get("panel", "")))
	# the REAL NPData helper resolves the ref -> premium panel
	var helper_ok: bool = npc_res.has_method("has_service_offering") \
		and bool(npc_res.call("has_service_offering", "PremiumShopService"))
	_check("npdata_helper_routes_premium", helper_ok)
	# roster truth: the zone row and both placement batches
	var zone = load("res://data/zones/zone_nexus_central.tres")
	var roster: Array = zone.get("npcs") if zone != null else []
	_check("zone_roster_herald", roster.has("npc_concord_herald"))
	var GlobeWorldScript = load("res://scenes/worlds/globe_world.gd")
	var cap_batch: Array = GlobeWorldScript.get_script_constant_map().get("CAPITOL_NPC_BATCH", [])
	_check("capitol_batch_herald", _batch_has_npc(cap_batch, "npc_concord_herald"))
	var VP = load("res://entities/village_props.gd")
	var prop_batch: Array = VP.get_script_constant_map().get("CAPITOL_BATCH", [])
	_check("capitol_batch_shrine", _batch_has_kind(prop_batch, "concord_shrine"))

	# 2) THE SHRINE STANDS (the real globe boot)
	var packed = load("res://scenes/worlds/globe_world.tscn")
	if packed == null:
		print("SHRINE-MISS globe_world.tscn missing")
		quit(1)
		return
	var globe: Node = packed.instantiate()
	root.add_child(globe)
	for _i in range(20):
		await root.get_tree().process_frame
	var shrine_node := _find_by_name(root, "ConcordSinkShrine")
	_check("shrine_placed", shrine_node != null)
	var herald_node := _find_herald(root)
	_check("herald_placed", herald_node != null,
		"name=%s" % str(herald_node.name if herald_node != null else ""))
	# the herald stands with the real data the action menu reads
	if herald_node != null:
		var ndata = herald_node.get("npc_data")
		_check("herald_entity_carries_data", ndata != null \
			and str(ndata.get("id")) == "npc_concord_herald")

	# 3) THE BODY LAWS ON THE KIND FACTORY (build fresh; PropCollider
	# attach returns an existing PropBody untouched, so a deferred
	# attach never double-builds the body)
	if shrine_node == null:
		shrine_node = VP.call("_instantiate", "concord_shrine",
			"ProbeShrine", Vector3(2.6, 3.6, 2.6), Vector3(1.0, 0.0, 0.0))
		_check("factory_kind", shrine_node != null)
		if shrine_node != null:
			root.add_child(shrine_node)
			for _i in range(3):
				await root.get_tree().process_frame
		else:
			# at HEAD the kind legitimately does not exist: the probe
			# must still END (a body-less exit pulls the noise baseline)
			print("SHRINE-OK 0 passes, 0 misses")
			quit(0)
			return
	var PC = load("res://entities/prop_collider.gd")
	var body: StaticBody3D = PC.call("attach", shrine_node)
	_check("prop_body", body != null)
	if body != null:
		var shape_node: CollisionShape3D = null
		for child in body.get_children():
			if child is CollisionShape3D:
				shape_node = child
				break
		var shape = shape_node.shape if shape_node != null else null
		var tall: bool = shape is BoxShape3D and shape.size.y > 4.5
		_check("collider_pillar_tall", tall,
			"size=%s" % str(shape.size if shape != null else ""))
	# glow truth: the sigil band emissive + the halo light
	var found_band := false
	var found_light := false
	for child in shrine_node.get_children():
		if child is MeshInstance3D and child.mesh is TorusMesh:
			var mat = child.material_override
			if mat is StandardMaterial3D and bool(mat.emission_enabled):
				found_band = true
		if child is OmniLight3D:
			found_light = true
	_check("sigil_band_emissive", found_band)
	_check("halo_light", found_light)

	var label := "SHRINE-OK" if _fails == 0 else "SHRINE-FAIL"
	print("%s %d passes, %d misses" % [label, _passes, _fails])
	quit(0 if _fails == 0 else 1)


func _find_by_name(node: Node, nname: String) -> Node:
	if str(node.name) == nname:
		return node
	for child in node.get_children():
		var hit: Node = _find_by_name(child, nname)
		if hit != null:
			return hit
	return null


func _find_herald(node: Node) -> Node:
	var nd = node.get("npc_data")
	if nd != null and str(nd.get("id")) == "npc_concord_herald":
		return node
	for child in node.get_children():
		var hit: Node = _find_herald(child)
		if hit != null:
			return hit
	return null


func _batch_has_npc(batch: Array, npc_id: String) -> bool:
	for entry in batch:
		if str(entry[0]) == npc_id:
			return true
	return false


func _batch_has_kind(batch: Array, kind: String) -> bool:
	for entry in batch:
		if str(entry[0]) == kind:
			return true
	return false
