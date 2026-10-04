## WorldStateProjection - world entity + player live state -> state tree.
##
## The character half (durable progress) lives under /player/<id>/ and is
## written by PlayerProgress on its checkpoint cadence. This service owns
## the EPHEMERAL half under /world/zones/<zone>/..., scoped so a resync
## snapshot only covers the zone a client is in -- the horde story: 200
## mobs in zone A never bloat zone B's snapshot, and horde-scale PLAYER
## counts stay out of other zones' snapshots too.
##
## Node layout (all writes go through TickService's command buffer so
## they land atomically in Phase 2 and re-root once in Phase 3):
##   /world/zones/<zone>/entities/<id>/identity  type=other  {kind,display_name,level}
##   /world/zones/<zone>/entities/<id>/health    type=health {current,max}
##   /world/zones/<zone>/players/<id>/live       type=other  {hp_cur,hp_max,pos_x,pos_y,pos_z}
##
## Cadence design:
## - entity lifecycle (spawn/die/despawn/zone move) routes identity nodes
##   through the tick buffer immediately -- cheap, deterministic.
## - health churn and player positions are COALESCED to the tick boundary:
##   mark_dirty / player zone moves only queue into TickService on the
##   next tick_completed, so a 200-mob pack pull produces ONE re-root per
##   tick, not one per hit.
## - When TickService is absent (pure script mode), the tick pipeline is
##   unavailable, so flush() falls back to direct tree writes -- the
##   only mode where that is correct (no tick to atomically batch into).
extends Node

const StateTreeScript = preload("res://core/frame/kv/state_tree.gd")
const StateSchemaScript = preload("res://core/frame/schemas/state_schema.gd")
const ProgressBridgeScript = preload("res://core/frame/bridge/progress_bridge.gd")

## Coalesce window before a tick drains the queue (seconds). Marked
## dirty twice inside one window = one tree write.
const FLUSH_INTERVAL := 0.5

## Max player live-state nodes projected per zone snapshot (horde guard:
## a 1000-player zone still returns a bounded snapshot; clients AOI-cull).
const MAX_ZONE_SNAPSHOT_NODES := 2000

var _dirty: Dictionary = {}
var _flush_accum: float = 0.0
var _last_drain_ms: int = 0
## entity_id -> zone id its identity was projected under (health rides
## the same scope so wandering mobs never split across zones).
var _projected_zone: Dictionary = {}
## player_id -> zone id their live node is projected under (drift
## detection deletes the stale scope on zone crossing).
var _projected_player_zone: Dictionary = {}
var _state_tree_ref: StateTreeScript = null
var _schema: StateSchemaScript = null
## entity_id -> true, written by lifecycle handlers; drained at tick
## boundary into the buffer (identity nodes only change on lifecycle).
var _identity_pending: Dictionary = {}
## entity_id -> last projected health pair; skips writes when unchanged.
var _last_health: Dictionary = {}
## entity_id -> scope token override ("instance:<scope>"). Stamped by
## HordeEventService for instance-scoped hordes so a dungeon horde's
## mobs (and participating players' live nodes) project under
## /world/instances/<scope>/ instead of a /world/zones/ scope.
var _scope_overrides: Dictionary = {}
## player_id -> last projected live payload (String form for compare).
var _last_player_live: Dictionary = {}
## players currently projected (for snapshot + teardown).
var _projected_players: Dictionary = {}
## zone_id -> true, zones that currently hold projected entities.
var _active_zones: Dictionary = {}

