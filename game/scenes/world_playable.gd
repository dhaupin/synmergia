## WorldPlayable - Root controller for the gameplay scene
## Wires the scene-placed player and enemies into the service layer
## (EntityService/TargetingManager), attaches EnemyAI brains, and bridges
## combat events into the HUD (DamageNumbers + CombatLog).
extends Node3D

const CharacterData := preload("res://core/schemas/character_data.gd")
const EnemyAIScript := preload("res://core/ai/enemy_ai.gd")
const SpawnMetadataScript := preload("res://core/events/spawn_metadata.gd")
const DamageNumbersScript := preload("res://ui/components/damage_numbers.gd")
const EnemyScript := preload("res://entities/enemy.gd")

const LOCAL_PLAYER_ID := "player_1"
const SCENE_ZONE_ID := "world_playable"

var _damage_numbers = null
var _player_registered := false

## Scene spawn bookkeeping for the enemy respawn cycle: one record per
## scene-placed enemy, carrying where it stood and what it was so a
## killed enemy can be rebuilt after its EnemyData.respawn_time.
class SceneSpawn:
	var display_name: String = ""
	var enemy_data: Resource = null
	var level: int = 1
	var spawn_position: Vector3 = Vector3.ZERO
	var respawn_time: float = 60.0
	var entity_id: String = ""
	var respawn_pending: bool = false

var _scene_spawns: Array[SceneSpawn] = []


func _ready() -> void:
	var char_data: Resource = GameManager.selected_character_data
	if char_data is CharacterData:
		_apply_character_data(char_data)
	else:
		GameLog.warn("WorldPlayable: No character data found, using defaults")
	_apply_player_from_data(char_data)
	_register_player()
	_restore_player_progress()
	_setup_enemies()
	_setup_guards()
	_setup_offering_npcs()
	_setup_housing()
	_setup_portal()
	_setup_hud_bridge()
	_setup_touch_hud()
	_notify_world_entry()
	_enter_scene_zone()
	_capture_scene_spawns()


## Restore the saved progression (xp/gold/level/position) onto the
## scene player. Must run before _enter_scene_zone so the zone entry
## sees the restored position. A character with no save keeps defaults.
func _restore_player_progress() -> void:
	var player := get_node_or_null("Player")
	if player == null or not ("entity_id" in player) or str(player.entity_id) == "":
		return
	if PlayerProgress == null:
		return
	PlayerProgress.restore_player(player)


## Session-exit checkpoint: the last durable copy of the character is
## written when the world scene unloads (quit to menu, app close).
func _exit_tree() -> void:
	if PlayerProgress == null:
		return
	var player := get_node_or_null("Player")
	if player != null and is_instance_valid(player) \
			and "entity_id" in player and str(player.entity_id) != "":
		PlayerProgress.save_player(player, "exit")


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
			var old_id: String = player.entity_id
			player.entity_id = data.character_id
			# PlayerController._ready (child) ran BEFORE this (parent) and
			# registered the bag under the fallback id ("player_1") because
			# entity_id was still empty. Every panel/service asking for the
			# live character id then got null. Re-key the registration.
			if old_id != player.entity_id and InventoryService:
				var comp = InventoryService.get_inventory(old_id) if InventoryService.has_method("get_inventory") else null
				if comp:
					InventoryService.register_inventory(player.entity_id, comp)
					if "set_owner_id" in comp:
						comp.set_owner_id(player.entity_id)
					InventoryService.unregister_inventory(old_id)
					GameLog.info("WorldPlayable: re-keyed inventory %s -> %s" % [old_id, player.entity_id])


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


## Fire the world-entry event for direct playable-scene runs. The login
## flow emits this in GameManager._handle_playing_state; when the scene
## is run directly there is no login, so the scene does it here. The
## dedupe in GameManager keeps both paths idempotent.
func _notify_world_entry() -> void:
	var player := get_node_or_null("Player")
	if player == null or not ("entity_id" in player):
		return
	var player_id := str(player.entity_id)
	if player_id == "":
		return
	if GameManager and GameManager.has_method("notify_player_entered_world"):
		GameManager.notify_player_entered_world(player_id, GameManager.selected_character_data)


