## Probe: play-test round 12 panel fixes.
##
## A. WorldMap opens FULL-SIZED. R6 wired the minimap button to
##    toggle(), but toggle only flipped visibility: _ready had pinned
##    the control to 150x150 corner geometry, so "the map" was a tiny
##    empty corner box. toggle() now expands to full-rect + shows, and
##    closing restores the corner geometry. The full map also carries a
##    backdrop now (the globe streams per-face terrain, mounts no
##    ZoneData, so MapTexture is textureless and the map drew black).
## B. FactionUI shows faction NAMES. The schema field is display_name;
##    the panel read "name" and rendered a column of "? Rep: 0".
## C. QuestUI tabs are buttons with real widths (Bank treatment), not
##    one crammed text run.
##
## NOTE: probe scripts compile before autoloads register -- resolve
## services via root.get_node_or_null.
##
## Run: godot --headless --path game --script res://tests/probe_playtest_r12.gd
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
	var vp_size: Vector2 = root.get_viewport().get_visible_rect().size

	# --- A. WorldMap opens full-sized -----------------------------------
	var MapScript = load("res://ui/components/world_map.gd")
	var map = MapScript.new()
	root.add_child(map)
	await process_frame
	# _ready hides it and pins corner geometry (150x150).
	map.toggle()
	await process_frame
	ok = _check("A1 toggle() opens the map", map.visible) and ok
	ok = _check("A2 open map is NOT minimap mode", not map.is_minimap()) and ok
	ok = _check("A3 open map covers the viewport",
		map.size.x >= vp_size.x * 0.9 and map.size.y >= vp_size.y * 0.9) and ok
	var backdrop = map.find_child("MapBackdrop", true, false)
	ok = _check("A4 full map has a backdrop (not raw black)", backdrop != null) and ok
	map.toggle()
	await process_frame
	ok = _check("A5 second toggle closes the map", not map.visible) and ok
	ok = _check("A6 closed map restored corner size", map.size.x <= 200.0) and ok

	# --- B. FactionUI names ---------------------------------------------
	# Script mode has no loaded faction KV store; the fix under test is
	# the ROW rendering (_create_faction_row reading display_name). Feed
	# it the real faction resource and a defensive Dictionary.
	var FacScript = load("res://ui/social/faction_ui.gd")
	var fui = FacScript.new()
	root.add_child(fui)
	await process_frame
	var faction_res = load("res://data/factions/faction_human.tres")
	ok = _check("B1 faction resource loads", faction_res != null) and ok
	var row = fui._create_faction_row(faction_res)
	var first_name := _first_label_text(row)
	ok = _check("B2 resource row shows display_name (got '%s')" % first_name,
		first_name == "Human Alliance") and ok
	var dict_row = fui._create_faction_row({"id": "faction_x", "display_name": "Dict Faction"})
	var dict_name := _first_label_text(dict_row)
	ok = _check("B3 dict row shows display_name (got '%s')" % dict_name,
		dict_name == "Dict Faction") and ok
	var anon_row = fui._create_faction_row({})
	var anon_name := _first_label_text(anon_row)
	ok = _check("B4 empty faction never renders '?' (got '%s')" % anon_name,
		anon_name != "?" and anon_name != "") and ok
	fui.queue_free()

	# --- C. QuestUI tab widths -------------------------------------------
	var QuestScript = load("res://ui/components/quest_ui.gd")
	var qui = QuestScript.new()
	root.add_child(qui)
	await process_frame
	var widths_ok := true
	var btn_count := 0
	for btn in qui._tab_buttons:
		if btn is Button:
			btn_count += 1
			if btn.custom_minimum_size.x < 80.0:
				widths_ok = false
	ok = _check("C1 quest tabs present (3)", btn_count == 3) and ok
	ok = _check("C2 quest tabs have real widths", widths_ok) and ok
	qui.queue_free()

	print("probe_playtest_r12: %d checks, %s" % [_checks, "PASS" if ok else "FAIL"])
	quit(0 if ok else 1)


## First Label text walking a faction row (row > HBox > name Label).
func _first_label_text(row: Control) -> String:
	for child in row.get_children():
		if child is HBoxContainer:
			for sub in child.get_children():
				if sub is Label:
					return sub.text
	return ""
