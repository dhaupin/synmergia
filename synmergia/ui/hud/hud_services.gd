## HudServices - Wires HUD social panels and admin tools to their
## respective backend services. Bridges MenuManager (which owns the
## panels) with PartyService, GuildService, FriendsService, etc.
##
## The MenuManager creates panels but doesn't bind them to data. This
## node is the place where every "open X panel → load from Y service"
## translation happens.
extends Node

var _hud: CanvasLayer
var _mm: Node  # MenuManager

## Cached panel references.
var _inventory: Node
var _character: Node
var _friends: Node
var _party: Node
var _guild: Node
var _trade: Node
var _quest: Node
var _chat: Node
var _admin_toolbar: Node

## Active state.
var _character_data: Resource = null


func bind(hud: CanvasLayer) -> void:
	_hud = hud
	_resolve_panels()
	_connect_services()
	_refresh_from_game_manager()


func _resolve_panels() -> void:
	if not _hud:
		return
	# MenuManager is itself a child; its child panels are accessed via
	# its API (get_panel) or directly by name.
	_mm = _hud.get_node_or_null("MenuManager")
	# Many panels are added to the HudLayer directly (we don't want to
	# duplicate them under MenuManager). We also probe MenuManager.
	_inventory = _find_panel(["InventoryUI", "Inventory"])
	_character = _find_panel(["CharacterPanel", "CharacterUI", "CharacterStatsUI"])
	_friends = _find_panel(["FriendsListUI", "FriendsUI", "FriendsList"])
	_party = _find_panel(["PartyUI"])
	_guild = _find_panel(["GuildUI"])
	_trade = _find_panel(["TradeUI"])
	_quest = _find_panel(["QuestUI", "QuestJournal"])
	_chat = _hud.get_node_or_null("ChatUI")
	_admin_toolbar = _hud.get_node_or_null("AdminToolbar")


func _find_panel(names: Array) -> Node:
	for n in names:
		var p: Node = _hud.get_node_or_null(n)
		if p:
			return p
	if _mm:
		for n in names:
			var p: Node = _mm.get_node_or_null(n)
			if p:
				return p
	return null