func _ready() -> void:
	_schema = StateSchemaScript.new()
	var es := get_node_or_null("/root/EntityService")
	if es != null:
		if es.has_signal("entity_registered") and not es.entity_registered.is_connected(_on_entity_spawned):
			es.entity_registered.connect(_on_entity_spawned)
		if es.has_signal("entity_unregistered") and not es.entity_unregistered.is_connected(_on_entity_unregistered):
			es.entity_unregistered.connect(_on_entity_unregistered)
	if EventHub != null:
		if EventHub.has_signal("entity_spawned") and not EventHub.entity_spawned.is_connected(_on_entity_spawned):
			EventHub.entity_spawned.connect(_on_entity_spawned)
		if EventHub.has_signal("entity_died") and not EventHub.entity_died.is_connected(_on_entity_died):
			EventHub.entity_died.connect(_on_entity_died)
		if EventHub.has_signal("entity_despawned") and not EventHub.entity_despawned.is_connected(_on_entity_despawned_id):
			EventHub.entity_despawned.connect(_on_entity_despawned_id)
		if EventHub.has_signal("damage_dealt") and not EventHub.damage_dealt.is_connected(_on_damage_dealt):
			EventHub.damage_dealt.connect(_on_damage_dealt)
		# Mob zone crossings re-project the entity whole under the new scope.
		if EventHub.has_signal("entity_entered_zone") and not EventHub.entity_entered_zone.is_connected(_on_entity_entered_zone):
			EventHub.entity_entered_zone.connect(_on_entity_entered_zone)
	# Player zone membership: ZoneManager tracks every zone enter/exit
	# for players AND enemies (entity_entered_zone fires for both).
	var zm := get_node_or_null("/root/ZoneManager")
	if zm != null and zm.has_signal("player_entered_zone"):
		if not zm.player_entered_zone.is_connected(_on_player_entered_zone):
			zm.player_entered_zone.connect(_on_player_entered_zone)
		if zm.has_signal("player_exited_zone") and not zm.player_exited_zone.is_connected(_on_player_exited_zone):
			zm.player_exited_zone.connect(_on_player_exited_zone)
	# Drain coalesced writes at the tick boundary: all Phase-2 buffered
	# mutations land atomically, then Phase 3 re-roots once.
	var ts := get_node_or_null("/root/TickService")
	if ts != null and ts.has_signal("tick_completed"):
		if not ts.tick_completed.is_connected(_on_tick_completed):
			ts.tick_completed.connect(_on_tick_completed)
	GameLog.info("WorldStateProjection: Ready")

func _process(delta: float) -> void:
	_flush_accum += delta
	if _flush_accum < FLUSH_INTERVAL:
		return
	_flush_accum = 0.0
	# No tick loop (script mode): drain directly. With a tick loop the
	# tick drain owns the cadence (see _on_tick_completed).
	if not _tick_available():
		flush()

## ---------------------------------------------------------------------------
## Tick drain: buffered -> atomic
## ---------------------------------------------------------------------------

func _on_tick_completed(_tick_number: int, _timings: Dictionary) -> void:
	# Gate on the coalesce window, ALIGNED to tick boundaries: health
	# churn writes at most once per FLUSH_INTERVAL (a pack pull announces
	# one root hash per window, not one per hit or per tick), and every
	# batch lands in a tick's atomic Phase 2 + single Phase 3 re-root.
	var now: int = Time.get_ticks_msec()
	if now - _last_drain_ms < int(FLUSH_INTERVAL * 1000.0):
		return
	_last_drain_ms = now
	flush()

func _tick_available() -> bool:
	var ts := get_node_or_null("/root/TickService")
	return ts != null and ts.has_signal("tick_completed")

## ---------------------------------------------------------------------------
## Event handlers (all duck-typed; never crash on signal-shape drift)
## ---------------------------------------------------------------------------

func _on_entity_spawned(entity, _metadata = null) -> void:
	if not _is_projectable(entity):
		return
	_identity_pending[str(entity.entity_id)] = true
	mark_dirty(str(entity.entity_id))

func _on_entity_died(entity, _killer = null, _metadata = null) -> void:
	if entity == null:
		return
	remove_entity(str(entity.entity_id))

## EntityService.entity_unregistered carries (Node, SpawnMetadata).
func _on_entity_unregistered(entity, _metadata = null) -> void:
	if entity != null and is_instance_valid(entity):
		remove_entity(str(entity.entity_id))

## EventHub.entity_despawned carries an ID + reason string, not a Node
## (SpawnService.despawn_enemy path). Duck-type the shape: id-first
## removes the projection; node-shaped fallback for other emitters.
func _on_entity_despawned_id(first, _reason = null) -> void:
	if first is Node:
		if is_instance_valid(first):
			remove_entity(str(first.entity_id))
		return
	if first != null:
		remove_entity(str(first))

