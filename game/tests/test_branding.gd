## test_branding.gd - Brand asset loader + menu/loading integration.
##
## Exercised through the dir seam (no repo mutation): a temp dir with
## runtime-generated PNGs proves the drop-in contract, then the SHIPPED
## pack in assets/branding/ is verified directly.
##
## Run: cd game && godot --headless --path . --script res://tests/test_branding.gd
extends SceneTree

const BrandScript = preload("res://core/utils/branding.gd")
const SHIP_DIR := "res://assets/branding/"

var _fails := 0
var _asserts := 0
var _tmp_dir := ""


func _init() -> void:
	call_deferred("_run")


func _ok(label: String, cond: bool) -> void:
	_asserts += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _run() -> void:
	await process_frame
	_test_empty_dir_falls_back()
	await _test_drop_in_pickup()
	_test_shipped_pack()
	_cleanup()
	print("--- test_branding: %d asserts, %d failures ---" % [_asserts, _fails])
	quit(0 if _fails == 0 else 1)


func _make_png(path: String) -> bool:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.7, 0.9, 0.85))
	var err := img.save_png(path)
	return err == OK


func _test_empty_dir_falls_back() -> void:
	# Fresh empty dir = "no pack yet": every lookup null, text fallback.
	_tmp_dir = "user://branding_test_%d/" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_tmp_dir)
	_ok("empty dir: emblem null", BrandScript.emblem(_tmp_dir) == null)
	_ok("empty dir: lockup null", BrandScript.lockup(_tmp_dir) == null)
	_ok("empty dir: has_pack false", not BrandScript.has_pack(_tmp_dir))


func _test_drop_in_pickup() -> void:
	# Drop one real PNG with the shipped name: loader picks it up
	# without any import step (the direct-decode path).
	_ok("png written", _make_png(_tmp_dir + "logo-synmergia-emblem.png"))
	var tex: Texture2D = BrandScript.emblem(_tmp_dir)
	_ok("drop-in emblem picked up", tex != null)
	_ok("drop-in has_pack true", BrandScript.has_pack(_tmp_dir))
	_ok("partial pack: wordmark still null", BrandScript.wordmark(_tmp_dir) == null)


func _test_shipped_pack() -> void:
	# The real pack in assets/branding/ (user-uploaded, imported).
	_ok("shipped: has_pack", BrandScript.has_pack(SHIP_DIR))
	_ok("shipped: emblem", BrandScript.emblem(SHIP_DIR) != null)
	_ok("shipped: emblem_small", BrandScript.emblem_small(SHIP_DIR) != null)
	_ok("shipped: lockup", BrandScript.lockup(SHIP_DIR) != null)
	_ok("shipped: wordmark", BrandScript.wordmark(SHIP_DIR) != null)


func _cleanup() -> void:
	if _tmp_dir == "":
		return
	for f in ["logo-synmergia-emblem.png", "logo-synmergia-wordmark.png"]:
		var path: String = _tmp_dir + str(f)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(_tmp_dir)
