## HudIntegrator - Wires the HUD widgets to live game data.
##
## Sits alongside HudLayer. Connects:
##   - PlayerManager health/mana/exp -> MenuManager status bars
##   - TargetingManager target_* -> TargetFrame + BossHealthBar
##   - EntityService entity_spawned/died -> CombatLog + floating nameplate (entities/floating_name.gd)
##   - EventHub entity_died, player_died -> CombatLog kill messages
##   - ChatService message_received -> ChatUI
##   - NotificationService notifications -> SystemCombatLog entries
##
## All connections are guarded by `has_signal`/`has_method` so a missing
## service or widget silently no-ops.
extends Node
const UIStyles = preload("res://ui/components/ui_styles.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind


const HudLayer := preload("res://ui/hud/hud_layer.gd")

var _hud: CanvasLayer
var _mm: Node  # MenuManager
var _action_bar: Node
var _quick_access_bar: Node
var _buff_bar: Node
var _combat_log: Node
var _target_frame: Node
var _boss_health_bar: Node
var _horde_bar: Node
var _action_menu: Node
var _minimap: Node
## Damped heading (radians) fed to the minimap arrow each frame.
var _last_player_yaw: float = 0.0
var _world_map: Node
var _chat: Node
var _tooltip: Node
## Dedicated toast face (ui/components/notification_toast.gd) -- the rich
## corner stack with types/click actions/notification center. Legacy
## TooltipManager.show_toast() remains the fallback for HUD scenes that
## predate this wiring.
var _toast_face: Node
## Rolling 5s gate for the double-wired notification_sent/
## notification_received pair: one send() hits _on_notification twice with
## identical payloads, and the toast stack should only see it once.
var _toast_seen: Dictionary = {}

## True when a toast with this key fired inside the last 5 seconds.
func _toast_dedupe_key(key: String) -> bool:
	var now := Time.get_ticks_msec()
	var seen_at: int = int(_toast_seen.get(key, -100000))
	if now - seen_at < 5000:
		return true
	_toast_seen[key] = now
	# Sweep stale keys so the map cannot grow unbounded.
	if _toast_seen.size() > 64:
		for k in _toast_seen.keys():
			if now - int(_toast_seen[k]) >= 5000:
				_toast_seen.erase(k)
	if _toast_seen.size() > 128:
		_toast_seen.clear()
	return false

## Track active target so the boss bar can fall back when clearing.
var _current_target: Dictionary = {}
## SkyTotem (aurora windows) — WeatherEventService wiring below.
var _sky_totem: Node


func bind(hud: CanvasLayer) -> void:
	_hud = hud
	_mm = _find("MenuManager")
	_action_bar = _find("ActionBar")
	_quick_access_bar = _find("QuickAccessBar")
	_buff_bar = _find("BuffBar")
	_combat_log = _find("CombatLog")
	_target_frame = _find("TargetFrame")
	_boss_health_bar = _find("BossHealthBar")
	_horde_bar = _find("HordeBar")
	_sky_totem = _find("SkyTotem")
	_minimap = _find("Minimap")
	_world_map = _find("WorldMap")
	_chat = _find("ChatUI")
	_tooltip = _find("TooltipManager")
	_toast_face = _find("NotificationToast")
	_action_menu = _find("ActionMenu")
	_connect_all()
	_push_initial_state()


func _find(node_name: String) -> Node:
	if not _hud:
		return null
	var node: Node = _hud.get_node_or_null(node_name)
	if node:
		return node
	if _mm:
		return _mm.get_node_or_null(node_name)
	return null


func _connect_all() -> void:
	# Player resources -> MenuManager status bars (HP/MP/XP).
	if PlayerManager:
		if not PlayerManager.health_changed.is_connected(_on_health_changed):
			PlayerManager.health_changed.connect(_on_health_changed)
		if not PlayerManager.mana_changed.is_connected(_on_mana_changed):
			PlayerManager.mana_changed.connect(_on_mana_changed)
		if not PlayerManager.experience_changed.is_connected(_on_xp_changed):
			PlayerManager.experience_changed.connect(_on_xp_changed)
		if not PlayerManager.level_up.is_connected(_on_level_up):
			PlayerManager.level_up.connect(_on_level_up)
		if not PlayerManager.died.is_connected(_on_player_died):
			PlayerManager.died.connect(_on_player_died)

	# Targeting -> TargetFrame + BossHealthBar.
	if TargetingManager:
		if not TargetingManager.target_acquired.is_connected(_on_target_acquired):
			TargetingManager.target_acquired.connect(_on_target_acquired)
		if not TargetingManager.target_cleared.is_connected(_on_target_cleared):
			TargetingManager.target_cleared.connect(_on_target_cleared)
		if not TargetingManager.target_updated.is_connected(_on_target_updated):
			TargetingManager.target_updated.connect(_on_target_updated)
		if not TargetingManager.action_executed.is_connected(_on_action_executed):
			TargetingManager.action_executed.connect(_on_action_executed)

	# Entity lifecycle -> CombatLog + floating nameplate.
	if EntityService:
		if EntityService.has_signal("entity_registered") \
				and not EntityService.entity_registered.is_connected(_on_entity_spawned):
			EntityService.entity_registered.connect(_on_entity_spawned)
		if EntityService.has_signal("entity_unregistered") \
				and not EntityService.entity_unregistered.is_connected(_on_entity_unregistered):
			EntityService.entity_unregistered.connect(_on_entity_unregistered)
		if EntityService.has_signal("player_joined") \
				and not EntityService.player_joined.is_connected(_on_entity_spawned):
			EntityService.player_joined.connect(_on_entity_spawned)
		if EntityService.has_signal("player_left") \
				and not EntityService.player_left.is_connected(_on_entity_unregistered):
			EntityService.player_left.connect(_on_entity_unregistered)

	# Death events -> kill messages in the combat log.
	if EventHub:
		if EventHub.has_signal("entity_died") \
				and not EventHub.entity_died.is_connected(_on_entity_died):
			EventHub.entity_died.connect(_on_entity_died)

	# Chat messages -> ChatUI.
	if ChatService and ChatService.has_signal("message_received") \
			and not ChatService.message_received.is_connected(_on_chat_received):
		ChatService.message_received.connect(_on_chat_received)

	# Notifications -> CombatLog system messages.
	if NotificationService:
		if NotificationService.has_signal("notification_received") \
				and not NotificationService.notification_received.is_connected(_on_notification):
			NotificationService.notification_received.connect(_on_notification)
		if NotificationService.has_signal("notification_sent") \
				and not NotificationService.notification_sent.is_connected(_on_notification):
			NotificationService.notification_sent.connect(_on_notification)

	# Buff/Debuff signals from the local player's AuraComponent.
	# Use a call_deferred so PlayerManager.local_player is settled.
	_bind_aura_signals()

	# ActionMenu -> handle trade, follow, inspect, etc.
	if _action_menu and _action_menu.has_signal("action_selected"):
		_action_menu.action_selected.connect(_on_action_selected)

	# SlotService container lifecycle -> MenuManager's ContainerUI.
	# The storage consumer the container_opened signal was designed
	# for: every service-driven open/close of a store session now
	# reaches a real panel (routing rides the ONE funnel law through
	# MenuManager.open_menu so the touch HUD + back stack agree).
	var slot_svc := _slot_service()
	if slot_svc != null and slot_svc.has_signal("container_opened"):
		if not slot_svc.container_opened.is_connected(_on_container_opened):
			slot_svc.container_opened.connect(_on_container_opened)
		if not slot_svc.container_closed.is_connected(_on_container_closed):
			slot_svc.container_closed.connect(_on_container_closed)

	# Controller plug/drop -> the connection toast (the pad's soft
	# state was invisible for the whole scaffolding era; the pair
	# signals sat with one leg emitting blind and one leg dead).
	if not InputManager.controller_connected.is_connected(_on_controller_connected):
		InputManager.controller_connected.connect(_on_controller_connected)
	if not InputManager.controller_disconnected.is_connected(_on_controller_disconnected):
		InputManager.controller_disconnected.connect(_on_controller_disconnected)

	# The whiff line: CombatSystem's skill_missed -> CombatLog.log_miss
	# (the miss leg was silent for the whole scaffolding era; the
	# log's own miss row had zero callers).
	var combat_svc := get_node_or_null("/root/CombatSystem")
	if combat_svc and combat_svc.has_signal("skill_missed"):
		if not combat_svc.skill_missed.is_connected(_on_skill_missed):
			combat_svc.skill_missed.connect(_on_skill_missed)

	# Governance badges -> the achievement toast (badge_earned was
	## listener-declared with zero emitters AND zero listeners).
	if CommunityGovernance and not CommunityGovernance.badge_earned.is_connected(_on_badge_earned):
		CommunityGovernance.badge_earned.connect(_on_badge_earned)

	# Player position -> Minimap (poll via process loop).
	set_process(true)

	# Horde event signals -> HordeBar.
	_bind_horde_signals()
	_bind_sky_totem_signals()

	# World map clicks -> the WaypointService ping. map_clicked and
	# waypoint_clicked sat as declared-contract signals; the map's own
	# class comment promised click-to-navigate. The consumer creates +
	# activates a pinned waypoint so the beacon + compass ride the
	# service law (deferred: the map control mounts with the HUD).
	_bind_map_ping.call_deferred()

	# The cast-sense rows: the player's own CombatComponent broadcasts
	# its honest lifecycle (cast starts, cast completions, channel
	# ends, combat enter/exit) with zero listeners -- the rows land in
	# CombatLog. Player-local on purpose: nearby enemies already
	# surface through the skill_hit/skill_resolved bridge.
	_bind_player_combat_feedback.call_deferred()

	# The wallet rows: two honest wallets carry the local player's
	# money (the node's own wallet pays kills/ground loot; the
	# mounted InventoryComponent takes vendor/vault spends). Their
	# gold_changed signals had no player-facing consumer -- the rows
	# land in CombatLog (gains ride the LOOT family, spends System).
	_bind_player_wallet_feedback.call_deferred()
	_bind_enemy_threat_sense.call_deferred()

	# (Boss arrivals need no hud bridge: boss_spawned was removed for
	# the no-void law -- the NotificationService bridge over
	# EventHub.entity_spawned already announces world bosses with the
	# metadata's server-wide scope; a hud listener would double the
	# voice.)


## WeatherEventService signals -> SkyTotem. The service owns the
## authoritative close time: it pushes the mystery id + seconds at
## open, and the countdown re-pushes every tick so a server/restart
## never lies to the player.
## Script-mode-safe resolve of SlotService (runtime load, not a
## parse-time reference: the class registry is not the autoload set
## and the bare identifier is the known --script-mode false-fail).
func _slot_service() -> Node:
	var slot_script: GDScript = load("res://core/services/slot_service.gd")
	if slot_script == null or not slot_script.can_instantiate():
		return null
	return slot_script.call("singleton")

## ---- World map click-to-navigate (the WaypointService ping) -------

func _bind_map_ping() -> void:
	var wm := _world_map_node()
	if wm == null or not wm.has_signal("map_clicked"):
		return
	if not wm.map_clicked.is_connected(_on_map_clicked):
		wm.map_clicked.connect(_on_map_clicked)
	if wm.has_signal("waypoint_clicked") and not wm.waypoint_clicked.is_connected(_on_waypoint_clicked):
		wm.waypoint_clicked.connect(_on_waypoint_clicked)

func _world_map_node() -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.find_child("WorldMap", true, false)

func _waypoint_service() -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath("WaypointService"))

