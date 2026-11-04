## test_sea_bar_hud_ready - THE SEABAR'S OWN _READY (S14.7.4).
##
## The SeaBar used to be verified only through a bare-script bar
## (update_from_body driven by hand). This receipt walks the REAL
## install seam: hud_layer.tscn instantiates, hud_layer.gd's own
## _ready() installs the chip (the _install_sea_bar leg), and the
## wet-truth legs read the INSTALLED bar -- the one the game's HUD
## actually carries -- plus the heartbeat through the bar's own
## _process (the poll law, wired to PlayerManager's local body).
##   1. _ready() installs SeaBar under the live HUD (named SeaBar),
##      hidden -- a dry body never sees it;
##   2. the installed bar tells the wet truth: band (SUBMERGED /
##      SQUEEZE / SURFACE SWIM), breath bar ratio, pressure pool,
##      the DROWNING flash, and dry hide;
##   3. the poll law: bind a wet body into PlayerManager's local
##      slot and the installed bar SHOWS ITSELF with no hand calls;
##      clear the slot and it hides again.
## Run: godot --headless --path game --script res://tests/test_sea_bar_hud_ready.gd
extends SceneTree

const POLL_WAIT_S: float = 0.45

var _passed := 0
var _failed := 0

func _ok(msg: String) -> void:
	_passed += 1
	print("   PASS  %s" % msg)

func _fail(msg: String) -> void:
	_failed += 1
	print("   FAIL  %s" % msg)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok(msg)
	else:
		_fail(msg)

func _finish() -> void:
	print("=== SEA BAR HUD READY RECEIPT: %d checks, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		print("SEA BAR HUD READY RECEIPT PASSED")
		quit(0)
	else:
		print("SEA BAR HUD READY RECEIPT FAILED")
		quit(1)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- SEA BAR (hud_layer._ready) RECEIPT ---")
	await process_frame

	var scene: PackedScene = load("res://ui/hud/hud_layer.tscn")
	if scene == null or not scene.can_instantiate():
		_fail("hud_layer.tscn did not load")
		_finish()
		return
	var hud := scene.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame

	# --- 1. THE INSTALL SEAM -------------------------------------------------
	var sea_bar: Control = hud.get_node_or_null("SeaBar")
	_check(sea_bar != null, "hud_layer._ready installs the SeaBar chip")
	if sea_bar == null:
		hud.queue_free()
		await process_frame
		_finish()
		return
	_check(str(sea_bar.name) == "SeaBar", "the chip is named SeaBar (the HUD dialect)")
	_check(not sea_bar.visible, "a dry body never sees it (hidden at install)")

	# --- 2. THE INSTALLED BAR TELLS THE WET TRUTH ---------------------------
	var wet_body := _sea_body(3, 55.0)
	root.add_child(wet_body)
	sea_bar.update_from_body(wet_body)
	_check(sea_bar.visible, "a wet body shows the installed bar")
	_check(sea_bar._band_label.text == "SQUEEZE", "the band row reads the squeeze")
	var breath_max: float = maxf(float(wet_body._sea_breath_max), 1.0)
	_check(absf(float(sea_bar._breath_bar.value) - (float(wet_body._sea_breath_s) / breath_max)) < 0.01,
		"the breath bar reads the book")
	_check(sea_bar._pressure_label.text.begins_with("Pressure"), "the pressure pool speaks")
	wet_body._sea_drowning_s = 2.0
	sea_bar.update_from_body(wet_body)
	_check(sea_bar._breath_label.text.contains("DROWNING"), "the drowning flash is honest")
	wet_body._sea_drowning_s = 0.0
	wet_body._sea_band = 2
	wet_body._sea_depth = 1.5
	sea_bar.update_from_body(wet_body)
	_check(sea_bar._band_label.text == "SURFACE SWIM", "the top-meter breath renames the band")
	sea_bar.update_from_body(null)
	_check(not sea_bar.visible, "a dry body hides the installed bar again")

	# --- 3. THE POLL LAW (the bar's own heartbeat) ---------------------------
	var pm: Node = root.get_node_or_null("PlayerManager")
	if pm == null:
		_fail("PlayerManager absent -- the poll law cannot be driven")
	else:
		pm.set_local_player(wet_body)
		var t0: float = Time.get_ticks_msec()
		while still_polling_possible(t0) and not sea_bar.visible:
			await process_frame
		_check(sea_bar.visible, "the heartbeat binds the local wet body (no hand call)")
		pm.set_local_player(null)
		t0 = Time.get_ticks_msec()
		while still_polling_possible(t0) and sea_bar.visible:
			await process_frame
	wet_body.queue_free()

	hud.queue_free()
	await process_frame
	_finish()

## Bounded poll loop guard: never wait longer than one poll cycle (~0.3 s).
func still_polling_possible(t0: float) -> bool:
	return float(Time.get_ticks_msec() - t0) < POLL_WAIT_S * 1000.0

## A globe_player-shaped swim book: the exact properties the SeaBar
## duck-reads (the stub the swim receipt rides too).
func _sea_body(band: int, depth: float) -> Node:
	var scr := GDScript.new()
	scr.source_code = "extends Node\nvar _sea_wet := true\nvar _sea_band := %d\nvar _sea_depth := %f\nvar _sea_breath_s := 20.0\nvar _sea_breath_max := 45.0\nvar _sea_drowning_s := 0.0\nvar _sea_pressure := 3.5\n" % [band, depth]
	scr.reload()
	return scr.new()

