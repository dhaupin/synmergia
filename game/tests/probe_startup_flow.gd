# probe_startup_flow.gd - the path from menu to playing, walked headless
# (owner request: "go through startup, guest, species select, class
# select, through playing flow and see what isn't wired up").
#
# Covers:
#   A. Species data reaches the picker (3 species, GM-free).
#   B. Species select -> the class list for that species (6 human
#      classes, no GM).
#   C. Class select enables the Play button (the dead-end check).
#   D. Play (direct path) lands in PLAYING with character data.
#   E. Guest login exists and the lobby refuses the unauthenticated.
#   F. The character_select scene is RESPONSIVE: cards live in a
#      scrollable full-rect strip (no fixed-pixel off-screen layout).
#
# Script mode: autoloads at runtime.
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ds = root.get_node_or_null("DataService")
	var gm = root.get_node_or_null("GameManager")
	var ls = root.get_node_or_null("LoginService")
	_check("DataService + GameManager + LoginService present", \
		ds != null and gm != null and ls != null)
	if ds == null or gm == null:
		quit(1)
		return
	if not ds._loaded:
		ds.load_all_data()

	# ---- A. Species reach the picker -----------------------------------------
	var CS = load("res://core/schemas/character_data.gd")
	var species: Array = CS.get_all_species()
	_check("species data loads (3 playable species)", species.size() == 3)
	var species_ids := []
	for sp in species:
		species_ids.append(str(sp.id))
	_check("the roster is the canon trio (akkan, human, synthetic)", \
		species_ids.has("akkan") and species_ids.has("human") and species_ids.has("synthetic"))

	# ---- B. Species select -> the class list ----------------------------------
	var human_classes: Array = CS.get_available_classes_for_species("human")
	_check("human has 6 playable classes (GM excluded)", human_classes.size() == 6)
	var gm_leak := false
	for c in human_classes:
		if str(c.id).begins_with("gm_") or CS.is_gm_class(c):
			gm_leak = true
	_check("no GM class leaks into the picker", not gm_leak)

	# ---- C. Class select enables Play (the dead-end check) ----------------------
	var select_scene: PackedScene = load("res://ui/menus/character_select.tscn")
	_check("character_select scene loads", select_scene != null)
	var panel = select_scene.instantiate()
	root.add_child(panel)
	await process_frame
	var play_btn: Button = panel.get_node("PlayButton")
	# Round 9: the strip is an HFlowContainer now (wraps like flex on
	# portrait devices), typed as its base FlowContainer.
	var species_box: FlowContainer = panel.get_node_or_null("SpeciesScroll/List/SpeciesContainer")
	_check("the card strip is inside a scroll (responsive layout)", species_box != null)
	var cards: Array = species_box.get_children() if species_box else []
	_check("the strip renders one card per species", cards.size() == species.size())
	_check("Play starts disabled (nothing chosen)", play_btn.disabled)
	# Pick human through the card signal (the exact path the card's
	# Select button drives).
	panel._on_species_card_selected("human")
	await process_frame
	_check("species select swaps in the class cards", \
		species_box.get_child_count() == human_classes.size())
	var first_class_id: String = str(human_classes[0].id)
	panel._on_class_selected(first_class_id)
	_check("class select ENABLES Play (the flow is not a dead end)", not play_btn.disabled)

	# ---- D. Play -> PLAYING with character data --------------------------------
	panel._on_play_pressed()
	await process_frame
	_check("the direct path reaches PLAYING", \
		gm.current_state == gm.GameState.PLAYING)
	var chosen = gm.selected_character_data
	_check("the character carries species + class + a home zone", \
		chosen != null and str(chosen.species_id) == "human" \
		and str(chosen.class_id) == first_class_id \
		and str(chosen.zone_id) != "")
	# Clean up the world scene the state change spawned.
	if gm.current_state == gm.GameState.PLAYING:
		var world = root.get_node_or_null("World")
		if world != null:
			world.queue_free()
		gm.current_state = gm.GameState.MAIN_MENU

	# ---- E. Guest exists; the lobby refuses the unauthenticated ---------------
	_check("guest login exists for the portal flow", ls.has_method("login_as_guest"))
	var before_state: int = gm.current_state
	gm.change_state(gm.GameState.LOBBY)  # from a non-LOBBY state, so the handler runs
	await process_frame
	_check("LOBBY without auth bounces to LOGIN (the gate holds)", \
		gm.current_state == gm.GameState.LOGIN)
	gm.current_state = before_state

	# ---- F. The responsive layout guarantees -----------------------------------
	_check("cards live in a full-rect scroll (no fixed 800px strip)", \
		panel.get_node_or_null("SpeciesScroll") != null \
		and panel.get_node("SpeciesScroll").anchors_preset == 15)
	_check("Back and Play anchor to opposite corners (thumb reach)", \
		panel.get_node("BackButton").anchor_left < 0.5 \
		and panel.get_node("PlayButton").anchor_left > 0.5)
	_check("cards are finger-sized (240px min height)", \
		load("res://ui/menus/species_card.tscn").instantiate().custom_minimum_size.y >= 240.0)

	panel.queue_free()
	if _fails == 0:
		print("STARTUP FLOW PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("STARTUP FLOW PROBE FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
