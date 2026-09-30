## SpawnService - Enemy/NPC spawn management
## Handles spawn points, respawn timers, spawn caps, and dynamic spawning
extends Node
const Faction = preload("res://core/schemas/faction.gd")
const NPCData = preload("res://core/schemas/npc_data.gd")
const ZoneData = preload("res://core/schemas/zone_data.gd")
const SpawnMetadata = preload("res://core/events/spawn_metadata.gd")
const EnemyData = preload("res://core/schemas/enemy_data.gd")
const NPCEntity = preload("res://core/entities/npc_entity.gd")
# Entity is not an autoload (class_name only). SpawnService calls
# Entity.new() and Entity.EntityType.X, which requires Entity's
# class_name registered at parse time. Preload it here.
const Entity = preload("res://core/entities/entity.gd")
const KillRewards = preload("res://core/services/kill_rewards.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind
const EnemyScript = preload("res://entities/enemy.gd")
const EnemyAIScript = preload("res://core/ai/enemy_ai.gd")
# Spawn points organized by zone (zone_id -> [SpawnPoint])
var _spawn_points: Dictionary = {}

# Active spawn timers (spawn_point_id -> time_until_spawn)
var _spawn_timers: Dictionary = {}

# Spawned entities (spawn_point_id -> [entity_ids])
var _spawned_entities: Dictionary = {}

# Data-placed offering NPCs (npc_id -> NPCEntity) for idempotent spawn.
# Both boot routes call spawn_all_offering_npcs; this registry plus the
# freed-entity prune at the top of that function guarantees one live
# entity per npc_id and re-spawn after scene changes.

# One entity per position, everywhere. A 2.0-unit hex-ring step keeps
# body-radius meshes from overlapping; callers needing exact stacking
# (visual formations) pass stack=true explicitly.
const SPAWN_RING_STEP := 2.0

## Anti-stack scatter: position for entity `index` of `count` around
## center. Deterministic (no rng): index 0 lands on center, the rest
## ring outward in hex rings at SPAWN_RING_STEP spacing. Survives
## repeated /spawn 1 invocations -- each new entity takes the next
## free hex slot instead of landing on the last one. stack=true
## returns center for exact stacking when a caller truly wants it.
static func ring_spread(center: Vector3, count: int, index: int, stack: bool = false) -> Vector3:
	if stack or count <= 1:
		return center
	var i := maxi(index, 0)
	if i == 0:
		return center
	var ring := 1
	while 3 * ring * (ring + 1) + 1 <= i:
		ring += 1
	var idx_in_ring := i - (3 * ring * (ring - 1) + 1)
	var side := idx_in_ring / ring
	var side_pos := idx_in_ring % ring
	var angle := TAU * float(side) / 6.0 + TAU * float(side_pos) / float(6 * ring)
	var radius := SPAWN_RING_STEP * float(ring)
	return center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
var _spawned_offering_npcs: Dictionary = {}

# World bosses (boss_id -> )
var _world_bosses: Dictionary = {}

# Spawn point schema
class SpawnPoint:
	var id: String
	var zone_id: String
	var position: Vector3
	var spawn_radius: float
	var enemy_template_id: String
	var enemy_data: EnemyData
	var species_id: String	# Links to Species for faction relationships
	var respawn_time: float	 # Base respawn time in seconds
	var min_enemies: int		 # Min spawned at this point
	var max_enemies: int		 # Max spawned at this point
	var current_count: int	 # Currently spawned
	var spawn_type: EnemyData.EnemyType
	var is_active: bool = true

	# Dynamic scaling
	var spawn_multiplier: float = 1.0	 # 1.0 = normal, 2.0 = double during events

	func _init(
		p_id: String,
		p_zone_id: String,
		p_position: Vector3,
		p_enemy_template: String,
		p_species_id: String = "",
		p_respawn: float = 60.0,
		p_min: int = 1,
		p_max: int = 1,
		p_type: EnemyData.EnemyType = EnemyData.EnemyType.NORMAL
	) -> void:
		id = p_id
		zone_id = p_zone_id
		position = p_position
		spawn_radius = 3.0
		enemy_template_id = p_enemy_template
		species_id = p_species_id
		respawn_time = p_respawn
		min_enemies = p_min
		max_enemies = p_max
		current_count = 0
		spawn_type = p_type

	func get_spawn_position() -> Vector3:
		# Anti-stack: entities from one spawn point ring out in hex slots
		# instead of dumping into one random box (the old randf_range box
		# could clump several bodies on the same spot). Respawn waves take
		# the next ring slot via current_count.
		var slot := maxi(current_count, 0)
		var spread: Vector3 = SpawnService.ring_spread(position, slot + 1, slot)
		if spawn_radius > 0.0:
			# Constrain to the point's configured radius (ring step 2.0
			# keeps every slot inside radius for the first ~hundreds).
			var max_r := maxf(spawn_radius, SpawnService.SPAWN_RING_STEP)
			var flat := Vector3(spread.x - position.x, 0.0, spread.z - position.z)
			if flat.length() > max_r:
				flat = flat.normalized() * max_r
			spread = position + flat
		return spread

	func should_spawn() -> bool:
		if not is_active:
			return false
		var effective_max = int(max_enemies * spawn_multiplier)
		return current_count < effective_max

## SpawnService-specific signals for spawn-point-aware listeners
## These complement the unified EventHub.entity_spawned with spawn-point context
signal spawn_point_registered(spawn_point: Dictionary)
signal enemy_spawned(entity, spawn_point_id: String, metadata: SpawnMetadata)
signal enemy_despawned(entity, spawn_point_id: String, metadata: SpawnMetadata)
signal boss_spawned(entity, boss_name: String, metadata: SpawnMetadata)
signal npc_spawned(npc, npc_id: String, metadata: SpawnMetadata)
signal spawn_point_cleared(spawn_point_id: String)
signal world_boss_schedule_started(schedule_id: String, config: Dictionary)
signal world_boss_schedule_spawned(schedule_id: String, boss: Entity)

func _ready() -> void:
	load_world_boss_schedules()
	GameLog.info("SpawnService: Ready")

## ---------------------------------------------------------------------------
## Timed world-boss schedules (data/world_bosses/*.tres -> WorldBossData)
## ---------------------------------------------------------------------------

## Live schedule entries: id -> {"config": WorldBossData.to_config(),
## "time_left": float, "boss_id": String ("" while down), "running":
## bool, "respawn_from_death": bool}. Timers tick in _process; the
## first spawn waits first_delay_s, later respawns count from the
## boss's DEATH (killed 2 min after appearing does not skip downtime).
var _world_boss_schedules: Dictionary = {}

## Scan data/world_bosses/ and start every schedule at boot. Called
## from _ready (DataService loads before SpawnService in project.godot
## autoload order, so get_enemy resolves templates).
func _process(delta: float) -> void:
	_tick_world_boss_schedules(delta)

const ResourceScan = preload("res://core/frame/srv/resource_scan.gd")

func load_world_boss_schedules() -> void:
	# Export-safe scan: the pack stores .tres as .res + .tres.remap.
	var paths := ResourceScan.list_resources("res://data/world_bosses")
	if paths.is_empty() and DirAccess.open("res://data/world_bosses") == null:
		GameLog.info("SpawnService: no world_bosses data dir; no schedules")
		return
	var count := 0
	for p in paths:
		var res: Resource = load(p)
		if res != null and res.has_method("to_config"):
			# Resource.get(key, default) lost its default arg in 4.7.2:
			# fall back to the file stem when the resource carries no id.
			var rid := str(res.get("id"))
			if rid.is_empty():
				rid = ResourceScan.resource_base(p.get_file()).trim_prefix("world_boss_")
			if start_world_boss_schedule(rid, res.to_config()) != "":
				count += 1
	GameLog.info("SpawnService: Loaded %d world-boss schedules" % count)

## Start one timed schedule. Returns the schedule id ("" on bad config
## or unknown template). An id that is already live is stopped first
## (runtime re-start replaces the entry, mirroring the admin surface).
func start_world_boss_schedule(schedule_id: String, config: Dictionary) -> String:
	var sid := str(schedule_id).strip_edges()
	var template_id := str(config.get("boss_template_id", ""))
	var zone := str(config.get("zone_id", ""))
	if sid.is_empty() or template_id.is_empty() or zone.is_empty():
		GameLog.warn("SpawnService: world-boss schedule '%s' missing id/template/zone" % sid)
		return ""
	var ds = DataService
	if ds == null or ds.get_enemy(template_id) == null:
		GameLog.warn("SpawnService: world-boss schedule '%s' template '%s' not found" % [sid, template_id])
		return ""
	stop_world_boss_schedule(sid, "restarted")
	_world_boss_schedules[sid] = {
		"config": config.duplicate(true),
		"time_left": maxf(0.0, float(config.get("first_delay_s", 0.0))),
		"boss_id": "",
		"window_left": maxf(0.0, float(config.get("window_seconds", 0.0))),
		"running": true,
	}
	GameLog.info("SpawnService: world-boss schedule '%s' started (%s in %s, every %ds)" % [
		sid, template_id, zone, int(config.get("interval_seconds", 0.0))])
	world_boss_schedule_started.emit(sid, config)
	return sid

## Stop a schedule: clears its live boss (quiet despawn) and drops the
## entry. Unknown ids are a no-op returning false.
func stop_world_boss_schedule(schedule_id: String, reason: String = "stopped") -> void:
	if not _world_boss_schedules.has(schedule_id):
		return
	var entry: Dictionary = _world_boss_schedules[schedule_id]
	var bid := str(entry.get("boss_id", ""))
	if bid != "":
		var boss = _world_bosses.get(bid)
		if boss != null and is_instance_valid(boss):
			despawn_boss(boss)
	_world_boss_schedules.erase(schedule_id)
	GameLog.info("SpawnService: world-boss schedule '%s' %s" % [schedule_id, reason])

## Schedule status for /boss schedule info and tests: a flat Dictionary
## with the config and current phase ("waiting" | "live").
func get_world_boss_schedule_status(schedule_id: String) -> Dictionary:
	if not _world_boss_schedules.has(schedule_id):
		return {}
	var entry: Dictionary = _world_boss_schedules[schedule_id]
	var out: Dictionary = entry.get("config", {}).duplicate(true)
	out["schedule_id"] = schedule_id
	out["state"] = "live" if str(entry.get("boss_id", "")) != "" else "waiting"
	out["time_left"] = float(entry.get("time_left", 0.0))
	out["boss_id"] = str(entry.get("boss_id", ""))
	return out

func get_world_boss_schedule_ids() -> Array:
	return _world_boss_schedules.keys()

## Fire a schedule's spawn NOW (admin /boss schedule run, tests). When
## the boss is already up, return it instead of spawning a duplicate.
## The timer resets to interval_seconds on the boss's death, so a forced
## early spawn keeps the post-kill downtime honest.
func run_world_boss_schedule_now(schedule_id: String) -> Variant:
	var entry: Dictionary = _world_boss_schedules.get(schedule_id, {})
	if entry.is_empty() or not bool(entry.get("running", false)):
		return null
	var live_bid := str(entry.get("boss_id", ""))
	if live_bid != "":
		var live = _world_bosses.get(live_bid)
		if live != null and is_instance_valid(live):
			return live
	return _spawn_scheduled_world_boss(schedule_id, entry)

## Spawn the scheduled boss (schedule trigger or forced run). Returns
## the boss Entity (null on zone loss or spawn failure -- the schedule
## stays alive and retries on its next tick).
func _spawn_scheduled_world_boss(schedule_id: String, entry: Dictionary) -> Variant:
	var cfg: Dictionary = entry.get("config", {})
	var template_id := str(cfg.get("boss_template_id", ""))
	var zone_id := str(cfg.get("zone_id", ""))
	var ds = DataService
	var template = ds.get_enemy(template_id) if ds != null else null
	if template == null:
		GameLog.error("SpawnService: schedule '%s' lost its template '%s'" % [schedule_id, template_id])
		return null
	var spawn_pos: Vector3 = cfg.get("position", Vector3.ZERO)
	if spawn_pos == Vector3.ZERO:
		var zm = ZoneManager
		if zm != null:
			var zone = zm.get_zone(zone_id)
			if zone != null and "zone_center" in zone:
				spawn_pos = zone.zone_center
	var boss_name := str(cfg.get("display_name", ""))
	if boss_name == "":
		boss_name = str(template.display_name)
	# announce=false must actually mute: force_announce=-1 overrides the
	# default-scope fallback in spawn_boss (an empty scope list otherwise
	# gets re-forced to server-wide).
	var announce: bool = bool(cfg.get("announce", true))
	var scopes: Array = [NotificationService.AlertScope.server_wide()] if announce else []
	var announce_cfg: int = 1 if announce else -1
	var boss = spawn_boss(template_id, spawn_pos, zone_id, boss_name, scopes,
		SpawnMetadata.SpawnType.WORLD_BOSS, announce_cfg)
	if boss == null:
		GameLog.error("SpawnService: schedule '%s' spawn failed; retries next tick" % schedule_id)
		return null
	entry["boss_id"] = str(boss.entity_id)
	entry["window_left"] = maxf(0.0, float(cfg.get("window_seconds", 0.0)))
	# Death -> respawn timer = interval_seconds (counted from DEATH).
	if boss.has_signal("died") and not boss.died.is_connected(_on_scheduled_boss_died):
		boss.died.connect(_on_scheduled_boss_died.bind(schedule_id))
	world_boss_schedule_spawned.emit(schedule_id, boss)
	GameLog.info("SpawnService: world boss '%s' spawned (schedule %s)" % [boss_name, schedule_id])
	return boss

## Scheduled boss death: pay rewards (shared boss path already did via
## _on_boss_entity_died -- this only rearms the respawn timer) and
## clear the window. Death, not spawn, starts the downtime.
func _on_scheduled_boss_died(_killer, schedule_id: String) -> void:
	var entry: Dictionary = _world_boss_schedules.get(schedule_id, {})
	if entry.is_empty():
		return
	var cfg: Dictionary = entry.get("config", {})
	var interval := float(cfg.get("interval_seconds", 0.0))
	entry["boss_id"] = ""
	entry["time_left"] = interval
	if interval <= 0.0:
		# One-shot schedule: the boss died and the loop is done.
		stop_world_boss_schedule(schedule_id, "completed (one-shot)")
		return
	GameLog.info("SpawnService: world boss down; '%s' respawns in %ds" % [schedule_id, int(interval)])

## Per-frame schedule tick: fires spawns when timers hit zero and
## sweeps unclaimed bosses whose window expired.
func _tick_world_boss_schedules(delta: float) -> void:
	for sid in _world_boss_schedules.keys():
		var entry: Dictionary = _world_boss_schedules[sid]
		var bid := str(entry.get("boss_id", ""))
		if bid != "":
			var boss = _world_bosses.get(bid)
			var gone: bool = boss == null or not is_instance_valid(boss)
			# A boss destroyed without emitting died (admin free, scene
			# teardown) must still rearm the timer, or the schedule wedges.
			if gone:
				_on_scheduled_boss_died(null, sid)
				continue
			var window := float(entry.get("window_left", 0.0))
			if window > 0.0:
				window -= delta
				entry["window_left"] = window
				if window <= 0.0:
					GameLog.info("SpawnService: world boss window expired; '%s' despawns" % sid)
					despawn_boss(boss)
					# despawn_boss frees without died; rearm here.
					_on_scheduled_boss_died(null, sid)
			continue
		var left := float(entry.get("time_left", 0.0)) - delta
		if left <= 0.0:
			entry["time_left"] = 0.0
			_spawn_scheduled_world_boss(sid, entry)
		else:
			entry["time_left"] = left

## Register a spawn point
func register_spawn_point(
	zone_id: String,
	position: Vector3,
	enemy_template_id: String,
				species_id: String = "",
	respawn_time: float = 60.0,
	min_enemies: int = 1,
	max_enemies: int = 1,
	enemy_type: EnemyData.EnemyType = EnemyData.EnemyType.NORMAL
) -> String:
	var spawn_point_id = "spawn_%s_%d" % [zone_id, _spawn_timers.size()]

	var spawn_point := SpawnPoint.new(
		spawn_point_id,
		zone_id,
		position,
		enemy_template_id,
		species_id,
		respawn_time,
		min_enemies,
		max_enemies,
		enemy_type
	)

	# Load enemy data
	var data_service = DataService
	if data_service:
		spawn_point.enemy_data = data_service.get_enemy(enemy_template_id)

	if not _spawn_points.has(zone_id):
		_spawn_points[zone_id] = []
	_spawn_points[zone_id].append(spawn_point)
	_spawned_entities[spawn_point_id] = []

	spawn_point_registered.emit({
		"id": spawn_point_id,
		"zone_id": zone_id,
		"position": position,
		"enemy_template": enemy_template_id
	})

	GameLog.debug("SpawnService: Registered spawn point %s in zone %s" % [spawn_point_id, zone_id])
	return spawn_point_id

## Register spawn point from config
func register_spawn_point_from_config(config: Dictionary) -> String:
	## Positional order must match register_spawn_point's signature:
	## (zone_id, position, enemy_template_id, species_id, respawn_time,
	##  min_enemies, max_enemies, enemy_type). The previous mapping put
	## respawn_time in the species_id slot and shifted the rest.
	return register_spawn_point(
		config.get("zone_id", ""),
		config.get("position", Vector3.ZERO),
		config.get("enemy_template_id", ""),
		config.get("species_id", ""),
		config.get("respawn_time", 60.0),
		config.get("min_enemies", 1),
		config.get("max_enemies", 1),
		config.get("enemy_type", EnemyData.EnemyType.NORMAL)
	)

## Get spawn points for a zone
func get_zone_spawn_points(zone_id: String) -> Array:
	return _spawn_points.get(zone_id, [])

## Spawn enemy at a spawn point
func spawn_enemy(spawn_point_id: String) -> Variant:
	var spawn_point = _get_spawn_point(spawn_point_id)
	if spawn_point == null or not spawn_point.should_spawn():
		return null

	# Check proximity to players
	if _is_spawn_point_safe(spawn_point) == false:
		return null	 # Players too close, delay spawn

	# Create enemy entity
	var enemy = _create_enemy(spawn_point)
	if enemy == null:
		return null

	# Track spawned entity
	spawn_point.current_count += 1
	_spawned_entities[spawn_point_id].append(enemy.entity_id)

	# Create spawn metadata with position for zone notifications
	var metadata := SpawnMetadata.enemy(
		enemy.display_name,
		spawn_point.zone_id,
		spawn_point.position,
		enemy.level
	)
	metadata.faction = enemy.faction

	# Apply elite/boss notification settings based on enemy type
	if spawn_point.spawn_type == EnemyData.EnemyType.ELITE:
		metadata = SpawnMetadata.elite(
			enemy.display_name,
			spawn_point.zone_id,
			spawn_point.position,
			enemy.level
		)
	elif spawn_point.spawn_type == EnemyData.EnemyType.BOSS:
		metadata = SpawnMetadata.boss(
			enemy.display_name,
			spawn_point.zone_id,
			spawn_point.position,
			enemy.level
		)

	# Register with EntityService (emits EventHub.entity_spawned with metadata)
	var entity_service = EntityService
	if entity_service:
		entity_service.register_entity(enemy, metadata)

	# Register with TargetingManager
	var targeting_manager = TargetingManager
	if targeting_manager:
		targeting_manager.register_targetable(
			enemy.entity_id,
			"enemy",
			enemy,
			enemy.display_name,
			spawn_point.get_spawn_position(),
			enemy.entity_type
		)

	# Position enemy
	enemy.global_position = spawn_point.get_spawn_position()

	# Attach an AI brain configured from EnemyData ranges. Without this the
	# enemy stands inert: aggro/threat/memory systems are unreachable.
	var ai = EnemyAIScript.new()
	ai.aggro_range = spawn_point.enemy_data.aggro_range
	ai.chase_range = spawn_point.enemy_data.chase_range
	ai.attack_range = spawn_point.enemy_data.attack_range
	enemy.attach_ai(ai)

	# Parent into the scene tree so _physics_process runs (movement, AI
	# steering) and the enemy is visible. SpawnService is an autoload Node;
	# spawn under the current scene's root.
	var ml = Engine.get_main_loop()
	if ml is SceneTree and is_instance_valid(enemy):
		var tree := ml as SceneTree
		var parent_node: Node = tree.current_scene if tree.current_scene else tree.root
		parent_node.add_child(enemy)

	# Add to zone
	var zone_manager = ZoneManager
	if zone_manager:
		var zone = zone_manager.get_zone(spawn_point.zone_id)
		if zone:
			zone_manager.entity_enter_zone(enemy, zone)

	# Emit service-specific signal with spawn point context
	enemy_spawned.emit(enemy, spawn_point_id, metadata)
	GameLog.debug("SpawnService: Spawned %s at %s" % [enemy.display_name, spawn_point_id])

	return enemy

## Spawn boss
##
## metadata_type picks the spawn metadata class (default WORLD_BOSS, the
## historical behavior; SpawnMetadata.BOSS_SILENT mutes the spawn
## announcement for admin testing). alert_scopes empty = metadata
## default: an enabled metadata gets a server-wide announcement (an
## empty scope list would otherwise silently reach nobody); callers
## pass explicit scopes for zone/nearby alerts. Horde wave bosses pass
## BOSS-type ids so a mid-horde champion does not read as a world event.
func spawn_boss(
	boss_template_id: String,
	position: Vector3,
	zone_id: String,
	boss_name: String = "",
	alert_scopes: Array = [],
	metadata_type: int = -1,
	force_announce: int = 0
) -> Variant:
	## force_announce: -1 = mute notifications (announce=false schedules,
	## quiet admin testing); 0 = caller default (empty scopes still get
	## the classic server-wide world-boss callout); +1 = caller scopes
	## win over any metadata default.
	var data_service = DataService
	if data_service == null:
		return null

	var boss_data = data_service.get_enemy(boss_template_id)
	if boss_data == null:
		GameLog.warn("SpawnService: Boss template %s not found" % boss_template_id)
		return null

	var boss = Entity.new()
	boss.display_name = boss_name if boss_name != "" else boss_data.display_name
	boss.entity_type = Entity.EntityType.ENEMY
	boss.level = boss_data.level
	boss.faction = Entity.Relation.HOSTILE
	boss.faction_id = boss_data.faction
	# Carry the template on the node: KillRewards reads enemy_data for
	# xp/gold, achievement listeners classify boss/elite, and
	# WorldStateProjection only projects entities carrying enemy_data.
	boss.enemy_data = boss_data

	# Apply stats from template
	boss.stats["strength"] = boss_data.strength
	boss.stats["agility"] = boss_data.agility
	boss.stats["intelligence"] = boss_data.intelligence
	boss.stats["vitality"] = boss_data.vitality

	boss.max_health = boss_data.health
	boss.current_health = boss_data.health

	# Create spawn metadata with notification settings
	var mtype: int = metadata_type
	var silent: bool = mtype == SpawnMetadata.BOSS_SILENT
	if silent:
		mtype = SpawnMetadata.SpawnType.BOSS
	if mtype < 0:
		mtype = SpawnMetadata.SpawnType.WORLD_BOSS
	var metadata: SpawnMetadata
	match mtype:
		SpawnMetadata.SpawnType.WORLD_BOSS:
			metadata = SpawnMetadata.world_boss(boss.display_name, zone_id, position, boss.level)
		SpawnMetadata.SpawnType.ELITE:
			metadata = SpawnMetadata.elite(boss.display_name, zone_id, position, boss.level)
		SpawnMetadata.SpawnType.NORMAL:
			metadata = SpawnMetadata.enemy(boss.display_name, zone_id, position, boss.level)
		_:
			metadata = SpawnMetadata.boss(boss.display_name, zone_id, position, boss.level)
	metadata.faction = boss.faction
	if silent or force_announce < 0:
		metadata.notification_enabled = false
	elif alert_scopes.size() > 0:
		metadata.notification_enabled = true
		metadata.notification_scopes = alert_scopes
	elif force_announce == 0 and metadata.notification_enabled:
		# Enabled metadata with an empty scope list reaches nobody
		# (broadcast_alert walks zero scopes): default to server-wide so
		# the classic world-boss spawn actually announces.
		metadata.notification_scopes = [NotificationService.AlertScope.server_wide()]

	# Parent into the scene tree BEFORE registration: register_entity
	# derives the NSC-9 spatial address from global_position, which
	# errors on a node outside the tree. Parenting here also keeps the
	# kill-credit lesson (tree presence makes _is_valid_combatant
	# (KillRewards) accept the boss -- without it boss kills were
	# creditless: no kill_rewarded, no XP/gold, no participation).
	# Prefer the current scene (world visibility), fall back to root for
	# headless/script mode.
	var tree := get_tree()
	if tree != null and not boss.is_inside_tree():
		var parent_node: Node = tree.current_scene if tree.current_scene else tree.root
		parent_node.add_child(boss)
	boss.global_position = position

	# Register with EntityService (emits EventHub.entity_spawned with metadata)
	var entity_service = EntityService
	if entity_service:
		entity_service.register_entity(boss, metadata)

	# Register with TargetingManager
	var targeting_manager = TargetingManager
	if targeting_manager:
		targeting_manager.register_targetable(
			boss.entity_id,
			"enemy",
			boss,
			boss.display_name,
			position,
			boss.entity_type
		)

	_world_bosses[boss.entity_id] = boss

	# Boss death -> kill rewards: bare Entities skip Enemy._on_died, so
	# nothing ever emitted kill_rewarded for a boss kill (no XP/gold,
	# no quest kill objectives, no achievements, no horde participation).
	# Route through KillRewards exactly like the enemy death path does;
	# its credit resolution (direct killer or threat owner) applies to
	# the killer argument Entity.die already carries. Connected BEFORE
	# any consumer's died-hook (hordes connect after spawn returns) so
	# kill_rewarded arrives while a running horde can still credit it.
	if boss.has_signal("died") and not boss.died.is_connected(_on_boss_entity_died):
		boss.died.connect(_on_boss_entity_died.bind(boss, mtype == SpawnMetadata.SpawnType.WORLD_BOSS))

	# Add to zone
	var zone_manager = ZoneManager
	if zone_manager:
		var zone = zone_manager.get_zone(zone_id)
		if zone:
			zone_manager.entity_enter_zone(boss, zone)

	# Emit service-specific signal with spawn context
	boss_spawned.emit(boss, boss.display_name, metadata)
	GameLog.info("SpawnService: Spawned BOSS %s at %s" % [boss.display_name, str(position)])

	# Notification is now handled by NotificationService listening to EventHub.entity_spawned

	return boss

## Entity.die(killer) handler for bare-Entity bosses: pays kill rewards
## exactly like Enemy._on_died does (KillRewards resolves credit, grants
## XP/gold, emits EventHub.kill_rewarded for quests/achievements/hordes).
func _on_boss_entity_died(killer, boss, is_world_boss: bool = false) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	KillRewards.award_kill(boss, killer)
	# Spawns announce ("X has appeared!"); kills stayed silent. Mirror the
	# spawn callout -- but only for TRUE world bosses: horde wave champions
	# share this death handler (they connect with is_world_boss=false), and
	# the horde state machine already narrates its own bosses ("wave
	# cleared", finale). Runtime lookup: NotificationService loads after
	# this service (forward edge, bare references poison --script tests).
	if not is_world_boss:
		return
	var notif := get_node_or_null("/root/NotificationService")
	if notif != null and notif.has_method("notify"):
		notif.notify(
			NotifKind.CUSTOM,
			"WORLD BOSS DEFEATED: %s has been slain!" % str(boss.display_name),
			"SpawnService",
			"boss_slain:%s" % str(boss.entity_id),
			{"boss_id": str(boss.entity_id), "display_name": str(boss.display_name)})


## Direct template-driven enemy spawn (admin /spawn, future event
## systems). Unlike spawn_enemy() this has no spawn point of its own --
## no point bookkeeping, no 30m player proximity guard -- the caller
## supplies template, position, and zone. Same full Enemy pipeline as
## the horde/point paths: template stats, optional species, AI from
## EnemyData ranges, EntityService + TargetingManager registration,
## zone entry.
##
## Metadata mirrors the template's enemy_type (NORMAL -> enemy,
## ELITE/BOSS/WORLD_BOSS factories) so achievements and HUD read the
## spawn class rather than just stats; callers may override with
## metadata_type for scripted spawns. alert=false suppresses the spawn
## notification (quiet admin testing / events that announce themselves).
## Returns the spawned Enemy (null on unknown template or service miss).
func spawn_enemy_direct(
	template_id: String,
	position: Vector3,
	zone_id: String,
	level_override: int = 0,
	metadata_type: int = -1,
	alert: bool = true
) -> Variant:
	var data_service = DataService
	if data_service == null:
		return null
	var template = data_service.get_enemy(template_id)
	if template == null:
		GameLog.warn("SpawnService: Direct spawn template %s not found" % template_id)
		return null

	var enemy = EnemyScript.new()
	enemy.enemy_data = template
	enemy.display_name = template.display_name
	enemy.entity_type = Entity.EntityType.ENEMY
	enemy.relation = Entity.Relation.HOSTILE
	enemy.faction_id = template.faction
	enemy.level = template.level if level_override <= 0 else level_override

	# Species when the template declares one (species modifiers shift
	# stats, so apply before copying them).
	if "species_id" in template and str(template.species_id) != "":
		var species = data_service.get_species(str(template.species_id))
		if species != null:
			enemy.apply_species(species)

	# Stats from the template; health scales with the resolved level
	# (level_override raised spawns are tougher, matching horde scaling).
	enemy.stats["strength"] = template.strength
	enemy.stats["agility"] = template.agility
	enemy.stats["intelligence"] = template.intelligence
	enemy.stats["vitality"] = template.vitality
	enemy.max_health = template.get_scaled_stat(template.health, enemy.level)
	enemy.current_health = enemy.max_health

	# Mark the pre-applied data so Enemy._ready's _load_from_data() does
	# not clobber the level override (and scaled stats) back to template
	# defaults when add_child runs.
	enemy.spawn_data_applied = true

	# Parent into the tree BEFORE registration: register_entity derives
	# the NSC-9 spatial address from global_position (tree-required).
	var tree := get_tree()
	if tree != null and not enemy.is_inside_tree():
		var parent_node: Node = tree.current_scene if tree.current_scene else tree.root
		parent_node.add_child(enemy)
	enemy.global_position = position

	# AI configured from the template's ranges (same surface as
	# spawn_enemy): without it the enemy stands inert.
	var ai = EnemyAIScript.new()
	ai.aggro_range = template.aggro_range
	ai.chase_range = template.chase_range
	enemy.attach_ai(ai)

	var mtype: int = metadata_type
	if mtype < 0:
		match int(template.enemy_type):
			EnemyData.EnemyType.ELITE:
				mtype = SpawnMetadata.SpawnType.ELITE
			EnemyData.EnemyType.BOSS:
				mtype = SpawnMetadata.SpawnType.BOSS
			EnemyData.EnemyType.WORLD_BOSS:
				mtype = SpawnMetadata.SpawnType.WORLD_BOSS
			_:
				mtype = SpawnMetadata.SpawnType.NORMAL
	var metadata := SpawnMetadata.new(mtype, enemy.display_name, zone_id, position)
	metadata.level = enemy.level
	metadata.faction = enemy.faction
	metadata.notification_enabled = alert

	var entity_service = EntityService
	if entity_service:
		entity_service.register_entity(enemy, metadata)

	var targeting_manager = TargetingManager
	if targeting_manager:
		targeting_manager.register_targetable(
			enemy.entity_id,
			"enemy",
			enemy,
			enemy.display_name,
			position,
			enemy.entity_type
		)

	var zone_manager = ZoneManager
	if zone_manager:
		var zone = zone_manager.get_zone(zone_id)
		if zone:
			zone_manager.entity_enter_zone(enemy, zone)

	GameLog.info("SpawnService: Direct-spawned %s (lvl %d) in %s" % [
		enemy.display_name, enemy.level, zone_id])
	return enemy

## Despawn a world boss
func despawn_boss(entity) -> void:
	if entity == null:
		return

	# Remove from world bosses
	_world_bosses.erase(entity.entity_id)

	# Remove from TargetingManager
	var targeting_manager = TargetingManager
	if targeting_manager:
		targeting_manager.unregister_targetable(entity.entity_id)

	# Remove from services
	var entity_service = EntityService
	if entity_service:
		entity_service.unregister_entity(entity)

	# Remove from world
	if is_instance_valid(entity):
		entity.queue_free()

	GameLog.info("SpawnService: Despawned boss %s" % entity.display_name)

## Spawn boss with server-wide alert (convenience method)
func spawn_world_boss(boss_template_id: String, position: Vector3, zone_id: String, boss_name: String = "") -> Variant:
	return spawn_boss(boss_template_id, position, zone_id, boss_name, [NotificationService.AlertScope.server_wide()])

## Spawn boss with zone + neighbors alert (convenience method)
func spawn_zone_boss(boss_template_id: String, position: Vector3, zone_id: String, boss_name: String = "", include_neighbors: bool = true) -> Variant:
	return spawn_boss(boss_template_id, position, zone_id, boss_name, [NotificationService.AlertScope.zone(zone_id, include_neighbors)])

## Spawn mini-boss with nearby alert only (convenience method)
func spawn_mini_boss(boss_template_id: String, position: Vector3, zone_id: String, boss_name: String = "", radius: float = 50.0) -> Variant:
	return spawn_boss(boss_template_id, position, zone_id, boss_name, [NotificationService.AlertScope.nearby(position, radius)])

## Despawn enemy
func despawn_enemy(entity) -> void:
	if entity == null:
		return

	# Find spawn point
	var spawn_point_id = _find_entity_spawn_point(entity.entity_id)
	var metadata: SpawnMetadata = EntityService.get_entity_metadata(entity.entity_id) if EntityService else null

	if spawn_point_id != "":
		var spawn_point = _get_spawn_point(spawn_point_id)
		if spawn_point:
			spawn_point.current_count -= 1
			_spawned_entities[spawn_point_id].erase(entity.entity_id)

			# Start respawn timer
			_start_respawn_timer(spawn_point_id, spawn_point.respawn_time)

	# Emit service-specific despawn signal with metadata
	enemy_despawned.emit(entity, spawn_point_id, metadata)

	# Remove from TargetingManager
	var targeting_manager = TargetingManager
	if targeting_manager:
		targeting_manager.unregister_targetable(entity.entity_id)

	# Remove from services (emits EventHub.entity_despawned with metadata)
	var entity_service = EntityService
	if entity_service:
		entity_service.unregister_entity(entity, "spawn_despawn")

	# Remove from world
	if is_instance_valid(entity):
		entity.queue_free()

## Get spawn count for a zone
func get_zone_spawn_count(zone_id: String) -> int:
	var count = 0
	for spawn_point in _spawn_points.get(zone_id, []):
		count += spawn_point.current_count
	return count

## Get spawn cap for a zone
func get_zone_spawn_cap(zone_id: String) -> int:
	var cap = 0
	for spawn_point in _spawn_points.get(zone_id, []):
		cap += spawn_point.max_enemies
	return cap

## Check if zone is at spawn cap
func is_zone_at_cap(zone_id: String) -> bool:
	return get_zone_spawn_count(zone_id) >= get_zone_spawn_cap(zone_id)

## Set spawn multiplier (for events)
func set_spawn_multiplier(zone_id: String, multiplier: float) -> void:
	for spawn_point in _spawn_points.get(zone_id, []):
		spawn_point.spawn_multiplier = multiplier
	GameLog.info("SpawnService: Set spawn multiplier to %.1f for zone %s" % [multiplier, zone_id])

## Clear all spawns in a zone
func clear_zone_spawns(zone_id: String) -> void:
	for spawn_point in _spawn_points.get(zone_id, []):
		_clear_spawn_point(spawn_point)
	GameLog.info("SpawnService: Cleared all spawns in zone %s" % zone_id)

## Enable/disable spawn point
func set_spawn_point_active(spawn_point_id: String, active: bool) -> void:
	var spawn_point = _get_spawn_point(spawn_point_id)
	if spawn_point:
		spawn_point.is_active = active
		if not active:
			_spawn_timers.erase(spawn_point_id)

## Force spawn all spawn points in a zone
func force_spawn_zone(zone_id: String) -> int:
	var spawned = 0
	for spawn_point in _spawn_points.get(zone_id, []):
		while spawn_point.should_spawn():
			var enemy = spawn_enemy(spawn_point.id)
			if enemy == null:
				break
			spawned += 1
	return spawned

## Process spawn timers (call from _process)
func process_spawns(delta: float) -> void:
	var timers_to_remove: Array[String] = []

	for spawn_point_id in _spawn_timers:
		_spawn_timers[spawn_point_id] -= delta
		if _spawn_timers[spawn_point_id] <= 0:
			spawn_enemy(spawn_point_id)
			timers_to_remove.append(spawn_point_id)

	for spawn_point_id in timers_to_remove:
		_spawn_timers.erase(spawn_point_id)

# --- Private methods ---

func _get_spawn_point(spawn_point_id: String) -> SpawnPoint:
	for spawn_point_array in _spawn_points.values():
		for sp in spawn_point_array:
			if sp.id == spawn_point_id:
				return sp
	return null

func _find_entity_spawn_point(entity_id: String) -> String:
	for spawn_point_id in _spawned_entities:
		if _spawned_entities[spawn_point_id].has(entity_id):
			return spawn_point_id
	return ""

func _is_spawn_point_safe(spawn_point: SpawnPoint) -> bool:
	var zone_manager = ZoneManager
	if zone_manager == null:
		return true	 # No zone manager, assume safe

	var players = zone_manager.get_players_in_zone(spawn_point.zone_id)
	var safe_distance := spawn_point.spawn_radius + 30.0	# 30 units buffer

	for player in players:
		if spawn_point.position.distance_to(player.global_position) < safe_distance:
			return false
	return true

func _start_respawn_timer(spawn_point_id: String, respawn_time: float) -> void:
	_spawn_timers[spawn_point_id] = respawn_time

func _clear_spawn_point(spawn_point: SpawnPoint) -> void:
	var entities = _spawned_entities.get(spawn_point.id, [])
	for entity_id in entities:
		var entity_service = EntityService
		if entity_service:
			var entity = entity_service.get_entity(entity_id)
			if entity and is_instance_valid(entity):
				entity.queue_free()

	_spawned_entities[spawn_point.id].clear()
	spawn_point.current_count = 0
	_spawn_timers.erase(spawn_point.id)
	spawn_point_cleared.emit(spawn_point.id)

func _create_enemy(spawn_point: SpawnPoint) -> Variant:
	if spawn_point.enemy_data == null:
		GameLog.warn("SpawnService: No enemy data for template %s" % spawn_point.enemy_template_id)
		return null

	# Full Enemy class (has HealthComponent + AggroComponent + damage
	# events), not the bare Entity this used to create.
	var enemy = EnemyScript.new()
	enemy.enemy_data = spawn_point.enemy_data
	enemy.display_name = spawn_point.enemy_data.display_name
	enemy.entity_type = Entity.EntityType.ENEMY
	enemy.relation = Entity.Relation.HOSTILE
	enemy.faction_id = spawn_point.enemy_data.faction
	enemy.level = spawn_point.enemy_data.level

	# Apply species if set
	var effective_species_id: String = spawn_point.species_id if spawn_point.species_id != "" else spawn_point.enemy_data.species_id
	if effective_species_id != "":
		var data_service = DataService
		if data_service:
			var species = data_service.get_species(effective_species_id)
			if species:
				enemy.apply_species(species)

	# Apply stats from template
	enemy.stats["strength"] = spawn_point.enemy_data.strength
	enemy.stats["agility"] = spawn_point.enemy_data.agility
	enemy.stats["intelligence"] = spawn_point.enemy_data.intelligence
	enemy.stats["vitality"] = spawn_point.enemy_data.vitality

	enemy.max_health = spawn_point.enemy_data.health
	enemy.current_health = spawn_point.enemy_data.health

	return enemy

## Spawn a unified NPCEntity from NPCData resource.
## Loads the NPC's offerings via includes[] and registers with all services.
## If scene_path exists in npc_data, instances the scene; otherwise creates NPCEntity.new().
func spawn_npc_entity(
		zone_id: String,
		position: Vector3,
		npc_data: NPCData
) -> NPCEntity:
	if npc_data == null:
		push_warning("SpawnService: Cannot spawn NPC -- npc_data is null")
		return null

	var entity: NPCEntity

	# Instance the scene if scene_path is set
	if npc_data.get("scene_path") and not npc_data.scene_path.is_empty():
		var scene_path := npc_data.scene_path as String
		var scene_res := load(scene_path)
		if scene_res and scene_res is PackedScene:
			var packed: PackedScene = scene_res as PackedScene
			var instance := packed.instantiate()
			if instance is NPCEntity:
				entity = instance as NPCEntity
				GameLog.info("SpawnService: Loaded scene '%s' for NPC '%s'" % [scene_path, npc_data.id])
			else:
				push_warning("SpawnService: Scene '%s' does not extend NPCEntity" % scene_path)
				entity = NPCEntity.new()
		else:
			push_warning("SpawnService: Failed to load scene: %s" % scene_path)
			entity = NPCEntity.new()
	else:
		entity = NPCEntity.new()

	# Configure entity
	entity.npc_data = npc_data
	entity.entity_id = npc_data.id
	entity.display_name = npc_data.display_name
	entity.level = npc_data.level
	entity.entity_type = Entity.EntityType.NPC
	entity.relation = Entity.Relation.FRIENDLY

	# Update NameLabel if present (for non-scene NPCs)
	var name_label := entity.get_node_or_null("NameLabel") as Label3D
	if name_label:
		name_label.text = npc_data.display_name

	# Parent into the tree BEFORE positioning/registration: global_position
	# reads and writes throw outside the tree ("!is_inside_tree()" engine
	# errors + identity transforms reaching TargetingManager), and
	# register_entity derives the NSC-9 spatial address + default spawn
	# metadata from global_position. Same ordering as the /spawn enemy path.
	# Deferred when called during scene setup (world_playable._ready spawns
	# offering NPCs while the scene is still adding children -- a sync add
	# there is rejected and the NPC landed half-configured).
	var tree := get_tree()
	if tree != null and entity is Node3D and not entity.is_inside_tree():
		var parent_node: Node = tree.current_scene if tree.current_scene else tree.root
		if parent_node.is_inside_tree() and not parent_node.is_node_ready():
			parent_node.add_child.call_deferred(entity)
		else:
			parent_node.add_child(entity)
	if entity is Node3D:
		entity.global_position = position

	# Register with EntityService
	if EntityService:
		EntityService.register_entity(entity)

	# Register with TargetingManager
	if TargetingManager:
		TargetingManager.register_targetable(
			entity.entity_id,
			"npc",
			entity,
			entity.display_name,
			position,
			entity.entity_type
		)

	# Add to zone
	if ZoneManager:
		var zone := ZoneManager.get_zone(zone_id)
		if zone:
			ZoneManager.entity_enter_zone(entity, zone)

	GameLog.info("SpawnService: Spawned NPCEntity '%s' in zone %s" % [entity.display_name, zone_id])
	return entity

## Spawn all offering NPCs for every zone.
## Placement is data-driven: NPCData.zone_id names the ZoneManager zone
## (spawn at the zone's bind point + spawn_offset). NPCs with an empty
## zone_id are authored but not yet placed -- skipped with a log, never
## scattered. A zone_id that matches no registered zone is a broken
## data reference: warned and skipped. Previously this inferred the
## zone from the NPC id prefix, which invented phantom zones
## (zone_village / zone_capital were never authored) and fell back to
## a random scatter at the world origin when they did not exist.
func spawn_all_offering_npcs() -> void:
	if not DataService:
		GameLog.warn("SpawnService: DataService not available, skipping NPC spawns")
		return

	## Single spawn path for data-placed NPCs. Idempotent: both boot
	## routes call it (GameManager for headless/server boots,
	## world_playable._ready for scene runs), so track what we spawned
	## and skip ids that still have a live entity. Entries whose entity
	## was freed without despawn (scene change on the login path frees
	## NPCs parented to the old scene) are pruned first, so the next
	## call re-spawns them -- never two live entities for one id.
	for npc_id in _spawned_offering_npcs.keys():
		var ent = _spawned_offering_npcs[npc_id]
		if ent == null or not is_instance_valid(ent):
			_spawned_offering_npcs.erase(npc_id)

	var all_npcs: Array = DataService.get_all_npcs()
	var spawned := 0
	# Direct scene runs reach this before world_playable calls
	# ZoneManager.load_zones (world_playable defers it via
	# _enter_scene_zone). Load once on demand so zone lookups resolve.
	if ZoneManager and ZoneManager._zones.is_empty():
		ZoneManager.load_zones()
	for npc_data in all_npcs:
		if npc_data == null:
			continue
		if _spawned_offering_npcs.has(npc_data.id):
			continue
		if npc_data.includes.is_empty():
			continue
		var zone_id := str(npc_data.get("zone_id"))
		if zone_id.is_empty():
			GameLog.info("SpawnService: NPC '%s' has offerings but no zone_id -- not placed yet, skipping" % npc_data.id)
			continue
		var zone_data: ZoneData = null
		if ZoneManager:
			zone_data = ZoneManager.get_zone(zone_id)
		if zone_data == null:
			GameLog.warn("SpawnService: NPC '%s' references unknown zone '%s' -- skipping (broken data reference)" % [npc_data.id, zone_id])
			continue
		var spawn_pos: Vector3 = zone_data.bind_point + npc_data.spawn_offset
		var entity := spawn_npc_entity(zone_id, spawn_pos, npc_data)
		if entity != null:
			_spawned_offering_npcs[npc_data.id] = entity
			spawned += 1

	GameLog.info("SpawnService: Spawned %d offering NPCs" % spawned)



## Despawn an NPC
func despawn_npc(entity) -> void:
	if entity == null:
		return

	# Remove from TargetingManager
	var targeting_manager = TargetingManager
	if targeting_manager:
		targeting_manager.unregister_targetable(entity.entity_id)

	# Remove from services
	var entity_service = EntityService
	if entity_service:
		entity_service.unregister_entity(entity)

	# Remove from world
	if is_instance_valid(entity):
		entity.queue_free()

	GameLog.info("SpawnService: Despawned NPC %s" % entity.display_name)
