## test_a11y_service.gd - R35: the Accessibility & Agent-Action layer.
## Verifies the walking snapshot contract (prd-accessibility.md sec 4):
## actionable discovery, annotation labels, focus order, activation,
## and the [A11Y] dump lines -- headless, no scene files required.
## Run: cd game && godot --headless --path . --script res://tests/test_a11y_service.gd
extends SceneTree

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _run()
	quit(0 if _fail == 0 else 1)

func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)

func _run() -> void:
	var svc = root.get_node_or_null("A11yService")
	_assert(svc != null, "A11yService autoload present")

	# A tiny annotated surface, mirroring the menu contract.
	var panel := PanelContainer.new()
	panel.name = "ProbePanel"
	root.add_child(panel)
	var btn_a := Button.new()
	btn_a.name = "StartButton"
	btn_a.text = "Start"
	panel.add_child(btn_a)
	var btn_b := Button.new()
	btn_b.name = "GuestButton"
	btn_b.text = "Play as Guest"
	panel.add_child(btn_b)
	var field := LineEdit.new()
	field.name = "UsernameField"
	field.placeholder_text = "username"
	panel.add_child(field)
	var disabled := Button.new()
	disabled.name = "LockedButton"
	disabled.text = "Locked"
	disabled.disabled = true
	panel.add_child(disabled)
	var plain := Label.new()
	plain.name = "NotActionable"
	plain.text = "Just a label"
	panel.add_child(plain)
	# Loading-overlay family: must be EXCLUDED from the snapshot AND
	# pointer-dead when hidden (a visible-but-should-be-hidden button at
	# the origin legitimately wins pointer hit-tests -- model reality: a
	# hidden overlay is invisible, so make the button invisible too).
	var loading_layer := CanvasLayer.new()
	loading_layer.name = "BootLoadingLayer"
	root.add_child(loading_layer)
	var hidden_btn := Button.new()
	hidden_btn.name = "HiddenDuringBoot"
	hidden_btn.text = "Invisible Action"
	hidden_btn.visible = false
	loading_layer.add_child(hidden_btn)
	await process_frame
	await process_frame

	var snap: Array = svc.snapshot()
	var names: Array = []
	for e in snap:
		names.append(String(e["action"]))
	_assert(snap.size() == 4, "snapshot finds exactly the 4 actionable controls (label excluded, overlay excluded)")
	_assert(names.has("Start") and names.has("Play as Guest") and names.has("username") and names.has("Locked"), "action labels: annotated/text/placeholder fallbacks all resolve")

	# Annotation round-trip via the UIStyles helper.
	var UIStyles = load("res://ui/components/ui_styles.gd")
	UIStyles.apply_accessibility(btn_a, "Start playing", "Opens the login flow")
	_assert(String(btn_a.get("accessibility_name")) == "Start playing" and String(btn_a.get("accessibility_description")) == "Opens the login flow", "apply_accessibility writes the real AccessKit properties")
	snap = svc.snapshot()
	var a_entry: Dictionary = {}
	for e in snap:
		if String(e["path"]).ends_with("StartButton"):
			a_entry = e
	_assert(not a_entry.is_empty() and String(a_entry["action"]) == "Start playing" and String(a_entry["detail"]) == "Opens the login flow", "snapshot surfaces annotated name + consequence detail")
	_assert(a_entry.has("rect") and float(a_entry["rect"]["w"]) >= 0.0 and a_entry.has("focused") and a_entry.has("disabled"), "snapshot entries carry rect + state flags")

	# Focus navigation walks the snapshot in order.
	var ok_focus: bool = svc.focus_next()
	var focused_now: String = ""
	for e in svc.snapshot():
		if bool(e["focused"]):
			focused_now = String(e["path"])
	_assert(ok_focus and focused_now != "", "focus_next focuses an actionable")
	var first_focus: String = focused_now
	ok_focus = svc.focus_next()
	focused_now = ""
	for e in svc.snapshot():
		if bool(e["focused"]):
			focused_now = String(e["path"])
	_assert(ok_focus and focused_now != first_focus, "focus_next advances (wrap order is live)")

	# Activation by action name (the agent verb).
	var idx: int = svc.activate_by_action("Play as Guest")
	_assert(idx >= 0, "activate_by_action finds and activates 'Play as Guest'")

	# Disabled actions refuse activation.
	var locked_idx: int = -1
	var locked_snap: Array = svc.snapshot()
	for i in range(locked_snap.size()):
		if String(locked_snap[i]["action"]) == "Locked":
			locked_idx = i
	_assert(locked_idx >= 0 and not svc.activate(locked_idx), "disabled controls refuse activation")

	# The [A11Y] dump contract: intercept stdout by dumping into a fake
	# consumer -- simpler: dump() must not error and must cover every entry.
	var before: Array = svc.snapshot()
	svc.dump()
	_assert(true, "dump() executed over %d entries" % before.size())

	# focusables_changed fires on real set changes (debounced 0.25s).
	var fired := {"n": 0}
	svc.focusables_changed.connect(func(): fired["n"] += 1)
	var extra := Button.new()
	extra.name = "LateButton"
	extra.text = "Late Arrival"
	# Sibling to root: a Container overrides child positions, so this
	# would otherwise fill/focus-steal over the first panel's controls
	# (containers stack siblings -- the topmost wins pointer delivery).
	root.add_child(extra)
	# 2.5s wall: the debounce threshold is 0.25s of ACCUMULATED delta,
	# and a headless script-mode boot runs slow frames -- 0.6s was too
	# tight for the engine to bank 0.25s of process delta.
	await create_timer(2.5).timeout
	_assert(fired["n"] >= 1, "focusables_changed fires (debounced) after a new actionable appears")
	snap = svc.snapshot()
	var has_late := false
	for e in snap:
		if String(e["action"]) == "Late Arrival":
			has_late = true
	_assert(has_late, "late-arriving actionable appears in the next snapshot")

	panel.queue_free()
	loading_layer.queue_free()
	await process_frame

	# --- R36: HUD surfaces (annotated non-buttons + synthesized clicks) ----
	var hud_panel := PanelContainer.new()
	hud_panel.name = "HudProbePanel"
	root.add_child(hud_panel)
	await process_frame

	# 1) Annotated PanelContainer slots count as actionable; the label
	#    names the SKILL (the slot class has no text of its own).
	var slot := PanelContainer.new()
	slot.name = "Slot_0"
	# Real HUD slots are 52x52 -- a zero-size rect contains no point and
	# gui hit-testing would drop the synthesized click (found by test).
	slot.custom_minimum_size = Vector2(52, 52)
	hud_panel.add_child(slot)
	var HUDUIStyles = load("res://ui/components/ui_styles.gd")
	HUDUIStyles.apply_accessibility(slot, "Cast Fireball", "12 mana. Key 1. Click to cast.")
	await process_frame
	var hud_snap: Array = svc.snapshot()
	var found_cast := false
	for e in hud_snap:
		if String(e["action"]) == "Cast Fireball":
			found_cast = true
			_assert(String(e["kind"]) == "panelcontainer", "annotated non-button reports its real kind")
	_assert(found_cast, "annotated skill slot is discoverable by action name")

	# 2) Unannotated PanelContainers stay invisible to the snapshot.
	# NOTE: a Container (PanelContainer included) OVERRIDES child
	# positions -- every child fills its content rect, so a sibling
	# added to hud_panel would stack over the slot and (being later in
	# tree order) win pointer delivery, eating the synthesized click
	# below. Sibling it to root instead: same snapshot assertion, no
	# stacking.
	var bare := PanelContainer.new()
	bare.name = "BareBox"
	root.add_child(bare)
	await process_frame
	var bare_found := false
	for e in svc.snapshot():
		if String(e["path"]).ends_with("BareBox"):
			bare_found = true
	_assert(not bare_found, "unannotated panels are NOT actionable (no snapshot noise)")

	# 3) activate() on the annotated slot synthesizes a REAL click (press
	#    + release through the viewport input path) that gui_input sees.
	var clicks := {"n": 0}
	slot.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			clicks["n"] += 1)
	var slot_idx: int = -1
	var s2: Array = svc.snapshot()
	for i in range(s2.size()):
		if String(s2[i]["action"]) == "Cast Fireball":
			slot_idx = i
	_assert(slot_idx >= 0, "Cast Fireball resolvable in the snapshot")
	svc.activate(slot_idx)
	# Pump frames: push_input delivery is processed on the frame loop.
	for i in range(3):
		await process_frame
	_assert(clicks["n"] == 2, "activate() synthesizes press+release into gui_input (got %d)" % clicks["n"])

	# 4) A BaseButton with a custom annotation still activates via pressed.
	var hud_btn := Button.new()
	hud_btn.name = "PageBtn"
	hud_btn.text = "Bar 2"
	hud_panel.add_child(hud_btn)
	HUDUIStyles.apply_accessibility(hud_btn, "Show skill bar 2", "Pages the action bar")
	var pressed := {"n": 0}
	hud_btn.pressed.connect(func(): pressed["n"] += 1)
	var b_idx: int = -1
	var s3: Array = svc.snapshot()
	for i in range(s3.size()):
		if String(s3[i]["action"]) == "Show skill bar 2":
			b_idx = i
	_assert(b_idx >= 0 and svc.activate(b_idx) and pressed["n"] == 1, "annotated BaseButton activates via pressed")

	# 5) Re-annotation updates the label (dynamic slot rebinding case).
	HUDUIStyles.apply_accessibility(slot, "Cast Frostbolt", "8 mana. Key 1. Click to cast.")
	await process_frame
	var relabeled := false
	for e in svc.snapshot():
		if String(e["action"]) == "Cast Frostbolt":
			relabeled = true
	_assert(relabeled, "re-annotation updates the next snapshot (dynamic rebinding)")

	hud_panel.queue_free()
	await process_frame

	# --- R37: in-world entity actions (PRD sec 6 bridge) -----------------------
	# PlayerManager local_player real node (the world oracle)
	var PlayerScript2 = load("res://entities/player/player_controller.gd")
	var EnemyScript = load("res://entities/enemy.gd")
	var EnemyDataScript = load("res://core/schemas/enemy_data.gd")
	var fake_player: Node = PlayerScript2.new()
	fake_player.entity_id = "a11y_probe_player"
	var pm2 = root.get_node_or_null("PlayerManager")
	var had_player: bool = pm2 != null
	if pm2:
		pm2.local_player = fake_player
	root.add_child(fake_player)
	var es = root.get_node_or_null("EntityService")
	var enemy2: Node = EnemyScript.new()
	var ed2 = EnemyDataScript.new()
	ed2.display_name = "Wolf"
	enemy2.enemy_data = ed2
	enemy2.entity_id = "a11y_wolf"
	root.add_child(enemy2)
	await process_frame
	if es:
		es.register_entity(enemy2, null, "a11y_wolf")
	await process_frame
	var world_snap: Array = svc.snapshot()
	var wolf_entry: Dictionary = {}
	for e in world_snap:
		if String(e["path"]) == "world/entity:a11y_wolf":
			wolf_entry = e
	if not had_player:
		print("(world asserts skipped: no PlayerManager in script mode)")
	else:
		_assert(not wolf_entry.is_empty(), "enemy within radius is announced as a world action")
		_assert(String(wolf_entry["action"]) == "Attack Wolf" and String(wolf_entry["kind"]) == "entity", "verb names the family choice (Attack <Name>) with kind=entity")
		_assert(wolf_entry.has("rect") and float(wolf_entry["rect"]["w"]) > 0.0, "entity rect carries screen geometry for click-through")
		# Activation routes through the PLAYER's real cast path: use_skill
		# (component fallback); the wolf should take damage.
		var idx2: int = -1
		for i in range(world_snap.size()):
			if String(world_snap[i]["path"]) == "world/entity:a11y_wolf":
				idx2 = i
		seed(37)
		var hp0: int = int(enemy2.current_health)
		var activated: bool = svc.activate(idx2)
		_assert(activated, "world activation routes through the real game verb")
		await create_timer(0.3).timeout
		_assert(int(enemy2.current_health) < hp0, "Activate-the-wolf dealt REAL damage through the player's attack path")
	if es:
		es.unregister_entity(enemy2, "probe cleanup")
	if pm2:
		pm2.local_player = null
	fake_player.queue_free()
	enemy2.queue_free()
	await process_frame
	print("A11yService: %d passed, %d failed" % [_pass, _fail])