func _connect_services() -> void:
	# Party events → PartyUI.
	if _party and PartyService:
		if PartyService.has_signal("player_joined_party"):
			PartyService.player_joined_party.connect(_on_party_member_changed)
		if PartyService.has_signal("player_left_party"):
			PartyService.player_left_party.connect(_on_party_member_changed)
		if PartyService.has_signal("party_created"):
			PartyService.party_created.connect(_on_party_member_changed)
		if PartyService.has_signal("party_disbanded"):
			PartyService.party_disbanded.connect(_on_party_disbanded)

	# Guild events → GuildUI.
	if _guild and GuildService:
		if GuildService.has_signal("player_joined_guild"):
			GuildService.player_joined_guild.connect(_on_guild_changed)
		if GuildService.has_signal("player_left_guild"):
			GuildService.player_left_guild.connect(_on_guild_changed)
		if GuildService.has_signal("guild_info_updated"):
			GuildService.guild_info_updated.connect(_on_guild_changed)

	# Friends events → FriendsListUI.
	if _friends and FriendsService:
		if FriendsService.has_signal("friend_added"):
			FriendsService.friend_added.connect(_on_friends_changed)
		if FriendsService.has_signal("friend_removed"):
			FriendsService.friend_removed.connect(_on_friends_changed)

	# Trade events → TradeUI.
	if _trade and TradeService:
		if TradeService.has_signal("trade_started"):
			TradeService.trade_started.connect(_on_trade_started)
		if TradeService.has_signal("trade_completed"):
			TradeService.trade_completed.connect(_on_trade_completed)
		if TradeService.has_signal("trade_cancelled"):
			TradeService.trade_cancelled.connect(_on_trade_cancelled)
		if TradeService.has_signal("trade_expired"):
			TradeService.trade_expired.connect(_on_trade_expired)
		if TradeService.has_signal("trade_failed"):
			TradeService.trade_failed.connect(_on_trade_failed)

	# Quest events → QuestUI.
	if _quest and QuestService:
		if QuestService.has_signal("quest_accepted"):
			QuestService.quest_accepted.connect(_on_quest_changed)
		if QuestService.has_signal("quest_updated"):
			QuestService.quest_updated.connect(_on_quest_changed)
		if QuestService.has_signal("quest_completed"):
			QuestService.quest_completed.connect(_on_quest_changed)
		if QuestService.has_signal("quest_failed"):
			QuestService.quest_failed.connect(_on_quest_changed)

	# SkillAcademy events → CharacterPanel.
	if _character and SkillAcademyService:
		if SkillAcademyService.has_signal("upgrade_applied"):
			SkillAcademyService.upgrade_applied.connect(_on_skill_upgrade_applied)
		if SkillAcademyService.has_signal("respec_completed"):
			SkillAcademyService.respec_completed.connect(_on_skill_respec_completed)
		if SkillAcademyService.has_signal("signature_selected"):
			SkillAcademyService.signature_selected.connect(_on_signature_selected)

	# Inventory events → InventoryUI + notifications.
	if InventoryService:
		if InventoryService.has_signal("item_transferred"):
			InventoryService.item_transferred.connect(_on_item_transferred)
		if InventoryService.has_signal("gold_transferred"):
			InventoryService.gold_transferred.connect(_on_gold_transferred)

	# SameAccountTransfer events → CharacterTransferUI.
	var char_transfer: Node = _find_panel(["CharacterTransferUI"])
	if char_transfer and SameAccountTransferService:
		if SameAccountTransferService.has_signal("transfer_completed"):
			SameAccountTransferService.transfer_completed.connect(_on_transfer_completed)
		if SameAccountTransferService.has_signal("transfer_cancelled"):
			SameAccountTransferService.transfer_cancelled.connect(_on_transfer_cancelled)
		if SameAccountTransferService.has_signal("transfer_limit_reached"):
			SameAccountTransferService.transfer_limit_reached.connect(_on_transfer_limit_reached)
		if SameAccountTransferService.has_signal("cooldown_active"):
			SameAccountTransferService.cooldown_active.connect(_on_transfer_cooldown_active)

	# QoS events → toast + status bar.
	if QoSService:
		if QoSService.has_signal("connection_quality_changed"):
			QoSService.connection_quality_changed.connect(_on_connection_quality_changed)
		if QoSService.has_signal("latency_warning"):
			QoSService.latency_warning.connect(_on_latency_warning)
		if QoSService.has_signal("throttled"):
			QoSService.throttled.connect(_on_qos_throttled)

	# Blacksmith events → BlacksmithUI.
	if BlacksmithService:
		if BlacksmithService.has_signal("repair_completed"):
			BlacksmithService.repair_completed.connect(_on_repair_completed)
		if BlacksmithService.has_signal("repair_failed"):
			BlacksmithService.repair_failed.connect(_on_repair_failed)
		if BlacksmithService.has_signal("item_too_broken"):
			BlacksmithService.item_too_broken.connect(_on_item_too_broken)

	# Loot events → toast player.
	if LootService:
		if LootService.has_signal("loot_picked_up"):
			LootService.loot_picked_up.connect(_on_loot_picked_up)
		if LootService.has_signal("loot_assigned"):
			LootService.loot_assigned.connect(_on_loot_assigned)
		if LootService.has_signal("loot_expired"):
			LootService.loot_expired.connect(_on_loot_expired)
		if LootService.has_signal("loot_dropped"):
			LootService.loot_dropped.connect(_on_loot_dropped)
		if LootService.has_signal("loot_rolled"):
			LootService.loot_rolled.connect(_on_loot_rolled)

	# Achievement events → toast player (AchievementService is not autoloaded).
	for method_name in ["get_instance"]:
		if AchievementService.has_method(method_name):
			var ach_inst = AchievementService.call(method_name)
			if ach_inst and ach_inst.has_signal("achievement_unlocked"):
				ach_inst.achievement_unlocked.connect(_on_achievement_unlocked)
				if ach_inst and ach_inst.has_signal("achievement_progressed"):
					ach_inst.achievement_progressed.connect(_on_achievement_progressed)
			break

	# Faction events → toast player.
	if FactionManager:
		if FactionManager.has_signal("war_declared"):
			FactionManager.war_declared.connect(_on_faction_war_declared)
		if FactionManager.has_signal("war_ended"):
			FactionManager.war_ended.connect(_on_faction_war_ended)
		if FactionManager.has_signal("reputation_changed"):
			FactionManager.reputation_changed.connect(_on_reputation_changed)

	# RespawnService events -> toast.
	if RespawnService:
		if RespawnService.has_signal("respawn_completed"):
			RespawnService.respawn_completed.connect(_on_respawn_completed)
		if RespawnService.has_signal("karma_gained"):
			RespawnService.karma_gained.connect(_on_karma_gained)
		if RespawnService.has_signal("karma_lost"):
			RespawnService.karma_lost.connect(_on_karma_lost)

	# DeathFeatures events -> toast.
	if DeathFeatures:
		if DeathFeatures.has_signal("kill_streak_rewarded"):
			DeathFeatures.kill_streak_rewarded.connect(_on_kill_streak_rewarded)
		if DeathFeatures.has_signal("death_penalty_applied"):
			DeathFeatures.death_penalty_applied.connect(_on_death_penalty_applied)

	# VaultService events -> refresh BankUI.
	if VaultService:
		if VaultService.has_signal("item_deposited"):
			VaultService.item_deposited.connect(_on_vault_item_changed)
		if VaultService.has_signal("item_withdrawn"):
			VaultService.item_withdrawn.connect(_on_vault_item_changed)
		if VaultService.has_signal("gold_deposited"):
			VaultService.gold_deposited.connect(_on_vault_gold_changed)
		if VaultService.has_signal("gold_withdrawn"):
			VaultService.gold_withdrawn.connect(_on_vault_gold_changed)

	# Entity events (player join/leave).
	if EntityService:
		if EntityService.has_signal("player_joined"):
			EntityService.player_joined.connect(_on_player_joined)
		if EntityService.has_signal("player_left"):
			EntityService.player_left.connect(_on_player_left)


	# ZoneManager events.
	if ZoneManager:
		if ZoneManager.has_signal("player_entered_zone"):
			ZoneManager.player_entered_zone.connect(_on_player_entered_zone)

	# CommunityGovernance events.
	if CommunityGovernance:
		if CommunityGovernance.has_signal("level_up"):
			CommunityGovernance.level_up.connect(_on_level_up)
		if CommunityGovernance.has_signal("vote_created"):
			CommunityGovernance.vote_created.connect(_on_vote_created)
		if CommunityGovernance.has_signal("vote_closed"):
			CommunityGovernance.vote_closed.connect(_on_vote_closed)
		if CommunityGovernance.has_signal("vote_expired"):
			CommunityGovernance.vote_expired.connect(_on_vote_expired)

	# FactionManager: alliance_formed.
	if FactionManager:
		if FactionManager.has_signal("alliance_formed"):
			FactionManager.alliance_formed.connect(_on_alliance_formed)

	# RespawnService: respawn_canceled.
	if RespawnService:
		if RespawnService.has_signal("respawn_canceled"):
			RespawnService.respawn_canceled.connect(_on_respawn_canceled)

	# Character creation events → CharacterPanel refresh.
	if GameManager:
		GameManager.game_state_changed.connect(_on_game_state_changed)


