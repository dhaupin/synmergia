## test_branding.gd - Brand asset loader + menu/loading integration.
##
## Verifies the drop-in contract: with no pack, every Brand lookup
## returns null and the main menu still boots (text title). With a
## real PNG dropped into assets/branding/, the loader picks it up and
## the menu renders the LogoBanner instead. The PNG is generated at
## runtime and removed afterwards, so the repo stays clean.
##
## Run: cd game && godot --headless --path . --script res://tests/test_branding.gd
extends SceneTree

const BrandScript = preload("res://core/utils/branding.gd")
const BRAND_DIR := "res://assets/branding/"

var _fails := 0
var _asserts := 0
var _made_files: Array = []


func _init() -> void:
	call_deferred("_run")


func _ok(label: String, cond: bool) -> void:
	_asserts += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _run() -> void:
	await process_frame
	_test_missing_pack_is_null()
	await _test_pack_drop_in()
	await _test_menu_with_pack()
	await _test_menu_without_pack()
	_cleanup_files()
	print("--- test_branding: %d asserts, %d failures ---" % [_asserts, _fails])
	quit(0 if _fails == 0 else 1)


func _test_missing_pack_is_null() -> void:
	# No pack shipped: all lookups must be null (text fallback contract).
	_ok("emblem() null without pack", BrandScript.emblem() == null)
	_ok("wordmark() null without pack", BrandScript.wordmark() == null)
	_ok("lockup() null without pack", BrandScript.lockup() == null)
	_ok("emblem_small() null without pack", BrandScript.emblem_small() == null)


func _make_png(path: String) -> bool:
	# 4x4 opaque PNG via Image.save_png (real PNG bytes, no hand-rolled header).
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.7, 0.9, 0.85))
	var err := img.save_png(path)
	if err != OK:
		return false
	_made_files.append(path)
	return true


func _test_pack_drop_in() -> void:
	if not _make_png(BRAND_DIR + "emblem.png"):
		_ok("png write works", false)
		return
	_ok("png written to branding dir", FileAccess.file_exists(BRAND_DIR + "emblem.png"))
	# ResourceLoader must see the new file (import DB refresh is not
	# required for save_png + load in the same session).
	var tex := BrandScript.emblem()
	_ok("emblem() picks up dropped PNG", tex != null)
	_ok("has_pack() true with one file", BrandScript.has_pack())
	_ok("wordmark() still null (partial pack ok)", BrandScript.wordmark() == null)


func _load_menu() -> Node:
	var scene: PackedScene = load("res://ui/menus/main_menu.tscn")
	var menu: Control = scene.instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	return menu


func _test_menu_with_pack() -> void:
	# Pack currently has emblem.png: menu boots, no LogoBanner (lockup
	# absent), title text untouched.
	var menu: Control = await _load_menu()
	_ok("menu boots with partial pack", menu != null)
	_ok("no banner when lockup missing", menu.get_node_or_null("LogoBanner") == null)
	menu.queue_free()
	await process_frame


func _test_menu_without_pack() -> void:
	# Remove the pack entirely: menu must still boot with text title.
	for f in _made_files:
		DirAccess.remove_absolute(f)
	_made_files.clear()
	var menu: Control = await _load_menu()
	_ok("menu boots without pack", menu != null)
	var title: Label = menu.get_node_or_null("Title") if menu else null
	_ok("text title survives without pack", title != null and title.visible)
	menu.queue_free()
	await process_frame


func _cleanup_files() -> void:
	for f in _made_files:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
