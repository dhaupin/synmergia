extends SceneTree

## Dialogue -> Quest -> Reward receipt.
##
## Round 2 caught two real defects on the dialogue/quest lane:
##
##  BUG A (quest rewards never granted). QuestService._apply_rewards folded
##  the structured `rewards` array into a summary dict and THREW IT AWAY:
##  turn_in_quest marked the quest REWARDED but granted no XP, gold, item,
##  faction or title. Every shipped quest declares xp_reward/gold_reward
##  (and most also the `rewards` array) but the player was paid nothing.
##  Fix: fold BOTH authoring forms (array wins when present, scalars are
##  the fallback -- the catalog duplicates the values, so paying both would
##  double every reward) and GRANT the summary through the live services
##  plus the PlayerManager mirror, exactly like KillRewards does.
##
##  BUG B (dialog actions call nonexistent methods). DialogService.execute_action
##  called FollowService.cancel_follow (real: stop_follow), TitleService.unlock_title
##  (real: unlock), and InventoryService.add_item(player,item,qty) (the service
##  has no add_item; the ONE purse is the mounted component). GIVE_CURRENCY and
##  the REMOVE_* cases were log-only stubs. Fix: call the real endpoints and
##  route money/items through the mounted InventoryComponent.
##
## Run:
##   godot --headless --path . --script res://tests/test_dialogue_quest_reward.gd

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	# Autoload-lag law: the body runs on the first idle frame.
	call_deferred("_run")

func _ok(msg: String) -> void:
	_passed += 1
	print("[OK] " + msg)

func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL: " + msg)

