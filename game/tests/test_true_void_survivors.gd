extends SceneTree

## True-void survivors receipt:
##   1. The threat family found its consumer: an enemy's aggro
##      target flip ONTO the local player rows "turns its attention
##      on you"; the flip away rows "slip out of"; out_of_combat after
##      a local-focus rows "breaks off"; a stranger's flip is silence.
##   2. threat_overflow earns its first honest emit: ONE overflow call
##      when the clamp leg first hits the cap (not every add after).
##   3. threat_changed is REMOVED from the component (no-void); the
##      zone trio consumer: InstanceService holds a live subscription
##      to ZoneManager's instance_created/destroyed and rebuilds its
##      instanced-zone registry (the stale-registry bug dies).
##   4. The retirements are honest: SpawnService has no npc_spawned
##      signal, NotificationService no notification_queued (and the
##      overflow drop now WARNs), AgentConnector no observation_ready,
##      InstanceService no instance_contract_changed.
## Run:
##   godot --headless --path . --script res://tests/test_true_void_survivors.gd

const HudPath = "res://ui/hud/hud_integrator.gd"
const CombatLogPath = "res://ui/components/combat_log.gd"
const AggroPath = "res://core/components/aggro_component.gd"
const SpawnPath = "res://core/services/spawn_service.gd"
const _InstancePath = "res://core/services/instance_service.gd"
const NotificationPath = "res://core/services/notification_service.gd"
const AgentConnectorPath = "res://core/schemas/agent_connector.gd"

func _initialize() -> void:
	# Autoload-lag law: the body runs on the first idle frame.
	_run.call_deferred()

func _fail(msg: String) -> void:
	push_error("FAIL: " + msg)
	quit(1)

