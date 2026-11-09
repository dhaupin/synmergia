## play_full_flow.gd - The WHOLE journey, played like a player plays it.
##
## Boots the project's real main scene and walks every screen in order:
##
##   main_menu -> [Start] -> login [Guest] -> lobby [Create] ->
##   character_select -> pick species (real card signal) -> class list
##   -> pick class (real card signal) -> [Play] -> linked character ->
##   lobby auto-play -> GameManager.PLAYING -> world -> combat + loot
##   + journal. (Round-6 menu: one Start button, one flow.)
##
## A second leg exercises the ACCOUNT flow end to end: register a real
## account through LoginService, land in the lobby, /create -> character
## select (creating_for_account) -> linked character -> auto-play from
## the lobby.
##
## Run (RENDERING mode for screenshots):
##   cd game && xvfb-run -a godot --path . --script res://tests/play_full_flow.gd
##
## Exit 0 = the full journey worked. Photos land in captures/screenshots/.
extends SceneTree

var _t := 0.0
var _schedule: Array = []      # [[time, Callable], ...]
var _pass := 0
var _fail := 0
var _shots := 0
var _journal: Array = []       # adventure log lines for the summary

# combat taps for the play leg
var _hit_outcomes := {}
var _dmg_dealt := [0]
var _crits := [0]
var _rewards := [0]
var _loot_drops := [0]

func _initialize() -> void:
	print("=== FULL-FLOW PLAY: booting like a player ===")
	# Classic-world beats (dummies, journal) live in the planar scene;
	# pin the shape so the shipped spherical default does not change the walk.
	ProjectSettings.set_setting("synmergia/world/shape", "planar")
	var err := change_scene_to_file("res://ui/menus/main_menu.tscn")
	if err != OK:
		print("  FAIL: could not open main_menu.tscn (err %d)" % err)
		quit(1)
		return
	_schedule = [
		[1.2, _leg1_menu],
		[1.5, _leg1_press_start],
		[2.3, _leg1_login_guest],
		[3.5, _leg1_lobby_create],
		[4.6, _leg1_char_select],
		[4.9, _leg1_pick_species],
		[5.2, _leg1_pick_class],
		[5.5, _leg1_press_play_btn],
		[7.5, _leg1_world_check],
		[7.8, _leg1_play_combat],
		[11.0, _leg1_world_journal],
		[11.3, _leg2_register],
		[12.5, _leg2_lobby],
		[12.8, _leg2_create],
		[13.8, _leg2_char_select],
		[14.1, _leg2_pick_species],
		[14.4, _leg2_pick_class],
		[14.7, _leg2_confirm],
		[17.7, _leg2_back_in_lobby],
		[18.3, _leg2_world_check],
		[18.9, _leg2_sweep_and_finish],
	]

func _process(delta: float) -> bool:
	_t += delta
	while not _schedule.is_empty() and _t >= float(_schedule[0][0]):
		var step: Array = _schedule.pop_front()
		(step[1] as Callable).call()
	return false

## ------------------------------------------------------------- framework

func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS: %s %s" % [label, detail])
	else:
		_fail += 1
		print("  FAIL: %s %s" % [label, detail])
	_journal.append("%s %s" % ["OK  " if cond else "FAIL", label])

func _scene() -> Node:
	return current_scene

func _gm() -> Node:
	return root.get_node_or_null("GameManager")

func _player() -> Node:
	var s := _scene()
	if s == null:
		return null
	# Shape-aware: the globe anchors its body on the scene node (`player`).
	var p: Node = s.get_node_or_null("Player")
	if p == null:
		p = s.get("player")
	if p == null:
		p = s.get_node_or_null("GlobePlayer")
	return p

func _press(node_path: String) -> void:
	var s := _scene()
	var btn: Button = s.get_node_or_null(node_path) if s else null
	if btn and not btn.disabled:
		btn.pressed.emit()
	else:
		print("  [journey] button missing/disabled: %s" % node_path)

func _shot(label: String) -> void:
	var ss = root.get_node_or_null("ScreenshotService")
	if ss == null:
		return
	var path: String = ss.save_dev_screenshot()
	if path != "":
		_shots += 1
		print("  [photo] %s -> %s" % [label, path.get_file()])

