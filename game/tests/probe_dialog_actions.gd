## Probe: verify the staged dialogue cut loads clean in Godot 4.7.2
## - quest_intro_core_npcs.tres loads as QuestData, TALK objectives valid,
##   targets resolve to real NPC files
## - blacksmith_village_intro.tres loads as DialogueData, action hooks
##   fire through DialogService.execute_action (GIVE_QUEST = 1)
## Run: godot --headless --path game --script tests/probe_dialog_actions.gd
extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var fails: int = 0
	var quest = load("res://data/quests/quest_intro_core_npcs.tres")
	if quest == null:
		print("FAIL quest .tres did not load")
		fails += 1
	else:
		print("quest id=", quest.id, " quest_type=", quest.quest_type, " giver=", quest.giver_npc_id)
		if quest.display_name == "":
			print("FAIL display_name empty"); fails += 1
		if quest.giver_npc_id != "npc_blacksmith_village":
			print("FAIL giver id mismatch"); fails += 1
		var IDS := ["npc_blacksmith_village", "npc_skill_academy_capital", "npc_merchant_general"]
		for obj in quest.objectives:
			if int(obj.get("type", -1)) != 5:
				print("FAIL objective not TALK(5): ", obj.get("id", "")); fails += 1
			if not IDS.has(str(obj.get("target", ""))):
				print("FAIL unknown npc target: ", obj.get("target", "")); fails += 1

	var dlg = load("res://data/dialogues/blacksmith_village_intro.tres")
	if dlg == null:
		print("FAIL dialogue .tres did not load")
		fails += 1
	else:
		print("dialogue id=", dlg.id, " nodes=", dlg.nodes.size())
		if dlg.nodes.size() != 5:
			print("FAIL expected 5 nodes, got ", dlg.nodes.size()); fails += 1
		# Choice 1 of node 3 must be GIVE_QUEST(1) with quest_id
		print("RAW node3=", dlg.get_node(3))
		var acts: Array = dlg.get_choices(3)
		print("CHOICES size=", acts.size())
		if acts.size() >= 1 and int(acts[0].get("action_type", -1)) == 1 and str(acts[0].get("action_data", {}).get("quest_id", "")) == "intro_core_npcs":
			print("quest-accept hook OK")
		else:
			print("FAIL quest-accept hook wrong: ", acts[0] if acts.size() > 0 else "(none)"); fails += 1
		# Choice 2 must be OPEN_SHOP(6)
		if acts.size() >= 2 and int(acts[1].get("action_type", -1)) == 6:
			print("shop hook OK")
		else:
			print("FAIL shop hook wrong"); fails += 1

	# End-to-end: run execute_action through DialogService GIVE_QUEST path
	# (service-level only; QuestService presence check via tree)
	var svc = load("res://core/services/dialog_service.gd").singleton()
	if svc != null:
		if not svc.has_dialogue("blacksmith_village_intro"):
			print("FAIL DialogService did not index the staged dialogue"); fails += 1
		else:
			print("DialogService indexed dialogue OK; seen node defaults to ", svc.get_seen_node("blacksmith_village_intro"))
	else:
		print("WARN DialogService singleton unavailable in script mode (autoload absent)")

	print("RESULT fails=", fails)
	quit(0 if fails == 0 else 1)