func _on_damage_dealt(_source, target, _amount, _type, _is_crit: bool = false) -> void:
	if target != null and is_instance_valid(target) and "entity_id" in target:
		mark_dirty(str(target.entity_id))
	if _is_player_target(target):
		mark_player_dirty(str(target.entity_id))

## Mob zone crossing: re-project the whole entity under the new scope
## (identity + health move together; nothing splits across zones).
func _on_entity_entered_zone(entity, _zone) -> void:
	if not _is_projectable(entity):
		return
	var eid := str(entity.entity_id)
	if _projected_zone.has(eid):
		# Already projected: tear down the old scope, re-queue identity.
		remove_entity(eid)
		_identity_pending[eid] = true
		mark_dirty(eid)

func _on_player_entered_zone(player, _zone) -> void:
	if player == null or not (player is Node) or not ("entity_id" in player):
		return
	# Register for polling; the next drain projects into the player's
	# CURRENT zone (drift detection handles any old-zone teardown).
	_projected_players[str(player.entity_id)] = true
	mark_player_dirty(str(player.entity_id))

func _on_player_exited_zone(player, zone) -> void:
	if player == null or not (player is Node) or not ("entity_id" in player):
		return
	var pid := str(player.entity_id)
	# Delete the node in the zone they LEFT; a matching enter signal (or
	# flush drift detection) re-projects them in the new zone.
	if zone != null and "id" in zone:
		if _tree().delete_state(_player_base(_safe_zone(str(zone.id)), pid) + "live"):
			_touch()
	_last_player_live.erase(pid)
	_projected_player_zone.erase(pid)
	mark_player_dirty(pid)

## ---------------------------------------------------------------------------
## Public API
## ---------------------------------------------------------------------------

## Register one entity's identity+health nodes under its CURRENT zone.
## Zone assignment is read live from ZoneManager at write time; entities
## outside any zone fall back to "unzoned" so nothing silently vanishes.
func write_entity(entity_id: String, data: Dictionary) -> bool:
	var eid := entity_id.strip_edges()
	if eid.is_empty() or data.is_empty():
		return false
	var zone := _entity_zone_id(eid)
	var tree := _tree()
	var base := _entity_base(zone, eid)

	var identity := {
		"kind": str(data.get("kind", "enemy")),
		"display_name": str(data.get("display_name", "")),
		"level": int(data.get("level", 1)),
	}
	tree.insert_state(base + "identity", eid, "other", identity)

	var health := {
		"current": int(data.get("current_health", 0)),
		"max": int(data.get("max_health", 0)),
	}
	tree.insert_state(base + "health", eid, "health", health)
	_active_zones[zone] = true
	_touch()
	return true

## Route one identity write through the tick buffer (lifecycle path).
func queue_entity_write(entity_id: String, data: Dictionary) -> void:
	var eid := entity_id.strip_edges()
	if eid.is_empty() or data.is_empty():
		return
	var zone := _entity_zone_id(eid)
	var base := _entity_base(zone, eid)
	_queue_insert(base + "identity", eid, "other", {
		"kind": str(data.get("kind", "enemy")),
		"display_name": str(data.get("display_name", "")),
		"level": int(data.get("level", 1)),
	})
	_active_zones[zone] = true

## Remove every node for one entity (death/despawn/zone move).
## Returns true when at least one node existed.
func remove_entity(entity_id: String) -> bool:
	var eid := entity_id.strip_edges()
	if eid.is_empty():
		return false
	var tree := _tree()
	var removed := false
	for zone in _active_zones.keys():
		var base := _entity_base(str(zone), eid)
		for leaf in ["identity", "health"]:
			if tree.delete_state(base + leaf):
				removed = true
	_dirty.erase(eid)
	_last_health.erase(eid)
	_projected_zone.erase(eid)
	if removed:
		_touch()
	return removed

## Mark an entity's health as changed; the flush window writes it once.
func mark_dirty(entity_id: String) -> void:
	if not entity_id.is_empty():
		_dirty[entity_id] = true

