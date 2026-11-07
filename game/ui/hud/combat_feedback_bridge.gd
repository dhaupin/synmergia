## CombatFeedbackBridge - the shared in-world combat feedback rows.
##
## Installed by HudLayer on EVERY playable scene (world_playable embeds
## hud_layer.tscn; globe_world calls HudLayer.ensure_installed). It is
## the ONE voice for the combat surface both worlds share:
##   - damage_dealt / heal_dealt -> floating numbers + CombatLog rows
##   - hit_resolved (miss/dodge/parry/block) -> floats + log + local toast
##   - kill_rewarded -> "+N XP, +M gold" row + float over the killer
##   - ground_loot_* -> loot row + minimap glints
##   - quest_updated / quest_completed -> tracker rows
##
## Extracted from world_playable so the globe inherits the same rows
## without a second copy (planar-retirement Step 2); Step 5 deletes the
## planar scene and this stays.
extends Node

const DamageNumbersScript := preload("res://ui/components/damage_numbers.gd")

var _hud: CanvasLayer
var _combat_log: Node
var _minimap: Node
var _damage_numbers: Node


func bind(hud: CanvasLayer) -> void:
	_hud = hud
	_combat_log = _find("CombatLog")
	_minimap = _find("Minimap")
	_ensure_damage_numbers()
	_connect_all()


func _find(node_name: String) -> Node:
	if _hud == null:
		return null
	return _hud.get_node_or_null(node_name)


## Floating combat text lives on the HUD CanvasLayer so both worlds get
## it from one owner (the planar scene used to add it under the scene
## root; a CanvasLayer projects the same way and rides the HUD lifecycle).
func _ensure_damage_numbers() -> void:
	if _hud == null:
		return
	_damage_numbers = _hud.get_node_or_null("DamageNumbers")
	if _damage_numbers == null:
		_damage_numbers = DamageNumbersScript.new()
		_damage_numbers.name = "DamageNumbers"
		_hud.add_child(_damage_numbers)


func _connect_all() -> void:
	if EventHub:
		if not EventHub.damage_dealt.is_connected(_on_combat_damage):
			EventHub.damage_dealt.connect(_on_combat_damage)
		if not EventHub.hit_resolved.is_connected(_on_hit_resolved):
			EventHub.hit_resolved.connect(_on_hit_resolved)
		if not EventHub.heal_dealt.is_connected(_on_combat_heal):
			EventHub.heal_dealt.connect(_on_combat_heal)
		if not EventHub.kill_rewarded.is_connected(_on_kill_rewarded):
			EventHub.kill_rewarded.connect(_on_kill_rewarded)
		if not EventHub.ground_loot_picked_up.is_connected(_on_ground_loot_picked_up):
			EventHub.ground_loot_picked_up.connect(_on_ground_loot_picked_up)
		if not EventHub.ground_loot_spawned.is_connected(_on_ground_loot_spawned):
			EventHub.ground_loot_spawned.connect(_on_ground_loot_spawned)
		if not EventHub.ground_loot_despawned.is_connected(_on_ground_loot_despawned):
			EventHub.ground_loot_despawned.connect(_on_ground_loot_despawned)
	if QuestService and QuestService.has_signal("quest_updated"):
		if not QuestService.quest_updated.is_connected(_on_quest_updated):
			QuestService.quest_updated.connect(_on_quest_updated)
	if QuestService and QuestService.has_signal("quest_completed"):
		if not QuestService.quest_completed.is_connected(_on_quest_completed):
			QuestService.quest_completed.connect(_on_quest_completed)


# == Damage / Heal ========================================================

func _on_combat_damage(source, target, amount: int, damage_type: String, is_crit: bool = false) -> void:
	if amount <= 0:
		return

	if _damage_numbers and target is Node3D:
		_damage_numbers.show_damage(target, amount, is_crit, damage_type)
	# Typed log methods so the Damage/Healing/Loot filters actually route
	# entries; crits get the [CRITICAL] line.
	if _combat_log == null:
		return
	var source_name: String = "Something"
	if source != null and "display_name" in source:
		source_name = str(source.display_name)
	var target_name: String = "Unknown"
	if target != null and "display_name" in target:
		target_name = str(target.display_name)
	if is_crit:
		_combat_log.log_critical(target_name, amount)
		_notify_crit_toast(source, target_name, amount)
	else:
		_combat_log.log_damage(target_name, amount, damage_type, source_name)


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
	if _combat_log == null:
		return
	var source_name: String = "Healing"
	if source != null and "display_name" in source:
		source_name = str(source.display_name)
	_combat_log.log_heal("you", amount, source_name)