func _refresh_from_game_manager() -> void:
	if not GameManager:
		return
	_apply_character_data(GameManager.selected_character_data)


func _on_game_state_changed(_state: int) -> void:
	# Reload character data when we transition to PLAYING (the player
	# may have just chosen a character).
	_apply_character_data(GameManager.selected_character_data)


func _apply_character_data(data: Resource) -> void:
	_character_data = data
	if not data:
		return
	if _character and _character.has_method("set_character_data"):
		_character.set_character_data(data)
	elif _character and _character.has_method("refresh_stats"):
		_character.refresh_stats()
	if _inventory and _inventory.has_method("refresh_inventory"):
		_inventory.refresh_inventory()


# ── Party ────────────────────────────────────────────────────────────────

func _on_party_member_changed(_a = null, _b = null, _c = null) -> void:
	if _party and _party.has_method("refresh"):
		_party.refresh()


func _on_party_disbanded(_party_id: String) -> void:
	if _party and _party.has_method("refresh"):
		_party.refresh()
	if _mm and _mm.has_method("close_menu"):
		_mm.close_menu("party")


# ── Guild ────────────────────────────────────────────────────────────────

func _on_guild_changed(_a = null, _b = null, _c = null) -> void:
	if _guild and _guild.has_method("refresh_all"):
		_guild.refresh_all()


