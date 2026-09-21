## Headless smoke test: AchievementService + AchievementListeners contract.
## Run: godot --headless --path . --script res://tests/test_achievements.gd
## Exit 0 = pass, 1 = fail.
##
## NOTE: --script mode does not pre-load autoloads. The service and the
## listeners bridge are instantiated manually here and driven through
## their instance methods (not the static autoload shims), so no tree
## resolution is needed.
extends SceneTree

const AchievementServiceScript = preload("res://core/services/achievement_service.gd")
const AchievementDataScript = preload("res://core/schemas/achievement_data.gd")
const ListenersScript = preload("res://core/services/achievement_listeners.gd")

var _fails: int = 0
var _unlock_emissions: int = 0

func _count_unlock(_pid: String, _aid: String) -> void:
	# Member method (not a lambda): lambdas capture locals by value in
	# GDScript 4, so a captured counter would never increment.
	_unlock_emissions += 1

func _initialize() -> void:
	# Let autoloads finish their _ready pass (this test does not require
	# them, but tests that run after boot expect a settled tree).
	await process_frame
	_test_catalog_loads()
	_test_double_unlock_guard()
	_test_track_progress_and_completion()
	_test_chain_gating()
	_test_listener_helpers()
	_test_tres_catalog_integrity()
	if _fails == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		print("FAILED: %d test(s)" % _fails)
		quit(1)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		push_error("FAIL: " + msg)
	else:
		print("  ok: " + msg)

func _fresh_service() -> Node:
	var svc: Node = AchievementServiceScript.new()
	return svc

## ---------------------------------------------------------------------------
## 1. Catalog: DataService may be absent in --script mode; defs come from .tres
##    via the service's fallback loader. Verify the def list is non-empty and
##    every def resolves by id.
func _test_catalog_loads() -> void:
	print("== catalog ==")
	var svc := _fresh_service()
	svc._load_achievement_definitions()
	var defs: Array = svc.get_all_achievements()
	_assert(defs.size() > 0, "catalog loaded (%d defs)" % defs.size())
	var first = defs[0]
	_assert(svc.get_achievement(first.id) != null, "get_achievement resolves id")
	_assert(svc._find_def("no_such_achievement") == null, "unknown id returns null")
	svc.free()

## ---------------------------------------------------------------------------
## 2. Double-unlock guard: unlock twice, exactly one reward/announce cycle.
func _test_double_unlock_guard() -> void:
	print("== double unlock guard ==")
	var svc := _fresh_service()
	svc._load_achievement_definitions()
	var def = svc.get_achievement("ob_wake")
	_assert(def != null, "ob_wake def exists")
	_unlock_emissions = 0
	svc.achievement_unlocked.connect(_count_unlock)
	svc._do_unlock("test_char_a", "ob_wake")
	_assert(_unlock_emissions == 1, "first unlock emits once (got %d)" % _unlock_emissions)
	# Second attempt must be a no-op: no new signal, state intact.
	svc._do_unlock("test_char_a", "ob_wake")
	_assert(_unlock_emissions == 1, "second unlock does not re-emit (got %d)" % _unlock_emissions)
	_assert(svc.has_unlocked("test_char_a", "ob_wake"), "unlock recorded")
	svc.free()

## ---------------------------------------------------------------------------
## 3. track() increments, unlocks at target, only for matching target_type.
func _test_track_progress_and_completion() -> void:
	print("== track -> unlock ==")
	var svc := _fresh_service()
	svc._load_achievement_definitions()
	# slayer_10: PROGRESS, target_type "enemy", target 10.
	svc._track_event("test_char_b", "enemy", 4)
	_assert(not svc.has_unlocked("test_char_b", "slayer_10"), "4/10 no unlock")
	_assert(not svc.has_unlocked("test_char_b", "slayer_100"), "other enemy-defs not unlocked by partial progress")
	var prog: Dictionary = svc.get_achievement_progress("test_char_b", "slayer_10")
	_assert(int(prog.get("progress", 0)) == 4, "progress stored (4)")
	svc._track_event("test_char_b", "enemy", 6)
	_assert(svc.has_unlocked("test_char_b", "slayer_10"), "10/10 unlocks")
	_assert(not svc.has_unlocked("test_char_b", "slayer_100"), "independent def untouched")
	svc.free()

