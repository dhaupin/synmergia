# probe_shipwreck_quay.gd - the shoreline content slice: the Shipwreck
# Quay arm (NPC offerings/dialogues/quest wiring) and the strait ferry
# data law (route ports exist, anchors sit on the authored chart).
#
# Covers:
#   A. Include-ref ownership: every ref_id loads, every dialogue_id is
#      a real loadable tree, every quest id in a quest offering is
#      real QuestData (the dangling salvor/ferry refs were the bug).
#   B. The chart: the three strait pins (moor, seaward, quay) sit ON
#      the authored corridor chart via the backend's own inverse
#      _chart -- never the zone-origin placeholder Vector3(0,0,0).
#   C. The ferry line: the barque's route_gateways resolve to gateway
#      data truth and the schedule integers are honest (6/day, SHIP).
#   D. The quest wiring: giver == Mag, turn_in == Brack, both sell the
#      offering, zone restriction matches both NPCs' zone.
#
# Data-truth discipline: content claims in .tres must resolve at load
# time; a dangling ref is a probe failure the moment it ships.
extends SceneTree

var _checks := 0
var _fails := 0

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  ok ", msg)
	else:
		_fails += 1
		push_error("FAIL: " + msg)
		print("FAIL: ", msg)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var DS = root.get_node_or_null("DataService")
	if DS == null:
		push_error("FATAL: no DataService")
		quit(1)
		return

	# ---- A. Include-ref ownership law --------------------------------------
	var strait_npcs := ["npc_salvor_wreck", "npc_ferryman_sundered"]
	for npc_file in strait_npcs:
		var npc_data: Resource = DS.get_npc(npc_file)
		_check(npc_data != null, "%s is data truth" % npc_file)
		if npc_data == null:
			continue
		for inc: Dictionary in npc_data.includes:
			var t := str(inc.get("type", ""))
			var ref_id := str(inc.get("ref_id", ""))
			var off: Resource = null
			if t == "offering" and not ref_id.is_empty():
				off = load("res://data/npc_offerings/%s.tres" % ref_id)
			var off_type := str(off.get("type")) if off != null else "?"
			if t == "offering" or off != null:
				_check(off != null, "%s include -> offering '%s' resolves (type=%s)" % [npc_file, ref_id, off_type])
			# Catalog law: every stock id resolves to real Item data.
			if off != null and str(off.get("type")) == "vendor":
				for entry: Dictionary in off.catalog_items:
					var iid := str(entry.get("item_id", ""))
					var it: Resource = DS.get_item(iid)
					_check(it != null, "%s vendor '%s' stock item '%s' resolves to Item data" % [npc_file, ref_id, iid])
					if it != null:
						_check(int(it.buy_price) >= 0 and int(it.sell_price) <= int(it.buy_price), "stock item '%s' pricing lawful (buy %d >= sell %d)" % [iid, int(it.buy_price), int(it.sell_price)])
					_check(int(entry.get("qty", 0)) > 0, "stock item '%s' has a lawful qty" % iid)
			if off != null and str(off.get("type")) == "quest":
				for qq: Variant in off.quest_ids:
						_check(DS.get_quest(str(qq)) != null, "quest offering '%s' resolves (quest data truth)" % str(qq))
			var dlg_id := str(inc.get("dialogue_id", ""))
			if t == "dialogue" and not dlg_id.is_empty():
				var dlg = load("res://data/dialogues/%s.tres" % dlg_id)
				_check(dlg != null, "%s dialogue '%s' resolves (loadable tree)" % [npc_file, dlg_id])
				if dlg != null:
					_check(dlg.nodes.size() >= 3, "%s dialogue tree has >= 3 nodes (%d)" % [dlg_id, dlg.nodes.size()])
					_check(str(dlg.npc_id) == str(npc_data.id), "dialogue npc_id == the owner NPC (%s)" % dlg_id)

	# ---- B. The chart law ---------------------------------------------------
	var Chart = load("res://core/services/strait_chart.gd")
	var Backend = load("res://scenes/worlds/backend_sundered.gd")
	var moor: Resource = DS.get_gateway("waypoint_strait_moor")
	var sea_gw: Resource = DS.get_gateway("waypoint_strait_seaward")
	var quay: Resource = DS.get_gateway("waypoint_shipwreck_quay")
	_check(moor != null and sea_gw != null and quay != null, "the three strait pins are data truth")

	# Round-trip: anchor_from_chart must invert the backend's own _chart.
	for x in [0.045, 0.06, 0.185, 0.31]:
		var d: Vector3 = Chart.dir_from_chart(x, 0.0)
		var ch: Vector2 = Backend._chart(d)
		_check(absf(ch.x - x) < 1e-4 and absf(ch.y) < 1e-6, "round-trip chart(%.3f) inverts within 1e-4 rad (got %.5f, %.5f)" % [x, ch.x, ch.y])

	# Pins sit inside the corridor band (x in (0.02, 0.40), |y| < 0.03)
	# and never at the zone-origin placeholder.
	if moor != null and sea_gw != null and quay != null:
		for gw in [moor, sea_gw, quay]:
			var d2: Vector3 = Vector3(gw.source_position).normalized()
			var ch2: Vector2 = Backend._chart(d2)
			_check(ch2.x > 0.02 and ch2.x < 0.40 and absf(ch2.y) < 0.03,
				"%s sits INSIDE the corridor band (x=%.3f y=%.3f)" % [gw.id, ch2.x, ch2.y])
		_check(moor.source_position.distance_to(sea_gw.source_position) > 500.0
			and moor.source_position.distance_to(quay.source_position) > 300.0,
			"the three pins are mutually distinct")
		_check(Vector3(moor.source_position).length_squared() > 4_000_000.0,
			"no pin authored at the zone-origin placeholder Vector3(0,0,0)")

	# ---- C. The ferry line: route ports are gateway data truth -------------
	var barque: Resource = DS.get_vehicle("veh_sundered_barque")
	_check(barque != null and int(barque.ferries_per_day) == 6, "the barque is scheduled data (6 crossings a day)")
	if barque != null:
		var route_ok := true
		for port_id: Variant in barque.route_gateways:
			route_ok = route_ok and DS.get_gateway(str(port_id)) != null
		var first_port: Resource = DS.get_gateway(str(barque.route_gateways[0]))
		_check(route_ok, "the barque's route ports resolve to real gateways")
		_check(first_port != null and int(first_port.gateway_type) == 4, "the barque sails from a SHIP-classed pin")

	# ---- D. The quest wiring -------------------------------------------------
	var quest: Resource = DS.get_quest("quest_shoal_freight")
	_check(quest != null, "quest_shoal_freight is data truth")
	if quest != null:
		var mag: Resource = DS.get_npc("npc_salvor_wreck")
		var brack: Resource = DS.get_npc("npc_ferryman_sundered")
		_check(str(quest.giver_npc_id) == "npc_salvor_wreck" and mag != null,
			"giver == Mag AND Mag is data truth (the giver party sells the quest)")
		_check(str(quest.turn_in_npc_id) == "npc_ferryman_sundered" and brack != null,
			"turn_in == Brack AND Brack is data truth")
		_check(str(quest.zone_restriction) == str(mag.zone_id),
			"zone restriction == the strait NPCs' zone (%s)" % str(quest.zone_restriction))
		_check(int(quest.gold_reward) > 0 and int(quest.xp_reward) > 0,
			"reward law: lawful gold+xp rewards (%d g / %d xp)" % [int(quest.gold_reward), int(quest.xp_reward)])

	if _fails == 0:
		print("SHIPWRECK QUAY PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("SHIPWRECK QUAY PROBE FAILED")
		quit(1)