func _tap_outcome(outcome: Dictionary) -> void:
	var key := int(outcome.get("hit_result", 0))
	_hit_outcomes[key] = int(_hit_outcomes.get(key, 0)) + 1

func _outcome_summary() -> String:
	if _hit_outcomes.is_empty():
		return "(no swings)"
	var names := {0: "hit", 1: "miss", 2: "dodge", 3: "block", 4: "parry"}
	var parts: Array = []
	for key in _hit_outcomes.keys():
		parts.append("%s x%d" % [names.get(key, "?"), _hit_outcomes[key]])
	return ", ".join(parts)

## =================================================================
## LEG 1: main menu -> character select (direct play) -> world combat
## =================================================================

func _leg1_menu() -> void:
	print("--- leg 1: main menu ---")
	var s := _scene()
	_ok("main menu is current scene", s != null and s.name == "MainMenu")
	_shot("01_main_menu")

func _leg1_press_start() -> void:
	print("--- leg 1: start (round-6 single flow) ---")
	_press("MenuButtons/StartButton")

func _leg1_login_guest() -> void:
	var s := _scene()
	_ok("login reached via Start", s != null and s.name == "Login",
		"(scene %s)" % (s.name if s else "null"))
	_press("Center/Panel/Form/Buttons/GuestButton")

func _leg1_lobby_create() -> void:
	var s := _scene()
	_ok("lobby reached via guest login", s != null and s.name == "Lobby",
		"(scene %s)" % (s.name if s else "null"))
	_press("Center/Panel/VBox/Buttons/CreateButton")

func _leg1_char_select() -> void:
	var s := _scene()
	_ok("character select reached", s != null and s.name == "CharacterSelect")
	var gm := _gm()
	_ok("state CHARACTER_SELECT", gm != null and gm.current_state == gm.GameState.CHARACTER_SELECT)
	_shot("02_character_select")

func _leg1_pick_species() -> void:
	# Real UI path: press the first species card's Select button.
	var s := _scene()
	var container: Node = s.get_node_or_null("SpeciesContainer") if s else null
	if container == null or container.get_child_count() == 0:
		_ok("species cards rendered", false)
		return
	var card: Node = container.get_child(0)
	var btn: Button = card.get_node_or_null("Margin/VBox/SelectBtn")
	_ok("species card has select button", btn != null)
	if btn:
		btn.pressed.emit()
		print("  [journey] species card pressed (card 1 of %d)" % container.get_child_count())

func _leg1_pick_class() -> void:
	# After species selection the container is rebuilt with class cards.
	var s := _scene()
	await process_frame
	await process_frame
	var container: Node = s.get_node_or_null("SpeciesContainer") if s else null
	if container == null or container.get_child_count() == 0:
		_ok("class cards rendered", false)
		return
	# Debug: identify the rebuilt container's children.
	var child_names: Array = []
	for ch in container.get_children():
		child_names.append(str(ch.name) if ch.get_script() == null else "%s(%s)" % [ch.name, ch.get_script().resource_path.get_file()])
	print("  [journey] container after species pick: %s" % ", ".join(child_names))
	# Find the first card with a working class_selected signal path.
	for ch in container.get_children():
		if ch.get_script() != null and ch.has_node("Margin/VBox/SelectBtn"):
			var btn: Button = ch.get_node("Margin/VBox/SelectBtn")
			btn.pressed.emit()
			print("  [journey] class card pressed (%s)" % ch.name)
			return
	_ok("class card found in rebuilt container", false, "(children: %s)" % ", ".join(child_names))

func _leg1_press_play_btn() -> void:
	var s := _scene()
	var play: Button = s.get_node_or_null("PlayButton") if s else null
	_ok("play button enabled after class pick", play != null and not play.disabled)
	_press("PlayButton")