## ---------------------------------------------------------------------------
## 4. Chain gating: ob_graduation requires ob_explorer which requires
##    ob_first_kill (chain rooted at ob_wake). track() must not unlock
##    a def whose required_achievements are locked.
func _test_chain_gating() -> void:
	print("== chain gating ==")
	var svc := _fresh_service()
	svc._load_achievement_definitions()
	# Quest 1/3 satisfies ob_graduation's target but not its chain.
	svc._track_event("test_char_c", "quest", 1)
	_assert(not svc.has_unlocked("test_char_c", "ob_graduation"), "gated def does not unlock early")
	# Now walk the whole chain: session -> skill -> kill -> loot -> zones -> quests.
	svc._do_unlock_event("test_char_c", "session")   # ob_wake
	svc._track_event("test_char_c", "skill", 1)      # ob_first_skill
	svc._track_event("test_char_c", "enemy", 1)      # ob_first_kill
	svc._track_event("test_char_c", "item", 1)       # ob_loot
	svc._track_event("test_char_c", "zone", 1)       # ob_explorer
	svc._track_event("test_char_c", "quest", 3)      # ob_graduation (3 quests)
	_assert(svc.has_unlocked("test_char_c", "ob_wake"), "chain: ob_wake")
	_assert(svc.has_unlocked("test_char_c", "ob_first_skill"), "chain: ob_first_skill")
	_assert(svc.has_unlocked("test_char_c", "ob_first_kill"), "chain: ob_first_kill")
	_assert(svc.has_unlocked("test_char_c", "ob_loot"), "chain: ob_loot")
	_assert(svc.has_unlocked("test_char_c", "ob_explorer"), "chain: ob_explorer")
	_assert(svc.has_unlocked("test_char_c", "ob_graduation"), "chain: ob_graduation")
	svc.free()

## ---------------------------------------------------------------------------
## 5. Listener helper contracts (pure functions, safe to exercise headless).
func _test_listener_helpers() -> void:
	print("== listener helpers ==")
	var listeners: Node = ListenersScript.new()
	# player id extraction
	_assert(listeners._player_id_of("char_42") == "char_42", "player id from String")
	_assert(listeners._player_id_of(null) == "", "player id from null")
	var fake := Node.new()
	fake.set("entity_id", "char_7")
	_assert(listeners._player_id_of(fake) == "char_7", "player id from entity_id property")
	fake.free()
	# player-entity filter: a plain Node with entity_type=1 (PLAYER) passes,
	# entity_type=2 (ENEMY) is rejected.
	var p := Node.new()
	p.set("entity_type", 1)
	_assert(listeners._is_player_entity(p), "entity_type 1 is player")
	var e := Node.new()
	e.set("entity_type", 2)
	_assert(not listeners._is_player_entity(e), "entity_type 2 is not player")
	_assert(not listeners._is_player_entity(null), "null is not player")
	p.free()
	e.free()
	listeners.free()

## ---------------------------------------------------------------------------
## 6. .tres catalog integrity: every chain reference points at a real id,
##    every event category the bridge emits has at least one listener def.
func _test_tres_catalog_integrity() -> void:
	print("== catalog integrity ==")
	var svc := _fresh_service()
	svc._load_achievement_definitions()
	var ids := {}
	var categories := {}
	for def in svc.get_all_achievements():
		ids[def.id] = true
		categories[def.target_type] = true
		_assert(str(def.id) != "", "def has non-empty id")
	# Chain references resolve.
	for def in svc.get_all_achievements():
		for req in def.required_achievements:
			_assert(ids.has(req), "chain ref '%s' (required by %s) exists" % [req, def.id])
	# Event categories the listeners emit all have a def.
	for cat in ["session", "skill", "enemy", "boss", "elite", "player_kill",
			"item", "zone", "quest", "party", "guild", "trade", "chat"]:
		_assert(categories.has(cat), "catalog covers event category '%s'" % cat)
	svc.free()