func _run() -> void:
	var qs: Node = root.get_node_or_null("QuestService")
	var ds: Node = root.get_node_or_null("DataService")
	var inv_svc: Node = root.get_node_or_null("InventoryService")
	var pm: Node = root.get_node_or_null("PlayerManager")
	if qs == null or ds == null or inv_svc == null or pm == null:
		_fail("QuestService/DataService/InventoryService/PlayerManager autoloads missing")
		_finish()
		return
	_ok("services present")

	# --- Mount a probe player: a node with the wallet surface the world
	# pays (entity_id + gold + a mounted InventoryComponent) parked in the
	# PlayerManager local slot. A bare Node gains no properties from set(),
	# so the tiny dynamic script declares them (the economy receipt's law).
	var comp = load("res://core/components/inventory_component.gd").new()
	comp.set_owner_id("dq_probe")
	var player_script := GDScript.new()
	player_script.source_code = "extends Node\nvar entity_id: String = 'dq_probe'\nvar gold: int = 0\nvar experience: int = 0\nvar level: int = 1\nvar inventory_component = null\nfunc add_gold(a: int) -> void:\n\tgold += a\nfunc add_experience(a: int) -> void:\n\texperience += a\n"
	player_script.reload()
	var fake_player = player_script.new()
	fake_player.name = "DqProbePlayer"
	fake_player.inventory_component = comp
	root.add_child(fake_player)
	pm.set_local_player(fake_player)
	inv_svc.register_inventory("dq_probe", comp)
	pm.gold = 0
	pm.experience = 0

	# --- Leg 1: dialogue -> GIVE_QUEST -> quest accepted (the live seam).
	var ds_svc = ds
	var dial = root.get_node_or_null("DialogService")
	if dial == null:
		_fail("DialogService autoload missing")
		_finish()
		return
	var dlg = ds_svc.get_quest("quest_wolves_hunt")
	if dlg == null:
		_fail("quest_wolves_hunt not loaded")
		_finish()
		return
	var accepted: bool = qs.accept_quest("dq_probe", "quest_wolves_hunt")
	if not accepted:
		_fail("accept_quest rejected a level-1 quest")
		_finish()
		return
	_ok("quest accepted through QuestService.accept_quest")

	# --- Leg 2: progress the KILL objective to completion (the kill bridge
	# credits by enemy display_name; the quest targets "Wolf").
	qs.update_quest_progress("dq_probe", 0, "Wolf", 10)
	var prog: Dictionary = qs.get_quest_progress("dq_probe", "quest_wolves_hunt")
	if int(prog.get("state", -1)) != 3:
		_fail("quest did not reach COMPLETE after objectives filled (state=%s)" % str(prog.get("state")))
		_finish()
		return
	_ok("KILL objectives completed -> quest COMPLETE")

	# --- Leg 3: turn-in GRANTS the rewards (the bug: it granted nothing).
	var pm_gold_before: int = int(pm.gold)
	var pm_xp_before: int = int(pm.experience)
	var rewarded: bool = qs.turn_in_quest("dq_probe", "quest_wolves_hunt")
	if not rewarded:
		_fail("turn_in_quest rejected a COMPLETE quest")
		_finish()
		return
	# quest_wolves_hunt authors gold_reward=100 + rewards[{gold,100},{experience,150}].
	if int(pm.gold) != pm_gold_before + 100:
		_fail("quest gold not granted (want +100, got %d)" % (int(pm.gold) - pm_gold_before))
	else:
		_ok("quest gold granted exactly once (+100, no double-pay)")
	if int(pm.experience) != pm_xp_before + 150:
		_fail("quest XP not granted (want +150, got %d)" % (int(pm.experience) - pm_xp_before))
	else:
		_ok("quest XP granted exactly once (+150, no double-pay)")
	# The local node wallet got the same delta (node + PlayerManager mirror).
	if int(fake_player.gold) != 100:
		_fail("local node wallet did not receive quest gold (got %d)" % int(fake_player.gold))
	else:
		_ok("local player node wallet received the gold delta")

	# --- Leg 4: item rewards land in the mounted bag (the daily quest
	# carries item_sky_crate_daily).
	qs.accept_quest("dq_probe", "quest_watch_the_sky")
	qs.update_quest_progress("dq_probe", 11, "sky_insight", 1)
	if int(qs.get_quest_progress("dq_probe", "quest_watch_the_sky").get("state", -1)) != 3:
		_fail("daily quest did not reach COMPLETE")
		_finish()
		return
	qs.turn_in_quest("dq_probe", "quest_watch_the_sky")
	var got_item := false
	for it in comp.get_all_items():
		if it != null and str(it.id) == "item_sky_crate_daily":
			got_item = true
	if not got_item:
		_fail("quest item reward was not placed in the bag")
	else:
		_ok("quest item reward placed in the mounted inventory")

	# --- Leg 5: optional objectives never gate completion, and auto_complete
	# pays on the spot. quest_intro_core_npcs authors meet_blacksmith (required)
	# + meet_academy/meet_store (optional) and auto_complete = true; the
	# completion check demanded the optional ones, accept_quest dropped the
	# flag, and auto_complete was never read at all.
	var intro_gold_before: int = int(pm.gold)
	qs.accept_quest("dq_probe", "quest_intro_core_npcs")
	qs.update_quest_progress("dq_probe", 5, "npc_blacksmith_village", 1)
	var intro: Dictionary = qs.get_quest_progress("dq_probe", "quest_intro_core_npcs")
	if int(intro.get("state", -1)) != 4:
		_fail("required-only objective did not complete+auto-pay the quest (state=%s)" % str(intro.get("state")))
	else:
		_ok("optional objectives do not gate completion; auto_complete pays on the spot")
	if int(pm.gold) != intro_gold_before + 25:
		_fail("auto_complete did not grant the gold reward (want +25, got %d)" % (int(pm.gold) - intro_gold_before))
	else:
		_ok("auto_complete granted the gold reward exactly once")

	# --- Leg 6: dialog actions call real endpoints (BUG B).
	# STOP_FOLLOW: stop_follow exists and returns false when not following
	# (the old cancel_follow call was a silent no-op / nonexistent method).
	var DialogActionType = load("res://core/schemas/dialogue_data.gd").DialogActionType
	var sf_ok: bool = dial.execute_action(DialogActionType.STOP_FOLLOW, {}, "dq_probe")
	if sf_ok:
		_fail("STOP_FOLLOW reported success while not following")
	else:
		_ok("STOP_FOLLOW routes to the real FollowService.stop_follow (honest false)")
	# GIVE_ITEM: routes through the mounted component (was add_item on the
	# service, which has no such method).
	var gi_ok: bool = dial.execute_action(
		DialogActionType.GIVE_ITEM,
		{"item_id": "item_ancient_coin", "quantity": 2},
		"dq_probe")
	var coin_count := 0
	for it in comp.get_all_items():
		if it != null and str(it.id) == "item_ancient_coin":
			coin_count += 1
	if not gi_ok or coin_count < 1:
		_fail("GIVE_ITEM did not place the item through the mounted purse (ok=%s count=%d)" % [str(gi_ok), coin_count])
	else:
		_ok("GIVE_ITEM grants through the ONE purse")
	# GIVE_CURRENCY routes through the mounted purse (the ONE wallet the
	# component owns); the probe node wallet is a separate mirror here.
	var gold_before_currency: int = int(comp.get_gold())
	var gc_ok: bool = dial.execute_action(
		DialogActionType.GIVE_CURRENCY, {"amount": 30, "currency": "gold"}, "dq_probe")
	if not gc_ok or int(comp.get_gold()) != gold_before_currency + 30:
		_fail("GIVE_CURRENCY did not move gold (ok=%s gold=%d)" % [str(gc_ok), int(comp.get_gold())])
	else:
		_ok("GIVE_CURRENCY moves real gold")
	# REMOVE_ITEM: removes it back (was an unhandled enum case).
	var ri_ok: bool = dial.execute_action(
		DialogActionType.REMOVE_ITEM, {"item_id": "item_ancient_coin", "quantity": 1}, "dq_probe")
	if not ri_ok:
		_fail("REMOVE_ITEM did not remove the item")
	else:
		_ok("REMOVE_ITEM routes through the purse")

	inv_svc.unregister_inventory("dq_probe")
	pm.set_local_player(null)
	_finish()

func _finish() -> void:
	print("--- DIALOGUE/QUEST REWARD: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
