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
	if _guild and _guild.has_method("refresh"):
		_guild.refresh()


# ── Friends ──────────────────────────────────────────────────────────────

func _on_friends_changed(_a = null, _b = null) -> void:
	if _friends and _friends.has_method("refresh"):
		_friends.refresh()


# ── Trade ───────────────────────────────────────────────────────────────

func _on_trade_started(initiator_id: String, target_id: String) -> void:
	if _trade and _trade.has_method("open_trade"):
		_trade.open_trade(initiator_id, target_id)
	if _mm and _mm.has_method("open_menu"):
		_mm.open_menu("trade")


func _on_trade_completed(_initiator_id: String, _target_id: String, _success: bool) -> void:
	if _mm and _mm.has_method("close_menu"):
		_mm.close_menu("trade")


# ── Quest ────────────────────────────────────────────────────────────────

func _on_quest_changed(_a = null, _b = null, _c = null, _d = null) -> void:
	if _quest and _quest.has_method("refresh"):
		_quest.refresh()