func _local_player_id() -> String:
	var tree := get_tree()
	var pm: Node = tree.root.get_node_or_null(NodePath("PlayerManager")) if tree and tree.root else null
	if pm == null:
		return ""
	var lp: Variant = pm.get("local_player")
	if lp != null and is_instance_valid(lp):
		return str(lp.get("entity_id"))
	if pm.has_method("get_local_player_id"):
		return str(pm.call("get_local_player_id"))
	return ""

## The player's tracked zone id ("" when untracked) -- WaypointService
## tolerates an empty zone, the name is display-grouping only.
func _map_pin_zone(player_id: String) -> String:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return ""
	var ess: Node = tree.root.get_node_or_null(NodePath("EntityService"))
	var zm: Node = tree.root.get_node_or_null(NodePath("ZoneManager"))
	if ess == null or zm == null or not zm.has_method("get_entity_zone_id"):
		return ""
	var ent = ess.get_entity(player_id)
	if ent == null or not is_instance_valid(ent):
		return ""
	return str(zm.get_entity_zone_id(ent))

func _on_map_clicked(pos: Vector3) -> void:
	_route_map_ping(pos, "")

func _on_waypoint_clicked(pos: Vector3) -> void:
	var label := ""
	var wm := _world_map_node()
	if wm != null and wm.has_method("last_waypoint_hit"):
		var hit: Dictionary = wm.call("last_waypoint_hit")
		label = str(hit.get("label", ""))
	_route_map_ping(pos, label)

