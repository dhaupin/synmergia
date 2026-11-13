## Regression test: the craft credit bridge (the forge's law).
##
## CraftingService emits craft_completed once per SUCCESSFUL craft with
## the recipe id; QuestService threads that signal into CRAFT objectives
## whose target is the recipe id verbatim ("recipe_"-prefixed). Before
## this bridge no CRAFT objective could ever advance -- craft_completed
## had NO consumers anywhere, so "The Copper Seam" (the smith's quest,
## which promises "he will show you what a green-veined rock is good
## for") could never deliver its payoff.
##
## Data contract under test: quest_copper_seam.tres is a COLLECT (Copper
## Ore x8) + CRAFT (recipe_copper_ingot x1) quest, offered by the village
## smith.
##
## Run: godot --headless --path . --script res://tests/test_quest_craft_bridge.gd

extends SceneTree

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root_node := get_root()
	var qs = root_node.get_node_or_null("QuestService")
	var cs = root_node.get_node_or_null("CraftingService")
	var inv_svc = root_node.get_node_or_null("InventoryService")
	var ds = root_node.get_node_or_null("DataService")
	if qs == null:
		_fail("QuestService autoload missing")
		_finish()
		return
	if cs == null:
		_fail("CraftingService autoload missing")
		_finish()
		return
	if inv_svc == null or ds == null:
		_fail("InventoryService/DataService autoload missing")
		_finish()
		return
	_ok("QuestService + CraftingService + InventoryService + DataService present")

	# The connect is DEFERRED (CraftingService is a later autoload; the
	# insight/swim/glide pattern) -- wait one flush before asserting.
	await process_frame
	if cs.craft_completed.is_connected(qs._on_craft_completed_for_quest):
		_ok("CRAFT bridge connected (craft_completed)")
	else:
		_fail("CRAFT bridge not connected")
		_finish()
		return

	# --- The .tres shape: one-id law, no candidate fallbacks -----------
	var qdata = load("res://data/quests/quest_copper_seam.tres")
	if qdata == null:
		_fail("quest_copper_seam.tres failed to load")
		_finish()
		return
	var objs: Array = qdata.objectives
	if objs.size() == 2:
		var collect_obj: Dictionary = objs[0]
		var craft_obj: Dictionary = objs[1]
		var collect_shape: bool = int(collect_obj.get("type", -1)) == qs.QuestData.ObjectiveType.COLLECT \
				and str(collect_obj.get("target", "")) == "Copper Ore" \
				and int(collect_obj.get("count", 0)) == 8
		_ok("COLLECT objective targets Copper Ore x8 verbatim" if collect_shape \
				else "COLLECT objective shape wrong: %s" % str(collect_obj))
		if not collect_shape:
			_failed += 1
		var craft_shape: bool = int(craft_obj.get("type", -1)) == qs.QuestData.ObjectiveType.CRAFT \
				and str(craft_obj.get("target", "")) == "recipe_copper_ingot" \
				and int(craft_obj.get("count", 0)) == 1
		_ok("CRAFT objective targets recipe_copper_ingot x1 verbatim" if craft_shape \
				else "CRAFT objective shape wrong: %s" % str(craft_obj))
		if not craft_shape:
			_failed += 1
	else:
		_fail("quest has %d objectives, expected 2" % objs.size())

	# --- The real accept path ---------------------------------------
	var pid := "craft_bridge_tester"
	qs.load_player_quests(pid)
	if not qs.accept_quest(pid, "quest_copper_seam"):
		_fail("the smith's copper quest did not accept")
		_finish()
		return
	_ok("quest_copper_seam accepts")

	# --- Seed a real purse: 2 copper ore (the ingot recipe's bill) ---
	var InvComp = load("res://core/components/inventory_component.gd")
	var bag = InvComp.new()
	bag.set_owner_id(pid)
	inv_svc.register_inventory(pid, bag)
	var copper_ore = ds.get_item("res_copper_ore")
	if copper_ore == null:
		_fail("res_copper_ore item missing from the catalog")
		_finish()
		return
	bag.add_item(copper_ore, 2)
	_ok("purse seeded with 2 copper ore")

	# --- The craft credits through the LIVE path --------------------
	# recipe_copper_ingot carries a 0.1 failure roll. This test proves the
	# BRIDGE, not the forge's RNG, so pin the roll to success for the
	# duration (restored at the end).
	var ingot_recipe = cs.get_recipe("recipe_copper_ingot")
	var iron_recipe = cs.get_recipe("recipe_iron_ingot")
	if ingot_recipe == null or iron_recipe == null:
		_fail("copper/iron ingot recipe missing")
		_finish()
		return
	var saved_ingot_rate: float = float(ingot_recipe.failure_rate)
	var saved_iron_rate: float = float(iron_recipe.failure_rate)
	ingot_recipe.failure_rate = 0.0
	iron_recipe.failure_rate = 0.0

	var result: Dictionary = cs.craft(pid, "recipe_copper_ingot")
	if not bool(result.get("ok", false)):
		_fail("the ingot craft did not succeed (results=%s)" % str(result.get("results", [])))
	else:
		_ok("recipe_copper_ingot crafts from the purse")
	var prog: Dictionary = qs.get_quest_progress(pid, "quest_copper_seam")
	var craft_current := -1
	for o in (prog.get("objectives", []) as Array):
		if str(o.get("id", "")) == "smelt_the_seam":
			craft_current = int(o.get("current", 0))
	if craft_current == 1:
		_ok("one craft_completed ticked the CRAFT objective 1/1")
	else:
		_fail("CRAFT objective current=%d, expected 1" % craft_current)

	# A SECOND craft of the same recipe must not over-tick a completed
	# objective (the one-id law: the objective is done, credit stops).
	bag.add_item(copper_ore, 2)
	cs.craft(pid, "recipe_copper_ingot")
	prog = qs.get_quest_progress(pid, "quest_copper_seam")
	var craft_steady := -1
	for o in (prog.get("objectives", []) as Array):
		if str(o.get("id", "")) == "smelt_the_seam":
			craft_steady = int(o.get("current", 0))
	if craft_steady == 1:
		_ok("a second craft does not over-tick the completed objective")
	else:
		_fail("over-tick from a second craft (current=%d)" % craft_steady)

	# A DIFFERENT recipe must not credit this quest's target: craft an
	# iron ingot (its own recipe id) and assert the copper objective holds.
	bag.add_item(ds.get_item("res_iron_ore"), 2)
	cs.craft(pid, "recipe_iron_ingot")
	prog = qs.get_quest_progress(pid, "quest_copper_seam")
	var craft_other := -1
	for o in (prog.get("objectives", []) as Array):
		if str(o.get("id", "")) == "smelt_the_seam":
			craft_other = int(o.get("current", 0))
	if craft_other == 1:
		_ok("an unrelated recipe does not credit the copper objective")
	else:
		_fail("cross-recipe credit leaked (current=%d)" % craft_other)

	ingot_recipe.failure_rate = saved_ingot_rate
	iron_recipe.failure_rate = saved_iron_rate

	_finish()

func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] ", msg)

func _fail(msg: String) -> void:
	_failed += 1
	print("  [FAIL] ", msg)

func _finish() -> void:
	print("--- QUEST CRAFT BRIDGE: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