## Place the player in the starter zone so ZoneManager signals fire for
## direct playable-scene runs (achievement zone tracking, minimap, etc).
## Zones self-register in ZoneManager._ready before this scene loads.
func _enter_scene_zone() -> void:
	if ZoneManager == null or not ZoneManager.has_method("entity_enter_zone"):
		return
	var player := get_node_or_null("Player")
	if player == null or not ("entity_id" in player):
		return
	# Direct scene runs skip WorldService.initialize_world (the login path's
	# zone loader), so load zone defs on demand the first time.
	var zone = ZoneManager.get_zone("starter_plains")
	if zone == null and ZoneManager.has_method("load_zones"):
		ZoneManager.load_zones()
		zone = ZoneManager.get_zone("starter_plains")
	if zone == null:
		GameLog.warn("WorldPlayable: starter_plains zone not registered")
		return
	if not ZoneManager.entity_enter_zone(player, zone):
		GameLog.warn("WorldPlayable: could not place player in starter_plains")


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


## Snapshot every scene-placed enemy (position, data, level) so the
## respawn cycle can rebuild it after a kill. Scene enemies are real
## nodes, not SpawnService-managed: without this they died forever and
## the world slowly emptied.
func _capture_scene_spawns() -> void:
	var _tracked := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.has_method("attach_guard_ai"):
			continue  # guards are placements, not respawning wildlife
		var record := SceneSpawn.new()
		record.display_name = str(enemy.display_name)
		record.enemy_data = enemy.enemy_data
		record.level = int(enemy.level)
		record.spawn_position = enemy.global_position
		record.entity_id = str(enemy.entity_id)
		if enemy.enemy_data != null and "respawn_time" in enemy.enemy_data:
			record.respawn_time = float(enemy.enemy_data.respawn_time)
		_scene_spawns.append(record)
		_tracked += 1
	if not EventHub.entity_died.is_connected(_on_scene_enemy_died):
		EventHub.entity_died.connect(_on_scene_enemy_died)
	if _tracked > 0:
		GameLog.info("WorldPlayable: %d scene spawns tracked for respawn" % _tracked)


## A tracked scene enemy died: schedule its respawn at the original
## spawn point after the configured delay. Guards and SpawnService
## enemies are ignored (they own their own cycles).
func _on_scene_enemy_died(entity, _killer, _metadata) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var dead_id := str(entity.entity_id) if "entity_id" in entity else ""
	for record in _scene_spawns:
		if record.entity_id == dead_id and not record.respawn_pending:
			record.respawn_pending = true
			_respawn_scene_enemy_later(record)
			return


func _respawn_scene_enemy_later(record: SceneSpawn) -> void:
	var delay: float = maxf(1.0, record.respawn_time)
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func(): _respawn_scene_enemy(record))


## Rebuild one scene enemy from its snapshot: fresh Enemy node, real
## data/level/health, AI brain from EnemyData, and a fresh service
## registration (the death unregistered the old one).
func _respawn_scene_enemy(record: SceneSpawn) -> void:
	if not is_inside_tree():
		return
	record.respawn_pending = false

	var enemy: Node = EnemyScript.new()
	enemy.enemy_data = record.enemy_data
	enemy.display_name = record.display_name
	enemy.level = record.level
	if record.enemy_data != null and "loot_table_id" in record.enemy_data:
		enemy.loot_table_id = record.enemy_data.loot_table_id
	# _ready (inside add_child) applies enemy_data stats and builds
	# HealthComponent + AggroComponent.
	add_child(enemy)
	enemy.global_position = record.spawn_position

	var ai = EnemyAIScript.new()
	if record.enemy_data != null:
		ai.aggro_range = record.enemy_data.aggro_range
		ai.chase_range = record.enemy_data.chase_range
		ai.attack_range = record.enemy_data.attack_range
	enemy.attach_ai(ai)

	var es = EntityService
	if es:
		var metadata = SpawnMetadataScript.enemy(
			enemy.display_name, SCENE_ZONE_ID, record.spawn_position, enemy.level)
		es.register_entity(enemy, metadata)
	if TargetingManager:
		TargetingManager.register_targetable(
			enemy.entity_id, "enemy", enemy, enemy.display_name,
			record.spawn_position, enemy.entity_type)

	# Re-point the snapshot at the new entity so a second kill also
	# respawns.
	record.entity_id = str(enemy.entity_id)
	GameLog.info("WorldPlayable: %s respawned at its spawn point" % enemy.display_name)