## Create + activate the pinned waypoint: the beacon (pillar of light)
## and the compass ride WaypointService's own law, and the service's
## notify path already tells the player what happened (create, cap,
## invalid, rate limit). A failed create needs no extra consumer toast.
func _route_map_ping(pos: Vector3, quest_label: String) -> void:
	if pos == Vector3.ZERO:
		return
	var wsvc := _waypoint_service()
	if wsvc == null or not wsvc.has_method("create_waypoint"):
		return
	var player_id := _local_player_id()
	if player_id.is_empty():
		return
	var waypoint_name := "Map Marker" if quest_label.is_empty() else "Quest: %s" % quest_label
	var result: Dictionary = wsvc.create_waypoint(player_id, waypoint_name, pos, _map_pin_zone(player_id))
	if not bool(result.get("success", false)):
		return
	var wp: Variant = result.get("waypoint", {})
	var wp_id := str(wp.get("id", "")) if wp is Dictionary else ""
	if wp_id != "" and wsvc.has_method("activate_waypoint"):
		wsvc.activate_waypoint(player_id, wp_id)

## ---- Cast-sense rows (the player's own CombatComponent) -----------

func _bind_player_combat_feedback() -> void:
	var player: Node = null
	var pm := get_node_or_null("/root/PlayerManager")
	if pm != null:
		var lp: Variant = pm.get("local_player")
		if lp != null and is_instance_valid(lp):
			player = lp
	if player == null:
		return
	var comp: Variant = player.get("combat_component") if "combat_component" in player else null
	if comp == null or not is_instance_valid(comp):
		return
	if comp.cast_started.is_connected(_on_cast_started):
		return
	comp.cast_started.connect(_on_cast_started)
	comp.cast_finished.connect(_on_cast_finished)
	comp.channel_ended.connect(_on_channel_ended)
	comp.combat_entered.connect(_on_combat_entered)
	comp.combat_exited.connect(_on_combat_exited)

## Skill display name with the same guard the miss row uses (cast
## data is engine content, not user text -- no escape needed).
func _cast_label(skill) -> String:
	if skill == null:
		return "a skill"
	if "display_name" in skill:
		var s := str(skill.get("display_name"))
		if not s.is_empty():
			return s
	if "name" in skill:
		var n := str(skill.get("name"))
		if not n.is_empty():
			return n
	return "a skill"

func _combat_state_row(text: String) -> void:
	if _combat_log != null and _combat_log.has_method("add_message"):
		_combat_log.call("add_message", text, _combat_log.EntryType.SYSTEM)

func _on_cast_started(skill) -> void:
	_combat_state_row("You begin casting %s." % _cast_label(skill))

func _on_cast_finished(skill) -> void:
	_combat_state_row("You finish casting %s." % _cast_label(skill))

func _on_channel_ended(skill, completed: bool) -> void:
	var verdict := "" if bool(completed) else " (interrupted)"
	_combat_state_row("You stop channeling %s%s." % [_cast_label(skill), verdict])

func _on_combat_entered() -> void:
	_combat_state_row("You have entered combat.")

func _on_combat_exited() -> void:
	_combat_state_row("You have left combat.")

## ---- Wallet rows (the local player's two honest wallets) ----------

var _node_gold_seen: int = -1
var _comp_gold_seen: int = -1

func _bind_player_wallet_feedback() -> void:
	var player: Node = null
	var pm := get_node_or_null("/root/PlayerManager")
	if pm != null:
		var lp: Variant = pm.get("local_player")
		if lp != null and is_instance_valid(lp):
			player = lp
	if player == null:
		return
	# The node wallet (kills, ground loot, housing spends). It
	# carries the running TOTAL, so seed the seen-value to stay quiet
	# through hydration and speak only in real deltas. Per-leg guards:
	# a rebind must not skip the component legs below. The globe body
	# (GlobeWorldPlayer) is the playable local player but declares no
	# `gold`/`gold_changed` (its purse is the mounted component), so gate
	# on has_signal before reading the property or connecting.
	if player.has_signal("gold_changed") and not player.gold_changed.is_connected(_on_node_gold_changed):
		_node_gold_seen = int(player.gold) if "gold" in player else -1
		player.gold_changed.connect(_on_node_gold_changed)
	# The component wallet (vendors, vault, ferry, blacksmith) and
	# its equipped voice.
	var comp: Variant = null
	if "inventory_component" in player:
		comp = player.get("inventory_component")
	if comp != null and is_instance_valid(comp):
		if comp.has_signal("gold_changed") and not comp.gold_changed.is_connected(_on_component_gold_changed):
			_comp_gold_seen = comp.get_gold()
			comp.gold_changed.connect(_on_component_gold_changed)
		if comp.has_signal("item_equipped") \
				and not comp.item_equipped.is_connected(_on_item_equipped_changed):
			comp.item_equipped.connect(_on_item_equipped_changed)
		# Non-gold currency voice (the ONE ledger's other currencies):
		# scrip, favor, sigils. The signal carries signed deltas and
		# only fires through the ledger API (restores are silent), so
		# every emit is a REAL movement -- no seeding needed.
		if comp.has_signal("currency_changed") \
				and not comp.currency_changed.is_connected(_on_component_currency_changed):
			comp.currency_changed.connect(_on_component_currency_changed)

