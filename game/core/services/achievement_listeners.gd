## AchievementListeners - Autoload bridge from game signals to AchievementService
## Sits late in the autoload order (after AchievementService and the services
## it listens to) and wires the event sources that feed the achievement
## system. All signal signatures here were verified against the emitting code:
##   - CombatSystem.skill_executed(caster: Entity, skill, targets)  -> skills_cast
##   - EventHub.kill_rewarded(entity, killer, rewards)              -> enemy kills
##   - EventHub.entity_killed(killer, victim, damage_type)          -> PvP kills
##   - EventHub.ground_loot_picked_up(player, loot_id, items)       -> items
##   - ZoneManager.player_entered_zone(entity, zone)                -> zones
##   - GameManager.player_entered_world(player_id, char_data)       -> session
##   - QuestService.quest_completed(player_id, quest_id)            -> quests
##   - PartyService.player_joined_party(party_id, player_id)        -> party
##   - GuildService.player_joined_guild(guild_id, player_id, rank)  -> guild
##   - TradeService.trade_completed(trade_id, trades)               -> trade
##   - ChatService.message_received(sender_id, channel, msg, tgts)  -> chat
## AchievementService stays pure; this file owns every signal signature.
extends Node

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

## Session-scoped once-flags (zone credit, etc.). Deliberately in-memory:
## "once per session" semantics must reset every boot, so persisting these
## through the adapter layer would wrongly make them once-per-lifetime.
var _session_flags: Dictionary = {}

func _ready() -> void:
	_connect_all()
	_log("info", "AchievementListeners: Wired achievement event sources")

## ============================================================================
## WIRING
## ============================================================================

func _connect_all() -> void:
	var hub := get_node_or_null("/root/EventHub")
	if hub != null:
		if hub.has_signal("kill_rewarded"):
			hub.kill_rewarded.connect(_on_kill_rewarded)
		if hub.has_signal("entity_killed"):
			hub.entity_killed.connect(_on_entity_killed)
		if hub.has_signal("ground_loot_picked_up"):
			hub.ground_loot_picked_up.connect(_on_ground_loot)

	var ach := get_node_or_null("/root/AchievementService")
	if ach != null and ach.has_signal("achievement_unlocked"):
		ach.achievement_unlocked.connect(_on_achievement_unlocked)

	var combat := get_node_or_null("/root/CombatSystem")
	if combat != null and combat.has_signal("skill_executed"):
		combat.skill_executed.connect(_on_skill_executed)

	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_signal("player_entered_world"):
		gm.player_entered_world.connect(_on_player_entered_world)

	var zone := get_node_or_null("/root/ZoneManager")
	if zone != null and zone.has_signal("player_entered_zone"):
		zone.player_entered_zone.connect(_on_player_entered_zone)

	var quest := get_node_or_null("/root/QuestService")
	if quest != null and quest.has_signal("quest_completed"):
		quest.quest_completed.connect(_on_quest_completed)

	var party := get_node_or_null("/root/PartyService")
	if party != null and party.has_signal("player_joined_party"):
		party.player_joined_party.connect(_on_party_joined)

	var guild := get_node_or_null("/root/GuildService")
	if guild != null and guild.has_signal("player_joined_guild"):
		guild.player_joined_guild.connect(_on_guild_joined)

	var trade := get_node_or_null("/root/TradeService")
	if trade != null and trade.has_signal("trade_completed"):
		trade.trade_completed.connect(_on_trade_completed)

	var chat := get_node_or_null("/root/ChatService")
	if chat != null and chat.has_signal("message_received"):
		chat.message_received.connect(_on_chat_message)

## ============================================================================
## HANDLERS
## ============================================================================

## CombatSystem.skill_executed(caster: Entity, skill: Skill, targets: Array)
func _on_skill_executed(caster, _skill, _targets) -> void:
	if not _is_player_entity(caster):
		return
	var pid := _player_id_of(caster)
	if pid == "":
		return
	AchievementService.track(pid, "skill", 1)

## EventHub.kill_rewarded(entity, killer, rewards: Dictionary)
## Only fires for credited kills (KillRewards.award_kill).
func _on_kill_rewarded(entity, killer, _rewards: Dictionary) -> void:
	# Player achievements only credit player killers; an enemy's kill of
	# an enemy (or an NPC guard executing a player) feeds nothing.
	if not _is_player_entity(killer):
		return
	var pid := _player_id_of(killer)
	if pid == "":
		return
	if _is_boss(entity):
		AchievementService.track(pid, "boss", 1)
	elif _is_elite(entity):
		AchievementService.track(pid, "elite", 1)
	AchievementService.track(pid, "enemy", 1)

## EventHub.entity_killed(killer, victim, damage_type: String) - PvP path
func _on_entity_killed(killer, victim, _damage_type: String) -> void:
	if killer == null or victim == null:
		return
	var kid := _player_id_of(killer)
	var vid := _player_id_of(victim)
	if kid == "" or vid == "" or kid == vid:
		return
	# Both sides must be player entities (PlayerController), not enemies.
	if not _is_player_entity(killer) or not _is_player_entity(victim):
		return
	AchievementService.track(kid, "player_kill", 1)

## EventHub.ground_loot_picked_up(player, loot_id: String, items: Array)
func _on_ground_loot(player, _loot_id: String, items: Array) -> void:
	var pid := _player_id_of(player)
	if pid == "":
		return
	AchievementService.track(pid, "item", maxi(1, items.size()))