# ── Friends ──────────────────────────────────────────────────────────────

func _on_friends_changed(_a = null, _b = null) -> void:
	if _friends and _friends.has_method("refresh_all"):
		_friends.refresh_all()


# ── Trade ───────────────────────────────────────────────────────────────

func _on_trade_started(trade_id: String, player1: String, player2: String) -> void:
	if _trade and _trade.has_method("open_trade"):
		_trade.open_trade(player1, player2)
	if _mm and _mm.has_method("open_menu"):
		_mm.open_menu("trade")


func _on_trade_completed(_trade_id: String, _trades: Dictionary) -> void:
	if _mm and _mm.has_method("close_menu"):
		_mm.close_menu("trade")


func _on_trade_cancelled(_trade_id: String, _cancelled_by: String) -> void:
	if _mm and _mm.has_method("close_menu"):
		_mm.close_menu("trade")


func _on_trade_expired(_trade_id: String) -> void:
	if _mm and _mm.has_method("close_menu"):
		_mm.close_menu("trade")


func _on_trade_failed(_trade_id: String) -> void:
	if _mm and _mm.has_method("close_menu"):
		_mm.close_menu("trade")


# ── Quest ────────────────────────────────────────────────────────────────

func _on_quest_changed(_a = null, _b = null, _c = null, _d = null) -> void:
	if _quest and _quest.has_method("refresh_quest_list"):
		_quest.refresh_quest_list()


# ── SkillAcademy ─────────────────────────────────────────────────────────

func _on_skill_upgrade_applied(_player_id: String, skill_id: String, new_level: int) -> void:
	if _character and _character.has_method("refresh_skills"):
		_character.refresh_skills()
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.SKILL_UPGRADED,
			"Skill upgraded to level %d" % new_level,
			"SkillAcademyService",
			"skill_upgrade:%s:%s" % [_player_id, skill_id],
			{"skill_id": skill_id, "new_level": new_level},
			_player_id
		)

func _on_skill_respec_completed(_player_id: String, points_refunded: int) -> void:
	if _character and _character.has_method("refresh_skills"):
		_character.refresh_skills()
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.SKILL_RESPEC,
			"Respec complete: %d points refunded" % points_refunded,
			"SkillAcademyService",
			"skill_respec:%s" % _player_id,
			{"points_refunded": points_refunded},
			_player_id
		)

func _on_signature_selected(_player_id: String, signature_id: String, _is_free: bool) -> void:
	if _character and _character.has_method("refresh_skills"):
		_character.refresh_skills()


# ── Inventory ────────────────────────────────────────────────────────────

func _on_item_transferred(from_id: String, to_id: String, _item, quantity: int) -> void:
	if _inventory and _inventory.has_method("refresh_inventory"):
		_inventory.refresh_inventory()
	if is_instance_valid(NotificationService):
		var msg := "Transferred %d items" % quantity
		NotificationService.notify(
			NotificationService.NotifKind.ITEM_TRANSFERRED,
			msg,
			"InventoryService",
			"item_transfer:%s:%s:%d" % [from_id, to_id, quantity],
			{"from": from_id, "to": to_id, "quantity": quantity},
			""
		)