func _wallet_row(delta: int, ever_seen: bool) -> void:
	if not ever_seen or _combat_log == null or _combat_log.has_method("add_message") != true:
		return
	if delta > 0:
		_combat_log.call("add_message", "+%d gold" % delta, _combat_log.EntryType.LOOT)
	elif delta < 0:
		_combat_log.call("add_message", "-%d gold" % -delta, _combat_log.EntryType.SYSTEM)

func _on_node_gold_changed(total: int) -> void:
	var previous := _node_gold_seen
	_node_gold_seen = total
	_wallet_row(total - previous, previous >= 0)

func _on_component_gold_changed(delta: int) -> void:
	# The component's signal carries the SIGNED delta directly.
	_comp_gold_seen = _comp_gold_seen + delta
	_wallet_row(delta, true)

func _on_component_currency_changed(currency_id: String, delta: int) -> void:
	if _combat_log == null or not _combat_log.has_method("add_message"):
		return
	if delta == 0 or currency_id == "" or currency_id == "currency_gold":
		# Gold rides its own leg (gold_listener above); the ledger's
		# gold routing never double-speaks.
		return
	var label := _currency_display_name(currency_id)
	if delta > 0:
		_combat_log.call("add_message", "+%d %s" % [delta, label], _combat_log.EntryType.LOOT)
	else:
		_combat_log.call("add_message", "-%d %s" % [-delta, label], _combat_log.EntryType.SYSTEM)

## DataService display_name for a currency id (the bare id as fallback).
func _currency_display_name(currency_id: String) -> String:
	var ds := get_node_or_null("/root/DataService")
	if ds != null and ds.has_method("get_currency"):
		var cd = ds.get_currency(currency_id)
		if cd != null and "display_name" in cd and str(cd.display_name) != "":
			return str(cd.display_name)
	return currency_id

func _on_item_equipped_changed(item, slot_name: String, equipped: bool) -> void:
	if _combat_log == null or not _combat_log.has_method("add_message"):
		return
	var label: String = "an item"
	if item != null and "display_name" in item:
		var s := str(item.get("display_name"))
		if not s.is_empty():
			label = s
	var verb := "equip" if bool(equipped) else "unequip"
	_combat_log.call("add_message", "You %s %s (%s)." % [verb, label, slot_name], _combat_log.EntryType.SYSTEM)

## ---- The threat sense (the enemy/threat telemetry consumer) -------
## Three aggro signals spoke to zero consumers for their whole life.
## This binder turns SpawnService.enemy_spawned into per-enemy
## bindings and speaks ONLY on the legs that touch the local player:
## focus flips on/off you, and your threat hitting the cap.

var _threat_sense_bound: bool = false
var _enemy_focused_local := {}   # enemy instance_id -> true while the
	# enemy's focus sits on the local player

func _bind_enemy_threat_sense() -> void:
	if _threat_sense_bound:
		return
	var ss := get_node_or_null("/root/SpawnService")
	if ss == null or not ss.has_signal("enemy_spawned"):
		return
	_threat_sense_bound = true
	ss.enemy_spawned.connect(_on_enemy_spawned_threat_sense)

func _on_enemy_spawned_threat_sense(enemy, _spawn_point_id: String, _metadata) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if not ("aggro_component" in enemy):
		return
	var aggro = enemy.get("aggro_component")
	if aggro == null or not is_instance_valid(aggro):
		return
	if aggro.has_signal("target_changed") \
			and not aggro.target_changed.is_connected(_on_enemy_focus_changed):
		aggro.target_changed.connect(_on_enemy_focus_changed.bind(enemy))
	if aggro.has_signal("threat_overflow") \
			and not aggro.threat_overflow.is_connected(_on_enemy_threat_overflow):
		aggro.threat_overflow.connect(_on_enemy_threat_overflow.bind(enemy))
	if aggro.has_signal("out_of_combat") \
			and not aggro.out_of_combat.is_connected(_on_enemy_fight_broken):
		aggro.out_of_combat.connect(_on_enemy_fight_broken.bind(enemy))

## Was this enemy's focus sitting on the local player just before this
## flip? (The out_of_combat leg reads the same book.)
func _enemy_focuses_local(enemy, target) -> bool:
	var me := _local_player_ref()
	if me == null:
		return false
	return target == me

func _local_player_ref() -> Node:
	var pm := get_node_or_null("/root/PlayerManager")
	if pm == null:
		return null
	var lp = pm.get("local_player")
	if lp == null or not is_instance_valid(lp):
		return null
	return lp

func _enemy_label(enemy) -> String:
	if enemy == null or not is_instance_valid(enemy):
		return "something"
	if "display_name" in enemy and str(enemy.get("display_name")) != "":
		return str(enemy.get("display_name"))
	return str(enemy.name)

func _threat_row(text: String) -> void:
	if _combat_log == null or not _combat_log.has_method("add_message"):
		return
	_combat_log.call("add_message", text, _combat_log.EntryType.SYSTEM)

func _on_enemy_focus_changed(old_target, new_target, enemy) -> void:
	var me := _local_player_ref()
	if me == null:
		return
	var label := _enemy_label(enemy)
	if new_target == me and old_target != me:
		if enemy != null and is_instance_valid(enemy):
			_enemy_focused_local[enemy.get_instance_id()] = true
		_threat_row("The %s turns its attention on you." % label)
	elif old_target == me and new_target != me:
		if enemy != null and is_instance_valid(enemy):
			_enemy_focused_local.erase(enemy.get_instance_id())
		_threat_row("You slip out of the %s's attention." % label)

func _on_enemy_threat_overflow(source, enemy) -> void:
	if source != _local_player_ref():
		return
	_threat_row("Your threat on the %s maxes out." % _enemy_label(enemy))

