## One-shot probe: play-day round 2 UI fixes.
## A. ScrollFrame builds, scrolls, and shows/hides the overflow arrows.
## B. Settings panel got its header + close X (second header pass).
## C. MenuManager re-arms the touch HUD when a panel's own X closes it.
## D. Chat z sits above the panel stack.
extends SceneTree

var _checks := 0


func _check(label: String, cond: bool) -> bool:
	_checks += 1
	print("  %s %s" % ["PASS" if cond else "FAIL", label])
	return cond


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true

	# --- A. ScrollFrame -------------------------------------------------
	var SF = load("res://ui/components/scroll_frame.gd")
	var frame = SF.new()
	root.add_child(frame)
	var tall := VBoxContainer.new()
	for i in range(60):
		var lbl := Label.new()
		lbl.text = "row %d" % i
		lbl.custom_minimum_size.y = 24
		tall.add_child(lbl)
	frame.set_content(tall)
	await process_frame
	await process_frame
	var scroll = frame.get_node_or_null("Scroll")
	ok = _check("ScrollFrame hosts content", scroll != null and scroll.get_child_count() > 0) and ok
	await process_frame
	var down = frame.get_node_or_null("ScrollDownBtn")
	var up = frame.get_node_or_null("ScrollUpBtn")
	# Arrows are children 0 and 2 of the frame (built in _init).
	var kids: Array = frame.get_children()
	var up_btn = null
	var down_btn = null
	for k in kids:
		if k is Button:
			if str(k.text) == "^":
				up_btn = k
			elif str(k.text) == "v":
				down_btn = k
	ok = _check("down arrow visible on overflow", down_btn != null and down_btn.visible) and ok
	ok = _check("up arrow hidden at top", up_btn != null and not up_btn.visible) and ok
	if down_btn != null:
		# Headless viewport is 64 px tall: page by bar units, not size.
		var vbar2 = scroll.get_v_scroll_bar()
		scroll.scroll_vertical = int(vbar2.max_value * 0.5)
		await process_frame
		ok = _check("scrolled + arrows flipped", \
			scroll.scroll_vertical > 0 and up_btn.visible) and ok
		scroll.set_deferred("scroll_vertical", 0)
		await process_frame
		await process_frame
		ok = _check("return to top (up arrow hides)", \
			scroll.scroll_vertical <= 0 and not up_btn.visible) and ok
	frame.queue_free()

	# --- B/C/D. Panels via MenuManager (lives under HudLayer) -----------
	var HudLayerScript = load("res://ui/hud/hud_layer.gd")
	HudLayerScript.ensure_installed(root)
	# The deferred header pass on UI panels needs a frame to run.
	await process_frame
	await process_frame
	var hud = root.get_node_or_null("HudLayer")
	var mm = hud.get_node_or_null("MenuManager") if hud != null else null
	ok = _check("MenuManager available", mm != null) and ok
	if mm == null:
		quit(1)
		return

	var settings = hud.get_node_or_null("SettingsPanel") if hud != null else null
	ok = _check("SettingsPanel available", settings != null) and ok
	if settings != null:
		var panel = settings.get_node_or_null("Panel")
		var header = panel.get_node_or_null("Main/Header") if panel != null else null
		ok = _check("settings has standard header", header != null) and ok
		var x = header.get_node_or_null("CloseButton") if header != null else null
		ok = _check("settings has close X", x != null) and ok
		var title = header.get_node_or_null("Title") if header != null else null
		ok = _check("settings title reads 'Settings'", \
			title != null and title.text == "Settings") and ok

	var chat = mm.get_node_or_null("ChatUI")
	ok = _check("chat exists", chat != null) and ok
	if chat != null:
		ok = _check("chat z above panels (700 > 500)", int(chat.z_index) > 500) and ok

	# C. X-close re-arm: open character panel via the funnel, then close
	# it the way the X button does (panel.close() -> panel_closed ->
	# _on_panel_closed). The touch HUD must re-arm.
	var im = root.get_node_or_null("InputManager")
	var vj = im.get("_virtual_joystick") if im != null else null
	if vj != null and im.has_method("set_touch_hud_panels_open"):
		im.set_touch_hud_panels_open(true)
		ok = _check("panels_open disarms touch hud", vj._panels_open and not vj._enabled) and ok
		var char_panel = mm._get_panel("character")
		ok = _check("character panel resolvable", char_panel != null) and ok
		if char_panel != null:
			mm._open_menu_internal("character")
			ok = _check("panel tracks in _open_panels", mm._open_panels.has("character")) and ok
			char_panel.close()  # the X path
			await process_frame
			ok = _check("X-close clears _open_panels", not mm._open_panels.has("character")) and ok
			ok = _check("X-close re-arms touch hud", not vj._panels_open) and ok

	print("PASS: round-2 UI (%d checks)" % _checks) if ok else push_error("FAIL: round-2 UI")
	quit(0 if ok else 1)