## Register scene-placed offering NPCs (MerchantNPC, ElderNPC) with the
## entity/targeting/zone services so they are targetable and the NPC
## context menu / [E] interact pipeline can resolve their npc_data.
## Their visual nodes live in the scene (like enemies/guards); the
## service-side `spawn_all_offering_npcs` twins stay non-visual and are
## ignored here by the "no offering entries" filter.
func _setup_offering_npcs() -> void:
	var es = EntityService
	var registered := 0
	for npc in get_tree().get_nodes_in_group("offering_npcs"):
		if not is_instance_valid(npc) or npc.entity_id != "":
			continue
		if not ("npc_data" in npc) or npc.npc_data == null:
			continue
		if not npc.npc_data.has_live_offering():
			continue
		if es:
			var metadata = SpawnMetadataScript.npc(
				npc.display_name, SCENE_ZONE_ID, npc.global_position, npc.level)
			es.register_entity(npc, metadata)
		if TargetingManager:
			TargetingManager.register_targetable(
				npc.entity_id, "npc", npc, npc.display_name,
				npc.global_position, npc.entity_type)
		registered += 1
	GameLog.info("WorldPlayable: %d offering NPCs active" % registered)


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
## Register the purchasable demo plot with DwellingService so
## /buyplot, /placeguard and /placeankh have something to act on.
## Anchored at the Merchant (-5, -5): players pass it every session.
func _setup_housing() -> void:
	if DwellingService == null:
		return
	DwellingService.register_plot(
		"plot_haven_1", SCENE_ZONE_ID, Vector3(-5, 0, -5), 10.0, 50000)
	GameLog.info("WorldPlayable: demo plot registered (stand near the merchant, /buyplot)")


## Register the scene-placed dungeon portal with WorldService from its
## authored GatewayData .tres, and make it targetable ("teleport" type
## -> long-press -> Enter). Walking through lands the player in the
## dungeon zone, whose horde_config_id auto-starts vault_seal -- the
## portal -> dungeon -> horde loop, all data-driven.
## The GatewayRecord shape is WorldService's runtime format (from_zone/
## to_zone/position), NOT the GatewayData schema fields, so this maps
## between them.
func _setup_portal() -> void:
	var portal := get_node_or_null("DungeonPortal")
	if portal == null:
		return
	# Authored config: data/gateways/<id>.tres. The portal node itself is
	# pure visual; the .tres carries destination + requirements. Loaded by
	# path (not class_name) -- brand-new schemas miss the global class
	# cache until an editor import pass (the GuardData lesson).
	var gateway_data = load("res://data/gateways/dungeon_forest_depths_entrance.tres")
	if gateway_data == null:
		return
	var ws = get_node_or_null("/root/WorldService")
	var es = EntityService
	var tm = TargetingManager
	if ws == null or es == null:
		return
	var gateway_id: String = ws.register_gateway({
		"display_name": str(gateway_data.display_name),
		"position": portal.global_position,
		"from_zone": SCENE_ZONE_ID,
		"to_zone": str(gateway_data.destination_zone_id),
		"to_position": gateway_data.destination_position,
		"required_level": int(gateway_data.min_level),
		"radius": 5.0,
		"activation_radius": 6.0,
	})
	if tm:
		tm.register_targetable(
			gateway_id, "teleport", portal,
			str(gateway_data.display_name), portal.global_position,
			Entity.EntityType.TELEPORT
		)
	GameLog.info("WorldPlayable: dungeon portal active (%s -> %s, /horde starts on entry)" % [
		gateway_id, str(gateway_data.destination_zone_id)])


func _setup_hud_bridge() -> void:
	_ensure_damage_numbers()
	if not EventHub.damage_dealt.is_connected(_on_combat_damage):
		EventHub.damage_dealt.connect(_on_combat_damage)
	# Healing was invisible: no event existed at all, so no heal floats and
	# no combat-log lines. health_component.heal now emits heal_dealt.
	if not EventHub.heal_dealt.is_connected(_on_combat_heal):
		EventHub.heal_dealt.connect(_on_combat_heal)
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