func _on_enemy_fight_broken(enemy) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var was_id := int(enemy.get_instance_id())
	if not _enemy_focused_local.has(was_id):
		return
	_enemy_focused_local.erase(was_id)
	_threat_row("The %s forgets the fight and breaks off." % _enemy_label(enemy))

func _on_container_opened(key: String, container_type: int) -> void:
	if _mm == null:
		return
	var panel: Control = _mm.get_panel_node("container")
	if panel == null:
		return
	panel.show_container(key, container_type)
	_mm.call("open_menu", "container")

func _on_container_closed(key: String) -> void:
	if _mm == null:
		return
	var panel: Control = _mm.get_panel_node("container")
	if panel == null:
		return
	if panel.is_showing(key):
		_mm.call("close_menu", "container")

## The pad's plug/drop toast (consumer contract for the pair).
func _on_controller_connected() -> void:
	if NotificationService:
		NotificationService.notify(
			NotifKind.CONNECTION_QUALITY,
			"Gamepad connected",
			"InputManager",
			"ctrl:connected",
			{},
			""
		)

func _on_controller_disconnected() -> void:
	if NotificationService:
		NotificationService.notify(
			NotifKind.CONNECTION_QUALITY,
			"Gamepad disconnected",
			"InputManager",
			"ctrl:disconnected",
			{},
			""
		)

## The governance badge toast (achievement-shaped so the kind map
## already has its color path).
func _on_badge_earned(player_id: String, badge: String) -> void:
	if NotificationService:
		NotificationService.notify(
			NotifKind.ACHIEVEMENT_UNLOCKED,
			"Badge earned: %s" % badge.capitalize(),
			"CommunityGovernance",
			"badge:%s:%s" % [player_id, badge],
			{"player_id": player_id, "badge": badge},
			player_id
		)

func _bind_sky_totem_signals() -> void:
	var we := get_weather_event_service()
	if we == null or _sky_totem == null:
		return
	if we.has_signal("aurora_window_opened"):
		we.aurora_window_opened.connect(_on_aurora_window_opened)
	if we.has_signal("aurora_window_closed"):
		we.aurora_window_closed.connect(func(_mid: String) -> void: _sky_totem.hide_window())
	# Authoritative countdown: re-push each service tick if the totem is up.
	if we.has_signal("aurora_window_time"):
		we.aurora_window_time.connect(func(mid: String, sec_total: float, _t: float) -> void:
			_sky_totem.set_window_remaining(mid, sec_total, sec_total))

## The service is a world-scene child ("WeatherEvents"), not an
## autoload — the totem binding waits for the playable scene to exist
## (the /root lookup misses; the scene-scoped lookup hits once the
## world is up).
func get_weather_event_service() -> Node:
	var svc := get_node_or_null("/root/WeatherEventService")
	if svc != null:
		return svc
	var scene_root: Node = get_tree().current_scene if get_tree() != null else null
	if scene_root != null:
		return scene_root.get_node_or_null("WeatherEvents")
	return null


func _on_aurora_window_opened(mystery_id: String) -> void:
	var we := get_weather_event_service()
	var total: float = 1800.0
	if we != null and "AURORA_WINDOW_SEC" in we:
		total = float(we.AURORA_WINDOW_SEC)
	_sky_totem.show_window(mystery_id)
	_sky_totem.set_window_remaining(mystery_id, total, total)


## HordeEventService signals -> HordeBar. Every service signal carries
## horde_id first, so the bar only refreshes for the horde it shows
## (a second horde starting elsewhere can't hijack the display).
func _bind_horde_signals() -> void:
	var svc := get_node_or_null("/root/HordeEventService")
	if svc == null or _horde_bar == null:
		return
	if svc.has_signal("horde_started"):
		svc.horde_started.connect(func(horde_id, zone_id, total_waves):
			_horde_bar.show_horde_started(horde_id, zone_id, total_waves))
	if svc.has_signal("horde_wave_started"):
		svc.horde_wave_started.connect(func(horde_id, wave, total):
			if _horde_bar.active_horde_id() == horde_id:
				_horde_bar.show_wave_started(wave, total))
	if svc.has_signal("horde_wave_progress"):
		svc.horde_wave_progress.connect(func(horde_id, _wave, remaining):
			if _horde_bar.active_horde_id() == horde_id:
				_horde_bar.show_wave_progress(remaining))
	if svc.has_signal("horde_wave_cleared"):
		svc.horde_wave_cleared.connect(func(horde_id, _wave):
			if _horde_bar.active_horde_id() == horde_id:
				_horde_bar.show_wave_cleared())
	if svc.has_signal("horde_boss_spawned"):
		svc.horde_boss_spawned.connect(func(horde_id, _boss):
			if _horde_bar.active_horde_id() == horde_id:
				_horde_bar.show_boss())
	if svc.has_signal("horde_completed"):
		svc.horde_completed.connect(func(horde_id, _success):
			if _horde_bar.active_horde_id() == horde_id:
				_horde_bar.hide_horde())

	# A horde may already be running when the HUD binds (rejoin).
	if svc.has_method("active_horde_in_zone") and PlayerManager:
		var pid: String = ""
		if PlayerManager.has_method("get_local_player_id"):
			pid = str(PlayerManager.get_local_player_id())
		if pid != "" and svc.has_method("active_horde_in_zone"):
			var es := get_node_or_null("/root/EntityService")
			if es != null and es.has_method("get_entity"):
				var player = es.get_entity(pid)
				if player != null:
					var zm := get_node_or_null("/root/ZoneManager")
					if zm != null and zm.has_method("get_entity_zone_id"):
						var zid := str(zm.get_entity_zone_id(player))
						var horde_id: String = svc.active_horde_in_zone(zid)
						if horde_id != "":
							var status: Dictionary = svc.get_horde_status(horde_id)
							status["horde_id"] = horde_id
							_horde_bar.set_horde_state(status)