func _leg1_world_check() -> void:
	print("--- leg 1: entering world ---")
	var s := _scene()
	var in_world: bool = s != null and s.name == "GlobeWorld"
	_ok("world loaded via character select (globe)", in_world)
	var gm := _gm()
	_ok("state PLAYING", gm != null and gm.current_state == gm.GameState.PLAYING)
	var cd = gm.selected_character_data if gm else null
	_ok("selected_character_data carried class+species",
		cd != null and str(cd.class_id) != "" and str(cd.species_id) != "",
		"(%s/%s)" % [str(cd.species_id) if cd else "?", str(cd.class_id) if cd else "?"])
	_shot("03_world_entered")

func _leg1_play_combat() -> void:
	# PLAY: honest swings at the training dummy + skillbar check.
	var hub = root.get_node_or_null("EventHub")
	if hub == null:
		return
	hub.hit_resolved.connect(func(_a, _d, outcome, _s, _amt): _tap_outcome(outcome))
	hub.damage_dealt.connect(func(source, _t, amount: int, _dt, is_crit):
		var p := _player()
		if source != null and p != null and source == p:
			_dmg_dealt[0] += amount
			if is_crit:
				_crits[0] += 1)
	hub.kill_rewarded.connect(func(_e, _k, _r): _rewards[0] += 1)
	var gls = root.get_node_or_null("GroundLootService")
	if gls != null:
		root.get_node_or_null("EventHub").ground_loot_spawned.connect(
			func(_lid, _pos, _items): _loot_drops[0] += 1)

	var p := _player()
	_ok("player present after full journey", p != null)
	if p == null:
		return
	_ok("skillbar populated from class data", not p.skillbar.is_empty(),
		"(%d skill(s))" % p.skillbar.size())
	var dummies: Array = []
	for n in get_nodes_in_group("enemies"):
		if is_instance_valid(n) and str(n.display_name) == "Training Dummy":
			dummies.append(n)
	if dummies.is_empty():
		_ok("training dummy present", false)
		return
	var dummy: Node = dummies[0]
	dummy.global_position = p.global_position + Vector3(0, 0, -1.5)
	await process_frame
	var hp0: int = dummy.health_component.current_health
	for i in range(6):
		p.create_hitbox(p.basic_attack)
		await process_frame
		await process_frame
	var hp1: int = dummy.health_component.current_health
	_ok("combat works after the full journey", hp1 < hp0,
		"(%d dmg through armor)" % (hp0 - hp1))

func _leg1_world_journal() -> void:
	print("--- leg 1 journal ---")
	print("  Swing outcomes: %s" % _outcome_summary())
	print("  Damage dealt: %d (crits %d), kill rewards: %d" % [_dmg_dealt[0], _crits[0], _rewards[0]])
	_ok("damage was dealt in the world", _dmg_dealt[0] > 0)
	_ok("hit table produced outcomes", not _hit_outcomes.is_empty())
	_shot("04_combat")

## =================================================================
## LEG 2: register -> lobby -> create -> linked char -> auto-play
## =================================================================

func _leg2_register() -> void:
	print("--- leg 2: account flow ---")
	# Leave the world; simulate the end_game path back to the front door.
	var gm := _gm()
	gm.change_state(gm.GameState.MAIN_MENU)
	await process_frame
	await process_frame
	# Round-6 menu: the one Start button opens the login screen. A real
	# player presses Start, flips the form to REGISTER mode, fills it,
	# and submits.
	_press("MenuButtons/StartButton")
	await process_frame
	await process_frame
	# login.gd: switch to REGISTER mode, fill the form, submit.
	var s := _scene()
	_ok("login screen reached", s != null and s.name == "Login")
	var create_btn: Button = s.get_node_or_null("Center/Panel/Form/Buttons/RegisterButton") if s else null
	if create_btn:
		create_btn.pressed.emit()  # flips to REGISTER mode
		await process_frame
	var uname: LineEdit = s.get_node_or_null("Center/Panel/Form/UsernameField")
	var passwd: LineEdit = s.get_node_or_null("Center/Panel/Form/PasswordField")
	var dname: LineEdit = s.get_node_or_null("Center/Panel/Form/DisplayNameField")
	if uname == null or passwd == null:
		_ok("login form fields present", false)
		return
	var acc := "hero_%d" % (int(Time.get_unix_time_from_system()) % 1000000)
	uname.text = acc
	passwd.text = "hunter2hunter2"
	if dname:
		dname.text = "Journey"
	print("  [journey] registering account '%s'" % acc)
	var ls = root.get_node_or_null("LoginService")
	_ok("register accepted", ls != null and ls.register(acc, passwd.text, "Journey"))
	_shot("05_registered")