## ZoneManager.player_entered_zone(entity, zone: ZoneData)
func _on_player_entered_zone(entity, zone) -> void:
	var pid := _player_id_of(entity)
	if pid == "" or zone == null:
		return
	var zone_id := str(zone.get("id")) if zone.get("id") != null else ""
	if zone_id == "":
		return
	# Zone credit is once-per-session per zone id.
	if _session_flag(pid, "zone:%s" % zone_id):
		return
	AchievementService.track(pid, "zone", 1)

## GameManager.player_entered_world(player_id: String, character_data)
func _on_player_entered_world(player_id: String, _character_data) -> void:
	if player_id == "":
		return
	AchievementService.unlock_event(player_id, "session")

## QuestService.quest_completed(player_id: String, quest_id: String)
func _on_quest_completed(player_id: String, _quest_id: String) -> void:
	if player_id == "":
		return
	AchievementService.track(player_id, "quest", 1)

## PartyService.player_joined_party(party_id: String, player_id: String)
func _on_party_joined(_party_id: String, player_id: String) -> void:
	if player_id == "":
		return
	AchievementService.unlock_event(player_id, "party")

## GuildService.player_joined_guild(guild_id, player_id, rank: GuildRank)
func _on_guild_joined(_guild_id: String, player_id: String, _rank = null) -> void:
	if player_id == "":
		return
	AchievementService.unlock_event(player_id, "guild")

## TradeService.trade_completed(trade_id, trades) - two real shapes:
##   normal:  {player_id: {"items": [...], "gold": int}}
##   quick path emits a result dict carrying from_id/to_id attribution.
func _on_trade_completed(_trade_id: String, trades: Dictionary) -> void:
	if trades.has("from_id") or trades.has("to_id"):
		for key in ["from_id", "to_id"]:
			var pid := str(trades.get(key, ""))
			if pid != "":
				AchievementService.unlock_event(pid, "trade")
		return
	for player_id in trades.keys():
		var pid := String(player_id)
		if pid == "":
			continue
		AchievementService.unlock_event(pid, "trade")

## ChatService.message_received(sender_id, channel, message, targets)
## Skip system senders: send_system_message() re-emits message_received,
## so crediting them would unlock chat achievements for a phantom
## "SYSTEM" player (and re-announce through the unlock moment).
func _on_chat_message(sender_id: String, _channel, _message: String, _targets: Array) -> void:
	if sender_id == "" or sender_id == "SYSTEM":
		return
	AchievementService.track(sender_id, "chat", 1)

## AchievementService.achievement_unlocked(player_id, achievement_id)
## Re-toast with the display name; hud_services also fires its own toast,
## dedupe collapses them. Listeners own presentation strings so the
## service stays presentation-free.
func _on_achievement_unlocked(player_id: String, achievement_id: String) -> void:
	var notif := get_node_or_null("/root/NotificationService")
	if notif == null or not notif.has_method("notify"):
		return
	var def = AchievementService.get_achievement(achievement_id)
	var title := achievement_id
	if def != null and "display_name" in def and str(def.display_name) != "":
		title = str(def.display_name)
	notif.notify(
		NotifKind.ACHIEVEMENT_UNLOCKED,
		"Achievement Unlocked: \"%s\"!" % title,
		"AchievementService",
		"ach_unlock:%s:%s" % [player_id, achievement_id],
		{"achievement_id": achievement_id},
		player_id
	)

## ============================================================================
## HELPERS
## ============================================================================

func _log(level: String, msg: String) -> void:
	var gl := get_node_or_null("/root/GameLog")
	if gl != null and gl.has_method(level):
		gl.call(level, msg)

## Resolve a player id from an entity-ish argument (node with entity_id,
## or an id string directly).
func _player_id_of(entity) -> String:
	if entity == null:
		return ""
	if entity is String:
		return String(entity)
	if entity is Node and is_instance_valid(entity):
		var eid = entity.get("entity_id")
		if eid != null:
			return String(eid)
	return ""

func _is_player_entity(node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	# Canonical: Entity nodes carry entity_type; PLAYER is unambiguous.
	if "entity_type" in node:
		return int(node.entity_type) == 1  # Entity.EntityType.PLAYER
	# Fallback for non-Entity nodes (e.g. plain Node wrappers).
	var cls: Script = node.get_script()
	if cls == null:
		return false
	var path := str(cls.resource_path)
	return path.contains("globe_player") or path.contains("player_base") \
			or path.contains("/player/")

## Boss/elite detection: EnemyData fields, with bare-property fallbacks.
func _is_boss(entity) -> bool:
	if entity == null or not is_instance_valid(entity):
		return false
	if "enemy_data" in entity and entity.enemy_data != null and "is_boss" in entity.enemy_data:
		return bool(entity.enemy_data.is_boss)
	if "is_boss" in entity:
		return bool(entity.is_boss)
	return false

func _is_elite(entity) -> bool:
	if entity == null or not is_instance_valid(entity):
		return false
	if "enemy_data" in entity and entity.enemy_data != null and "is_elite" in entity.enemy_data:
		return bool(entity.enemy_data.is_elite)
	if "is_elite" in entity:
		return bool(entity.is_elite)
	return false

## Session-scoped once flags (zones visited this session, etc.)
func _session_flag(player_id: String, key: String) -> bool:
	var sk := "%s|%s" % [player_id, key]
	if _session_flags.has(sk):
		return true
	_session_flags[sk] = true
	return false