func _push_initial_state() -> void:
	if PlayerManager:
		_on_health_changed(PlayerManager.current_health, PlayerManager.max_health)
		_on_mana_changed(PlayerManager.current_mana, PlayerManager.max_mana)
		_on_xp_changed(PlayerManager.experience, PlayerManager.level)
	# Load quick-access items from inventory
	if _quick_access_bar and _quick_access_bar.has_method("load_from_inventory"):
		_quick_access_bar.load_from_inventory()


func _process(_delta: float) -> void:
	# Feed the minimap (and the expanded map) with the local player position.
	if _minimap == null or not _minimap.has_method("set_player_position"):
		return
	var p: Node = PlayerManager.local_player if PlayerManager else null
	if p == null or not is_instance_valid(p) or not (p is Node3D):
		return
	var pos: Vector3 = p.global_position
	_minimap.set_player_position(pos)
	# THE HEADING FEED (the "doesn't turn" fix): nothing ever called
	# set_player_rotation, so the arrow froze at spawn heading. The
	# player's own facing getter is the one truth (targeting reads it
	# too); damping keeps the arrow from trembling on idle jitter.
	if _minimap.has_method("set_player_rotation") and p.has_method("get_look_direction"):
		var look: Vector3 = p.get_look_direction()
		if look.length_squared() > 0.0001:
			var yaw: float = atan2(look.x, look.z)
			if abs(yaw - _last_player_yaw) > PI:  # wrap -PI..PI
				_last_player_yaw = yaw
			else:
				_last_player_yaw = lerp_angle(_last_player_yaw, yaw, 0.35)
			_minimap.set_player_rotation(_last_player_yaw)
	_minimap.set_zone_name(_get_current_zone(p))
	if _world_map != null and _world_map.has_method("set_player_position") \
			and _world_map.has_method("is_minimap") and not _world_map.is_minimap():
		_world_map.set_player_position(pos)


func _get_current_zone(player: Node) -> String:
	# Prefer the player's live zone; fall back to the meadow spawn default.
	if ZoneManager and player != null and "entity_id" in player \
			and ZoneManager.has_method("get_entity_zone_id"):
		var z: String = str(ZoneManager.get_entity_zone_id(player))
		if not z.is_empty():
			var zone: Variant = ZoneManager.get_zone(z) if ZoneManager.has_method("get_zone") else null
			if zone != null and "display_name" in zone:
				var display: String = str(zone.display_name)
				if not display.is_empty():
					return display
			return str(z).replace("zone_", "").capitalize()
	return "Meadowhaven"


# == Player resource handlers =============================================

func _on_health_changed(current: int, maximum: int) -> void:
	if _mm and _mm.has_method("update_hp"):
		_mm.update_hp(current, maximum)


func _on_mana_changed(current: int, maximum: int) -> void:
	if _mm and _mm.has_method("update_mp"):
		_mm.update_mp(current, maximum)


func _on_xp_changed(current: int, level: int) -> void:
	if _mm and _mm.has_method("update_xp"):
		# XP-to-next is approximated; PlayerManager tracks it as
		# `experience_to_next_level` on the autoload.
		var to_next: int = PlayerManager.experience_to_next_level if PlayerManager else 100
		_mm.update_xp(current, to_next)


func _on_level_up(new_level: int) -> void:
	_log("LEVEL UP! You are now level %d" % new_level, _color_gold())


func _on_player_died() -> void:
	_log("You have died.", _color_error())


# == Targeting handlers ===================================================

func _on_target_acquired(target) -> void:
	_current_target = _target_to_dict(target)
	if _target_frame and _target_frame.has_method("set_target"):
		_target_frame.set_target(target)
	_update_boss_visibility(target)


func _on_target_cleared(_previous) -> void:
	_current_target.clear()
	if _target_frame and _target_frame.has_method("clear_target"):
		_target_frame.clear_target()
	if _boss_health_bar:
		_boss_health_bar.visible = false


func _on_target_updated(target) -> void:
	_current_target = _target_to_dict(target)
	if _target_frame and _target_frame.has_method("update_target"):
		_target_frame.update_target(target)
	_update_boss_visibility(target)


func _on_action_executed(action_id: String, target_id: String, result: Dictionary) -> void:
	# Typed UI actions from the targeting pass: Check Lobby opens the
	# lobby panel (TargetingManager returns action=open_lobby).
	if action_id == "check_lobby" or str(result.get("action", "")) == "open_lobby":
		if _mm and _mm.has_method("open_menu"):
			# A gate result carries its zone; focus the Bouts tab before
			# opening so the stone's mode is the panel's landing state.
			var zone_id: String = str(result.get("zone_id", ""))
			if zone_id != "":
				var lobby_panel = _mm.get_panel_node("lobby")
				if lobby_panel != null and lobby_panel.has_method("focus_zone"):
					lobby_panel.focus_zone(zone_id)
			_mm.open_menu("lobby")
		return

	# Mirror action results into the combat log.
	if not _combat_log or not _combat_log.has_method("add_message"):
		return
	var dmg: int = int(result.get("damage", 0))
	if dmg > 0:
		_combat_log.add_message("You", 0, "%s: %d dmg to %s" % [action_id, dmg, target_id], 1)
	elif result.get("heal", 0) > 0:
		_combat_log.add_message("You", 0, "%s: +%d heal" % [action_id, int(result["heal"])], 2)
	elif result.get("success", false):
		_combat_log.add_message("You", 0, "%s on %s" % [action_id, target_id], 3)


func _update_boss_visibility(target) -> void:
	if not _boss_health_bar:
		return
	var is_boss: bool = _target_is_boss(target)
	_boss_health_bar.visible = is_boss
	if is_boss and _boss_health_bar.has_method("set_target"):
		_boss_health_bar.set_target(target)