func _on_gold_transferred(from_id: String, to_id: String, amount: int) -> void:
	if _inventory and _inventory.has_method("refresh_inventory"):
		_inventory.refresh_inventory()
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.GOLD_TRANSFERRED,
			"Transferred %d gold" % amount,
			"InventoryService",
			"gold_transfer:%s:%s:%d" % [from_id, to_id, amount],
			{"from": from_id, "to": to_id, "amount": amount},
			""
		)


# ── SameAccountTransfer ────────────────────────────────────────

func _on_transfer_completed(from_char: String, to_char: String, gold: int, items: Array) -> void:
	var char_transfer: Node = _find_panel(["CharacterTransferUI"])
	if char_transfer and char_transfer.has_method("refresh"):
		char_transfer.refresh()
	if _inventory and _inventory.has_method("refresh_inventory"):
		_inventory.refresh_inventory()
	if is_instance_valid(NotificationService):
		var msg := "Transfer complete: %d gold, %d items" % [gold, items.size()]
		NotificationService.notify(
			NotificationService.NotifKind.ITEM_TRANSFERRED,
			msg,
			"SameAccountTransferService",
			"transfer:%s:%s" % [from_char, to_char],
			{"from": from_char, "to": to_char, "gold": gold, "items": items.size()},
			from_char
		)

func _on_transfer_cancelled(from_char: String, to_char: String, reason: String) -> void:
	var char_transfer: Node = _find_panel(["CharacterTransferUI"])
	if char_transfer and char_transfer.has_method("refresh"):
		char_transfer.refresh()

func _on_transfer_limit_reached(account_id: String, limit_type: String) -> void:
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.ITEM_FULL,
			"Transfer limit reached: %s" % limit_type,
			"SameAccountTransferService",
			"transfer_limit:%s:%s" % [account_id, limit_type],
			{"limit_type": limit_type},
			""
		)
# ── Blacksmith ─────────────────────────────────────────────────────────

func _on_repair_completed(player_id: String, items_repaired: int, total_cost: int) -> void:
	var bs_panel: Node = _find_panel(["BlacksmithUI"])
	if bs_panel and bs_panel.has_method("refresh"):
		bs_panel.refresh()
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.ITEM_REPAIRED,
			"Repaired %d items for %d gold!" % [items_repaired, total_cost],
			"BlacksmithService",
			"repair:%s:%d" % [player_id, items_repaired],
			{"items_repaired": items_repaired, "total_cost": total_cost},
			player_id
		)

func _on_repair_failed(player_id: String, reason: String) -> void:
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.SYSTEM,
			reason,
			"BlacksmithService",
			"repair_fail:%s:%d" % [player_id, reason.hash()],
			{"reason": reason},
			player_id
		)

func _on_item_too_broken(player_id: String, item_id: String) -> void:
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.ITEM_FULL,
			"Item %s is too damaged to repair." % item_id,
			"BlacksmithService",
			"too_broken:%s:%s" % [player_id, item_id],
			{"item_id": item_id},
			player_id
		)

# ── Loot ────────────────────────────────────────────────────────────────

func _on_loot_picked_up(player_id: String, items: Array) -> void:
	if is_instance_valid(NotificationService):
		var names := items.map(func(it): return it.get("display_name", "?") if it else "?")
		var msg := "Loot: %s" % ", ".join(names) if not names.is_empty() else "Loot picked up"
		NotificationService.notify(
			NotificationService.NotifKind.LOOT_DROPPED,
			msg,
			"LootService",
			"loot:%s:%d" % [player_id, items.size()],
			{"item_count": items.size()},
			player_id
		)

