## CharacterSelect - Species and class selection screen
## Uses UIStyles for consistent theming
extends Control
const UIStyles = preload("res://ui/components/ui_styles.gd")


const SpeciesCard := preload("res://ui/menus/species_card.tscn")
const ClassCard := preload("res://ui/menus/class_card.tscn")
const CharacterData := preload("res://core/schemas/character_data.gd")

var selected_species_id: String = ""
var selected_class_id: String = ""
var selected_class: CharacterClass
var selected_species: Species
var player_name: String = "Hero"

@onready var species_container: HBoxContainer = $SpeciesContainer
@onready var play_button: Button = $PlayButton
@onready var back_button: Button = $BackButton

signal character_confirmed(data: CharacterData)


func _ready() -> void:
	print("[CHAR_SELECT] _ready called")
	back_button.pressed.connect(_on_back_pressed)
	play_button.pressed.connect(_on_play_pressed)
	play_button.disabled = true
	_apply_button_styles()
	_load_species()


func _load_species() -> void:
	for child in species_container.get_children():
		child.queue_free()

	var all_species := CharacterData.get_all_species()
	for sp in all_species:
		var card := SpeciesCard.instantiate()
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

	var label := Label.new()
	label.text = "CLASSES -- " + selected_species.display_name.to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	species_container.add_child(label)

	var all_classes := CharacterData.get_available_classes_for_species(selected_species_id)
	for cls in all_classes:
		var card := ClassCard.instantiate()
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

	# If we got here from the lobby "Create New" button, link the new
	# character to the current account and persist it; then go back to
	# the lobby. If we got here from the legacy main-menu path, just
	# jump straight into the world.
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

	character_confirmed.emit(data)

# F5 = auto-select first species/class, F6 = play (for headless testing)
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			_cycle_focus([back_button, play_button], event.shift)
		elif event.keycode == KEY_F5:
			print("[CHAR_SELECT] F5 pressed")
			_auto_select()
		elif event.keycode == KEY_F6:
			print("[CHAR_SELECT] F6 pressed, play_button.disabled=", play_button.disabled)
			_auto_play()


func _cycle_focus(buttons: Array, reverse: bool) -> void:
	var current := get_viewport().gui_get_focus_owner()
	var idx := -1
	for i in range(buttons.size()):
		if buttons[i] == current:
			idx = i
			break
	if reverse:
		idx = (idx - 1 + buttons.size()) % buttons.size()
	else:
		idx = (idx + 1) % buttons.size()
	buttons[idx].grab_focus()

func _auto_select() -> void:
	print("[CHAR_SELECT] _auto_select called, selected_species_id=", selected_species_id)
	if selected_species_id == "":
		# Select first species
		var all_species = CharacterData.get_all_species()
		print("[CHAR_SELECT] all_species count=", all_species.size() if all_species else 0)
		if all_species and not all_species.is_empty():
			var first = all_species[0]
			print("[CHAR_SELECT] first species id=", first.id)
			_on_species_card_selected(first.id)
			# Select first class after species
			await get_tree().process_frame
			await get_tree().process_frame
			var all_classes = CharacterData.get_available_classes_for_species(selected_species_id)
			print("[CHAR_SELECT] all_classes count=", all_classes.size() if all_classes else 0)
			if all_classes and not all_classes.is_empty():
				var first_class = all_classes[0]
				print("[CHAR_SELECT] first class id=", first_class.id)
				_on_class_selected(first_class.id)

func _auto_play() -> void:
	if not play_button.disabled:
		_on_play_pressed()


func _lobby_save_character(data: CharacterData, _account_id: String) -> void:
	# Append to characters.json under the account key. The lobby reads
	# this on _ready; both writers are in this process so we don't need
	# file locking. Server-authoritative path would use RPC instead.
	var path := "user://characters.json"
	var by_account: Dictionary = {}
	if FileAccess.file_exists(path):
		var rf := FileAccess.open(path, FileAccess.READ)
		if rf:
			var parsed = JSON.parse_string(rf.get_as_text())
			rf.close()
			if parsed is Dictionary:
				by_account = parsed
	var list: Array = by_account.get(_account_id, [])
	list.append(data.to_dict())
	by_account[_account_id] = list
	var wf := FileAccess.open(path, FileAccess.WRITE)
	if wf:
		wf.store_string(JSON.stringify(by_account))
		wf.close()


func _apply_button_styles() -> void:
	var button_styles := UIStyles.create_button_style()
	UIStyles.apply_button_styles(play_button, button_styles)
	UIStyles.apply_button_styles(back_button, button_styles)

func _on_back_pressed() -> void:
	# If we were routed here from the lobby "Create New" flow, return
	# to the lobby. Otherwise, fall back to the main menu (legacy path).
	var creating_for: String = GameManager.get_meta("creating_for_account", "") if GameManager else ""
	if creating_for != "" and GameManager:
		GameManager.set_meta("creating_for_account", "")
		GameManager.change_state(GameManager.GameState.LOBBY)
		return
	get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")