func _target_is_boss(target) -> bool:
	if target == null:
		return false
	# Support both TargetInfo objects and plain dicts.
	var t: String = ""
	if target is Dictionary:
		t = String(target.get("entity_type", ""))
		var data: Variant = target.get("entity_data", null)
		if data and "is_boss" in data:
			return bool(data.is_boss)
		if data and "enemy_type" in data:
			return String(data.enemy_type).to_lower().contains("boss")
		return t == "BOSS" or t == "WORLD_BOSS"
	if "entity_type" in target:
		t = str(target.entity_type)
	if "entity_data" in target and target.entity_data:
		var ed: Variant = target.entity_data
		if "enemy_type" in ed:
			return String(ed.enemy_type).to_lower().contains("boss")
		if "is_boss" in ed:
			return bool(ed.is_boss)
	return t.contains("BOSS") if t != "" else false


func _target_to_dict(target) -> Dictionary:
	if target == null:
		return {}
	if target is Dictionary:
		return target.duplicate()
	var d: Dictionary = {}
	if "entity_id" in target:
		d["entity_id"] = target.entity_id
	if "entity_type" in target:
		d["entity_type"] = str(target.entity_type)
	if "display_name" in target:
		d["display_name"] = target.display_name
	if "health" in target:
		d["health"] = target.health
	if "max_health" in target:
		d["max_health"] = target.max_health
	if "level" in target:
		d["level"] = target.level
	if "faction" in target:
		d["faction"] = str(target.faction)
	if "relation" in target:
		d["relation"] = str(target.relation)
	return d


# == Entity lifecycle =====================================================

func _on_entity_spawned(entity, _metadata) -> void:
	# Push markers to the minimap.
	if not entity or not _minimap:
		return
	if not _minimap.has_method("add_marker"):
		return
	if not (entity is Node3D):
		return
	var pos: Vector3 = entity.global_position
	var et: String = str(entity.entity_type) if "entity_type" in entity else ""
	var label: String = entity.display_name if "display_name" in entity else entity.name
	match et:
		"PLAYER":
			_minimap.add_marker(entity.entity_id, pos, 1, label)
		"NPC":
			_minimap.add_marker(entity.entity_id, pos, 2, label)
		"ENEMY":
			_minimap.add_marker(entity.entity_id, pos, 3, label)
		"LOOT":
			_minimap.add_marker(entity.entity_id, pos, 4, label)
		_:
			_minimap.add_marker(entity.entity_id, pos, 0, label)


func _on_entity_unregistered(entity, _metadata = null) -> void:
	if not entity:
		return
	var entity_id: String = entity.entity_id if "entity_id" in entity else (entity.name if entity else "")
	if entity_id != "" and _minimap and _minimap.has_method("remove_marker"):
		_minimap.remove_marker(entity_id)


## The whiff row the log was built for (caster's own skill names
## included; guard log row for non-entity casters).
func _on_skill_missed(caster, _skill) -> void:
	if _combat_log == null:
		return
	var caster_name: String = caster.display_name if caster != null and "display_name" in caster else "Unknown"
	_combat_log.log_miss(caster_name)

func _on_entity_died(entity, _killer, _metadata) -> void:
	var name_str: String = entity.display_name if entity and "display_name" in entity else "Unknown"
	_log("%s has been slain." % name_str, _color_kill())


# == Chat =================================================================

func _on_chat_received(sender_id: String, channel: int, message: String, _targets: Array) -> void:
	if _chat and _chat.has_method("add_message"):
		_chat.add_message(sender_id, channel, message)


# == Notifications ========================================================

func _on_notification(_entity_id: String, notification: Dictionary) -> void:
	# NotificationService passes a Dictionary; render the text into the
	# combat log as a system message so it shows up in the same stream
	# the player already watches.
	if not notification:
		return
	var text: String = str(notification.get("message", notification.get("text", "")))
	if text == "":
		return
	var color: Color = _notification_color(notification)
	_log(text, color)

	# Corner toast: route by location -- NotificationService.send_event()
	# already maps HIGH+ kinds to CENTER_SCREEN and everything else to
	# CORNER. Only the CORNER entries belong on the toast stack; the
	# center-screen ones have their own billboard/showcase face upstream.
	# Prefer the dedicated NotificationToast face (rich stack: types,
	# click actions, notification center); fall back to TooltipManager's
	# legacy bar when the new face is absent (HUD scenes installed before
	# this wiring).
	var location: Variant = notification.get("location", NotificationService.DisplayLocation.CHAT_LOG)
	if int(location) != NotificationService.DisplayLocation.CORNER:
		return
	# Legacy single-signal shape: the old notifications carried their
	# location inside the dict; double-reporting comes from BOTH the
	# notification_sent and notification_received connections on the same
	# send() call, so gate identical payloads with a rolling 5s key.
	if _toast_dedupe_key("hud_toast:%s" % text.md5_text()):
		return
	if _toast_face and _toast_face.has_method("show_toast"):
		_toast_face.show_toast(text, NotificationToast.ToastType.INFO, "", 5.0)
	elif _tooltip and _tooltip.has_method("show_toast"):
		_tooltip.show_toast(text, color, 3.0)


func _notification_color(notification: Dictionary) -> Color:
	var t: Variant = notification.get("type", "")
	if t is String:
		match t.to_lower():
			"error", "alert":
				return _color_error()
			"warning":
				return Color(1, 0.7, 0.2)
			"reward", "loot":
				return _color_gold()
	return Color(0.85, 0.85, 0.9)


# == Buffs / Debuffs ======================================================

# Find the local player's AuraComponent and subscribe to its buff/debuff
# signals. Buffs go to the BuffBar; status effects as debuffs to the
# BuffBar's debuff slot. Bound once at HUD ready (PlayerManager.set_local_player
# fires no signal to rebind on; scene transitions that swap the player
# node need an explicit HUD refresh).
func _bind_aura_signals() -> void:
	if not PlayerManager or not PlayerManager.local_player:
		return
	var player: Node = PlayerManager.local_player
	var aura: Node = player.get_node_or_null("AuraComponent")
	if not aura and "aura_component" in player and player.aura_component != null:
		# _ensure_effect_stack attaches the component as a child with an
		# auto-generated node name (@AuraComponent@N) -- the canonical
		# handle is the entity's field, not a node-path lookup.
		aura = player.aura_component
	if not aura:
		# Last resort: scan children. get_class() returns the ENGINE class
		# ("Node"), never the script class_name -- compare scripts instead
		# or the scan never matches anything.
		for child in player.get_children():
			if child is AuraComponent:
				aura = child
				break
	if not aura:
		return
	if aura.has_signal("buff_added") and not aura.is_connected("buff_added", _on_buff_added):
		aura.buff_added.connect(_on_buff_added)
	if aura.has_signal("buff_removed") and not aura.is_connected("buff_removed", _on_buff_removed):
		aura.buff_removed.connect(_on_buff_removed)
	if aura.has_signal("debuff_added") and not aura.is_connected("debuff_added", _on_debuff_added):
		aura.debuff_added.connect(_on_debuff_added)
	if aura.has_signal("debuff_removed") and not aura.is_connected("debuff_removed", _on_debuff_removed):
		aura.debuff_removed.connect(_on_debuff_removed)