## Hit-table bridge: one handler for every resolved swing.
##   Landed hit  -> damage float + log line arrive via damage_dealt (the
##                  target's take_damage path); blocks also get their
##                  "Blocked X" annotation here.
##   Whiff       -> defender-side "Miss/Dodge/Parry" float, log line, and
##                  a toast when the LOCAL player is the defender (you
##                  dodged) or attacker (your swing missed).
func _on_hit_resolved(attacker, defender, outcome: Dictionary, _skill, amount: int) -> void:
	var outcome_id: int = int(outcome.get("hit_result", CombatMath.HitResult.HIT))
	if outcome_id == CombatMath.HitResult.HIT and not bool(outcome.get("is_crit", false)):
		return  # plain landed hit: damage_dealt already drew the number

	var label: String = CombatMath.hit_label(outcome)
	var local = PlayerManager.get_local_player()

	# Whiff floats over the DEFENDER ("you dodged" reads best over the
	# dodger's head); blocks land as "Blocked <chip>" on the defender.
	if _damage_numbers and defender != null and defender is Node3D:
		if CombatMath.is_whiff(outcome_id):
			_damage_numbers.show_miss(defender, label)
		elif outcome_id == CombatMath.HitResult.BLOCK:
			_damage_numbers.show_miss(defender, label)

	if _combat_log != null and _combat_log.has_method("log_miss"):
		var attacker_name: String = "Something"
		if attacker != null and "display_name" in attacker:
			attacker_name = str(attacker.display_name)
		var defender_name: String = "Unknown"
		if defender != null and "display_name" in defender:
			defender_name = str(defender.display_name)
		if CombatMath.is_whiff(outcome_id):
			_combat_log.log_miss("%s's attack (%s vs %s)" % [attacker_name, label, defender_name])
		elif outcome_id == CombatMath.HitResult.BLOCK:
			_combat_log.add_message(
				"%s blocks %s's attack (%d chip through)" % [defender_name, attacker_name, amount],
				0)

	# Defender toasts through the legacy notify_combat pipeline: the local
	# player sees DODGE/PARRY/BLOCK when THEY defend, and a miss notice
	# when their own swing whiffs. notify_combat rewrites the message for
	# the known types, so pass a short payload.
	if local == null:
		return
	var notif = get_node_or_null("/root/NotificationService")
	if notif == null or not notif.has_method("notify_combat"):
		return
	if CombatMath.is_whiff(outcome_id):
		if defender == local:
			notif.notify_combat(str(local.entity_id), label.to_upper(), label, true)
		elif attacker == local:
			notif.notify_combat(str(local.entity_id), "MISS", label, false)
	elif outcome_id == CombatMath.HitResult.BLOCK and defender == local:
		notif.notify_combat(str(local.entity_id), "BLOCK", label, true)


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


# == Kill rewards ========================================================

func _on_kill_rewarded(entity, killer, rewards: Dictionary) -> void:
	var xp: int = int(rewards.get("xp", 0))
	var gold: int = int(rewards.get("gold", 0))

	if _combat_log != null and _combat_log.has_method("add_message"):
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
			_combat_log.add_message(
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


# == Ground loot =========================================================

func _on_ground_loot_picked_up(player, loot_id: String, items: Array) -> void:
	_clear_loot_marker(loot_id)
	if _combat_log == null or not _combat_log.has_method("log_loot"):
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
		_combat_log.log_loot(item_name, qty)


## Minimap loot glints: a gold 4-point star per live drop, removed on
## pickup/despawn. Markers live on the HudLayer Minimap node.
func _on_ground_loot_spawned(loot_id: String, position: Vector3, _items: Array) -> void:
	if _minimap != null and _minimap.has_method("add_marker"):
		_minimap.add_marker("loot_%s" % loot_id, position, _minimap.MARKER_LOOT, "")


func _on_ground_loot_despawned(loot_id: String, _reason: String) -> void:
	_clear_loot_marker(loot_id)


func _clear_loot_marker(loot_id: String) -> void:
	if _minimap != null and _minimap.has_method("remove_marker"):
		_minimap.remove_marker("loot_%s" % loot_id)


# == Quests ==============================================================

func _on_quest_updated(player_id: String, quest_id: String, objective_id: String, progress: int) -> void:
	var local = PlayerManager.get_local_player()
	if local == null or not ("entity_id" in local) or str(local.entity_id) != player_id:
		return
	if _combat_log and _combat_log.has_method("add_message"):
		_combat_log.add_message("Quest %s: %s progress %d" % [quest_id, objective_id, progress])


func _on_quest_completed(player_id: String, quest_id: String) -> void:
	var local = PlayerManager.get_local_player()
	if local == null or not ("entity_id" in local) or str(local.entity_id) != player_id:
		return
	if _combat_log and _combat_log.has_method("add_message"):
		_combat_log.add_message("QUEST COMPLETE: %s -- return to the quest giver" % quest_id)
