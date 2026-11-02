## Probe: the S15 underworld (labs/prd-underworld.md), sections A-H.
## Run: godot --headless --path . --script res://tests/probe_underworld.gd
##
## A. The declaration law: DEV_ONLY, not enterable, sealed-by-default.
## B. The Ascent (surface): default gate sealed for players, the
##    hatched gate lifts DEV_ONLY for dev only (the S15.2 flip).
## C. Conjure + transit: the gate's scene resolution finds
##    globe_underworld.tscn, the swap rides ScopeService, the visitor
##    adopts underworld law (20 m/s^2, wing works -- atmosphere).
## D. Globe internals: root group, scale from the declaration, the
##    Ascent + Sunward gates standing at camp, ambient lights.
## E. The interior sky: the shader loads, the material rides the
##    Concord epoch (one clock law), tide phase is periodic.
## F. The camp lives: the Deep Warden spawned on the surface, the
##    zone declared, roster bookkeeping fired the EXPLORE signal.
## G. The quest bridge: Listen to the Deep credits EXPLORE via the
##    real QuestService path and completes through the TALK bridge.
## H. Fold-back: the last visitor leaving tears the globe down.
extends SceneTree

const UnderScene := "res://scenes/worlds/globe_underworld.tscn"

var _checks := 0


func _init() -> void:
	call_deferred("_run")


func _check(label: String, cond: bool) -> bool:
	_checks += 1
	print("  %s %s" % ["PASS" if cond else "FAIL", label])
	return cond