## Drain everything coalesced since the last tick: queued identity
## lifecycle writes, dirty mob health, and player live-state polling.
## Runs even when no mob is dirty (player positions poll here too).
## With a tick loop, writes are routed through the buffer so the next
## tick's Phase 2 applies them atomically; announces at most one touch.
## immediate=true bypasses the buffer (direct writes) for tests and CLI
## that need synchronous tree visibility.
func flush(immediate: bool = false) -> int:
	var written := 0
	written += _drain_identity(immediate)
	written += _flush_mob_health(immediate)
	written += _flush_players(immediate)
	if written > 0:
		_touch()
	return written

## Identity writes queued by lifecycle events drain here so a spawn
## followed by an instant hit lands in the same atomic batch.
func _drain_identity(immediate: bool) -> int:
	if _identity_pending.is_empty():
		return 0
	var es := _entity_service()
	var written := 0
	for pid in _identity_pending.keys():
		var pentity = null
		if es != null and es.has_method("get_entity"):
			pentity = es.get_entity(str(pid))
		if pentity == null or not is_instance_valid(pentity):
			continue
		var data: Dictionary = _extract(pentity)
		if data.is_empty():
			continue
		if immediate:
			var zid := _entity_zone_id(str(pid))
			_tree().insert_state(_entity_base(zid, str(pid)) + "identity", str(pid), "other", {
				"kind": str(data.get("kind", "enemy")),
				"display_name": str(data.get("display_name", "")),
				"level": int(data.get("level", 1)),
			})
			_active_zones[zid] = true
		else:
			queue_entity_write(str(pid), data)
		# Remember the scope identity was written under so health flushes
		# stay whole even while the mob wanders between zones.
		_projected_zone[str(pid)] = _entity_zone_id(str(pid))
		written += 1
	_identity_pending.clear()
	return written

## Coalesced mob health: one write per entity per window, skipped when
## the value signature is unchanged. Health rides the identity's zone
## scope so a crossing mob never splits across two zones.
func _flush_mob_health(immediate: bool) -> int:
	if _dirty.is_empty():
		return 0
	var ids: Array = _dirty.keys()
	_dirty.clear()
	var es := _entity_service()
	var written := 0
	for eid in ids:
		var entity = null
		if es != null and es.has_method("get_entity"):
			entity = es.get_entity(str(eid))
		if entity == null or not is_instance_valid(entity):
			continue
		var data: Dictionary = _extract(entity)
		if data.is_empty():
			continue
		var health := {
			"current": int(data.get("current_health", 0)),
			"max": int(data.get("max_health", 0)),
		}
		var sig := "%s/%s" % [health["current"], health["max"]]
		if _last_health.get(str(eid), "") == sig:
			continue
		_last_health[str(eid)] = sig
		var zone: String = _projected_zone.get(str(eid), _entity_zone_id(str(eid)))
		var base := _entity_base(zone, str(eid))
		if _tick_available() and not immediate:
			_queue_insert(base + "health", str(eid), "health", health)
		else:
			_tree().insert_state(base + "health", str(eid), "health", health)
		_active_zones[zone] = true
		written += 1
	return written

## Diagnostics: the tree this service writes into.
func state_tree() -> StateTreeScript:
	return _tree()

## Read back one entity's projected nodes ({} when absent) from its
## current zone scope.
func read_entity(entity_id: String) -> Dictionary:
	var eid := entity_id.strip_edges()
	var zone: String = _projected_zone.get(eid, _entity_zone_id(eid))
	var base := _entity_base(zone, eid)
	var out: Dictionary = {}
	for leaf in ["identity", "health"]:
		var value: Variant = _tree().get_state(base + leaf)
		if value is Dictionary and not value.is_empty():
			out[leaf] = value.get("payload", {})
	return out

## ---------------------------------------------------------------------------
## Player live-state half (horde players)
## ---------------------------------------------------------------------------

## Mark a player's live state for the next drain (damage taken, zone
## enter). Idempotent; players already projected just refresh.
func mark_player_dirty(player_id: String) -> void:
	var pid := player_id.strip_edges()
	if not pid.is_empty():
		_projected_players[pid] = true

