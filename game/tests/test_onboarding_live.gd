## test_onboarding_live.gd - LIVE onboarding-chain verification in the playable
## scene. Run in RENDERING mode (watch it fire for real):
##
##   cd game && xvfb-run godot --path . --script res://tests/test_onboarding_live.gd
##
## The scene auto-accepts quest_wolves_hunt on boot. This SceneTree driver
## boots the playable scene, then exercises the REAL integration chain in
## the order a new player experiences it:
##
##   boot -> ob_wake (session, via player_entered_world)
##        -> skill cast -> ob_first_skill (CombatSystem.skill_executed)
##        -> kill via KillRewards.award_kill (the real Enemy._on_died path)
##             -> EventHub.kill_rewarded (rewards carry player_id)
##             -> world_playable HUD bridge (combat log + XP/gold float)
##             -> QuestService objective advance (kill_wolves 1/10)
##             -> AchievementService.track("enemy") -> first_blood + ob_first_kill
##             -> NotificationService toasts
##
## NOTE: the scene wolf's aggro range used to reach the player spawn and
## killed an idle player around frame 33. Fixed systemically: EnemyAI now
## enforces a spawn sanctuary (no fresh aggro near zone spawn/bind points,
## grudged players exempt). This test ASSERTS the fix: the player must
## still be alive at full health after the idle boot window.
## Exit 0 = every hop observed. Failures print FAIL lines and exit 1.
extends SceneTree

var _pass := 0
var _fail := 0
var _done := false
var _frames := 0

func _initialize() -> void:
	print("=== ONBOARDING LIVE TEST: booting playable scene ===")
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	if scene == null:
		print("  FAIL: could not load world_playable.tscn")
		quit(1)
		return
	var inst := scene.instantiate()
	root.add_child(inst)
	current_scene = inst

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 90:
		_run()
	return false