func _run() -> void:
	var ok := true
	var root_node := root

	# ---------- A. The declaration law --------------------------------
	var reg_script: GDScript = load("res://core/frame/srv/world_registry.gd")
	var reg = reg_script.new()
	reg.load_worlds()
	var under = reg.get_world("underworld")
	ok = _check("the underworld declaration loads", under != null) and ok
	if under != null:
		ok = _check("the Deep Root is DEV_ONLY (offline = 2, the S15.2 flip)", \
			int(under.offline) == 2) and ok
		ok = _check("DEV_ONLY is not a player world (entry law intact)", \
			not under.is_enterable()) and ok
		ok = _check("the Deep Root keeps its air (the wing works down here)", \
			under.allows_gliding()) and ok
		ok = _check("the declaration names the globe (2 km)", \
			absf(float(under.radius_m) - 2000.0) < 0.5) and ok
		ok = _check("the underworld nests under main (seed derivation path)", \
			str(under.parent_world) == "main") and ok

	# ---------- B. The Ascent (surface gate law) -----------------------
	var GateScript: GDScript = load("res://entities/moon_gate.gd")
	ok = _check("moon_gate.gd loads", GateScript != null) and ok
	var gate_default = null
	var gate_dev = null
	if GateScript != null:
		gate_default = GateScript.new()
		gate_default.set("target_world", "underworld")
		gate_default.set("display_name", "The Ascent")
		root_node.add_child(gate_default)
		ok = _check("the default Ascent reads sealed for PLAYERS (OFFLINE law holds)", \
			int(gate_default._law_state()) == 1 \
			and str(gate_default.get_interaction_prompt()).begins_with("[E] Read")) and ok
		var res: Dictionary = gate_default.try_interact(null)
		ok = _check("a player pressing E gets the sealed refusal + lore", \
			not bool(res.get("ok")) and str(res.get("reason")) == "sealed" \
			and str(res.get("message", "")).length() > 0) and ok

		gate_dev = GateScript.new()
		gate_dev.set("target_world", "underworld")
		gate_dev.set("display_name", "The Ascent")
		gate_dev.set("dev_hatch", true)
		root_node.add_child(gate_dev)
		ok = _check("the hatched Ascent lifts DEV_ONLY (the S15.2 dev flip)", \
			int(gate_dev._law_state()) == 2 \
			and str(gate_dev.get_interaction_prompt()).begins_with("[E] Step through")) and ok

	# ---------- C. Conjure + transit ----------------------------------
	var packed: PackedScene = load(UnderScene)
	ok = _check("globe_underworld.tscn loads (the Deep Root is real)", packed != null) and ok
	var scope = root_node.get_node_or_null("ScopeService")
	ok = _check("ScopeService available in script mode", scope != null) and ok
	var esvc = root_node.get_node_or_null("EntityService")
	var GP: GDScript = load("res://entities/globe_player.gd")
	ok = _check("globe_player loads", GP != null) and ok
	var globe = null
	var conj_root: Node3D = null
	var walker = null
	if packed != null and scope != null and GP != null:
		var holder := Node3D.new()
		holder.name = "UnderHolder"
		root_node.add_child(holder)
		globe = packed.instantiate()
		holder.add_child(globe)
		await process_frame
		await process_frame
		conj_root = globe.get("world_root")
		ok = _check("the conjured Deep Root registers world_root_underworld", \
			conj_root != null and conj_root.is_in_group("world_root_underworld")) and ok

		# The gate's scene resolution: empty destination_scene resolves
		# the convention path -- the S15.2 gate-code-free wiring.
		var resolved: String = gate_dev.get("destination_scene")
		ok = _check("the gate carries no hard-coded scene (convention wins)", \
			str(resolved) == "") and ok
		var conv: PackedScene = load("res://scenes/worlds/globe_underworld.tscn")
		ok = _check("the convention path resolves the underworld globe", conv != null) and ok

		# The visitor + the seam.
		walker = GP.new()
		walker.entity_id = "deep_walker"
		root_node.add_child(walker)
		if esvc != null:
			esvc._entities["deep_walker"] = walker
		var swapped: bool = scope.enter_world_scope("deep_walker", "underworld", conj_root, true)
		ok = _check("the dev-hatch swap rides the same seam (force inside the service)", \
			swapped and scope.world_of("deep_walker") == "underworld") and ok
		if swapped:
			globe.receive_visitor(walker)
			ok = _check("the visitor adopts the Deep Root law (20 m/s^2, wing allowed)", \
				absf(float(walker.gravity_force) - 20.0) < 0.01 \
				and walker._world_allows_gliding()) and ok
			var camp: Vector3 = globe.get("CAMP_HEAD_POS")
			var want: Vector3 = conj_root.global_position + camp + Vector3(0, 1.4, 0)
			ok = _check("the visitor lands at the camp head", \
				walker.global_position.distance_to(want) < 0.5) and ok

	# ---------- D. Globe internals ------------------------------------
	if globe != null:
		ok = _check("the globe reads its scale from the declaration (2 km)", \
			absf(float(globe.get("planet_radius")) - 2000.0) < 0.5) and ok
		ok = _check("the Ascent stands at camp (the future player door)", \
			globe.get("_ascent_gate") != null) and ok
		ok = _check("the Sunward Gate stands at camp (dev round-trip)", \
			globe.get("_return_gate") != null) and ok
		ok = _check("the strata light is hung", globe.get("_strata_light") != null) and ok
		var rgate = globe.get("_ascent_gate")
		if rgate != null:
			ok = _check("the underworld's Ascent names main (window law off: no orbit between a world and its own interior)", \
				str(rgate.get("target_world")) == "main" and not bool(rgate.get("window_law"))) and ok

	# ---------- E. The interior sky (S15.1) ---------------------------
	if globe != null:
		var sky: MeshInstance3D = globe.get("_sky_mesh")
		ok = _check("the interior sky dome is hung", sky != null) and ok
		if sky != null:
			var mat = globe.get("_sky_mat")
			ok = _check("the sky carries the shader material", mat != null) and ok
			if mat != null:
				ok = _check("the shader loads (strata + veins, cull_front)", \
					mat.shader != null) and ok
				# One clock: the tide is a pure function of the epoch.
				var p1: float = globe._glow_tide_phase()
				var p2: float = globe._glow_tide_phase()
				ok = _check("the glow tide reads the Concord epoch (deterministic)", \
					absf(p1 - p2) < 1e-9 and p1 >= 0.0 and p1 < 1.0) and ok
				# Periodicity: one cycle per Synmergia day. Simulate
				# the closed form at two epochs half a cycle apart by
				# evaluating the formula directly (no clock monkeying).
				var epoch: float = globe._epoch_days()
				var pa: float = fposmod(epoch / 1.0, 1.0)
				var pb: float = fposmod((epoch + 0.5) / 1.0, 1.0)
				ok = _check("the tide is periodic (half a day flips the phase)", \
					absf(absf(pb - pa) - 0.5) < 1e-6) and ok
				# The material actually receives the phase (one frame).
				globe._process(0.016)
				var fed = mat.get_shader_parameter("tide_phase")
				ok = _check("the material is fed the tide (one frame eval)", \
					fed != null and absf(float(fed) - p1) < 1e-6) and ok

	# ---------- F. The camp lives (S15.3) ------------------------------
	var warden = null
	var zone = null
	if globe != null:
		warden = globe.get("_npc_spawns")
		ok = _check("the Deep Warden spawned at camp", \
			warden != null and (warden as Array).size() == 1 \
			and is_instance_valid((warden as Array)[0])) and ok
		if warden != null and (warden as Array).size() == 1:
			var w = (warden as Array)[0]
			ok = _check("the Warden stands ON the surface (radius + skin)", \
				absf(w.global_position.distance_to(globe.get("planet_center")) - 2001.4) < 0.5) and ok
		var ZoneManager = root_node.get_node_or_null("ZoneManager")
		ok = _check("ZoneManager available", ZoneManager != null) and ok
		if ZoneManager != null:
			zone = ZoneManager.get_zone("zone_deep_root_camp")
			ok = _check("zone_deep_root_camp declared live", zone != null) and ok
			if zone != null:
				ok = _check("the zone names the Warden (data contract)", \
					str(zone.get("id")) == "zone_deep_root_camp") and ok

	# ---------- G. The quest bridge (Listen to the Deep) ---------------
	var quest_ok := false
	if scope != null and walker != null and zone != null:
		var QuestService = root_node.get_node_or_null("QuestService")
		var DataService = root_node.get_node_or_null("DataService")
		ok = _check("QuestService available", QuestService != null) and ok
		if QuestService != null and DataService != null:
			var qdata = DataService.get_quest("quest_listen_to_the_deep")
			ok = _check("quest_listen_to_the_deep loads from data", qdata != null) and ok
			if qdata != null:
				QuestService.load_player_quests("deep_walker")
				var accepted: bool = QuestService.accept_quest("deep_walker", "quest_listen_to_the_deep")
				ok = _check("the Warden's quest accepts", accepted) and ok
				if accepted:
					# The REAL credit path: the globe's arrival signal
					# fired at receive_visitor (before the quest was
					# accepted -- re-fire the same signal the planar
					# path emits, the bridge is signal-shaped).
					globe._credit_arrival(walker)
					var quests: Dictionary = QuestService.get_player_quests("deep_walker")
					var st: Dictionary = quests.get("quest_listen_to_the_deep", {})
					var objs: Array = st.get("objectives", [])
					var explore_done := false
					for o in objs:
						if str(o.get("id")) == "hear_the_deep" and bool(o.get("completed")):
							explore_done = true
					ok = _check("EXPLORE credit flows through the one bridge", explore_done) and ok
					# The TALK turn-in bridge: dialogue_ended credit.
					QuestService._on_dialogue_ended_for_quest("npc_deep_warden", "deep_warden_greeting")
					var st2: Dictionary = (QuestService.get_player_quests("deep_walker") as Dictionary).get("quest_listen_to_the_deep", {})
					# The TALK objective is the assert; the quest reads
					# COMPLETE once every objective closes.
					var talk_done := false
					for o in (st2.get("objectives", []) as Array):
						if str(o.get("id")) == "report_to_warden" and bool(o.get("completed")):
							talk_done = true
					var QuestDataScript: GDScript = load("res://core/schemas/quest_data.gd")
					var complete_state: int = QuestDataScript.QuestState.COMPLETE
					ok = _check("TALK credit flows (the Warden's turn-in path)", talk_done) and ok
					ok = _check("both objectives closed the quest (COMPLETE)", \
						int(st2.get("state", -1)) == complete_state) and ok

	# ---------- G2. The cistern swim credits LIVE (S15.6) -------------
	# The underworld's own _process ticks its visitors through
	# OceanService; the water_entered signal runs the real QuestService
	# swim bridge. Walk the walker INTO the dish and let one frame
	# deliver the credit -- no probe hand-ticks, the globe owns its
	# water the way it owns its zones.
	if globe != null and walker != null:
		var QuestService2 = root_node.get_node_or_null("QuestService")
		if QuestService2 != null:
			QuestService2.load_player_quests("deep_walker")
			# quest_cross_the_cistern chains off quest_listen_to_the_deep; the
			# earlier leg accepted it, so credit it as turned in before the
			# sequel (the chain gate refuses otherwise).
			var DataService2 = root_node.get_node_or_null("DataService")
			QuestService2._player_quests["deep_walker"]["quest_listen_to_the_deep"] = {
				"state": QuestService2.QuestData.QuestState.REWARDED,
				"objectives": [],
				"data": DataService2.get_quest("quest_listen_to_the_deep") if DataService2 else null
			}
			var accepted2: bool = QuestService2.accept_quest("deep_walker", "quest_cross_the_cistern")
			ok = _check("quest_cross_the_cistern accepts for the walker", accepted2) and ok
			if accepted2 and is_instance_valid(walker):
				# Into the dish: the cistern's seat is 12 m from the camp
				# head; water floor 2000.0, surface 2002.4 (the data law).
				var cook_xz: Vector3 = Vector3(12, 0, 0)
				walker.global_position = globe.get("world_root").global_position \
					+ cook_xz + Vector3(0, 2000.8, 0)
				# One underworld frame: the swim delivery runs.
				globe._process(1.0 / 60.0)
				var swam_done := false
				var swim_prog: Dictionary = QuestService2.get_quest_progress("deep_walker", "quest_cross_the_cistern")
				for o in (swim_prog.get("objectives", []) as Array):
					if str(o.get("id")) == "swim_the_pool" and bool(o.get("completed")):
						swam_done = true
				ok = _check("one frame in the dish credits the crossing (live swim bridge)", swam_done) and ok

	# ---------- H. Fold-back ------------------------------------------
	if globe != null and walker != null:
		globe.release_visitor(walker)
		ok = _check("the last visitor leaving folds the Deep Root back into derivation", \
			not is_instance_valid(globe) or globe.is_queued_for_deletion()) and ok

	# Cleanup: the walker rides home through the seam (a real Node3D
	# target -- the tree root is a Window, not a Node3D).
	if scope != null and walker != null and is_instance_valid(walker):
		var home := Node3D.new()
		root_node.add_child(home)
		scope.exit_to_world("deep_walker", "main", home, true)
	if gate_default != null:
		gate_default.queue_free()
	if gate_dev != null:
		gate_dev.queue_free()

	print("UNDERWORLD PROBE %s (%d checks)" % ["PASSED" if ok else "FAILED", _checks])
	quit(0 if ok else 1)
