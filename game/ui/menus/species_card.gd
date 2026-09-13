## SpeciesCard - Species selection card for character select
extends PanelContainer
class_name SpeciesCard
const Species = preload("res://core/schemas/species.gd")


signal species_selected(species_id: String)

var species: Species

@onready var name_label: Label = $Margin/VBox/Name
@onready var faction_label: Label = $Margin/VBox/Faction
@onready var desc_label: Label = $Margin/VBox/Desc
@onready var stats_label: Label = $Margin/VBox/StatsLabel
@onready var select_btn: Button = $Margin/VBox/SelectBtn


func _ready() -> void:
	select_btn.pressed.connect(_on_select)


func setup(sp: Species) -> void:
	species = sp
	name_label.text = sp.display_name
	desc_label.text = sp.description if sp.description else ""

	var faction_name := _get_faction_name(sp.home_faction)
	faction_label.text = faction_name

	var mods := sp.stat_modifiers
	stats_label.text = (
		_mod("STR", mods.get("strength", 0)) + "  " +
		_mod("VIT", mods.get("vitality", 0)) + "  " +
		_mod("AGI", mods.get("agility", 0)) + "  " +
		_mod("INT", mods.get("intelligence", 0)) + "  " +
		_mod("WIS", mods.get("wisdom", 0)) + "  " +
		_mod("END", mods.get("endurance", 0))
	)


func _mod(label: String, val: int) -> String:
	if val >= 0:
		return "%s +%d" % [label, val]
	return "%s %d" % [label, val]


func _get_faction_name(faction_id: String) -> String:
	if DataService:
		var faction := DataService.get_faction(faction_id)
		if faction:
			return faction.display_name
	return faction_id


func _on_select() -> void:
	if species:
		species_selected.emit(species.id)
