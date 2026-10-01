## probe_boot_loader_rect.gd - measures the boot loading overlay's real
## layout (play-test round 7: "loader is small in the upper left corner,
## not overlaying the viewport"). Reproduces the EXACT boot path:
## CanvasLayer(100) + LoadingUI.new() + show_loading, then prints the
## global rects of every layer of the stack so the mis-sized node is
## visible in numbers instead of theory.
## Run: godot --headless --path . --script res://tests/probe_boot_loader_rect.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _check(label: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fails += 1
	print(("  PASS: " if cond else "  FAIL: ") + label + ("  " + detail if detail != "" else ""))


func _rect_line(node: Node) -> String:
	var c := node as Control
	if c == null:
		return "(not a Control)"
	var r := c.get_global_rect()
	return "pos=%s size=%s anchors=(%.2f,%.2f,%.2f,%.2f) offsets=(%s,%s,%s,%s)" % [
		r.position, r.size,
		c.anchor_left, c.anchor_top, c.anchor_right, c.anchor_bottom,
		c.offset_left, c.offset_top, c.offset_right, c.offset_bottom,
	]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== BOOT LOADER RECT PROBE ===")
	root.mode = Window.MODE_MINIMIZED if false else root.mode

	# Exactly what GameManager._ensure_boot_loading_overlay does.
	var layer := CanvasLayer.new()
	layer.name = "BootLoadingLayer"
	layer.layer = 100
	root.add_child(layer)

	var LUI = load("res://ui/components/loading_ui.gd")
	var overlay: Control = LUI.new()
	overlay.name = "BootLoadingOverlay"
	layer.add_child(overlay)
	await process_frame
	await process_frame

	print("viewport size: ", root.get_visible_rect().size)
	print("overlay: ", _rect_line(overlay))
	_check("overlay covers the viewport",
		overlay.get_global_rect().size.distance_to(root.get_visible_rect().size) < 2.0,
		_rect_line(overlay))

	overlay.show_loading("probe: measuring...")
	await process_frame
	await process_frame

	var backdrop := overlay.get_node_or_null("Backdrop") as ColorRect
	if backdrop != null:
		print("backdrop: ", _rect_line(backdrop))
		_check("backdrop covers the viewport",
			backdrop.get_global_rect().size.distance_to(root.get_visible_rect().size) < 2.0,
			_rect_line(backdrop))
	else:
		_check("backdrop exists", false)

	# The stray auto-panel must be gone (round 6 fix holds on the boot path).
	_check("no stray auto Panel", overlay.get_node_or_null("Panel") == null)

	# Center stack: where does the spinner actually sit?
	var center := overlay.find_child("Center", true, false) as Control
	if center != null:
		print("center: ", _rect_line(center))
		var vp := root.get_visible_rect().size
		var cr := center.get_global_rect()
		_check("center stack covers viewport (children center in it)",
			cr.position.distance_to(Vector2.ZERO) < 2.0 and (cr.position + cr.size).distance_to(vp) < 2.0,
			"viewport=%s" % vp)
	else:
		_check("Center container exists", false)

	print("=== %d checks, %d failed ===" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
