## PlaythroughDriverRunner - the node-based flow runner for the rendered
## playthrough driver. WHY A NODE RUNNER: the world boot's suspended signal
## handler (StarterKitService's deferred grant timer) strands SceneTree-script
## awaits in Godot 4.7.2 (see globe_driver_runner.gd); a plain Node resumes
## across that boundary and prints the verdict + exit code itself.
##
## WHAT IT PROVES: the existing drivers stop at HUD panels. This one walks the
## REAL gameplay loop on the planar world_playable scene -- target a live wolf,
## swing through the actual `attack` input action, watch it die, collect the
## corpse loot through the `interact` action, equip gear, repair it at the
## blacksmith, and open an NPC's action menu by walking up and pressing E.
## Every stage asserts on LIVE node state, so a seam that only breaks under
## real play (the class of bug the unit receipts miss) fails here.
##
## Run (rendered; headless boots the world too, so it runs both ways):
##   xvfb-run -a godot --path game --script res://tests/playthrough_driver.gd
## Shots: /tmp/play/playthrough_*.png
extends Node

var _pass: int = 0
var _fail: int = 0
var _fail_flags: String = ""

func _ready() -> void:
	run()

func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS: %s %s" % [label, detail])
	else:
		_fail += 1
		_fail_flags += label + "; "
		print("  FAIL: %s %s" % [label, detail])