func _on_buff_added(buff) -> void:
	if not _buff_bar or not _buff_bar.has_method("add_buff"):
		return
	# Buff extends StatusEffect: the id key is effect_id (never "id"),
	# and 4.7.2 dropped default args on Object.get -- read guarded fields.
	var id: String = str(buff.effect_id) if buff != null and "effect_id" in buff else ""
	var duration: float = float(buff.duration) if buff != null and "duration" in buff else 0.0
	if id == "":
		return
	_buff_bar.add_buff(id, null, duration, 1, false)


func _on_buff_removed(buff) -> void:
	if not _buff_bar or not _buff_bar.has_method("remove_buff"):
		return
	var id: String = str(buff.effect_id) if buff != null and "effect_id" in buff else ""
	if id != "":
		_buff_bar.remove_buff(id)


func _on_debuff_added(debuff) -> void:
	if not _buff_bar or not _buff_bar.has_method("add_buff"):
		return
	var id: String = str(debuff.effect_id) if debuff != null and "effect_id" in debuff else ""
	var duration: float = float(debuff.duration) if debuff != null and "duration" in debuff else 0.0
	if id == "":
		return
	_buff_bar.add_buff(id, null, duration, 1, true)


func _on_debuff_removed(debuff) -> void:
	if not _buff_bar or not _buff_bar.has_method("remove_buff"):
		return
	var id: String = str(debuff.effect_id) if debuff != null and "effect_id" in debuff else ""
	if id != "":
		_buff_bar.remove_buff(id)


# == Helpers ==============================================================

func _log(text: String, color: Color) -> void:
	if _combat_log:
		_combat_log.log_system(text)


func _color_gold() -> Color:
	if UIStyles:
		return UIStyles.COLORS.accent_gold
	return Color(1, 0.85, 0.3)


func _color_error() -> Color:
	if UIStyles:
		return UIStyles.COLORS.error
	return Color(1, 0.3, 0.3)


func _color_kill() -> Color:
	return Color(0.9, 0.4, 0.9)


func _on_action_selected(action_id: String, target_id: String) -> void:
	# Local player id, resolved once for all branches (match branches have
	# their own scope, so per-branch declarations would not be shared).
	var my_id: String = ""
	if PlayerManager:
		my_id = str(PlayerManager.get_local_player_id())
	match action_id:
		"trade":
			if TradeService:
				var ok := TradeService.request_trade(my_id, target_id)
				if not ok:
					GameLog.info("Trade request failed")
		"add_friend":
			if FriendsService:
				# PlayerManager has no get_local_player_name(); the guard was
				# always false, so friend requests went out with a blank name.
				# Read the live node's display_name instead.
				var my_name: String = ""
				if PlayerManager and PlayerManager.has_method("get_local_player"):
					var lp = PlayerManager.get_local_player()
					if lp != null and "display_name" in lp:
						my_name = str(lp.display_name)
				FriendsService.send_friend_request(my_id, my_name, target_id)
		"view_character":
			_open_character_inspect(target_id)
		"view_guild":
			_open_guild_info(target_id)
		"follow":
			_start_follow(target_id)
		"stop_follow":
			_stop_follow()
		"inspect":
			_open_character_inspect(target_id)
		"whisper":
			if ChatService:
				ChatService.open_whisper(target_id)
		"invite_party":
			if PartyService:
				PartyService.invite_player(my_id, target_id)
		"invite_guild":
			if GuildService:
				GuildService.invite_player(my_id, target_id)
		"report":
			# Player-facing report loop: the admin shell reports through
			# PlayerReporter (which alerts + webhooks); the target-menu
			# action dead-ended in a log line. Same path, menu-driven.
			if PlayerReporter and PlayerReporter.has_method("submit_report"):
				PlayerReporter.submit_report(my_id, PlayerReporter.ReportType.ABUSE, {
					"target": target_id,
					"reason": "Reported from the player target menu",
				})
				GameLog.info("Report action: %s" % target_id)


func _open_character_inspect(target_id: String) -> void:
	if not _mm:
		return
	# Open character panel in inspect mode with target player
	if _mm.has_method("open_character_inspect"):
		_mm.open_character_inspect(target_id)
	elif _mm.has_method("open_menu"):
		_mm.open_menu("character")


func _open_guild_info(target_id: String) -> void:
	# Get the player's guild and open guild info panel
	if GuildService and GuildService.has_method("get_player_guild"):
		var guild_id := GuildService.get_player_guild(target_id)
		if not guild_id.is_empty():
			# Open guild panel showing this guild
			if _mm and _mm.has_method("open_guild_info"):
				_mm.open_guild_info(guild_id)
			elif _mm and _mm.has_method("open_menu"):
				_mm.open_menu("guild")
		else:
			GameLog.info("Player %s is not in a guild" % target_id)


func _start_follow(target_id: String) -> void:
	if FollowService and PlayerManager:
		var my_id := str(PlayerManager.get_local_player_id())
		var ok := FollowService.request_follow(my_id, target_id)
		if not ok:
			GameLog.info("Follow request failed")


func _stop_follow() -> void:
	if FollowService and PlayerManager:
		var my_id := str(PlayerManager.get_local_player_id())
		FollowService.stop_follow(my_id, "cancelled")
