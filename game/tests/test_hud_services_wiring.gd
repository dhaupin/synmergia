## HUD services wiring receipt: every service->panel connection must be
## established by _connect_services() at bind time, NOT captured inside a
## one-shot event handler.
##
## The bug this locks: the "Consumer-side round" (8cef98b) inserted the
## xp_shared -> party-refresh handler IN THE MIDDLE of _connect_services,
## so the ~180 lines of guild/friends/trade/quest/skill/inventory/loot/
## faction/respawn/vault wiring below it became the BODY of _on_xp_shared.
## Those signals were therefore only connected the first time a party
## shared XP -- and because re-connecting an already-connected Callable
## raises ERR_INVALID_PARAMETER, a guild/trade/quest event could also
## raise on every fire after that. Panels that did not self-bind (TradeUI
## opens on trade_started; QuestUI's refresh) went dead.
##
## Legs:
##   1. After _connect_services(), the guild signal is connected and a
##      real emit reaches the panel's refresh.
##   2. trade_started opens the trade panel and the MenuManager menu.
##   3. quest_accepted refreshes the quest panel.
##   4. xp_shared still refreshes the party panel (the intended handler).
##   5. REGRESSION LOCK: calling _on_xp_shared directly on a fresh,
##      unbound instance must NOT connect the guild signal -- the wiring
##      belongs to _connect_services, never to the event handler.
##
## Run with:
##   godot --headless --path game/ --script res://tests/test_hud_services_wiring.gd
extends SceneTree

var _passed: int = 0
var _failed: int = 0


class FakeGuild extends Node:
	var refreshed: int = 0
	func refresh_all() -> void:
		refreshed += 1


class FakeParty extends Node:
	var refreshed: int = 0
	func refresh() -> void:
		refreshed += 1


class FakeTrade extends Node:
	var opened: Array = []
	func open_trade(p1: String, p2: String) -> void:
		opened.append([p1, p2])


class FakeQuest extends Node:
	var refreshed: int = 0
	func refresh_quest_list() -> void:
		refreshed += 1


class FakeMM extends Node:
	var opened: Array = []
	var closed: Array = []
	func open_menu(menu_name: String, _npc_pos = null) -> void:
		opened.append(menu_name)
	func close_menu(menu_name: String) -> void:
		closed.append(menu_name)


func _initialize() -> void:
	print("--- HUD SERVICES WIRING ---")
	await process_frame
	_test_connect_services_wires_social_signals()
	_test_regression_handler_does_not_wire()
	_finish()


func _mk_bound_instance() -> Array:
	var hs = load("res://ui/hud/hud_services.gd").new()
	root.add_child(hs)
	var hud := CanvasLayer.new()
	root.add_child(hud)
	hs._hud = hud
	var guild := FakeGuild.new()
	var party := FakeParty.new()
	var trade := FakeTrade.new()
	var quest := FakeQuest.new()
	var mm := FakeMM.new()
	root.add_child(guild)
	root.add_child(party)
	root.add_child(trade)
	root.add_child(quest)
	root.add_child(mm)
	hs._guild = guild
	hs._party = party
	hs._trade = trade
	hs._quest = quest
	hs._mm = mm
	return [hs, guild, party, trade, quest, mm]


func _test_connect_services_wires_social_signals() -> void:
	var ctx := _mk_bound_instance()
	var hs: Node = ctx[0]
	var guild: Node = ctx[1]
	var party: Node = ctx[2]
	var trade: Node = ctx[3]
	var quest: Node = ctx[4]
	var mm: Node = ctx[5]

	hs._connect_services()

	var guild_svc = root.get_node_or_null("GuildService")
	if guild_svc == null:
		_fail("GuildService autoload missing")
		return

	# 1. Guild signal connected at bind time, emit reaches the panel.
	_assert(guild_svc.player_joined_guild.is_connected(hs._on_guild_changed),
		"guild player_joined_guild connected by _connect_services")
	guild_svc.player_joined_guild.emit("g1", "p1", 0)
	_assert(guild.refreshed == 1, "guild emit refreshes the guild panel (got %d)" % guild.refreshed)

	# 2. trade_started opens the trade panel + the MenuManager menu.
	var trade_svc = root.get_node_or_null("TradeService")
	if trade_svc:
		_assert(trade_svc.trade_started.is_connected(hs._on_trade_started),
			"trade_started connected by _connect_services")
		trade_svc.trade_started.emit("t1", "p1", "p2")
		_assert(trade.opened.size() == 1, "trade_started opens the trade panel (got %d)" % trade.opened.size())
		_assert(mm.opened.has("trade"), "trade_started opens the trade menu")

	# 3. quest_accepted refreshes the quest panel.
	var quest_svc = root.get_node_or_null("QuestService")
	if quest_svc:
		_assert(quest_svc.quest_accepted.is_connected(hs._on_quest_changed),
			"quest_accepted connected by _connect_services")
		quest_svc.quest_accepted.emit("p1", "q1")
		_assert(quest.refreshed == 1, "quest_accepted refreshes the quest panel (got %d)" % quest.refreshed)

	# 4. xp_shared still refreshes the party panel (the intended handler).
	var party_svc = root.get_node_or_null("PartyService")
	if party_svc and party_svc.has_signal("xp_shared"):
		party_svc.xp_shared.emit("party1", 100, {}, "p1")
		_assert(party.refreshed >= 1, "xp_shared refreshes the party panel")

	hs.queue_free()
	guild.queue_free()
	party.queue_free()
	trade.queue_free()
	quest.queue_free()
	mm.queue_free()


## The regression lock: the guild wiring must live in _connect_services,
## not inside the xp_shared handler. A fresh instance whose _on_xp_shared
## is called directly (no _connect_services) must leave the guild signal
## untouched by THIS instance's handler.
func _test_regression_handler_does_not_wire() -> void:
	var hs = load("res://ui/hud/hud_services.gd").new()
	root.add_child(hs)
	var hud := CanvasLayer.new()
	root.add_child(hud)
	hs._hud = hud
	var guild := FakeGuild.new()
	root.add_child(guild)
	hs._guild = guild

	var guild_svc = root.get_node_or_null("GuildService")
	if guild_svc == null:
		_fail("GuildService autoload missing")
		return

	hs._on_xp_shared("party1", 100, {}, "p1")
	_assert(not guild_svc.player_joined_guild.is_connected(hs._on_guild_changed),
		"_on_xp_shared does NOT wire guild signals (wiring is _connect_services's job)")
	_assert(guild.refreshed == 0, "no guild refresh from a bare xp_shared call")

	hs.queue_free()
	guild.queue_free()


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  PASS: ", label)
	else:
		_failed += 1
		print("  FAIL: ", label)


func _fail(label: String) -> void:
	_failed += 1
	print("  FAIL: ", label)


func _finish() -> void:
	print("--- RESULT: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
