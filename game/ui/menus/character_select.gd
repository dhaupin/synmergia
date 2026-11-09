## CharacterSelect - Species and class selection screen
## Uses UIStyles for consistent theming
extends Control
const UIStyles = preload("res://ui/components/ui_styles.gd")
const PersistenceStore = preload("res://adapters/persistence/persistence_store.gd")


const SpeciesCard := preload("res://ui/menus/species_card.tscn")
const ClassCard := preload("res://ui/menus/class_card.tscn")
const CharacterData := preload("res://core/schemas/character_data.gd")
const Responsive := preload("res://ui/components/responsive.gd")

var selected_species_id: String = ""
var selected_class_id: String = ""
var selected_class: CharacterClass
var selected_species: Species
var player_name: String = "Hero"

@onready var species_container: FlowContainer = $SpeciesScroll/List/SpeciesContainer
@onready var list_container: VBoxContainer = $SpeciesScroll/List
@onready var play_button: Button = $PlayButton
@onready var back_button: Button = $BackButton

var _class_header: Label = null

signal character_confirmed(data: CharacterData)


func _ready() -> void:
	# print removed: print("[CHAR_SELECT] _ready called")
	back_button.pressed.connect(_on_back_pressed)
	play_button.pressed.connect(_on_play_pressed)
	play_button.disabled = true
	_apply_button_styles()
	# Accessibility & Agent-Action layer (prd-accessibility.md).
	if UIStyles:
		UIStyles.apply_accessibility(back_button, "Back to lobby", "Returns to the character lobby without creating")
		UIStyles.apply_accessibility(play_button, "Enter World", "Creates the chosen character and enters the world immediately")
	_load_species()


func _load_species() -> void:
	for child in species_container.get_children():
		child.queue_free()
	# The static SPECIES header belongs to this view only.
	if _class_header != null and is_instance_valid(_class_header):
		_class_header.visible = false
	if has_node("SpeciesLabel"):
		$SpeciesLabel.visible = true

	var all_species := CharacterData.get_all_species()
	for sp in all_species:
		var card := SpeciesCard.instantiate()
		# STABLE AGENT HANDLE: a dynamically-added node gets an auto name
		# (@PanelContainer@NNN) that changes with layout, so an agent's
		# ui: handle would not survive a rebuild. Name the card from its
		# DATA id instead -- the handle becomes
		# ui:CharacterSelect/.../SpeciesContainer/species_human/Margin/VBox/SelectBtn.
		card.name = "species_%s" % sp.id
		# RESPONSIVE (round 9): card mins adapt to the viewport class
		# (two-up on portrait phones, base size on wide screens).
		card.custom_minimum_size = Responsive.card_size(Vector2(300, 340))
		species_container.add_child(card)
		card.species_selected.connect(_on_species_card_selected)
		card.setup(sp)


func _on_species_card_selected(species_id: String) -> void:
	selected_species_id = species_id
	selected_species = CharacterData.load_species(species_id)
	_show_class_selection()


func _show_class_selection() -> void:
	for child in species_container.get_children():
		child.queue_free()
	# Round 9: the static SPECIES header overlapped the CLASSES header
	# (both visible at once on the portrait screenshot). One header at
	# a time.
	if has_node("SpeciesLabel"):
		$SpeciesLabel.visible = false
	# The class header is a ROW ABOVE the card strip (the List VBox),
	# not an inline sibling of the cards.
	if _class_header != null and is_instance_valid(_class_header):
		_class_header.queue_free()

	var label := Label.new()
	label.text = "CLASSES -- " + selected_species.display_name.to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	_class_header = label
	list_container.add_child(label)
	list_container.move_child(label, 0)

	var all_classes := CharacterData.get_available_classes_for_species(selected_species_id)
	for cls in all_classes:
		var card := ClassCard.instantiate()
		# STABLE AGENT HANDLE: name the class card from its data id (see the
		# species leg above) so the ui: handle survives a rebuild.
		card.name = "class_%s" % cls.id
		# RESPONSIVE (round 9): the class strip was a hard HBox that
		# clipped at both edges on portrait phones; the container is now
		# an HFlowContainer (wraps like flex) and card mins shrink so
		# two cards share a narrow row.
		card.custom_minimum_size = Responsive.card_size(Vector2(260, 380), 2.4)
		species_container.add_child(card)
		card.class_selected.connect(_on_class_selected)
		card.setup(cls, selected_species)


func _on_class_selected(class_id: String) -> void:
	selected_class_id = class_id
	selected_class = CharacterData.load_class(class_id)
	play_button.disabled = false


