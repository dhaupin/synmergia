## WorldPlayable - Root controller for the gameplay scene
extends Node3D

const CharacterData := preload("res://core/schemas/character_data.gd")


func _ready() -> void:
	var char_data: Resource = GameManager.selected_character_data
	if char_data is CharacterData:
		_apply_character_data(char_data)
	else:
		GameLog.warn("WorldPlayable: No character data found, using defaults")
	_apply_player_from_data(char_data)


func _apply_character_data(data: Resource) -> void:
	if not data is CharacterData:
		return
	GameLog.info("WorldPlayable: Spawning %s %s" % [data.species_id, data.class_id])
	if data.species_data:
		GameLog.info("  Faction: %s" % data.species_data.home_faction)
	if data.class_data:
		GameLog.info("  Role: %s" % data.class_data.role)


func _apply_player_from_data(data: Resource) -> void:
	var player: Node = get_node_or_null("Player")
	if not player:
		return
	if data is CharacterData:
		if "display_name" in player:
			player.display_name = data.display_name
		if data.class_data and "entity_id" in player:
			player.entity_id = data.character_id