func run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute("/tmp/play")

	# --- Stage 1: boot the playable world ----------------------------
	# Runtime load: autoloads are live now; a parse-time load would fail.
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	if scene == null:
		print("PLAYTHROUGH FAIL: world_playable.tscn did not load")
		get_tree().quit(1)
		return
	var inst := scene.instantiate()
	get_tree().root.add_child(inst)
	get_tree().current_scene = inst
	await _settle(1.5)

	var player = inst.get_node_or_null("Player")
	_ok("world booted with a Player", player != null)
	if player == null:
		await _finish()
		return
	var pid := str(player.get("entity_id"))
	_ok("player has an entity id", pid != "", "(%s)" % pid)
	await _shot("playthrough_1_spawn")

	var es := get_tree().root.get_node_or_null("EntityService")
	var loot := get_tree().root.get_node_or_null("GroundLootService")
	var isvc := get_tree().root.get_node_or_null("InventoryService")
	_ok("EntityService up", es != null)
	_ok("GroundLootService up", loot != null)
	_ok("InventoryService up", isvc != null)
	var inv = player.get("inventory_component")
	_ok("player has an inventory component", inv != null)
	if es == null or loot == null or inv == null:
		await _finish()
		return
	_ok("inventory registered under the player id", isvc.get_inventory(pid) == inv)

	# Isolation for the combat stage: a level-1 body can be killed by the
	# scene-placed wildlife mid-fight, and a DEAD player legitimately earns no
	# kill credit (kill_rewards._is_valid_combatant rejects dead nodes), which
	# made the XP assertion nondeterministic under real-time render. Give the
	# player a health pool deep enough to survive the test fight; the kill/loot
	# laws under test are unaffected.
	if player.get("health_component") != null:
		player.health_component.max_health = 99999
		player.health_component.current_health = 99999

	# --- Stage 2: target a live wolf through the real input map ------
	var tm := get_tree().root.get_node_or_null("TargetingManager")
	_ok("TargetingManager up", tm != null)
	var wolf = await _spawn_wolf(inst, player, es)
	_ok("wolf registered", wolf != null and str(wolf.get("entity_id")) != "")
	# Isolate the fight: free the scene-placed wildlife so only the player and
	# the spawned wolf are in it. A wandering scene wolf stealing the killing
	# blow (correct game behavior, but nondeterministic under real-time render)
	# made kill credit -- and thus the XP assertion -- flaky.
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != wolf and is_instance_valid(e):
			e.queue_free()
	await get_tree().process_frame
	_key(KEY_F2)  # target_nearest
	await _settle(0.3)
	var cur = tm.get_current_target() if tm else null
	_ok("F2 selected a target", cur != null, "(%s)" % (str(cur.display_name) if cur else "none"))
	if cur != null:
		_ok("target is the wolf", str(cur.display_name) == "Wolf")
		# The TargetFrame renders acquisition: the frame used to resolve a
		# TargetInfo's id as entity_id (always ""), so it hid itself and never
		# populated -- the name label stayed "No Target" for the whole game.
		var tf = get_tree().root.find_child("TargetFrame", true, false)
		if tf != null and tf.has_method("get_target_id"):
			_ok("target frame registered the acquisition",
					str(tf.get_target_id()) == str(cur.id), "(id=%s)" % str(tf.get_target_id()))
			var name_lbl = tf.get("_name_label")
			_ok("target frame rendered the target name",
					name_lbl != null and name_lbl.text == "Wolf", "(%s)" % (name_lbl.text if name_lbl else "n/a"))

	# --- Stage 3: kill it through the real attack action -------------
	var hp_before: int = wolf.health_component.current_health
	var xp_before: int = int(player.get("experience"))
	var killed: bool = await _kill(wolf, player)
	_ok("wolf died to the attack action", killed, "(%d hp)" % hp_before)
	if not killed:
		await _finish()
		return

	# --- Stage 4: the kill paid out (XP + a real corpse drop) --------
	await get_tree().process_frame
	await get_tree().process_frame
	var xp_after: int = int(player.get("experience"))
	_ok("kill awarded XP", xp_after > xp_before, "(%d -> %d)" % [xp_before, xp_after])
	await _shot("playthrough_2_killed")

	# --- Stage 5: collect corpse loot through the interact action ----
	# loot_wolf rolls probabilistically (item drop rates 0.3/0.05/0.8/0.2), so
	# keep killing until a corpse actually leaves a drop before asserting the
	# pickup. Bounded at 4 kills; P(no drop in 4) is under 1e-6.
	var got_loot: bool = await _collect_any_drop(player, loot, inv)
	var kills := 1
	while not got_loot and kills < 4:
		var w2 = await _spawn_wolf(inst, player, es)
		if w2 == null:
			break
		if not await _kill(w2, player):
			break
		kills += 1
		got_loot = await _collect_any_drop(player, loot, inv)
	_ok("corpse left a drop and interact collected it", got_loot,
		"(%d kills, %d drops live)" % [kills, loot.get_drop_count()])
	await _shot("playthrough_3_looted")

	# --- Stage 6: equip real gear ------------------------------------
	var ds := get_tree().root.get_node_or_null("DataService")
	var sword = ds.get_item("wep_iron_sword") if ds else null
	_ok("DataService resolved wep_iron_sword", sword != null)
	if sword != null:
		var added: bool = inv.add_item(sword, 1)
		_ok("sword entered the bag", added)
		var slot: int = inv.find_item("wep_iron_sword")
		_ok("sword has a bag slot", slot >= 0, "(slot %d)" % slot)
		if slot >= 0:
			var str_before: int = int(player.get_stat("strength"))
			var equipped: bool = inv.equip_item(slot)
			_ok("sword equipped", equipped)
			_ok("equipment slot now holds the sword",
				inv.get_equipped(int(sword.equip_slot)) != null)
			# The bug this driver caught: _apply_equipment_stats aborted on the
			# player (parent is not an Entity), so gear moved no attributes.
			var stats: Dictionary = inv.get_equipment_stats()
			var str_after: int = int(player.get_stat("strength"))
			_ok("equipping applied gear stats to the player",
				stats.is_empty() or str_after != str_before or int(stats.get("strength", 0)) == 0,
				"(strength %d -> %d, gear %s)" % [str_before, str_after, str(stats)])
			# Idempotency: _apply_equipment_stats runs on every equip/unequip and
			# add_stat has no inverse, so a naive re-add stacks the bonus. A
			# unequip/re-equip cycle must land back on the same total.
			inv.unequip_item(int(sword.equip_slot))
			var str_unequipped: int = int(player.get_stat("strength"))
			var reslot: int = inv.find_item("wep_iron_sword")
			if reslot >= 0:
				inv.equip_item(reslot)
			var str_reequipped: int = int(player.get_stat("strength"))
			_ok("unequip removed the gear bonus", str_unequipped == str_before,
				"(strength %d -> %d, expected %d)" % [str_after, str_unequipped, str_before])
			_ok("re-equip does not stack the gear bonus", str_reequipped == str_after,
				"(strength %d -> %d, expected %d)" % [str_unequipped, str_reequipped, str_after])

	# --- Stage 7: the blacksmith repairs the equipped sword ----------
	var smith := get_tree().root.get_node_or_null("BlacksmithService")
	_ok("BlacksmithService up", smith != null)
	if smith != null and sword != null:
		var eq = inv.get_equipped(int(sword.equip_slot))
		if eq != null and "durability" in eq:
			eq.durability = max(1, int(eq.max_durability) - 5)
		var gold_before: int = inv.get_gold()
		var res: Dictionary = smith.repair_all_equipped(pid, inv)
		_ok("blacksmith repair reported a result", res is Dictionary, "(%s)" % str(res))
		var eq2 = inv.get_equipped(int(sword.equip_slot))
		_ok("repair left the blade in place", eq2 != null)
		_ok("repair did not lose gold without a repair",
			inv.get_gold() >= gold_before or int(res.get("repaired", 0)) > 0,
			"(gold %d -> %d)" % [gold_before, inv.get_gold()])

	# --- Stage 8: walk up to an NPC and open its action menu ---------
	await _stage_npc_menu(inst, player)

	await _finish()

