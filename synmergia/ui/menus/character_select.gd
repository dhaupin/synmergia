## CharacterSelect - Species and class selection screen
## Uses UIStyles for consistent theming
extends Control

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
		card.setup(sp)
		card.species_selected.connect(_on_species_card_selected)
		species_container.add_child(card)


func _on_species_card_selected(species_id: String) -> void:
	selected_species_id = species_id
	selected_species = CharacterData.load_species(species_id)
	_show_class_selection()


func _show_class_selection() -> void:
	for child in species_container.get_children():
		child.queue_free()

	var label := Label.new()
	label.text = "CLASSES — " + selected_species.display_name.to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	species_container.add_child(label)

	var all_classes := CharacterData.get_available_classes_for_species(selected_species_id)
	for cls in all_classes:
		var card := ClassCard.instantiate()
		card.setup(cls, selected_species)
		card.class_selected.connect(_on_class_selected)
		species_container.add_child(card)


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

	GameManager.selected_character_data = data
	GameManager.change_state(GameManager.GameState.PLAYING)


func _apply_button_styles() -> void:
	var button_styles := UIStyles.create_button_style()
	UIStyles.apply_button_styles(play_button, button_styles)
	UIStyles.apply_button_styles(back_button, button_styles)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")