## Bridge the touch HUD into the player's camera. The VirtualJoystick
## emits camera_look for drags on the right half; the ThirdPersonCamera
## consumes them through the same orbit() path as mouse drags.
func _setup_touch_hud() -> void:
	var player := get_node_or_null("Player")
	if player == null or not ("camera_pivot" in player):
		return
	var joystick = InputManager.get_virtual_joystick() if InputManager else null
	if joystick == null:
		return
	var cam: Camera3D = player.camera_pivot.get_node_or_null("Camera3D")
	if cam == null or not cam.has_method("orbit"):
		return
	# camera_look carries raw pixel deltas; the camera wants radians, so
	# scale with the camera's own speed here (single touch-look owner: the
	# HUD; the camera's own ScreenDrag branch was removed to avoid double
	# rotation).
	var cam_speed: float = 0.003
	if "rotation_speed" in cam:
		cam_speed = float(cam.rotation_speed)
	# Base 1.5x: observed 0.006 rad/px (2.0x) was 440 deg per full-screen
	# swipe -- too hot. 1.5x gives ~330 deg/swipe at default sensitivity.
	# The user's camera_rotation_speed slider (ThirdPersonCamera.sensitivity)
	# scales this live, same as the mouse path.
	var look_handler := func(delta_px: Vector2) -> void:
		cam.orbit(delta_px * cam_speed * 1.5 * cam.sensitivity)
	if not joystick.camera_look.is_connected(look_handler):
		joystick.camera_look.connect(look_handler)
	GameLog.info("WorldPlayable: touch HUD wired to third-person camera")

func _on_ground_loot_picked_up(player, loot_id: String, items: Array) -> void:
	_clear_loot_marker(loot_id)
	var combat_log = get_node_or_null("HudLayer/CombatLog")
	if combat_log == null or not combat_log.has_method("log_loot"):
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
		combat_log.log_loot(item_name, qty)

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

func _on_combat_damage(source, target, amount: int, damage_type: String, is_crit: bool = false) -> void:
	if amount <= 0:
		return

	if _damage_numbers and target is Node3D:
		_damage_numbers.show_damage(target, amount, is_crit, damage_type)
	# Typed log methods so the Damage/Healing/Loot filters actually route
	# entries; crits get the [CRITICAL] line.
	var combat_log = get_node_or_null("HudLayer/CombatLog")
	if combat_log == null:
		return
	var source_name: String = "Something"
	if source != null and "display_name" in source:
		source_name = str(source.display_name)
	var target_name: String = "Unknown"
	if target != null and "display_name" in target:
		target_name = str(target.display_name)
	if is_crit:
		combat_log.log_critical(target_name, amount)
		_notify_crit_toast(source, target_name, amount)
	else:
		combat_log.log_damage(target_name, amount, damage_type, source_name)

## Heal floats + combat-log line. Local-player filter for the log keeps
## other players' heals from scrolling the hero's log.
func _on_combat_heal(source, target, amount: int) -> void:
	if amount <= 0:
		return
	if _damage_numbers and target is Node3D:
		_damage_numbers.show_heal(target, amount)
	var local = PlayerManager.get_local_player()
	if local == null or target != local:
		return
	var combat_log = get_node_or_null("HudLayer/CombatLog")
	if combat_log == null:
		return
	var source_name: String = "Healing"
	if source != null and "display_name" in source:
		source_name = str(source.display_name)
	combat_log.log_heal("you", amount, source_name)

## Crit toast through the typed-Kind pipeline (3s window dedupe so a
## crit-streak doesn't spam): the one combat event loud enough to leave
## the combat log and reach the toast layer. Local-player hits only.
func _notify_crit_toast(attacker, target_name: String, amount: int) -> void:
	var local = PlayerManager.get_local_player()
	if local == null or attacker == null or attacker != local:
		return
	var notif := get_node_or_null("/root/NotificationService")
	if notif == null or not notif.has_method("notify"):
		return
	var NotifKindConst = load("res://core/notifications/notification_kind.gd").NotifKind
	notif.notify(
			NotifKindConst.CUSTOM,
			"CRITICAL! You hit %s for %d!" % [target_name, amount],
			"CombatSystem",
			"crit:%s:%d" % [target_name, int(Time.get_ticks_msec() / 3000.0)],
			{"target": target_name, "amount": amount})

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
