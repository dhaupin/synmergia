## HudIntegrator - Wires the HUD widgets to live game data.
##
## Sits alongside HudLayer. Connects:
##   - PlayerManager health/mana/exp → MenuManager status bars
##   - TargetingManager target_* → TargetFrame + BossHealthBar
##   - EntityService entity_spawned/died → CombatLog + NamePlate spawn pool
##   - EventHub entity_died, player_died → CombatLog kill messages
##   - ChatService message_received → ChatUI
##   - NotificationService notifications → SystemCombatLog entries
##
## All connections are guarded by `has_signal`/`has_method` so a missing
## service or widget silently no-ops.
extends Node

const HudLayer := preload("res://ui/hud/hud_layer.gd")

var _hud: CanvasLayer
var _mm: Node  # MenuManager
var _action_bar: Node
var _quick_access_bar: Node
var _buff_bar: Node
var _combat_log: Node
var _target_frame: Node
var _boss_health_bar: Node
var _minimap: Node
var _world_map: Node
var _chat: Node
var _tooltip: Node

## Track active target so the boss bar can fall back when clearing.
var _current_target: Dictionary = {}


func bind(hud: CanvasLayer) -> void:
	_hud = hud
	_mm = _find("MenuManager")
	_action_bar = _find("ActionBar")
	_quick_access_bar = _find("QuickAccessBar")
	_buff_bar = _find("BuffBar")
	_combat_log = _find("CombatLog")
	_target_frame = _find("TargetFrame")
	_boss_health_bar = _find("BossHealthBar")
	_minimap = _find("Minimap")
	_world_map = _find("WorldMap")
	_chat = _find("ChatUI")
	_tooltip = _find("TooltipManager")
	_connect_all()
	_push_initial_state()


func _find(node_name: String) -> Node:
	return _hud.get_node_or_null(node_name) if _hud else null


func _connect_all() -> void:
	# Player resources → MenuManager status bars (HP/MP/XP).
	if PlayerManager:
		PlayerManager.health_changed.connect(_on_health_changed)
		PlayerManager.mana_changed.connect(_on_mana_changed)
		PlayerManager.experience_changed.connect(_on_xp_changed)
		PlayerManager.level_up.connect(_on_level_up)
		PlayerManager.died.connect(_on_player_died)

	# Targeting → TargetFrame + BossHealthBar.
	if TargetingManager:
		TargetingManager.target_acquired.connect(_on_target_acquired)
		TargetingManager.target_cleared.connect(_on_target_cleared)
		TargetingManager.target_updated.connect(_on_target_updated)
		TargetingManager.action_executed.connect(_on_action_executed)

	# Entity lifecycle → CombatLog + NamePlate.
	if EntityService:
		if EntityService.has_signal("entity_registered"):
			EntityService.entity_registered.connect(_on_entity_spawned)
		if EntityService.has_signal("entity_unregistered"):
			EntityService.entity_unregistered.connect(_on_entity_unregistered)
		if EntityService.has_signal("player_joined"):
			EntityService.player_joined.connect(_on_entity_spawned)
		if EntityService.has_signal("player_left"):
			EntityService.player_left.connect(_on_entity_unregistered)

	# Death events → kill messages in the combat log.
	if EventHub:
		if EventHub.has_signal("entity_died"):
			EventHub.entity_died.connect(_on_entity_died)

	# Chat messages → ChatUI.
	if ChatService:
		ChatService.message_received.connect(_on_chat_received)

	# Notifications → CombatLog system messages.
	if NotificationService:
		if NotificationService.has_signal("notification_received"):
			NotificationService.notification_received.connect(_on_notification)
		if NotificationService.has_signal("notification_sent"):
			NotificationService.notification_sent.connect(_on_notification)

	# Player position → Minimap (poll via process loop).
	set_process(true)


func _push_initial_state() -> void:
	if PlayerManager:
		_on_health_changed(PlayerManager.current_health, PlayerManager.max_health)
		_on_mana_changed(PlayerManager.current_mana, PlayerManager.max_mana)
		_on_xp_changed(PlayerManager.experience, PlayerManager.level)


func _process(_delta: float) -> void:
	# Feed the minimap with the local player position.
	if _minimap and PlayerManager and PlayerManager.local_player:
		var p: Node = PlayerManager.local_player
		if p and p.has_method("get_global_position"):
			var pos: Vector3 = p.get_global_position()
			_minimap.set_player_position(pos)
			_minimap.set_zone_name(_get_current_zone(p))
		if _world_map and _world_map.visible and _world_map.has_method("set_player_position"):
			_world_map.set_player_position(p.get_global_position())


func _get_current_zone(_player: Node) -> String:
	if ZoneManager and ZoneManager.has_method("get_current_zone_id"):
		var z: Variant = ZoneManager.get_current_zone_id()
		if z is String:
			return z
	return "Starter Plains"


# ── Player resource handlers ─────────────────────────────────────────────

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


# ── Targeting handlers ───────────────────────────────────────────────────

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
	return d


# ── Entity lifecycle ─────────────────────────────────────────────────────

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


func _on_entity_died(entity, _killer, _metadata) -> void:
	var name_str: String = entity.display_name if entity and "display_name" in entity else "Unknown"
	_log("%s has been slain." % name_str, _color_kill())


# ── Chat ─────────────────────────────────────────────────────────────────

func _on_chat_received(sender_id: String, channel: int, message: String, _targets: Array) -> void:
	if _chat and _chat.has_method("add_message"):
		_chat.add_message(sender_id, channel, message)


# ── Notifications ────────────────────────────────────────────────────────

func _on_notification(_entity_id: String, notification: Dictionary) -> void:
	# NotificationService passes a Dictionary; render the text into the
	# combat log as a system message so it shows up in the same stream
	# the player already watches. We also fall through to a ToastBar if
	# the HUD has one.
	if not notification:
		return
	var text: String = str(notification.get("message", notification.get("text", "")))
	if text == "":
		return
	var color: Color = _notification_color(notification)
	_log(text, color)
	if _tooltip and _tooltip.has_method("show_toast"):
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


# ── Helpers ──────────────────────────────────────────────────────────────

func _log(text: String, color: Color) -> void:
	if _combat_log and _combat_log.has_method("add_message"):
		_combat_log.add_message("System", 0, text, 3)


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