## Public bootstrap: start projecting a player who may not have fired a
## zone-enter (boot restore, mid-session registration).
func register_player(player) -> void:
	if player == null or not (player is Node) or not ("entity_id" in player):
		return
	mark_player_dirty(str(player.entity_id))

## Extract the live payload from a player node (hp + grid position).
func _player_live_payload(player) -> Dictionary:
	if player == null or not (player is Node) or not is_instance_valid(player):
		return {}
	var payload := {}
	if "health_component" in player and player.health_component != null:
		var hc = player.health_component
		payload["hp_cur"] = int(hc.current_health)
		payload["hp_max"] = int(hc.max_health)
	# Out-of-tree players (scene teardown race) have no valid transform;
	# skip the position payload instead of throwing every tick.
	if "global_position" in player and (not (player is Node3D) or player.is_inside_tree()):
		var p: Vector3 = player.global_position
		payload["pos_x"] = ProgressBridgeScript.quantize_coordinate(p.x)
		payload["pos_y"] = ProgressBridgeScript.quantize_coordinate(p.y)
		payload["pos_z"] = ProgressBridgeScript.quantize_coordinate(p.z)
	return payload

## Poll every projected player's live state. Runs on every drain (the
## coalescing is the cost control: one batch per tick, value signatures
## suppress no-op writes). Detects zone drift here so a player crossing
## zones has the stale-zone node deleted in the same atomic batch.
func _flush_players(immediate: bool) -> int:
	if _projected_players.is_empty():
		return 0
	var es := _entity_service()
	if es == null or not es.has_method("get_entity"):
		return 0
	var written := 0
	for pid in _projected_players.keys():
		var player = es.get_entity(str(pid))
		if player == null or not is_instance_valid(player):
			# Player gone (disconnect/logout): tear down their live node.
			unproject_player(str(pid))
			continue
		# Out-of-tree players (scene teardown race) have no valid transform:
		# skip this drain; the next one after full unregistration cleans up.
		if player is Node3D and not player.is_inside_tree():
			continue
		var payload := _player_live_payload(player)
		if payload.is_empty():
			continue
		var sig := str(payload)
		var zone := _entity_zone_id(str(pid))
		var old_zone: String = _projected_player_zone.get(str(pid), "")
		var zone_moved: bool = old_zone != "" and old_zone != zone
		if _last_player_live.get(str(pid), "") == sig and not zone_moved:
			continue
		if zone_moved:
			# Teardown the stale zone scope in the same batch.
			_tree().delete_state(_player_base(old_zone, str(pid)) + "live")
		_last_player_live[str(pid)] = sig
		_projected_player_zone[str(pid)] = zone
		var base := _player_base(zone, str(pid))
		if _tick_available() and not immediate:
			_queue_insert(base + "live", str(pid), "other", payload)
		else:
			_tree().insert_state(base + "live", str(pid), "other", payload)
		_active_zones[zone] = true
		written += 1
	return written

## Remove one player's live node (disconnect / logout / explicit).
## keep_record=true retains the player in _projected_players (zone move
## keeps them projected under the NEW zone via the drift path).
func unproject_player(player_id: String, keep_record: bool = false) -> void:
	var pid := player_id.strip_edges()
	if pid.is_empty():
		return
	var tree := _tree()
	var removed := false
	var z: String = _projected_player_zone.get(pid, "")
	if z != "":
		if tree.delete_state(_player_base(z, pid) + "live"):
			removed = true
	else:
		# No recorded zone: sweep every active zone (defensive).
		for zone in _active_zones.keys():
			if tree.delete_state(_player_base(str(zone), pid) + "live"):
				removed = true
	_last_player_live.erase(pid)
	_projected_player_zone.erase(pid)
	if not keep_record:
		_projected_players.erase(pid)
	if removed:
		_touch()

## ---------------------------------------------------------------------------
## Per-zone resync snapshots (the pruning lever)
## ---------------------------------------------------------------------------

