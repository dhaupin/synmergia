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
	_setup_guards()
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
		if enemy.has_method("attach_guard_ai"):
			continue  # guards get their brain in _setup_guards

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


## Give every scene-placed guard its GuardData + GuardAI brain.
## Guards load their watch config from a GuardData .tres when one is
## assigned at the scene level (guard_data property); otherwise they
## fall back to the town-guard preset.
func _setup_guards() -> void:
	var es = EntityService
	var guard_count := 0
	for guard in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(guard) or guard.entity_id != "":
			continue
		if not guard.has_method("attach_guard_ai"):
			continue
		var data = guard.get("guard_data")
		if data == null:
			data = load("res://data/guards/guard_town.tres")
		guard.attach_guard_ai(data)
		guard_count += 1
		if es:
			var metadata = SpawnMetadataScript.enemy(
				guard.display_name, SCENE_ZONE_ID, guard.global_position, guard.level)
			es.register_entity(guard, metadata)
	GameLog.info("WorldPlayable: %d guards active" % guard_count)


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
	# Ground loot feedback: combat-log line on pickup, drop notice on spawn.
	if not EventHub.ground_loot_picked_up.is_connected(_on_ground_loot_picked_up):
		EventHub.ground_loot_picked_up.connect(_on_ground_loot_picked_up)
	if not EventHub.ground_loot_spawned.is_connected(_on_ground_loot_spawned):
		EventHub.ground_loot_spawned.connect(_on_ground_loot_spawned)
	if not EventHub.ground_loot_despawned.is_connected(_on_ground_loot_despawned):
		EventHub.ground_loot_despawned.connect(_on_ground_loot_despawned)
	# Quest progress: objective updates and completions hit the combat log.
	if QuestService and QuestService.has_signal("quest_updated"):
		if not QuestService.quest_updated.is_connected(_on_quest_updated):
			QuestService.quest_updated.connect(_on_quest_updated)
	if QuestService and QuestService.has_signal("quest_completed"):
		if not QuestService.quest_completed.is_connected(_on_quest_completed):
			QuestService.quest_completed.connect(_on_quest_completed)
	# Make the starter quest available at the Village Elder (dialog/quest
	# UI already route through QuestService.accept_quest).
	_accept_starter_quest()


func _ensure_damage_numbers() -> void:
	_damage_numbers = get_node_or_null("DamageNumbers")
	if _damage_numbers == null:
		_damage_numbers = DamageNumbersScript.new()
		_damage_numbers.name = "DamageNumbers"
		add_child(_damage_numbers)


## Auto-accept the Wolf Hunt quest for the local player so the kill
## objective bridge is exercised in the playable scene. Players accept
## it through the elder NPC dialog in the full flow.
func _accept_starter_quest() -> void:
	var player := get_node_or_null("Player")
	if player == null or not ("entity_id" in player) or str(player.entity_id) == "":
		return
	var player_id := str(player.entity_id)
	if QuestService == null or not QuestService.has_method("accept_quest"):
		return
	var active: Array = QuestService.get_active_quests(player_id) if QuestService.has_method("get_active_quests") else []
	if not active.has("quest_wolves_hunt"):
		QuestService.accept_quest(player_id, "quest_wolves_hunt")

func _on_ground_loot_picked_up(player, loot_id: String, items: Array) -> void:
	_clear_loot_marker(loot_id)
	var combat_log = get_node_or_null("HudLayer/CombatLog")
	if combat_log == null or not combat_log.has_method("add_message"):
		return
	var local = PlayerManager.get_local_player()
	if local == null or player != local:
		return
	for item in items:
		var item_name: String = "an item"
		if item != null and "display_name" in item:
			item_name = str(item.display_name)
		var qty: int = 1
		if item != null and "current_stack" in item:
			qty = int(item.current_stack)
		combat_log.add_message("Picked up %s x%d" % [item_name, qty])

## Minimap loot glints: a gold 4-point star per live drop, removed on
## pickup/despawn. Markers live on the HudLayer Minimap node.
func _on_ground_loot_spawned(loot_id: String, position: Vector3, _items: Array) -> void:
	var minimap = _get_minimap()
	if minimap != null and minimap.has_method("add_marker"):
		minimap.add_marker("loot_%s" % loot_id, position, minimap.MARKER_LOOT, "")

func _on_ground_loot_despawned(loot_id: String, _reason: String) -> void:
	_clear_loot_marker(loot_id)

func _clear_loot_marker(loot_id: String) -> void:
	var minimap = _get_minimap()
	if minimap != null and minimap.has_method("remove_marker"):
		minimap.remove_marker("loot_%s" % loot_id)

func _get_minimap():
	var hud := get_node_or_null("HudLayer")
	return hud.get_node_or_null("Minimap") if hud != null else null

func _on_quest_updated(player_id: String, quest_id: String, objective_id: String, progress: int) -> void:
	var local = PlayerManager.get_local_player()
	if local == null or not ("entity_id" in local) or str(local.entity_id) != player_id:
		return
	var combat_log = get_node_or_null("HudLayer/CombatLog")
	if combat_log and combat_log.has_method("add_message"):
		combat_log.add_message("Quest %s: %s progress %d" % [quest_id, objective_id, progress])

func _on_quest_completed(player_id: String, quest_id: String) -> void:
	var local = PlayerManager.get_local_player()
	if local == null or not ("entity_id" in local) or str(local.entity_id) != player_id:
		return
	var combat_log = get_node_or_null("HudLayer/CombatLog")
	if combat_log and combat_log.has_method("add_message"):
		combat_log.add_message("QUEST COMPLETE: %s -- return to the quest giver" % quest_id)

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
