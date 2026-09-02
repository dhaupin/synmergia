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
