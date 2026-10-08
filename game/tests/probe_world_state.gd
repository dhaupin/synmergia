# probe_world_state.gd - V1 world-state engine slice.
#
# Covers:
#   A. The world delta primitive: set/get round-trip, provenance
#      (actor + epoch), key sanitation, refusal of empty writes.
#   B. Erasure is a delta: the cleared record stays auditable (who,
#      when), the live key is gone.
#   C. The agent-citizen law: a SYNTHETIC identity riding the SAME
#      write_entity path as a human projects and reads back
#      identically -- no side door, no species special-casing.
#   D. World namespaces: two worlds' zones project into disjoint
#      state; snapshot_for_world unions zone state + world deltas and
#      never bleeds across worlds; active_worlds tells the truth.
#
# Runs standalone (no autoloads): the projection is built directly,
# its ZoneManager/EntityService lookups fall through to their
# deterministic fallbacks.
extends SceneTree

var _checks: int = 0
var _fails: int = 0

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)

## set_world_state returns "" only on refusal; a wrong key here is a
## probe bug, so assert loudly before reading back.
func wls_set(ws, world: String, key: String, payload: Dictionary, actor: String, epoch: float) -> void:
	var k: String = ws.set_world_state(world, key, payload, actor, epoch)
	if k != key:
		print("  FAIL probe bug: set_world_state('%s', '%s') returned '%s'" % [world, key, k])

func _initialize() -> void:
	await process_frame
	await _run()
	quit(0 if _fails == 0 else 1)

