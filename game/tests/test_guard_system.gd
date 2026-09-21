## Guard system tests: per-player hostility, watch-group sharing,
## permanent grudges, ATTACKED trigger, and faction hostility.
## Covers the NPC/enemy hybrid contract: the guard is FRIENDLY to the
## world globally while HOSTILE to specific offenders.
extends SceneTree

## Runtime load() -- see test_loot_rules.gd note on parse-time preload
## of autoload-referencing scripts in --script mode.
var _guard_data_script: GDScript = null
var _guard_ai_script: GDScript = null
var _guard_script: GDScript = null

var _passed := 0
var _failed := 0


func _initialize() -> void:
	await process_frame
	_guard_data_script = load("res://core/schemas/guard_data.gd")
	_guard_ai_script = load("res://core/ai/guard_ai.gd")
	_guard_script = load("res://entities/guard.gd")
	_test_guard_data_factories()
	_test_hostility_is_per_player()
	_test_offense_shares_across_watch_group()
	_test_attacked_trigger_reports_offense()
	_test_grudge_is_permanent()
	_test_faction_hostility()
	_test_guard_entity_defaults()
	_test_guard_data_applied_to_entity()
	print("Guard tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


# --- helpers ---------------------------------------------------------------

func _mk_guard_data(group: String = "watch_test") -> Resource:
	var data: Resource = _guard_data_script.town_guard("guard_test", "Test Guard", "test_zone")
	data.watch_group = group
	return data


func _mk_guard_node(group: String = "watch_test"):
	var guard = _guard_script.new()
	guard.display_name = "Test Guard"
	guard.entity_id = "guard_%s" % str(group)
	root.add_child(guard)
	# Bypass _ready registration order issues: attach the AI directly.
	var ai = _guard_ai_script.new()
	ai.name = "GuardAI"
	guard.attach_ai(ai)
	guard._guard_ai = ai
	ai.setup(_mk_guard_data(group))
	return guard


# --- tests -----------------------------------------------------------------

func _test_guard_data_factories() -> void:
	var town: Resource = _guard_data_script.town_guard("g1", "Guard", "haven")
	_assert(str(town.watch_group) == "watch_haven", "town_guard derives watch group from zone")
	_assert(town.watches(_guard_data_script.WatchTrigger.ATTACKED), "town watch watches ATTACKED")
	_assert(town.watches(_guard_data_script.WatchTrigger.KILLING), "town watch watches KILLING")
	var house: Resource = _guard_data_script.house_guard("g2", "House Guard", "owner_1", ["friend_1"])
	_assert(str(house.owner_id) == "owner_1", "house guard owned by owner")
	_assert(house.allowed_player_ids.has("friend_1"), "house guard allowlist preserved")
	_assert(str(house.watch_group) == "", "personal guards keep their own watchlist")
	_assert(house.watches(_guard_data_script.WatchTrigger.TRESPASS), "house guard watches TRESPASS")


func _test_hostility_is_per_player() -> void:
	var guard = _mk_guard_node()
	var ai = guard._guard_ai
	_assert(not ai.is_hostile_to_player("p1"), "no hostility before offense")
	ai.mark_criminal("p1")
	_assert(ai.is_hostile_to_player("p1"), "offender marked hostile")
	_assert(not ai.is_hostile_to_player("p2"), "everyone else still un-hostile")
	# The entity face stays FRIENDLY: the world still sees an NPC.
	_assert(guard.relation == guard.Relation.FRIENDLY, "guard relation remains globally FRIENDLY")
	_assert(guard.entity_type == guard.EntityType.NPC, "guard presents as NPC globally")
	guard.free()


func _test_offense_shares_across_watch_group() -> void:
	var guard_a = _mk_guard_node("watch_shared")
	var guard_b = _mk_guard_node("watch_shared")
	_assert(guard_a._guard_ai.is_hostile_to_player("crime_1") == false, "watchlist empty before offense")
	guard_a._guard_ai.report_offense("crime_1", _guard_data_script.WatchTrigger.KILLING, "murder in the plaza")
	_assert(guard_a._guard_ai.is_hostile_to_player("crime_1"), "originating guard marks the offender")
	_assert(guard_b._guard_ai.is_hostile_to_player("crime_1"), "other guards in the watch group share the aggro")
	# A guard in a different watch does NOT inherit it.
	var guard_c = _mk_guard_node("watch_other")
	_assert(not guard_c._guard_ai.is_hostile_to_player("crime_1"), "unrelated watch does not inherit")
	guard_a.free()
	guard_b.free()
	guard_c.free()


func _test_attacked_trigger_reports_offense() -> void:
	var guard = _mk_guard_node()
	var ai = guard._guard_ai
	# Entity-based attacker stub (base on_damaged takes source: Entity).
	var attacker = load("res://tests/support/reward_enemy_stub.gd").new()
	attacker.name = "Attacker"
	attacker.entity_id = "aggressor_1"
	attacker.display_name = "Aggressor"
	root.add_child(attacker)
	ai.on_damaged(attacker)
	_assert(ai.is_hostile_to_player("aggressor_1"), "attacking a guard is itself a crime")
	attacker.free()
	guard.free()


func _test_grudge_is_permanent() -> void:
	var guard = _mk_guard_node()
	var ai = guard._guard_ai
	ai.mark_criminal("grudge_1")
	# Drive the decay pass -- criminal entries must be re-pinned.
	ai._decay_grudges()
	var tree = ai._get_memory_tree()
	if tree != null and ai._memory_agent_path != "":
		var mem: Dictionary = tree.get_memory(ai._memory_agent_path + "/events/criminal_grudge_1")
		if not mem.is_empty():
			_assert(absf(float(mem.get("weight", 0.0)) - 10.0) < 0.01, "criminal memory re-pinned at full weight after decay")
		# The watchlist itself never forgives.
		ai._decay_grudges()
		_assert(ai.is_hostile_to_player("grudge_1"), "grudge survives decay passes")
	# Pardon is an explicit admin-only hook, not a gameplay path.
	ai.pardon_player("grudge_1")
	_assert(not ai.is_hostile_to_player("grudge_1"), "admin pardon clears the watchlist entry")
	guard.free()


func _test_faction_hostility() -> void:
	var guard = _mk_guard_node()
	var ai = guard._guard_ai
	ai.guard_data.hostile_factions = ["undead_legion"]
	var foe = load("res://tests/support/reward_enemy_stub.gd").new()
	foe.name = "Foe"
	foe.entity_id = "faction_foe"
	foe.faction_id = "undead_legion"
	root.add_child(foe)
	_assert(ai._is_faction_hostile(foe), "faction member is hostile on sight")
	_assert(ai._is_valid_target(foe), "faction member is a valid target")
	var neutral = load("res://tests/support/reward_enemy_stub.gd").new()
	neutral.name = "Neutral"
	neutral.entity_id = "faction_neutral"
	neutral.faction_id = "town"
	root.add_child(neutral)
	_assert(not ai._is_faction_hostile(neutral), "non-listed faction left alone")
	_assert(not ai._is_valid_target(neutral), "innocent player is NOT a valid target")
	foe.free()
	neutral.free()
	guard.free()


func _test_guard_entity_defaults() -> void:
	var guard = _guard_script.new()
	guard._ready()
	_assert(guard.entity_type == guard.EntityType.NPC, "guard overrides Enemy's ENEMY type")
	_assert(guard.relation == guard.Relation.FRIENDLY, "guard overrides Enemy's HOSTILE relation")
	_assert(guard.get_interaction_prompt() == "Talk", "guard offers the NPC interaction prompt")
	guard.free()


func _test_guard_data_applied_to_entity() -> void:
	var guard = _mk_guard_node()
	var data: Resource = _mk_guard_data()
	data.level = 12
	data.health = 300
	guard.attach_guard_ai(data)
	_assert(guard.level == 12, "GuardData level mirrored onto entity")
	_assert(guard.max_health == 300, "GuardData health mirrored onto entity")
	_assert(guard._guard_ai != null, "GuardAI attached")
	_assert(guard._guard_ai.guard_data == data, "GuardAI holds the GuardData")
	guard.free()


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: %s" % msg)
		print("FAIL: %s" % msg)