func _on_loot_assigned(loot_id: String, player_id: String, items: Array) -> void:
	if is_instance_valid(NotificationService):
		var names := items.map(func(it): return it.get("display_name", "?") if it else "?")
		var msg := "You won: %s" % ", ".join(names)
		NotificationService.notify(
			NotificationService.NotifKind.ITEM_ADDED,
			msg,
			"LootService",
			"loot_win:%s:%s" % [loot_id, player_id],
			{"loot_id": loot_id, "item_count": items.size()},
			player_id
		)

func _on_loot_expired(loot_id: String) -> void:
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.SYSTEM,
			"Loot expired and was discarded.",
			"LootService",
			"loot_expired:%s" % loot_id,
			{"loot_id": loot_id},
			""
		)

func _on_loot_dropped(source_id: String, loot_id: String, items: Array, currency: Dictionary) -> void:
	if not is_instance_valid(NotificationService):
		return
	var item_count := items.size() if items else 0
	var msg := "Loot dropped: %d item%s" % [item_count, "s" if item_count != 1 else ""]
	NotificationService.notify(
		NotificationService.NotifKind.LOOT_DROPPED,
		msg,
		"LootService",
		"loot_dropped:%s" % loot_id,
		{"loot_id": loot_id, "item_count": item_count, "source_id": source_id},
		""
	)

func _on_loot_rolled(loot_id: String, player_id: String, roll_type, roll_value: int) -> void:
	if not is_instance_valid(NotificationService):
		return
	var roll_name := "Need" if roll_type == 0 else "Greed" if roll_type == 1 else "Pass"
	NotificationService.notify(
		NotificationService.NotifKind.SYSTEM,
		"You rolled %s: %d" % [roll_name, roll_value],
		"LootService",
		"loot_roll:%s:%s" % [loot_id, player_id],
		{"loot_id": loot_id, "roll_type": roll_type, "roll_value": roll_value},
		player_id
	)

# ── Achievement ────────────────────────────────────────────────────────

func _on_achievement_unlocked(player_id: String, achievement_id: String) -> void:
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.ACHIEVEMENT_UNLOCKED,
			"Achievement unlocked: %s" % achievement_id,
			"AchievementService",
			"achieve:%s:%s" % [player_id, achievement_id],
			{"achievement_id": achievement_id},
			player_id
		)

func _on_achievement_progressed(player_id: String, achievement_id: String, progress: float) -> void:
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.ACHIEVEMENT_PROGRESSED,
			"Achievement progress: %s (%.0f%%)" % [achievement_id, progress * 100.0],
			"AchievementService",
			"achieve_progress:%s:%s" % [player_id, achievement_id],
			{"achievement_id": achievement_id, "progress": progress},
			player_id
		)

# ── Faction ────────────────────────────────────────────────────────────

func _on_faction_war_declared(faction1, faction2) -> void:
	if is_instance_valid(NotificationService):
		var n1 := faction1.get("faction_name", "?") if faction1 else "?"
		var n2 := faction2.get("faction_name", "?") if faction2 else "?"
		NotificationService.notify(
			NotificationService.NotifKind.SYSTEM,
			"War declared: %s vs %s" % [n1, n2],
			"FactionManager",
			"war_declared:%s:%s" % [n1, n2],
			{},
			""
		)

func _on_faction_war_ended(faction1, faction2) -> void:
	if is_instance_valid(NotificationService):
		var n1 := faction1.get("faction_name", "?") if faction1 else "?"
		var n2 := faction2.get("faction_name", "?") if faction2 else "?"
		NotificationService.notify(
			NotificationService.NotifKind.SYSTEM,
			"War ended between %s and %s" % [n1, n2],
			"FactionManager",
			"war_ended:%s:%s" % [n1, n2],
			{},
			""
		)

func _on_reputation_changed(player_id: String, faction_id: String, old_rep: int, new_rep: int) -> void:
	var delta := new_rep - old_rep
	if delta == 0:
		return
	var sign := "+" if delta > 0 else ""
	var msg := "Faction reputation %s%d (now %d)" % [sign, delta, new_rep]
	NotificationService.notify(
		NotificationService.NotifKind.SYSTEM,
		msg,
		"FactionManager",
		"rep:%s:%s:%d" % [player_id, faction_id, new_rep],
		{"faction_id": faction_id, "old": old_rep, "new": new_rep, "delta": delta},
		player_id
	)