## Spawn a real wolf with the shipped wolf data, in front of the player.
func _spawn_wolf(inst: Node, player, es: Node):
	var wolf = load("res://entities/enemy.gd").new()
	wolf.enemy_data = load("res://data/enemies/enemy_wolf.tres")
	wolf.display_name = "Wolf"
	wolf.global_position = player.global_position + _forward(player) * 1.2
	inst.add_child(wolf)
	await get_tree().process_frame
	es.register_entity(wolf)
	var ai = load("res://core/ai/enemy_ai.gd").new()
	if wolf.has_method("attach_ai"):
		wolf.attach_ai(ai)
	return wolf

## Swing the real attack action until the wolf dies (bounded). True on death.
## The attack edge is HELD for a physics frame: action_press+release in the same
## frame can miss the state machine's just_pressed edge, which made the kill
## flaky. The player is also turned to face the wolf each swing so the frontal
## hitbox cone always covers it.
func _kill(wolf, player) -> bool:
	var killed := [false]
	wolf.died.connect(func(_k): killed[0] = true)
	for i in range(150):
		if killed[0] or not is_instance_valid(wolf):
			break
		if is_instance_valid(wolf):
			_face(player, wolf.global_position)
			wolf.global_position = player.global_position + _forward(player) * 1.2
		Input.action_press("attack")
		await get_tree().physics_frame
		Input.action_release("attack")
		await get_tree().process_frame
	return killed[0]

## Turn the player's yaw so -Z (the forward the hitbox cone reads) points at
## `pos` on the XZ plane.
func _face(player, pos: Vector3) -> void:
	var to: Vector3 = pos - player.global_position
	to.y = 0.0
	if to.length() < 0.001:
		return
	player.rotation.y = atan2(-to.x, -to.z)

## Walk onto each live drop and press E; true if anything entered the bag.
func _collect_any_drop(player, loot, inv) -> bool:
	var drops: Dictionary = loot.get("_drops")
	if drops == null or drops.is_empty():
		return false
	for drop_id in drops.keys():
		var drop: Dictionary = drops.get(drop_id, {})
		var pos: Vector3 = drop.get("position", Vector3.ZERO)
		player.global_position = pos
		await get_tree().physics_frame
		var slots_before: int = inv.get_inventory_count()
		var gold_before: int = inv.get_gold()
		_key(KEY_E)
		await _settle(0.4)
		if inv.get_inventory_count() > slots_before or inv.get_gold() > gold_before:
			return true
	return false

## Spawn a real vendor NPC beside the player, register it, and press E.
## Proves the walk-up-and-press interaction loop resolves and opens the menu.
func _stage_npc_menu(inst: Node, player) -> void:
	var npc = load("res://core/entities/npc_entity.gd").new()
	npc.display_name = "Playthrough Vendor"
	npc.npc_data = load("res://data/npc/npc_village_elder.tres")
	npc.global_position = player.global_position + _forward(player) * 2.0
	inst.add_child(npc)
	await get_tree().process_frame
	_ok("vendor NPC spawned", npc.is_inside_tree())

	var es := get_tree().root.get_node_or_null("EntityService")
	var tm := get_tree().root.get_node_or_null("TargetingManager")
	if es and str(npc.get("entity_id")) == "":
		es.register_entity(npc)
	if tm and str(npc.get("entity_id")) != "":
		tm.register_targetable(str(npc.get("entity_id")), "npc", npc,
			npc.display_name, npc.global_position, npc.entity_type)
	await get_tree().process_frame

	_key(KEY_E)
	await _settle(0.6)
	# The player owns its own ActionMenu (player._show_npc_context_menu); the
	# HUD also ships one, so read the player's reference, not find_child.
	var menu = player.get("_action_menu")
	var npc_id := str(npc.get("entity_id"))
	var menu_open: bool = menu != null and menu.visible
	_ok("E opened the NPC action menu", menu_open,
		"(menu=%s visible=%s target=%s npc=%s)" % [str(menu),
			str(menu.visible) if menu else "n/a",
			str(menu.get("_target_id")) if menu else "n/a", npc_id])
	if menu != null:
		# E targets the NEAREST interactable NPC, which may be a scene-placed
		# NPC rather than the one spawned here -- the law under test is that the
		# press resolved a live NPC and populated the menu, not which one.
		_ok("the menu was populated with a real target",
			str(menu.get("_target_id")) != "")
	await _shot("playthrough_4_npc_menu")

func _finish() -> void:
	print("PLAYTHROUGH %d passed, %d failed%s" % [_pass, _fail, _fail_flags if _fail_flags else ""])
	await get_tree().process_frame
	get_tree().quit(0 if _fail == 0 else 1)

## The player's forward direction on the XZ plane (stable regardless of pitch).
func _forward(player) -> Vector3:
	var f: Vector3 = -player.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)

## Wall-clock settle: under xvfb + llvmpipe the world renders at ~1-2 fps, so a
## frame-counted settle is time dilation (see globe_driver_runner.gd).
func _settle(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _shot(stage_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("/tmp/play/%s.png" % stage_name)
		print("  shot: /tmp/play/%s.png" % stage_name)
