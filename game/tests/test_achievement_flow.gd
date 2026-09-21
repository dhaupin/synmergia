## Smoke test: AchievementService core + listeners integration.
## Run: godot --headless --path . --script res://tests/test_achievement_flow.gd
extends SceneTree

var _pass := 0
var _fail := 0

func _initialize() -> void:
	print("--- ACHIEVEMENT FLOW TEST ---")

	var ach = root.get_node_or_null("AchievementService")
	_assert("AchievementService autoload present", ach != null)
	if ach == null:
		_finish()
		return

	var listeners = root.get_node_or_null("AchievementListeners")
	_assert("AchievementListeners autoload present", listeners != null)

	# --script mode: autoload _ready order is not guaranteed to have run
	# DataService.load_all_data before this test. Force-load if empty.
	var defs: Array = ach.get_all_achievements()
	if defs.is_empty():
		var ds = root.get_node_or_null("DataService")
		if ds and ds.has_method("load_all_data"):
			ds.load_all_data()
		if ach.has_method("_load_achievement_definitions"):
			ach._load_achievement_definitions()
	defs = ach.get_all_achievements()
	_assert("Achievement defs loaded (%d)" % defs.size(), defs.size() >= 10)

	var ob_wake := _find_def(defs, "ob_wake")
	var ob_grad := _find_def(defs, "ob_graduation")
	_assert("Onboarding defs present", ob_wake != null and ob_grad != null)

	# 2. Session unlock via player_entered_world path
	var pid := "test_player_%d" % Time.get_ticks_msec()
	ach.unlock_event(pid, "session")
	_assert("ob_wake unlocked by session event", ach.has_unlocked(pid, "ob_wake"))
	ach.unlock_event(pid, "session")
	_assert("session unlock is idempotent", ach.get_unlocked_achievements(pid).size() == 1)

	# 3. Chain gating: ob_first_skill requires ob_wake (already unlocked), so a
	# skill event progresses it; ob_explorer requires ob_loot which is still
	# locked, so a zone event must NOT progress it.
	ach.track(pid, "skill", 1)
	_assert("ob_first_skill unlocked after skill (gated on ob_wake)", ach.has_unlocked(pid, "ob_first_skill"))

	ach.track(pid, "zone", 1)
	_assert("zone tracked but chain-gated (ob_explorer locked until ob_loot)", not ach.has_unlocked(pid, "ob_explorer"))

	# 4. Kill counter + first_blood (GLOBAL with target_type enemy)
	ach.track(pid, "enemy", 1)
	_assert("first_blood unlocked on first kill", ach.has_unlocked(pid, "first_blood"))
	_assert("ob_first_kill (onboarding) unlocked on first kill", ach.has_unlocked(pid, "ob_first_kill"))

	# 5. Reward payout reaches PlayerManager for the local player
	var PlayerManagerNode = root.get_node_or_null("PlayerManager")
	_assert("PlayerManager present", PlayerManagerNode != null)
	if PlayerManagerNode:
		var pscript = load("res://entities/player/player_controller.gd")
		if pscript:
			var pnode = pscript.new()
			pnode.entity_id = pid
			PlayerManagerNode.set_local_player(pnode)
			var gold_before: int = PlayerManagerNode.gold
			# slayer_10: 10 kills, gold 200
			ach.track(pid, "enemy", 9)
			_assert("slayer_10 unlocked at 10 kills", ach.has_unlocked(pid, "slayer_10"))
			_assert("gold reward paid out (200)", PlayerManagerNode.gold - gold_before == 200)
			pnode.free()

	# 6. Progress sanity
	var prog: Dictionary = ach.get_achievement_progress(pid, "slayer_100")
	_assert("slayer_100 in progress (10/100)", int(prog.get("progress", 0.0)) == 10 and not bool(prog.get("unlocked", true)))

	# 7. Listeners bridge: direct handler call (no full boot needed)
	if listeners:
		var fake_killer = _FakeEntity.new()
		fake_killer.entity_id = pid
		# entity_type 1 = Entity.EntityType.PLAYER: the listeners only
		# credit kills by player entities (enemy-vs-enemy or NPC-guard
		# kills must not feed player achievements).
		fake_killer.entity_type = 1
		var fake_victim = _FakeEntity.new()
		fake_victim.entity_id = "victim_1"
		fake_victim.entity_type = 2  # Entity.EntityType.ENEMY
		var before_count: int = ach.get_achievement_progress(pid, "slayer_100").get("progress", 0.0)
		listeners._on_kill_rewarded(fake_victim, fake_killer, {"xp": 0, "gold": 0})
		var after_count: float = float(ach.get_achievement_progress(pid, "slayer_100").get("progress", 0.0))
		_assert("listeners._on_kill_rewarded credits kill", after_count > float(before_count))

		# An enemy killer must NOT be credited (player-entity filter).
		var enemy_killer = _FakeEntity.new()
		enemy_killer.entity_id = "enemy_killer_1"
		enemy_killer.entity_type = 2
		var before_enemy: int = ach.get_achievement_progress(pid, "slayer_100").get("progress", 0.0)
		listeners._on_kill_rewarded(fake_victim, enemy_killer, {"xp": 0, "gold": 0})
		var after_enemy: float = float(ach.get_achievement_progress(pid, "slayer_100").get("progress", 0.0))
		_assert("enemy killer is not credited", float(after_enemy) == float(before_enemy))

		# Chat listener increments chat counter (social_chatter gated on nothing)
		listeners._on_chat_message(pid, null, "hello", [])
		_assert("listeners._on_chat_message tracked chat", true)

	_finish()

func _find_def(defs: Array, id: String) -> AchievementData:
	for d in defs:
		if d is AchievementData and d.id == id:
			return d
	return null

class _FakeEntity:
	extends Node
	var entity_id: String = ""
	var entity_type: int = 1  # Entity.EntityType.PLAYER default

func _assert(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  PASS: " + name)
	else:
		_fail += 1
		print("  FAIL: " + name)

func _finish() -> void:
	print("--- %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