# ── Entity ─────────────────────────────────────────────────────────────

func _on_player_joined(player, metadata) -> void:
	pass  # Future: update player count in minimap/HUD

func _on_player_left(player, metadata) -> void:
	pass  # Future: update player count in minimap/HUD

func _on_player_entered_zone(player, zone) -> void:
	if not is_instance_valid(NotificationService):
		return
	var pid := player.entity_id if player and "entity_id" in player else ""
	var zone_name := zone.get("zone_name", "?") if zone else "?"
	NotificationService.notify(
		NotificationService.NotifKind.ZONE_CHANGED,
		"Entered: %s" % zone_name,
		"ZoneManager",
		"zone_enter:%s:%s" % [pid, zone_name],
		{"zone_name": zone_name},
		pid
	)

func _on_level_up(player_id: String, new_level: int) -> void:
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.LEVEL_UP,
			"Level up! You are now level %d" % new_level,
			"CommunityGovernance",
			"level_up:%s:%d" % [player_id, new_level],
			{"new_level": new_level},
			player_id
		)

func _on_vote_created(vote) -> void:
	if is_instance_valid(NotificationService):
		var title := vote.get("title", "?") if vote else "?"
		NotificationService.notify(
			NotificationService.NotifKind.VOTE_CREATED,
			"New vote: %s" % title,
			"CommunityGovernance",
			"vote_created:%s" % title.hash(),
			{"title": title},
			""
		)

func _on_vote_closed(vote) -> void:
	if is_instance_valid(NotificationService):
		var title := vote.get("title", "?") if vote else "?"
		NotificationService.notify(
			NotificationService.NotifKind.VOTE_ENDED,
			"Vote closed: %s" % title,
			"CommunityGovernance",
			"vote_closed:%s" % title.hash(),
			{"title": title},
			""
		)

func _on_vote_expired(vote) -> void:
	if is_instance_valid(NotificationService):
		var title := vote.get("title", "?") if vote else "?"
		NotificationService.notify(
			NotificationService.NotifKind.VOTE_ENDED,
			"Vote expired: %s" % title,
			"CommunityGovernance",
			"vote_expired:%s" % title.hash(),
			{"title": title},
			""
		)

func _on_alliance_formed(guild_id: String, faction) -> void:
	if is_instance_valid(NotificationService):
		var faction_name := faction.get("faction_name", "?") if faction else "?"
		NotificationService.notify(
			NotificationService.NotifKind.SYSTEM,
			"Alliance formed: %s" % faction_name,
			"FactionManager",
			"alliance:%s:%s" % [guild_id, faction_name],
			{"faction_name": faction_name},
			""
		)

# --- SameAccountTransfer ---------------------------------------------

func _on_transfer_cooldown_active(account_id: String, seconds_remaining: int) -> void:
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.SAME_ACCOUNT_TRANSFER_COOLDOWN,
			"Transfer on cooldown: %d seconds remaining" % seconds_remaining,
			"SameAccountTransferService",
			"cooldown:%s:%d" % [account_id, seconds_remaining],
			{"seconds_remaining": seconds_remaining},
			""
		)

# --- QoS -----------------------------------------------------------

func _on_connection_quality_changed(player_id: String, quality) -> void:
	# ConnectionQuality enum: QoSService.ConnectionQuality.keys()[value] -> name string.
	var quality_str := str(quality)  # fallback to integer if not resolved
	if QoSService and typeof(quality) == TYPE_INTEGER:
		var keys := QoSService.ConnectionQuality.keys()
		if quality >= 0 and quality < keys.size():
			quality_str = keys[quality]
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.CONNECTION_QUALITY,
			"Connection: %s" % quality_str,
			"QoSService",
			"qos_conn:%s:%s" % [player_id, quality_str],
			{"quality": quality_str},
			player_id
		)

