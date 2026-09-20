## WorldPlayable - Root controller for the gameplay scene
## Wires the scene-placed player and enemies into the service layer
## (EntityService/TargetingManager), attaches EnemyAI brains, and bridges
## combat events into the HUD (DamageNumbers + CombatLog).
extends Node3D

const CharacterData := preload("res://core/schemas/character_data.gd")
const EnemyAIScript := preload("res://core/ai/enemy_ai.gd")
const SpawnMetadataScript := preload("res://core/events/spawn_metadata.gd")
const DamageNumbersScript := preload("res://ui/components/damage_numbers.gd")

const LOCAL_PLAYER_ID := "player_1"
const SCENE_ZONE_ID := "world_playable"

var _damage_numbers = null
var _player_registered := false


func _ready() -> void:
	var char_data: Resource = GameManager.selected_character_data
	if char_data is CharacterData:
		_apply_character_data(char_data)
	else:
		GameLog.warn("WorldPlayable: No character data found, using defaults")
	_apply_player_from_data(char_data)
	_register_player()
	_setup_enemies()
	_setup_hud_bridge()


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


## Register the scene player with EntityService so enemy aggro scans
## (get_entities_in_radius PLAYER) can find them, and refresh the
## TargetingManager registration that _ready ran with an empty id.
func _register_player() -> void:
	var player: Node = get_node_or_null("Player")
	if player == null or not is_instance_valid(player):
		GameLog.warn("WorldPlayable: no Player node in scene")
		return
	if _player_registered:
		return

	if player.entity_id == "":
		player.entity_id = LOCAL_PLAYER_ID

	if TargetingManager:
		# PlayerController._ready registered under "" before an id existed.
		TargetingManager.unregister_targetable("")
		TargetingManager.set_local_player(player.entity_id)
		TargetingManager.register_targetable(
			player.entity_id,
			"player",
			player,
			player.display_name,
			player.global_position,
			player.entity_type
		)

	var es = EntityService
	if es and es.get_entity_metadata(player.entity_id) == null:
		var metadata = SpawnMetadataScript.new(0, player.display_name, SCENE_ZONE_ID, player.global_position)
		es.register_entity(player, metadata, player.entity_id)
	_player_registered = true

	GameLog.info("WorldPlayable: player registered as %s" % player.entity_id)


## Give every scene-placed enemy an AI brain and a service registration.
## Without this the enemies are statues: no aggro, no threat, no memory.
func _setup_enemies() -> void:
	var es = EntityService
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.entity_id != "":
			continue

		var ai = EnemyAIScript.new()
		if enemy.enemy_data:
			ai.aggro_range = enemy.enemy_data.aggro_range
			ai.chase_range = enemy.enemy_data.chase_range
			ai.attack_range = enemy.enemy_data.attack_range
		enemy.attach_ai(ai)

		if es:
			var metadata = SpawnMetadataScript.enemy(
				enemy.display_name, SCENE_ZONE_ID, enemy.global_position, enemy.level)
			es.register_entity(enemy, metadata)

	GameLog.info("WorldPlayable: %d enemies active" % get_tree().get_nodes_in_group("enemies").size())


## Bridge combat events into the HUD. Enemy.take_damage emits
## EventHub.damage_dealt for enemy<->player hits; player-side
## HealthComponent.take_damage emits the same signal, so both directions
## feed one handler.
func _setup_hud_bridge() -> void:
	_ensure_damage_numbers()
	if not EventHub.damage_dealt.is_connected(_on_combat_damage):
		EventHub.damage_dealt.connect(_on_combat_damage)
	# XP/gold kill rewards float over the player's head.
	if not EventHub.kill_rewarded.is_connected(_on_kill_rewarded):
		EventHub.kill_rewarded.connect(_on_kill_rewarded)


func _ensure_damage_numbers() -> void:
	_damage_numbers = get_node_or_null("DamageNumbers")
	if _damage_numbers == null:
		_damage_numbers = DamageNumbersScript.new()
		_damage_numbers.name = "DamageNumbers"
		add_child(_damage_numbers)


func _on_combat_damage(source, target, amount: int, damage_type: String) -> void:
	if amount <= 0:
		return

	if _damage_numbers and target is Node3D:
		_damage_numbers.show_damage(target, amount, false, damage_type)

	var combat_log = get_node_or_null("HudLayer/CombatLog")
	if combat_log and combat_log.has_method("add_message"):
		var source_name: String = "Something"
		if source != null and "display_name" in source:
			source_name = source.display_name
		var target_name: String = "Unknown"
		if target != null and "display_name" in target:
			target_name = target.display_name
		combat_log.add_message(
			"%s hits %s for %d %s damage" % [source_name, target_name, amount, damage_type])

func _on_kill_rewarded(entity, killer, rewards: Dictionary) -> void:
	var xp: int = int(rewards.get("xp", 0))
	var gold: int = int(rewards.get("gold", 0))

	var combat_log = get_node_or_null("HudLayer/CombatLog")
	if combat_log and combat_log.has_method("add_message"):
		var killer_name: String = "Something"
		if killer != null and "display_name" in killer:
			killer_name = killer.display_name
		var enemy_name: String = "enemy"
		if entity != null and "display_name" in entity:
			enemy_name = entity.display_name
		var parts: Array[String] = []
		if xp > 0:
			parts.append("+%d XP" % xp)
		if gold > 0:
			parts.append("+%d gold" % gold)
		if rewards.get("party_shared", false):
			parts.append("(party)")
		if not parts.is_empty():
			combat_log.add_message(
				"%s killed %s: %s" % [killer_name, enemy_name, ", ".join(parts)])

	# Float over the player only when they earned the reward.
	if _damage_numbers and killer != null and killer is Node3D and gold + xp > 0:
		var local = PlayerManager.get_local_player()
		if local != null and local == killer:
			var parts2: Array[String] = []
			if xp > 0:
				parts2.append("+%d XP" % xp)
			if gold > 0:
				parts2.append("+%d gold" % gold)
			if not parts2.is_empty():
				_damage_numbers.show_text(killer, ", ".join(parts2), Color(1.0, 0.9, 0.4))