func _on_play_pressed() -> void:
	if selected_class_id == "" or selected_species_id == "":
		return

	# GM classes are filtered out by get_available_classes_for_species()
	# so non-admins can never select them. Server should still validate.

	var data := CharacterData.new(selected_species_id, selected_class_id, player_name)
	data.species_data = selected_species
	data.class_data = selected_class
	data.zone_id = selected_species.home_zone if selected_species else "zone_starter_plains"

	# The confirmed-selection announce (cheap-pair loop): BOTH legs here
	# are creation paths (a fresh CharacterData either way), so Enter
	# World emits the declared signal. StarterKitService's tree relay
	# listens on it to mark the character fresh, which is how the
	# starting kit starts firing once per character instead of once per
	# boot (returning characters were collecting the kit again).
	character_confirmed.emit(data)

	# If we got here from the lobby "Create New" button, link the new
	# character to the current account and persist it; then go back to
	# the lobby. If we got here from the main menu path, go directly
	# to playing.
	var creating_for: String = GameManager.get_meta("creating_for_account", "") if GameManager else ""
	if creating_for != "" and AccountService:
		data.character_id = "%s_%d" % [creating_for, Time.get_ticks_msec()]
		AccountService.link_character(data.character_id, creating_for, {
			"name": data.display_name,
			"species_id": data.species_id,
			"class_id": data.class_id,
			"zone_id": data.zone_id,
		})
		GameLog.info("CharacterSelect: Linked new character %s to account %s" % [data.character_id, creating_for])
		# Save to local characters.json
		_lobby_save_character(data, creating_for)
		# Signal Lobby._ready() to auto-select and play this character
		GameManager.set_meta("last_character_id", data.character_id)
		GameManager.set_meta("creating_for_account", "")
		GameManager.change_state(GameManager.GameState.LOBBY)
		return

	# Direct play from main menu (offline/single-player flow)
	GameManager.selected_character_data = data
	GameManager.change_state(GameManager.GameState.PLAYING)

# TAB = focus navigation (accessibility). _auto_select/_auto_play
# remain as methods for headless tests, but no longer bound to keys.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			# Focus cycling lives on A11yService (one implementation for
			# every menu; prd-accessibility.md sec 8 disposition).
			if event.shift:
				A11yService.focus_prev()
			else:
				A11yService.focus_next()


func _auto_select() -> void:
	# print removed: print("[CHAR_SELECT] _auto_select called, selected_species_id=", selected_species_id)
	if selected_species_id == "":
		# Select first species
		var all_species = CharacterData.get_all_species()
	# print removed: print("[CHAR_SELECT] all_species count=", all_species.size() if all_species else 0)
		if all_species and not all_species.is_empty():
			var first = all_species[0]
	# print removed: print("[CHAR_SELECT] first species id=", first.id)
			_on_species_card_selected(first.id)
			# Select first class after species
			await get_tree().process_frame
			await get_tree().process_frame
			var all_classes = CharacterData.get_available_classes_for_species(selected_species_id)
	# print removed: print("[CHAR_SELECT] all_classes count=", all_classes.size() if all_classes else 0)
			if all_classes and not all_classes.is_empty():
				var first_class = all_classes[0]
	# print removed: print("[CHAR_SELECT] first class id=", first_class.id)
				_on_class_selected(first_class.id)

func _auto_play() -> void:
	if not play_button.disabled:
		_on_play_pressed()


func _get_registry() -> Node:
	if get_tree() == null:
		return null
	return get_tree().root.get_node_or_null("AdapterRegistry")

func _get_store() -> PersistenceStore:
	var reg := _get_registry()
	if reg == null:
		GameLog.warn("CharacterSelect: AdapterRegistry not found")
		return null
	var store: PersistenceStore = reg.get_persistence("characters")
	if store == null:
		GameLog.warn("CharacterSelect: characters store not registered")
	return store

func _lobby_save_character(data: CharacterData, _account_id: String) -> void:
	# Save character blob to AdapterRegistry characters store
	var store := _get_store()
	if store == null:
		return

	# Load existing characters for this account
	var key := "account:%s" % _account_id
	var rows = store.query("SELECT value FROM kv WHERE key = $1", [key])
	var by_account: Dictionary = {}
	if not rows.is_empty():
		var raw = rows[0].get("value", "")
		if raw != "":
			var parsed = JSON.parse_string(raw)
			if parsed is Dictionary:
				by_account = parsed

	var list: Array = by_account.get(_account_id, [])
	list.append(data.to_dict())
	by_account[_account_id] = list

	var json = JSON.stringify(by_account)
	store.execute("DELETE FROM kv WHERE key = $1", [key])
	store.execute("INSERT INTO kv (key, value) VALUES ($1, $2)", [key, json])


func _apply_button_styles() -> void:
	# CTA hierarchy (play-test round 8, item 7): Enter World is THE
	# forward action -- Synmergia green, large, unmistakable. Back is a
	# neutral secondary. Card buttons say "Select" (a selection, not a
	# jump into the world); Enter World is what enters the world.
	play_button.custom_minimum_size = Vector2(340, 64)
	UIStyles.apply_cta_button(play_button, 26)
	back_button.custom_minimum_size = Vector2(180, 64)
	var button_styles := UIStyles.create_button_style()
	UIStyles.apply_button_styles(back_button, button_styles)
	back_button.add_theme_font_size_override("font_size", 22)

func _on_back_pressed() -> void:
	# If we were routed here from the lobby "Create New" flow, return
	# to the lobby. Otherwise, fall back to the main menu (legacy path).
	var creating_for: String = GameManager.get_meta("creating_for_account", "") if GameManager else ""
	if creating_for != "" and GameManager:
		GameManager.set_meta("creating_for_account", "")
		GameManager.change_state(GameManager.GameState.LOBBY)
		return
	get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")
