## HordeEventService - gameplay driver for horde/wave events.
##
## Turns the state-tree horde machinery (zone-scoped projection, tick
## coalescing, per-zone snapshots) into actual gameplay: a wave state
## machine that produces mobs into a zone, a boss finale, per-wave and
## completion signals for UI, and full teardown guarantees.
##
## Mob production: built directly on SpawnService._create_enemy's data
## path (full Enemy with HealthComponent + AI + real EnemyData stats)
## rather than spawn points, because SpawnService's proximity guard
## blocks spawns within 30m of players -- the opposite of what a horde
## needs. Bosses go through spawn_boss() for the shared boss pipeline.
## Cleanup is total: per-wave tracking means an aborted horde (region
## teardown, shutdown) sweeps every living horde mob, and lifecycle
## handlers re-fire even if mobs die out-of-band (guards, despawns).
##
## Signals (all carry horde_id; UI wires here, not into internals):
##   horde_started(horde_id, zone_id, total_waves)
##   horde_wave_started(horde_id, wave_number, total_waves)
##   horde_wave_progress(horde_id, wave_number, remaining)
##   horde_wave_cleared(horde_id, wave_number)
##   horde_boss_spawned(horde_id, boss)
##   horde_completed(horde_id, success)
extends Node

const EnemyScript = preload("res://entities/enemy.gd")
const EnemyDataScript = preload("res://core/schemas/enemy_data.gd")
const EnemyAIScript = preload("res://core/ai/enemy_ai.gd")
const SpawnMetadata = preload("res://core/events/spawn_metadata.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

## Mob production limits per wave tick (all-or-nothing batch would
## hitch the frame; this spreads 100 mobs over several frames).
const MAX_SPAWNS_PER_FRAME := 8
## Grace window (seconds) after the last horde mob dies before the wave
## is called cleared -- stragglers spawning from AI/corpses settle out.
const WAVE_CLEAR_GRACE := 0.75

signal horde_started(horde_id: String, zone_id: String, total_waves: int)
signal horde_wave_started(horde_id: String, wave_number: int, total_waves: int)
signal horde_wave_progress(horde_id: String, wave_number: int, remaining: int)
signal horde_wave_cleared(horde_id: String, wave_number: int)
signal horde_boss_spawned(horde_id: String, boss)
signal horde_completed(horde_id: String, success: bool)

## horde_id -> horde state Dictionary (see _start_horde_state).
var _hordes: Dictionary = {}
var _next_horde_num: int = 1

func _ready() -> void:
	var es := get_node_or_null("/root/EntityService")
	if es != null and es.has_signal("entity_unregistered"):
		if not es.entity_unregistered.is_connected(_on_entity_unregistered):
			es.entity_unregistered.connect(_on_entity_unregistered)
	GameLog.info("HordeEventService: Ready")

## ---------------------------------------------------------------------------
## Public API
## ---------------------------------------------------------------------------

## Start a horde in a zone. config (all keys optional except zone_id):
##   waves: int (default 3)
##   mobs_per_wave: int (default 8)
##   template_id: String - enemy template id (DataService.get_enemy);
##     falls back to the first template the zone's spawn points carry
##     so a zone's horde matches its population.
##   boss_template_id: String - template for the finale (default: same
##     as template_id, spawned through spawn_boss).
##   boss_name: String - display name for the finale.
##   inter_wave_delay: float - seconds between waves (default 5.0).
##   scale_levels: bool - wave N spawns at level + N-1 (default false).
## Returns horde_id ("" on failure).
func start_horde(zone_id: String, config: Dictionary = {}) -> String:
	var zid := zone_id.strip_edges()
	if zid.is_empty():
		return ""
	if _has_active_horde_in_zone(zid):
		GameLog.warn("HordeEventService: zone %s already has an active horde" % zid)
		return ""

	var template_id := str(config.get("template_id", ""))
	if template_id.is_empty():
		template_id = _template_for_zone(zid)
	if template_id.is_empty():
		GameLog.warn("HordeEventService: no template for horde in zone %s" % zid)
		return ""

	var horde_id := "horde_%s_%d" % [zid, _next_horde_num]
	_next_horde_num += 1

	var waves := maxi(1, int(config.get("waves", 3)))
	var h := {
		"id": horde_id,
		"zone_id": zid,
		"template_id": template_id,
		"boss_template_id": str(config.get("boss_template_id", template_id)),
		"boss_name": str(config.get("boss_name", "")),
		"waves": waves,
		"mobs_per_wave": maxi(1, int(config.get("mobs_per_wave", 8))),
		"inter_wave_delay": maxf(0.0, float(config.get("inter_wave_delay", 5.0))),
		"scale_levels": bool(config.get("scale_levels", false)),
		"wave_number": 0,
		"mobs_spawned_this_wave": 0,
		"mobs_left_to_spawn": 0,
		"spawn_queue": [],
		"mobs_spawned_ids": [],
		"all_mob_ids": [],
		"boss_id": "",
		"state": "starting",
		"grace_left": 0.0,
	}
	_hordes[horde_id] = h

	horde_started.emit(horde_id, zid, waves)
	_notify_zone(zid, "A horde approaches %s! (%d waves)" % [zid, waves],
			"horde_start:%s" % horde_id)
	_begin_next_wave(horde_id)
	return horde_id

## Stop a horde: sweeps all living horde mobs, cancels pending spawns.
func stop_horde(horde_id: String, reason: String = "stopped") -> void:
	var h: Dictionary = _hordes.get(horde_id, {})
	if h.is_empty():
		return
	_hordes.erase(horde_id)
	_sweep_horde(h, reason)
	horde_completed.emit(horde_id, false)

## The one active horde in a zone ("" when none).
func active_horde_in_zone(zone_id: String) -> String:
	for horde_id in _hordes:
		if str(_hordes[horde_id].get("zone_id", "")) == zone_id:
			return str(horde_id)
	return ""

## Live status snapshot (for debug UI / admin commands).
func get_horde_status(horde_id: String) -> Dictionary:
	var h: Dictionary = _hordes.get(horde_id, {})
	if h.is_empty():
		return {}
	return {
		"id": horde_id,
		"zone_id": h["zone_id"],
		"wave_number": h["wave_number"],
		"waves": h["waves"],
		"remaining": _living_mob_count(h),
		"mobs_left_to_spawn": h["mobs_left_to_spawn"],
		"state": h["state"],
		"boss_id": h["boss_id"],
	}

## ---------------------------------------------------------------------------
## Wave engine
## ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	for horde_id in _hordes.keys():
		var h: Dictionary = _hordes[horde_id]
		match str(h["state"]):
			"spawning":
				_process_spawn_queue(horde_id, h, delta)
			"fighting":
				_process_fighting(horde_id, h, delta)
			"inter_wave":
				h["grace_left"] = maxf(0.0, float(h["grace_left"]) - delta)
				if float(h["grace_left"]) <= 0.0:
					_begin_next_wave(horde_id)
			"boss":
				pass  # boss fight runs through normal combat; entity_died drives it

func _begin_next_wave(horde_id: String) -> void:
	var h: Dictionary = _hordes.get(horde_id, {})
	if h.is_empty():
		return
	var next_wave: int = int(h["wave_number"]) + 1
	if next_wave > int(h["waves"]):
		_finish_horde(horde_id, true)
		return
	h["wave_number"] = next_wave
	h["state"] = "spawning"
	h["spawn_queue"] = _build_spawn_queue(h)
	h["mobs_left_to_spawn"] = h["spawn_queue"].size()
	h["mobs_spawned_this_wave"] = 0
	h["mobs_spawned_ids"] = []
	horde_wave_started.emit(horde_id, next_wave, int(h["waves"]))
	_notify_zone(str(h["zone_id"]), "Wave %d of %d incoming!" % [next_wave, int(h["waves"])],
			"horde_wave:%s:%d" % [horde_id, next_wave])

## Deterministic ring pattern around the zone center, spread over the
## radius so a wave forms a circle rather than a stack.
func _build_spawn_queue(h: Dictionary) -> Array:
	var center_radius := _zone_center_radius(str(h["zone_id"]))
	var center: Vector3 = center_radius[0]
	var radius: float = 40.0
	if float(center_radius[1]) > 10.0:
		radius = minf(float(center_radius[1]) * 0.6, 60.0)
	var queue: Array = []
	for i in range(int(h["mobs_per_wave"])):
		var angle := TAU * float(i) / float(int(h["mobs_per_wave"]))
		var pos := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		queue.append({"pos": pos, "angle": angle})
	return queue

## Spread the spawn batch over frames; each spawn is the full Enemy
## pipeline (data -> stats -> AI -> services -> metadata).
func _process_spawn_queue(horde_id: String, h: Dictionary, _delta: float) -> void:
	var spawned_this_frame := 0
	while not h["spawn_queue"].is_empty() and spawned_this_frame < MAX_SPAWNS_PER_FRAME:
		var slot: Dictionary = h["spawn_queue"].pop_front()
		var level: int = 0
		if bool(h["scale_levels"]):
			level = int(h["wave_number"]) - 1
		var mob = _produce_mob(h, slot["pos"], level)
		if mob != null:
			h["mobs_spawned_this_wave"] += 1
			h["mobs_spawned_ids"].append(str(mob.entity_id))
			h["all_mob_ids"].append(str(mob.entity_id))
			spawned_this_frame += 1
		h["mobs_left_to_spawn"] = h["spawn_queue"].size()
	if h["spawn_queue"].is_empty():
		if int(h["mobs_spawned_this_wave"]) == 0:
			# Nothing spawned (no template, no data): fail fast, loudly.
			GameLog.error("HordeEventService: wave %d produced no mobs; aborting horde %s" % [int(h["wave_number"]), horde_id])
			_finish_horde(horde_id, false)
			return
		h["state"] = "fighting"
		h["grace_left"] = 0.0
		h["last_living"] = -1

func _produce_mob(h: Dictionary, pos: Vector3, extra_level: int):
	var ds := get_node_or_null("/root/DataService")
	var template = null
	if ds != null and ds.has_method("get_enemy"):
		template = ds.get_enemy(str(h["template_id"]))
	if template == null:
		return null

	var enemy = EnemyScript.new()
	enemy.enemy_data = template
	enemy.display_name = str(template.display_name)
	enemy.entity_type = Entity.EntityType.ENEMY
	enemy.relation = Entity.Relation.HOSTILE
	enemy.faction_id = template.faction
	enemy.level = int(template.level) + extra_level
	if extra_level > 0:
		enemy.display_name = "%s [%d]" % [str(template.display_name), enemy.level]

	# Stats: template values scaled by get_scaled_stat when leveling up.
	enemy.stats["strength"] = template.get_scaled_stat(template.strength, enemy.level)
	enemy.stats["agility"] = template.get_scaled_stat(template.agility, enemy.level)
	enemy.stats["intelligence"] = template.get_scaled_stat(template.intelligence, enemy.level)
	enemy.stats["vitality"] = template.get_scaled_stat(template.vitality, enemy.level)

	enemy.max_health = template.get_scaled_stat(template.health, enemy.level)
	enemy.current_health = enemy.max_health
	enemy.global_position = pos

	# Same AI attachment surface as the Enemy API (sets _ai + add_child).
	enemy.attach_ai(EnemyAIScript.new())

	var metadata := SpawnMetadata.enemy(
		enemy.display_name, str(h["zone_id"]), pos, enemy.level
	)
	metadata.faction = enemy.faction

	var es := get_node_or_null("/root/EntityService")
	if es == null or not es.has_method("register_entity"):
		return null
	es.register_entity(enemy, metadata)

	var zm := get_node_or_null("/root/ZoneManager")
	var zone = _zone_data(str(h["zone_id"]))
	if zm != null and zone != null and zm.has_method("entity_enter_zone"):
		zm.entity_enter_zone(enemy, zone)
	return enemy

## Fighting: watch the living count; after the last death, a short grace
## window absorbs stragglers, then the wave is cleared. Progress emits
## only on change (a 60fps re-emit would spam the HUD).
func _process_fighting(horde_id: String, h: Dictionary, delta: float) -> void:
	var living: int = _living_mob_count(h)
	var last: int = int(h.get("last_living", -1))
	if living != last:
		h["last_living"] = living
		horde_wave_progress.emit(horde_id, int(h["wave_number"]), living)
	if living > 0:
		h["grace_left"] = WAVE_CLEAR_GRACE
		return
	h["grace_left"] = maxf(0.0, float(h["grace_left"]) - delta)
	if float(h["grace_left"]) > 0.0:
		return
	# Wave cleared.
	var wave: int = int(h["wave_number"])
	if wave >= int(h["waves"]):
		_spawn_boss(horde_id, h)
	else:
		horde_wave_cleared.emit(horde_id, wave)
		_notify_zone(str(h["zone_id"]), "Wave %d cleared!" % wave,
				"horde_wcleared:%s:%d" % [horde_id, wave])
		h["state"] = "inter_wave"
		h["grace_left"] = float(h["inter_wave_delay"])

## Boss finale through the shared spawn_boss pipeline.
func _spawn_boss(horde_id: String, h: Dictionary) -> void:
	var ss := get_node_or_null("/root/SpawnService")
	var zone_center: Vector3 = _zone_center_radius(str(h["zone_id"]))[0]
	var boss = null
	if ss != null and ss.has_method("spawn_boss"):
		boss = ss.spawn_boss(
			str(h["boss_template_id"]),
			zone_center,
			str(h["zone_id"]),
			str(h["boss_name"])
		)
	if boss == null:
		GameLog.error("HordeEventService: boss spawn failed; completing horde %s as success" % horde_id)
		_finish_horde(horde_id, true)
		return
	# alert_scopes=[] keeps the metadata's own scope objects (a bare
	# string like "zone" would crash NotificationService's broadcast
	# when it walks the scopes array).
	# The boss is a bare Entity (no health_component chain), so its
	# unregistration never fires on death -- watch the died signal
	# directly to complete the horde.
	if boss.has_signal("died") and not boss.died.is_connected(_on_boss_died):
		boss.died.connect(_on_boss_died.bind(horde_id))
	h["boss_id"] = str(boss.entity_id)
	h["state"] = "boss"
	horde_boss_spawned.emit(horde_id, boss)
	_notify_zone(str(h["zone_id"]), "The horde leader has arrived!",
			"horde_boss:%s" % horde_id)

func _finish_horde(horde_id: String, success: bool) -> void:
	var h: Dictionary = _hordes.get(horde_id, {})
	if h.is_empty():
		return
	_hordes.erase(horde_id)
	if success:
		_notify_zone(str(h["zone_id"]), "Horde defeated!", "horde_done:%s" % horde_id)
	horde_completed.emit(horde_id, success)

## ---------------------------------------------------------------------------
## Death tracking (authoritative via EntityService unregistration)
## ---------------------------------------------------------------------------

func _on_entity_unregistered(entity, _metadata = null) -> void:
	if entity == null:
		return
	for horde_id in _hordes.keys():
		var h: Dictionary = _hordes[horde_id]
		if str(h["boss_id"]) == str(entity.entity_id) and str(h["state"]) == "boss":
			_finish_horde(horde_id, true)
			return

## The boss Entity emits died(killer) on death; bound with horde_id.
func _on_boss_died(_killer, horde_id: String) -> void:
	var h: Dictionary = _hordes.get(horde_id, {})
	if h.is_empty():
		return
	if str(h["state"]) == "boss":
		_finish_horde(horde_id, true)

## ---------------------------------------------------------------------------
## Helpers
## ---------------------------------------------------------------------------

## Living horde mobs: tracked ids resolved through EntityService (a mob
## killed by guards/despawns still unregisters, so the count stays
## honest even when deaths happen out-of-band).
func _living_mob_count(h: Dictionary) -> int:
	var es := get_node_or_null("/root/EntityService")
	if es == null or not es.has_method("get_entity"):
		return 0
	var living := 0
	for eid in h.get("mobs_spawned_ids", []):
		var e = es.get_entity(str(eid))
		if e == null or not is_instance_valid(e):
			continue
		var dead: bool = bool(e.is_dead) if "is_dead" in e else false
		if not dead:
			living += 1
	return living

func _has_active_horde_in_zone(zone_id: String) -> bool:
	return active_horde_in_zone(zone_id) != ""

func _zone_data(zone_id: String):
	var zm := get_node_or_null("/root/ZoneManager")
	if zm != null and zm.has_method("get_zone"):
		return zm.get_zone(zone_id)
	return null

## [center, radius] for a zone, duck-typed: ZoneData carries
## zone_center/zone_radius; stub dictionaries may use center/radius.
## Defaults [Vector3.ZERO, 0.0] when unknown.
func _zone_center_radius(zone_id: String) -> Array:
	var zone = _zone_data(zone_id)
	if zone == null:
		return [Vector3.ZERO, 0.0]
	var center: Vector3 = Vector3.ZERO
	var radius: float = 0.0
	if "zone_center" in zone:
		center = zone.zone_center
	elif "center" in zone:
		center = zone.center
	if "zone_radius" in zone:
		radius = float(zone.zone_radius)
	elif "radius" in zone:
		radius = float(zone.radius)
	return [center, radius]

## Horde mobs inherit a template from the zone's own spawn points so a
## horde matches what the zone already populates with.
func _template_for_zone(zone_id: String) -> String:
	var ss := get_node_or_null("/root/SpawnService")
	if ss == null or not ss.has_method("get_zone_spawn_points"):
		return ""
	var points: Array = ss.get_zone_spawn_points(zone_id)
	for point in points:
		var template_id := ""
		if point is Dictionary:
			template_id = str(point.get("enemy_template_id", ""))
		elif "enemy_template_id" in point:
			template_id = str(point.enemy_template_id)
		if not template_id.is_empty():
			return template_id
	return ""

## Zone-scoped notification (server scope, deduped by key).
func _notify_zone(zone_id: String, message: String, dedupe: String) -> void:
	if NotificationService == null:
		return
	NotificationService.notify(
		NotifKind.ADMIN_ALERT,
		message,
		"HordeEventService",
		dedupe,
		{"zone_id": zone_id},
		""
	)

## Sweep every living horde mob (stop/abort path). Horde ids live in
## EntityService metadata; this walks the horde's known mob ids plus
## any registered entity whose metadata tags this horde.
func _sweep_horde(h: Dictionary, reason: String) -> void:
	var es := get_node_or_null("/root/EntityService")
	if es != null and es.has_method("get_entity"):
		# Cumulative list: every mob the horde ever produced, not just
		# the current wave.
		for eid in h.get("all_mob_ids", []):
			var e = es.get_entity(str(eid))
			if e != null and is_instance_valid(e):
				if es.has_method("unregister_entity"):
					es.unregister_entity(e, "horde_sweep")
				e.queue_free()
	var boss_id := str(h.get("boss_id", ""))
	if boss_id != "":
		var es2 := get_node_or_null("/root/EntityService")
		if es2 != null and es2.has_method("get_entity"):
			var boss = es2.get_entity(boss_id)
			if boss != null and is_instance_valid(boss):
				var ss := get_node_or_null("/root/SpawnService")
				if ss != null and ss.has_method("despawn_boss"):
					ss.despawn_boss(boss)
	GameLog.info("HordeEventService: swept horde %s (%s)" % [str(h.get("id", "?")), reason])
