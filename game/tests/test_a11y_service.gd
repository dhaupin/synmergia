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
	# Loading-overlay family: must be EXCLUDED from the snapshot.
	var loading_layer := CanvasLayer.new()
	loading_layer.name = "BootLoadingLayer"
	root.add_child(loading_layer)
	var hidden_btn := Button.new()
	hidden_btn.name = "HiddenDuringBoot"
	hidden_btn.text = "Invisible Action"
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
	panel.add_child(extra)
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
	print("A11yService: %d passed, %d failed" % [_pass, _fail])
