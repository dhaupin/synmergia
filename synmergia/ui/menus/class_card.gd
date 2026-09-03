## ClassCard - Class selection card for character select
class_name ClassCard
extends PanelContainer
const CharacterClass = preload("res://core/schemas/character_class.gd")
const Species = preload("res://core/schemas/species.gd")


signal class_selected(class_id: String)

var cls: CharacterClass

@onready var name_label: Label = $Margin/VBox/Name
@onready var role_label: Label = $Margin/VBox/Role
@onready var desc_label: Label = $Margin/VBox/Desc
@onready var resource_label: Label = $Margin/VBox/ResourceLabel
@onready var armor_label: Label = $Margin/VBox/ArmorLabel
@onready var skills_label: Label = $Margin/VBox/SkillsLabel
@onready var select_btn: Button = $Margin/VBox/SelectBtn


func _ready() -> void:
	select_btn.pressed.connect(_on_select)


func setup(c: CharacterClass, _sp: Species) -> void:
	cls = c
	name_label.text = c.display_name
	desc_label.text = c.description if c.description else ""

	var role_names := {
		0: "Tank",
		1: "Healer",
		2: "Melee DPS",
		3: "Ranged DPS",
		4: "Support"
	}
	role_label.text = role_names.get(c.role, "Unknown")

	var resource_names := {
		0: "STAMINA",
		1: "ENERGY",
		2: "RAGE",
		3: "RUNIC",
		4: "CHI"
	}
	resource_label.text = "Resource: " + resource_names.get(c.resource_type, "MANA")

	var armor_pieces := []
	var armor := c.can_use_armor
	if armor.get("cloth", false):
		armor_pieces.append("Cloth")
	if armor.get("leather", false):
		armor_pieces.append("Leather")
	if armor.get("mail", false):
		armor_pieces.append("Mail")
	if armor.get("plate", false):
		armor_pieces.append("Plate")
	armor_label.text = "Armor: " + (" / ".join(armor_pieces) if armor_pieces else "None")

	var all_skills := c.starting_skills.size()
	for v in c.skill_tree_unlocks.values():
		all_skills += v.size()
	skills_label.text = "Skills: %d unlocked" % all_skills


func _on_select() -> void:
	if cls:
		class_selected.emit(cls.id)