## Bounded, zone-scoped snapshot for client resync. Only this zone's
## entity + player live nodes are returned, so a horde in another zone
## never bloats the payload. Node count is capped at
## MAX_ZONE_SNAPSHOT_NODES (horde guard).
func snapshot_for_zone(zone_id: String) -> Array:
	var zid := _safe_zone(zone_id)
	var snapshot: Array = _tree().get_full_scope_snapshot("/world/zones/%s" % zid)
	if snapshot.size() <= MAX_ZONE_SNAPSHOT_NODES:
		return snapshot
	# Horde guard: keep the first N entries (T3 snapshot order is
	# deterministic); the client AOI culls from here.
	return snapshot.slice(0, MAX_ZONE_SNAPSHOT_NODES)

## Bounded instance-scoped snapshot (dungeon/arena resyncs). Same cap
## and contract as snapshot_for_zone, under /world/instances/<scope>/.
func snapshot_for_instance(scope: String) -> Array:
	var sid := _safe_zone(scope)
	var snapshot: Array = _tree().get_full_scope_snapshot("/world/instances/%s" % sid)
	if snapshot.size() <= MAX_ZONE_SNAPSHOT_NODES:
		return snapshot
	return snapshot.slice(0, MAX_ZONE_SNAPSHOT_NODES)

## Which zones currently hold projected state (diagnostics + tests).
func active_zones() -> Array:
	return _active_zones.keys()

## ---------------------------------------------------------------------------
## Helpers
## ---------------------------------------------------------------------------

## Projectable: a live Node carrying enemy_data (mobs). The player is
## projected via zone-enter + flush polling; signal shapes that pass
## ids/strings are ignored.
func _is_projectable(entity) -> bool:
	if entity == null or not (entity is Node) or not is_instance_valid(entity):
		return false
	if not ("entity_id" in entity) or str(entity.entity_id) == "":
		return false
	if not ("enemy_data" in entity) or entity.enemy_data == null:
		return false
	return true

## Is this target a player node (for the damage path)?
func _is_player_target(target) -> bool:
	if target == null or not (target is Node) or not is_instance_valid(target):
		return false
	return "entity_type" in target and target.entity_type == Entity.EntityType.PLAYER


## Snapshot the projectable fields of an entity. enemy_data may be a
## full EnemyData Resource or a stub Dictionary; both duck via .get().
## NOTE: only Dictionaries support get(key, default) in 4.7.2 --
## Resource.get lost its default argument, so Resource payloads take
## the guarded branch below.
func _extract(entity) -> Dictionary:
	if not _is_projectable(entity):
		return {}
	var ed = entity.enemy_data
	# 4.7.2: Resource.get(key, default) no longer takes a default --
	# branch on the payload shape instead of .get() with a fallback.
	var ed_name := ""
	var ed_level := 1
	if ed is Dictionary:
		if ed.has("display_name"):
			ed_name = str(ed["display_name"])
		if ed.has("level"):
			ed_level = int(ed["level"])
	else:
		if "display_name" in ed:
			ed_name = str(ed.display_name)
		if "level" in ed:
			ed_level = int(ed.level)
	var data := {
		"kind": "enemy",
		"display_name": ed_name,
		"level": ed_level,
	}
	if "display_name" in entity and str(entity.display_name) != "":
		data["display_name"] = str(entity.display_name)
	if "level" in entity and int(entity.level) > 0:
		data["level"] = int(entity.level)
	if "health_component" in entity and entity.health_component != null:
		var hc = entity.health_component
		data["current_health"] = int(hc.current_health)
		data["max_health"] = int(hc.max_health)
	return data

static func _safe_zone(zone_id: String) -> String:
	return zone_id.strip_edges().replace("/", "_")

## Scope token -> tree path prefix. Plain tokens are zone ids
## (/world/zones/<z>/...); "instance:<scope>" tokens live under the
## instance subtree (/world/instances/<scope>/...) so instance state
## never bloats overworld zone snapshots.
static func _scope_base(zone_or_scope: String, leaf_kind: String, id: String) -> String:
	var token := str(zone_or_scope)
	var safe := id.replace("/", "_")
	if token.begins_with("instance:"):
		var scope := _safe_zone(token.trim_prefix("instance:"))
		return "/world/instances/%s/%s/%s/" % [scope, leaf_kind, safe]
	return "/world/zones/%s/%s/%s/" % [_safe_zone(token), leaf_kind, safe]

