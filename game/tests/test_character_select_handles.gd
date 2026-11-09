## test_character_select_handles.gd - the STABLE-HANDLE receipt for character
## select. The species/class cards are built at runtime (one per data entry),
## so Godot names them @PanelContainer@NNN -- an auto name that changes with
## layout, which means an agent's ui: handle would not survive a rebuild. The
## cards are now named from their DATA id (species_<id> / class_<id>), so the
## handle is stable and reads back meaningfully.
##
##   cd game && xvfb-run godot --path . --script res://tests/test_character_select_handles.gd
##
## Legs:
##   1. the species strip renders one card per species, each named species_<id>.
##   2. picking a species rebuilds the strip with class_<id> cards.
##   3. no card carries an auto @-name (the class the fix kills).
##
## Exit 0 = every leg observed. Failures print FAIL lines and exit 1.
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load("res://ui/menus/character_select.tscn")
	_assert(scene != null, "character_select.tscn loads")
	if scene == null:
		return _finish()
	var ui: Control = scene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame

	var container: Node = ui.get_node_or_null("SpeciesScroll/List/SpeciesContainer")
	_assert(container != null, "species container present")
	if container == null:
		return _finish()

	_assert(container.get_child_count() > 0, "species cards rendered")
	var all_stable := true
	var any_auto := false
	var first_id := ""
	for card in container.get_children():
		var n := String(card.name)
		if n.begins_with("species_") and n.length() > "species_".length():
			if first_id == "":
				first_id = n.substr("species_".length())
		else:
			all_stable = false
		if n.begins_with("@"):
			any_auto = true
	_assert(all_stable, "every species card carries a stable species_<id> name")
	_assert(not any_auto, "no species card carries an auto @-name")
	_assert(first_id != "", "the species names carry a real data id")

	# Pick the first species -> the strip rebuilds with class cards.
	var btn: Button = container.get_child(0).get_node_or_null("Margin/VBox/SelectBtn")
	_assert(btn != null, "the first species card has its select button")
	if btn != null:
		btn.pressed.emit()
		await process_frame
		await process_frame

	var class_stable := true
	var class_auto := false
	var class_count := 0
	for card in container.get_children():
		var n := String(card.name)
		if n.begins_with("class_") and n.length() > "class_".length():
			class_count += 1
		else:
			class_stable = false
		if n.begins_with("@"):
			class_auto = true
	_assert(class_count > 0, "class cards rendered after a species pick")
	_assert(class_stable, "every class card carries a stable class_<id> name")
	_assert(not class_auto, "no class card carries an auto @-name")
	print("    [handles] species=%s class_count=%d" % [first_id, class_count])

	ui.queue_free()
	_finish()


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] %s" % label)
	else:
		_fail += 1
		print("  [FAIL] %s" % label)


func _finish() -> void:
	print("=== CHARACTER SELECT HANDLES: %d passed / %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