func _run() -> void:
	if _done:
		return
	_done = true
	var hub := root.get_node_or_null("EventHub")
	var qs := root.get_node_or_null("QuestService")
	var ach := root.get_node_or_null("AchievementService")
	var notif := root.get_node_or_null("NotificationService")
	if hub == null or qs == null or ach == null or notif == null:
		_mark_fail("autoloads missing (hub/qs/ach/notify)")
		return _finish()

	# --- 1. Record the hops as they fire -------------------------------
	var got := {
		"kill_rewarded": false,
		"quest_updated": false,
		"quest_completed": false,
		"first_blood": false,
		"ob_first_kill": false,
		"ach_toast": false,
		"quest_toast": false,
	}
	hub.kill_rewarded.connect(func(_e, _k, _r): got["kill_rewarded"] = true)

	# Ten credited kills advance kill_wolves to 10/10 -> completion.
	qs.quest_updated.connect(func(p, q, o, n):
		got["quest_updated"] = true
		print("    [hop] quest_updated %s %s %s -> %d" % [p, q, o, n]))
	qs.quest_completed.connect(func(_p, _q): got["quest_completed"] = true)

	ach.achievement_unlocked.connect(func(_p, aid):
		print("    [hop] achievement_unlocked: %s" % aid)
		if aid == "first_blood":
			got["first_blood"] = true
		elif aid == "ob_first_kill":
			got["ob_first_kill"] = true)

	notif.notification_sent.connect(func(_eid, n: Dictionary):
		var text := str(n.get("message", n.get("text", "")))
		if "Achievement" in text:
			got["ach_toast"] = true
		if "Quest" in text or "quest" in text:
			got["quest_toast"] = true)

	# --- 2. Verify scene boot state ------------------------------------
	# The player's entity_id is resolved from the node itself (never a
	# hard-coded string): it is "player_1" after the id-race fix, and the
	# same id QuestService accepted the starter quest under.
	var player := _find_player()
	_assert("player node present", player != null)
	if player == null:
		return _finish()
	var pid := str(player.entity_id)
	_assert("player entity_id stable and non-empty (got '%s')" % pid, pid != "")
	var active: Array = qs.get_active_quests(pid)
	_assert("starter quest accepted under real entity_id", active.has("quest_wolves_hunt"))

	# ob_wake (session) should already be unlocked from world entry.
	_assert("ob_wake unlocked at boot (session)", ach.has_unlocked(pid, "ob_wake"))

	# --- 3. Chain prerequisites: skill cast must come first ------------
	# ob_first_kill requires ob_first_skill; a kill alone can't unlock it.
	var skill = player.basic_attack
	_assert("player has basic_attack skill", skill != null)
	_assert("basic_attack castable now", skill.can_cast(player))
	# Script mode: resolve autoloads via /root (bare identifiers fail here).
	var combat := root.get_node_or_null("/root/CombatSystem")
	_assert("CombatSystem available", combat != null)
	if combat == null:
		return _finish()
	var result: Dictionary = combat.execute_skill(player, skill, null)
	_assert("skill executed (CombatSystem)", bool(result.get("success", false)))
	await process_frame
	await process_frame
	_assert("ob_first_skill unlocked via skill_executed", ach.has_unlocked(pid, "ob_first_skill"))

	# --- 4. Fire the REAL credited kill (KillRewards.award_kill) -------
	var wolf := _find_enemy("Wolf")
	_assert("Wolf present in scene", wolf != null)
	if wolf == null:
		return _finish()

	# The scene wolf used to be spawn-camped: its aggro range reached the
	# player spawn and the idle player died (~frame 33) before the test
	# window. The EnemyAI spawn-sanctuary rule now prevents exactly that,
	# so we ASSERT survival instead of hacking around it: the player must
	# still be alive at full health after the idle boot window.
	var hc = player.get("health_component")
	_assert("player alive after idle boot window (spawn sanctuary)",
		hc != null and not hc.is_dead())
	_assert("player at full health after idle boot (no spawn-camp damage)",
		hc != null and int(hc.current_health) == int(hc.max_health))

	# --- 4a. Kill chain first (highest-value assertions) ----------------
	# Prepare the slime probe deterministically: its IDLE state patrols at
	# a 1% per-frame chance, so during the boot window it may have drifted
	# out of its own 8.0 aggro radius (scan would miss the player no
	# matter what the grudge says). Freeze the brain and pin it 5 units
	# from the player: inside aggro range AND inside the sanctuary.
	var slime := _find_node("SlimeA")
	_assert("SlimeA present in scene", slime != null)
	if slime != null:
		if slime.get("_ai") != null and is_instance_valid(slime._ai):
			slime._ai.set_physics_process(false)
		slime.global_position = player.global_position + Vector3(5.0, 0.0, 0.0)

	var before_xp: int = int(player.experience)
	var before_gold: int = int(player.gold)
	var before_wolves: int = _wolf_progress(qs, pid)

	# Give the player credit the same way Enemy.take_damage does.
	wolf._last_damager = player
	# Drive the real death flow: health_depleted -> _on_died ->
	# loot roll + KillRewards.award_kill + despawn.
	wolf.health_component.current_health = 0
	wolf.health_component.health_depleted.emit()

	var frames2 := 0
	while frames2 < 15:
		await process_frame
		frames2 += 1

	# --- 4b. Assert every hop -------------------------------------------
	_assert("EventHub.kill_rewarded fired", got["kill_rewarded"])
	_assert("quest objective advanced (quest_updated)", got["quest_updated"])
	_assert("quest NOT completed at 1/10 (correct gate)", not got["quest_completed"])
	_assert("wolf progress incremented (QuestService)", _wolf_progress(qs, pid) == before_wolves + 1)
	_assert("first_blood unlocked", got["first_blood"])
	_assert("ob_first_kill unlocked (chain gate satisfied)", got["ob_first_kill"])
	_assert("achievement toast dispatched", got["ach_toast"])
	_assert("player granted kill XP", int(player.experience) > before_xp)
	_assert("player granted kill gold", int(player.gold) > before_gold)

	# --- 4c. Sanctuary semantics: no shield-abuse -----------------------
	# SlimeA sits 7.07 units from spawn (inside its 8.0 aggro range) with
	# its brain already frozen: fresh player -> no aggro (sanctuary
	# holds). Player attacks it -> grudge recorded via the REAL
	# Enemy.take_damage path -> grudge overrides sanctuary (no shield).
	if slime != null and slime.get("_ai") != null and is_instance_valid(slime._ai):
		var ai = slime._ai
		_assert("fresh player in sanctuary is not aggroed",
			ai._check_for_targets() == null)
		var before_slime_hp: int = int(slime.health_component.current_health)
		slime.take_damage(5, player)
		_assert("player attack landed on slime", int(slime.health_component.current_health) == before_slime_hp - 5)
		_assert("grudge recorded for attacking player",
			float(ai._known_threats.get(player.entity_id, 0.0)) > 0.0)
		_assert("grudged player re-aggroed despite sanctuary (no combat shield)",
			ai._check_for_targets() == player)

	_finish()

## Read the kill_wolves objective's current progress from quest state.
func _wolf_progress(qs, pid: String) -> int:
	var prog: Dictionary = qs.get_quest_progress(pid, "quest_wolves_hunt")
	var objectives: Array = prog.get("objectives", [])
	for obj in objectives:
		if str(obj.get("id", "")) == "kill_wolves":
			return int(obj.get("current", 0))
	return -1

func _find_player() -> Node:
	return _dfs(root, func(n: Node) -> bool:
		var s: Script = n.get_script()
		if s == null:
			return false
		var p := str(s.resource_path)
		return p.contains("player_controller"))

func _find_enemy(display: String) -> Node:
	return _dfs(root, func(n: Node) -> bool:
		return "display_name" in n and str(n.display_name) == display \
			and "enemy_data" in n)

func _find_node(node_name: String) -> Node:
	return _dfs(root, func(n: Node) -> bool:
		return str(n.name) == node_name)

func _dfs(n: Node, pred: Callable) -> Node:
	if n != root and pred.call(n):
		return n
	for c in n.get_children():
		var r = _dfs(c, pred)
		if r != null:
			return r
	return null

func _assert(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  PASS: " + name)
	else:
		_fail += 1
		print("  FAIL: " + name)

func _mark_fail(name: String) -> void:
	_fail += 1
	print("  FAIL: " + name)

func _finish() -> void:
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
