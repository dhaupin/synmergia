## Probe: the WorldMap GLOBE view (play-day pass 3: the flat equirect
## "map looks odd" near the poles). Headless script mode:
##   godot --headless --path game --script res://tests/probe_world_map_globe.gd
##
## Live-run contract (real UI nodes, no autoload dependency in the open
## path: MenuManager/InputManager lookups are null-safe in script mode):
##   G1. The flat canvas still generates row-chunked (no freeze) and
##       commits a texture.
##   G2. Toggling globe folds the equirect into an orthographic disk:
##       a DIFFERENT texture, generated row-chunked (never blocks), and
##       a completed fold (no stuck _globe_generating).
##   G3. The globe texture is square; the disk radius shrinks toward
##       the limb (opaque only inside a circle, transparent corners).
##   G4. The player marker in globe mode sits at the CSS center of the
##       square's drawn area (player-centered view => dot at center).
##   G5. Toggling back to flat restores the equirect texture.
extends SceneTree

var _fails: int = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		_fails += 1
		printerr("FAIL: " + label)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var WM = load("res://ui/components/world_map.gd")
	var map: Control = WM.new()
	root.add_child(map)
	await process_frame
	await process_frame

	# Full map open path (same entry the M key / button uses).
	map.expand_to_fullscreen()
	var gen_wait := 0
	while map.get("_generating") and gen_wait < 400:
		await process_frame
		gen_wait += 1
	_check(not map.get("_generating"), "flat canvas generation completes")
	_check(map.get("_canvas_texture") != null, "flat canvas commits a texture (G1a)")

	# Globe toggle.
	map.call("_toggle_globe_mode")
	_check(map.get("_globe_mode"), "toggle arms globe mode")
	var globe_wait := 0
	while map.get("_globe_generating") and globe_wait < 400:
		await process_frame
		globe_wait += 1
	_check(not map.get("_globe_generating"), "globe fold completes row-chunked (no stuck generator)")
	var globe_tex = map.get("_globe_texture")
	_check(globe_tex != null, "globe commits its own texture (G2)")
	_check(globe_tex is Texture2D and globe_tex.get_width() == globe_tex.get_height(), "globe texture is square (disk)")
	var globe_img: Image = (globe_tex as Texture2D).get_image()
	# Transparent outside the disk: corners must be transparent (G3).
	var gs: int = globe_img.get_height()
	_check(globe_img.get_pixel(0, 0).a < 0.05, "corner outside the disk is transparent")
	_check(globe_img.get_pixel(gs - 1, gs - 1).a < 0.05, "opposite corner outside the disk is transparent")
	_check(globe_img.get_pixel(gs / 2, gs / 2).a > 0.9, "disk center is painted")

	# Player marker rides the globe disk at the drawn center (G4).
	map.set_player_lat_lon(12.0, 34.0)
	await process_frame
	var mk: Control = map.get("_player_marker")
	var m_size: Vector2 = map.size
	var expected_x: float = maxf(0.0, (m_size.x - m_size.y) * 0.5) + m_size.y * 0.5 - mk.size.x * 0.5
	var expected_y: float = m_size.y * 0.5 - mk.size.y * 0.5
	_check(mk.position.distance_to(Vector2(expected_x, expected_y)) < 2.0,
		"globe marker sits at the disk center (player-centered)")

	# Toggle back to flat (G5).
	map.call("_toggle_globe_mode")
	_check(not map.get("_globe_mode"), "toggle returns to flat")
	await process_frame
	_check(map.get_node("Container/MapView/MapTexture").texture == map.get("_canvas_texture"),
		"flat mode restores the equirect texture")

	print("WORLD MAP GLOBE probe: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