func _on_latency_warning(player_id: String, latency_ms: int) -> void:
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.QOS_DEGRADED,
			"High latency: %dms" % latency_ms,
			"QoSService",
			"qos_lat:%s:%d" % [player_id, latency_ms],
			{"latency_ms": latency_ms},
			player_id
		)

func _on_qos_throttled(player_id: String, reason: String) -> void:
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.THROTTLED,
			reason,
			"QoSService",
			"qos_throttle:%s" % player_id,
			{"reason": reason},
			player_id
		)

# --- Respawn -------------------------------------------------------

func _on_respawn_completed(player, respawn_point) -> void:
	var pid := player.entity_id if player and "entity_id" in player else ""
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.RESPAWNED,
			"You have respawned.",
			"RespawnService",
			"respawn:%s" % pid,
			{},
			pid
		)

func _on_respawn_canceled(player, reason: String) -> void:
	var pid := player.entity_id if player and "entity_id" in player else ""
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.SYSTEM,
			"Respawn cancelled: %s" % reason,
			"RespawnService",
			"respawn_canceled:%s" % pid,
			{"reason": reason},
			pid
		)

func _on_karma_gained(entity_id: String, amount: int, reason: String) -> void:
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.KARMA_CHANGED,
			"Karma +%d (%s)" % [amount, reason],
			"RespawnService",
			"karma_gain:%s:%d" % [entity_id, amount],
			{"amount": amount, "reason": reason},
			entity_id
		)

func _on_karma_lost(entity_id: String, amount: int, reason: String) -> void:
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.KARMA_CHANGED,
			"Karma -%d (%s)" % [amount, reason],
			"RespawnService",
			"karma_loss:%s:%d" % [entity_id, amount],
			{"amount": amount, "reason": reason},
			entity_id
		)

# --- DeathFeatures -------------------------------------------------

func _on_kill_streak_rewarded(killer_id: String, streak: int, xp_bonus: int, gold_bonus: int) -> void:
	if is_instance_valid(NotificationService):
		NotificationService.notify(
			NotificationService.NotifKind.KILL_STREAK,
			"Kill streak %d! +%d XP, +%d gold" % [streak, xp_bonus, gold_bonus],
			"DeathFeatures",
			"kill_streak:%s:%d" % [killer_id, streak],
			{"streak": streak, "xp_bonus": xp_bonus, "gold_bonus": gold_bonus},
			killer_id
		)

func _on_death_penalty_applied(entity_id: String, xp_loss: int, gold_loss: int, durability_loss: float) -> void:
	if is_instance_valid(NotificationService):
		var parts := []
		if xp_loss > 0:
			parts.append("-%d XP" % xp_loss)
		if gold_loss > 0:
			parts.append("-%d gold" % gold_loss)
		if durability_loss > 0:
			parts.append("-%.0f%% durability" % (durability_loss * 100))
		var msg := "Death penalty: " + ", ".join(parts) if not parts.is_empty() else "Death penalty applied"
		NotificationService.notify(
			NotificationService.NotifKind.RESPAWN_PENALTY_APPLIED,
			msg,
			"DeathFeatures",
			"death_penalty:%s" % entity_id,
			{"xp_loss": xp_loss, "gold_loss": gold_loss, "durability_loss": durability_loss},
			entity_id
		)

# --- Vault ---------------------------------------------------------

func _on_vault_item_changed(player_id: String, vault_type, item_id: String, quantity: int) -> void:
	var bank_panel: Node = _find_panel(["BankUI", "VaultUI"])
	if bank_panel and bank_panel.has_method("_refresh_vault"):
		bank_panel._refresh_vault()

func _on_vault_gold_changed(player_id: String, vault_type, amount: int) -> void:
	var bank_panel: Node = _find_panel(["BankUI", "VaultUI"])
	if bank_panel and bank_panel.has_method("_refresh_vault"):
		bank_panel._refresh_vault()