func _leg2_lobby() -> void:
	await process_frame
	var s := _scene()
	_ok("lobby reached after register", s != null and s.name == "Lobby")
	var gm := _gm()
	_ok("state LOBBY", gm != null and gm.current_state == gm.GameState.LOBBY)
	_shot("06_lobby")

func _leg2_create() -> void:
	_press("Center/Panel/VBox/Buttons/CreateButton")

func _leg2_char_select() -> void:
	var s := _scene()
	_ok("character select reached from lobby", s != null and s.name == "CharacterSelect")
	var gm := _gm()
	var creating: String = gm.get_meta("creating_for_account", "") if gm else ""
	_ok("creating_for_account meta set", creating != "", "(%s)" % creating)

func _leg2_pick_species() -> void:
	_leg1_pick_species()

func _leg2_pick_class() -> void:
	await process_frame
	await process_frame
	_leg1_pick_class()

func _leg2_confirm() -> void:
	var s := _scene()
	var play: Button = s.get_node_or_null("PlayButton") if s else null
	if play and not play.disabled:
		play.pressed.emit()

func _leg2_back_in_lobby() -> void:
	# The create path links the character to the account, returns to the
	# lobby, and the lobby auto-plays the fresh character via the
	# last_character_id meta. By now that auto-play has already fired, so
	# we verify the linkage trail instead of pressing anything.
	var gm := _gm()
	var creating: String = gm.get_meta("creating_for_account", "") if gm else ""
	_ok("creating_for_account meta cleared", creating == "")
	var acc_id := ""
	var ls = root.get_node_or_null("LoginService")
	if ls != null:
		acc_id = ls.get_current_account_id()
	var reg = root.get_node_or_null("AdapterRegistry")
	var found := false
	if reg != null and acc_id != "":
		var store = reg.get_persistence("characters")
		if store != null:
			var rows = store.query("SELECT value FROM kv WHERE key = $1", ["account:%s" % acc_id])
			if not rows.is_empty():
				var parsed = JSON.parse_string(str(rows[0].get("value", "")))
				if parsed is Dictionary:
					var list: Array = parsed.get(acc_id, [])
					found = list.size() > 0
	_ok("account has a persisted character", found, "(account %s)" % acc_id)
	_shot("07_account_character_linked")

func _leg2_world_check() -> void:
	print("--- leg 2: world via account flow ---")
	var s := _scene()
	var in_world: bool = s != null and s.name == "GlobeWorld"
	_ok("world loaded via lobby play (globe)", in_world)
	var gm := _gm()
	_ok("state PLAYING (account flow)", gm != null and gm.current_state == gm.GameState.PLAYING)
	var cd = gm.selected_character_data if gm else null
	_ok("character_id is account-linked", cd != null and str(cd.character_id) != "",
		"(id %s)" % str(cd.character_id) if cd else "")
	_shot("08_world_account_flow")

func _leg2_sweep_and_finish() -> void:
	# Final play beat: one swing + journal + goodbye.
	var p := _player()
	if p != null:
		var dummies: Array = []
		for n in get_nodes_in_group("enemies"):
			if is_instance_valid(n) and str(n.display_name) == "Training Dummy":
				dummies.append(n)
		if not dummies.is_empty():
			var dummy: Node = dummies[0]
			dummy.global_position = p.global_position + Vector3(0, 0, -1.5)
			await process_frame
			p.create_hitbox(p.basic_attack)
			await process_frame
			await process_frame
	print("--- FULL JOURNEY SUMMARY ---")
	print("  Swing outcomes: %s" % _outcome_summary())
	print("  Damage dealt: %d | crits: %d | kill rewards: %d | loot drops seen: %d" % [
		_dmg_dealt[0], _crits[0], _rewards[0], _loot_drops[0]])
	print("  Screenshots: %d" % _shots)
	_ok("journey completed with screenshots", _shots > 0)
	print("=== FULL-FLOW JOURNEY: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