func _run() -> void:
	var ProjectionScript = load("res://core/services/world_state_projection.gd")

	# Standalone projection: no tick loop, immediate writes.
	var proj = ProjectionScript.new()
	root.add_child(proj)
	await process_frame

	# -- A. The world delta primitive --------------------------------
	var ws = proj.world_state()
	_check("the primitive shares the projection's tree (one book, no side door)",
		ws != null and ws._state_tree == proj.state_tree())

	var k: String = ws.set_world_state("underworld", "gate/abyss_seal",
		{"state": "opened", "by": "quest_wolves_hunt"}, "player_1", 100.5)
	_check("a delta writes under its world and returns the sanitized key",
		k == "gate/abyss_seal")

	var got: Dictionary = ws.get_world_state("underworld", "gate/abyss_seal")
	var got_payload: Dictionary = got.get("payload", {}) if got.get("payload", {}) is Dictionary else {}
	_check("the delta reads back whole: payload, actor, epoch",
		str(got_payload.get("state", "")) == "opened" and str(got.get("actor", "")) == "player_1" \
		and float(got.get("epoch", 0.0)) == 100.5 and str(got.get("key", "")) == "gate/abyss_seal")

	_check("keys are sanitized (unsafe chars drop, the write still lands)",
		ws.set_world_state("main", "har vest;01", {"hp": 1}, "sys", 1.0) == "harvest01" \
		and not ws.get_world_state("main", "harvest01").is_empty())

	_check("empty payloads and empty keys never write",
		ws.set_world_state("main", "junk", {}, "sys", 1.0) == "" \
		and ws.set_world_state("main", "", {"x": 1}, "sys", 1.0) == "")

	# -- B. Erasure is a delta ---------------------------------------
	var cleared: String = ws.erase_world_state("underworld", "gate/abyss_seal", "gm_derek", 101.0)
	var cleared_state: Dictionary = ws.get_world_state("underworld", "gate/abyss_seal")
	var cleared_payload: Dictionary = cleared_state.get("payload", {}) if cleared_state.get("payload", {}) is Dictionary else {}
	_check("erasure replaces the live value with an auditable cleared record",
		cleared == "gate/abyss_seal" and bool(cleared_payload.get("cleared", false)) \
		and str(cleared_state.get("actor", "")) == "gm_derek")

	# -- C. The agent-citizen law ------------------------------------
	# A synthetic and a human ride the SAME write_entity path. The
	# projection reads the node from EntityService in the identity
	# drain; standalone, write_entity's direct path needs the data
	# handed in -- so both identities call it with identical shapes.
	var human: Dictionary = {
		"kind": "human", "display_name": "Tess", "level": 3,
		"current_health": 80, "max_health": 100,
	}
	var synthetic: Dictionary = {
		"kind": "synthetic", "display_name": "Cairn-1", "level": 3,
		"current_health": 80, "max_health": 100,
	}
	_check("the human and the synthetic project through the ONE chain",
		proj.write_entity("ws_human", human) \
		and proj.write_entity("ws_synth_1", synthetic))

	var h_read: Dictionary = proj.read_entity("ws_human")
	var s_read: Dictionary = proj.read_entity("ws_synth_1")
	var h_ident: Dictionary = h_read.get("identity", {}) if h_read.get("identity", {}) is Dictionary else {}
	var s_ident: Dictionary = s_read.get("identity", {}) if s_read.get("identity", {}) is Dictionary else {}
	var h_health: Dictionary = h_read.get("health", {}) if h_read.get("health", {}) is Dictionary else {}
	var s_health: Dictionary = s_read.get("health", {}) if s_read.get("health", {}) is Dictionary else {}
	_check("both identities read back under the same node shape (identity + health + world stamp)",
		str(h_ident.get("kind", "")) == "human" and str(s_ident.get("kind", "")) == "synthetic" \
		and int(h_health.get("current", -1)) == 80 and int(s_health.get("current", -1)) == 80 \
		and str(h_ident.get("world_id", "")) == "main" and str(s_ident.get("world_id", "")) == "main")
	_check("no worlds hold state before any zone stamps",
		proj.active_worlds().is_empty())

	# -- D. World namespaces -----------------------------------------
	# Two entities in different worlds' zones (the projection falls
	# back to unzoned/main without ZoneManager, so world stamps come
	# from explicit zones via _world_id_for_scope's fallback = main).
	# The world-level deltas are what make the namespaces distinct.
	ws.set_world_state("main", "siege/haven_wall", {"breach": true}, "player_2", 102.0)
	ws.set_world_state("moon", "harvest/regolith_1", {"depleted": true}, "syn_agent", 103.0)

	var main_keys: Array = ws.world_state_keys("main")
	var moon_keys: Array = ws.world_state_keys("moon")
	_check("world deltas namespace by world (main's keys, moon's keys, no bleed)",
		main_keys.has("siege/haven_wall") and not main_keys.has("harvest/regolith_1") \
		and moon_keys.has("harvest/regolith_1") and not moon_keys.has("siege/haven_wall"))

	var main_snap: Array = proj.snapshot_for_world("main")
	var moon_snap: Array = proj.snapshot_for_world("moon")
	var _ms_paths: Array = []
	for e in main_snap:
		_ms_paths.append(str(e[0]))
	var _mo_paths: Array = []
	for e in moon_snap:
		_mo_paths.append(str(e[0]))

	_check("snapshot_for_world carries the world's deltas",
		_ms_paths.has("world/w/main/state/siege/haven_wall") \
		and _mo_paths.has("world/w/moon/state/harvest/regolith_1"))

	_check("world snapshots never bleed (moon's siege, main's regolith: absent)",
		not _mo_paths.has("world/w/main/state/siege/haven_wall") \
		and not _ms_paths.has("world/w/moon/state/harvest/regolith_1"))

	_check("the summary stamps and reads back under the world prefix",
		ws.stamp_world_summary("moon", {"radius_m": 1200.0, "gravity": 6.0}) \
		and float(ws.world_summary("moon").get("radius_m", 0.0)) == 1200.0)

	# -- D2. The zone-union branch (real zone data) -------------------
	# zone_deep_root_camp carries world_id = "underworld" in data
	# truth. Load the REAL zones (script mode boots ZoneManager empty;
	# the game scene flow calls load_zones), then stamp through the
	# projection's zone->world bookkeeping, drop a node in its zone
	# scope, and the underworld snapshot must carry it while main's
	# must not (the cross-world bleed proof on the ZONE half, not just
	# the delta half).
	var zm: Node = root.get_node_or_null("ZoneManager")
	if zm != null and zm.has_method("load_zones"):
		zm.load_zones()
	proj._stamp_zone_world("zone_deep_root_camp")
	proj.state_tree().insert_state(
		"/world/zones/zone_deep_root_camp/entities/deep_warden/identity",
		"deep_warden", "other",
		{"kind": "enemy", "display_name": "Deep Warden", "level": 5, "world_id": "underworld"})
	var uw_snap: Array = proj.snapshot_for_world("underworld")
	var uw_paths: Array = []
	for e in uw_snap:
		uw_paths.append(str(e[0]).trim_prefix("/"))
	var main_paths: Array = []
	for e in proj.snapshot_for_world("main"):
		main_paths.append(str(e[0]).trim_prefix("/"))
	_check("a stamped zone's state unions into its world's snapshot",
		uw_paths.has("world/zones/zone_deep_root_camp/entities/deep_warden/identity"))
	_check("the zone half never bleeds across worlds either",
		not main_paths.has("world/zones/zone_deep_root_camp/entities/deep_warden/identity"))
	_check("active_worlds answers truthfully once zones stamp",
		proj.active_worlds().has("underworld") \
		and not proj.active_worlds().has("moon"))

	# The agent-citizen delta: a synthetic ACTOR writes world state
	# through the same primitive and the provenance reads back equal
	# to a human's -- the ledger does not care who held the pen.
	wls_set(ws, "moon", "camp/site_1", {"claimed": true}, "syn_cairn", 104.0)
	var by_agent: Dictionary = ws.get_world_state("moon", "camp/site_1")
	_check("a synthetic actor's world delta carries the same provenance shape as a human's",
		str(by_agent.get("actor", "")) == "syn_cairn" and float(by_agent.get("epoch", 0.0)) == 104.0)

	print("probe_world_state: %d checks, %d failures" % [_checks, _fails])