static func _entity_base(zone_id: String, entity_id: String) -> String:
	return _scope_base(zone_id, "entities", entity_id)

static func _player_base(zone_id: String, player_id: String) -> String:
	return _scope_base(zone_id, "players", player_id)

## Live scope for an entity: explicit instance override first, then
## ZoneManager's tracked zone id, else "unzoned" (deterministic fallback
## so entities outside any registered zone still project).
func _entity_zone_id(entity_id: String) -> String:
	var override: String = str(_scope_overrides.get(entity_id, ""))
	if override != "":
		return override
	var zm := get_node_or_null("/root/ZoneManager")
	if zm != null and zm.has_method("get_entity_zone_id"):
		var entity = null
		var es := _entity_service()
		if es != null and es.has_method("get_entity"):
			entity = es.get_entity(entity_id)
		if entity != null and is_instance_valid(entity):
			var zid: Variant = zm.get_entity_zone_id(entity)
			if zid != null and str(zid) != "":
				return str(zid)
	return "unzoned"

## ---------------------------------------------------------------------------
## Instance scope overrides (dungeon/arena hordes)
## ---------------------------------------------------------------------------

## Pin an entity's projected state under /world/instances/<scope>/.
## Callers: HordeEventService stamps horde mobs and (on participation)
## players for instance-scoped hordes. Empty scope clears the pin.
func set_entity_scope_override(entity_id: String, scope: String) -> void:
	var eid := entity_id.strip_edges()
	var sc := scope.strip_edges()
	if eid.is_empty():
		return
	if sc.is_empty():
		_scope_overrides.erase(eid)
		# Health re-resolves against ZoneManager on the next flush.
		_last_health.erase(eid)
		return
	_scope_overrides[eid] = "instance:" + sc
	# Re-resolve on the next flush so identity + health move together.
	_last_health.erase(eid)

func clear_entity_scope_override(entity_id: String) -> void:
	set_entity_scope_override(entity_id, "")

## Current override token ("" when none). TickService reads this to
## route instance-scoped diff entries to participating clients.
func get_entity_scope_override(entity_id: String) -> String:
	return str(_scope_overrides.get(entity_id, ""))

## Instance scopes that currently hold projected state (for teardown
## and diagnostics).
func active_instance_scopes() -> Array:
	var scopes: Array = []
	for eid in _projected_zone:
		var token := str(_projected_zone[eid])
		if token.begins_with("instance:") and not scopes.has(token):
			scopes.append(token)
	return scopes

## Queue one insert/update through TickService's command buffer so the
## write lands in the next tick's atomic Phase-2 batch (one re-root for
## the whole batch). Falls back to a direct write when no tick exists.
func _queue_insert(path: String, entity_id: String, state_type: String, payload: Dictionary) -> void:
	var ts := get_node_or_null("/root/TickService")
	if ts != null and ts.has_method("queue_state_command"):
		ts.queue_state_command({
			"type": "update",
			"path": path,
			"entity_id": entity_id,
			"state_type": state_type,
			"payload": payload,
		})
	else:
		_tree().insert_state(path, entity_id, state_type, payload)

## The shared world state tree on FrameService; script-mode fallback is
## a private tree with identical semantics (tests still exercise the
## real insert/read/delete paths).
func _tree() -> StateTreeScript:
	if _state_tree_ref == null:
		var fs := _frame_service()
		if fs != null and fs.has_method("get_world_state_tree"):
			_state_tree_ref = fs.get_world_state_tree()
		if _state_tree_ref == null:
			_state_tree_ref = StateTreeScript.new()
			_schema = _schema if _schema != null else StateSchemaScript.new()
	return _state_tree_ref

func _touch() -> void:
	var fs := _frame_service()
	if fs != null and fs.has_method("touch_world_tree"):
		fs.touch_world_tree()

func _frame_service() -> Node:
	return get_node_or_null("/root/FrameService")

func _entity_service() -> Node:
	return get_node_or_null("/root/EntityService")