func _run() -> void:
	var hud = load(HudPath).new()
	root.add_child(hud)
	var log_ui = load(CombatLogPath).new()
	root.add_child(log_ui)
	hud._combat_log = log_ui

	var pm: Node = root.get_node_or_null("PlayerManager")
	if pm == null or not pm.has_method("set_local_player"):
		_fail("PlayerManager.set_local_player not reachable in script mode")
		return
	var fake_player := Node.new()
	fake_player.name = "ThreatSenseProbePlayer"
	root.add_child(fake_player)
	pm.set_local_player(fake_player)

	# 1. The binder binds itself once through the (real) service seam;
	# the enemy arrives through enemy_spawned like play does.
	hud._bind_enemy_threat_sense()
	if not hud._threat_sense_bound:
		_fail("the threat sense never bound")
		return
	var ss: Node = root.get_node_or_null("SpawnService")
	if ss == null or not ss.has_signal("enemy_spawned"):
		_fail("SpawnService.enemy_spawned not reachable in script mode")
		return
	var aggro = load(AggroPath).new()
	# Script-mode law (the economy receipt's probe lore): a bare Node
	# gains NO properties from set() -- the probe enemy declares its
	# surface in a tiny dynamic script, like the wallet probe did.
	var enemy_script := GDScript.new()
	enemy_script.source_code = "extends Node\nvar display_name: String = 'Wolf'\nvar aggro_component = null\n"
	enemy_script.reload()
	var enemy = enemy_script.new()
	enemy.name = "ProbeWolf"
	enemy.aggro_component = aggro
	root.add_child(enemy)
	ss.enemy_spawned.emit(enemy, "probe_point", null)

	var base_rows: int = log_ui.get_message_count()
	# A stranger's flip is silence; the local flip speaks.
	var stranger := Node.new()
	aggro._set_target(stranger)
	if log_ui.get_message_count() != base_rows:
		_fail("a stranger's focus flip spoke")
		return
	aggro._set_target(fake_player)
	if log_ui.get_message_count() != base_rows + 1:
		_fail("the local focus flip produced no row")
		return
	if not _last_row(log_ui).contains("Wolf turns its attention on you"):
		_fail("focus row wrong: " + _last_row(log_ui))
		return
	aggro._set_target(null)
	if log_ui.get_message_count() != base_rows + 2:
		_fail("the focus-lost flip produced no row")
		return
	if not _last_row(log_ui).contains("slip out of"):
		_fail("focus-lost row wrong: " + _last_row(log_ui))
		return
	print("[OK] the threat sense rows the local flips and keeps stranger silence")

	# 2. The overflow leg: ONE emit at the cap crossing, none after.
	var overflow_count := [0]
	var overflow_leg: Callable = func(_source): overflow_count[0] += 1
	aggro.threat_overflow.connect(overflow_leg)
	aggro.max_threat_per_target = 10
	aggro._threat_table[fake_player] = 8
	aggro.add_threat(fake_player, 5)   # would-be 13 -> clamp; FIRST overflow
	aggro.add_threat(fake_player, 5)   # already at cap -> no new emit
	if overflow_count[0] != 1:
		_fail("the overflow emitted %d times (want exactly 1)" % overflow_count[0])
		return
	print("[OK] threat_overflow emits exactly once at first cap crossing")

	# 3. The removals are honest (has_signal false) and the fight-
	# broken leg rows after a local focus.
	if aggro.has_signal("threat_changed"):
		_fail("threat_changed still declared (no-void)")
		return
	var spawn = load(SpawnPath)
	var spawn_probe: Node = _instance_of(spawn)
	if spawn_probe != null and spawn_probe.has_signal("npc_spawned"):
		_fail("npc_spawned still declared on SpawnService")
		return
	var notif: Node = root.get_node_or_null("NotificationService")
	if notif != null and notif.has_signal("notification_queued"):
		_fail("notification_queued still declared")
		return
	var connector = load(AgentConnectorPath)
	var connector_probe: Node = _instance_of(connector)
	if connector_probe != null and connector_probe.has_signal("observation_ready"):
		_fail("observation_ready still declared")
		return
	print("[OK] the retirements hold: no npc_spawned / notification_queued / observation_ready / threat_changed")

	# The out_of_combat book: after a local focus, the row speaks.
	aggro._set_target(fake_player)
	aggro.out_of_combat.emit()
	if not _last_row(log_ui).contains("breaks off"):
		_fail("the fight-broken leg did not speak after a local focus")
		return
	print("[OK] the fight-broken leg rows after a local focus")

	# 4. The zone trio consumer: a live instance_created re-rebuilds
	# the instanced-zone registry.
	var isvc: Node = root.get_node_or_null("InstanceService")
	if isvc == null or not isvc.has_method("_rebuild_arena_registry"):
		_fail("InstanceService not reachable in script mode")
		return
	var zm: Node = root.get_node_or_null("ZoneManager")
	if zm == null or not zm.has_signal("instance_created"):
		_fail("ZoneManager.instance_created not reachable in script mode")
		return
	var stale_zone: Dictionary = {
		"base_zone_id": "zone_starter_plains",
	}
	var before: bool = bool(isvc.call("is_instanced_zone", "zone_starter_plains")) if isvc.has_method("is_instanced_zone") else false
	zm._instances["probe_instance_live"] = stale_zone
	zm.instance_created.emit("probe_instance_live", null)
	var after: bool = bool(isvc.call("is_instanced_zone", "zone_starter_plains")) if isvc.has_method("is_instanced_zone") else false
	if after == before and not before:
		_fail("the zone trio consumer did not rebuild the registry")
		return
	if isvc.has_signal("instance_contract_changed"):
		_fail("instance_contract_changed still declared")
		return
	print("[OK] the zone trio consumer rebuilds the instanced-zone registry live")

	print("TRUE-VOID-SURVIVORS-ALL-OK")
	quit(0)

func _last_row(log_ui) -> String:
	var entries = log_ui.get("_entries")
	if entries == null or entries.size() == 0:
		return ""
	var row = entries[entries.size() - 1]
	return str(row.get("text")) if row is Dictionary else str(row)

## Instance a service script without tree attachment (for decl checks).
func _instance_of(script: GDScript) -> Node:
	if script == null or not script.can_instantiate():
		return null
	return script.new()
