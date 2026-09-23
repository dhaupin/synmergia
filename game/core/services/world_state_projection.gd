## WorldStateProjection - world/mob entity state -> shared frame state tree.
##
## The character half of the projection lives in PlayerProgress (via
## core/frame/bridge/progress_bridge.gd). This service covers the OTHER
## half: world entities (mobs). Together both writers fill the ONE shared
## FrameService world state tree so the frame's canonical hashing and
## D027 diffing see the whole live world.
##
## Node layout (per entity):
##   /world/entities/<entity_id>/identity  type=other   {kind,display_name,level}
##   /world/entities/<entity_id>/health    type=health  {current,max}
##
## Wiring: EventHub.entity_spawned -> write identity+health;
## EventHub.entity_died / entity_despawned -> remove nodes.
## Health churn is coalesced: damage marks the entity dirty, a 0.5s
## flush writes current values once and touches the tree once (a pack
## pull produces one hash announcement per tick window, not per hit).
##
## Duck-typing: only entities carrying enemy_data are projected -- the
## player is PlayerProgress's job, NPCs/containers have their own cycle.
extends Node

const StateTreeScript = preload("res://core/frame/kv/state_tree.gd")

## Seconds between health flushes.
const FLUSH_INTERVAL: float = 0.5

var _dirty: Dictionary = {}      # entity_id -> true
var _flush_accum: float = 0.0
var _private_tree: StateTreeScript = null   # script-mode fallback


func _ready() -> void:
	# EntityService registrations are the authoritative lifecycle (every
	# register_entity/unregister_entity fires them); EventHub signals are
	# the redundant second net (damage marks dirty below).
	var es := get_node_or_null("/root/EntityService")
	if es != null:
		if es.has_signal("entity_registered") and not es.entity_registered.is_connected(_on_entity_spawned):
			es.entity_registered.connect(_on_entity_spawned)
		if es.has_signal("entity_unregistered") and not es.entity_unregistered.is_connected(_on_entity_despawned):
			es.entity_unregistered.connect(_on_entity_despawned)
	if EventHub != null:
		if EventHub.has_signal("entity_spawned") and not EventHub.entity_spawned.is_connected(_on_entity_spawned):
			EventHub.entity_spawned.connect(_on_entity_spawned)
		if EventHub.has_signal("entity_died") and not EventHub.entity_died.is_connected(_on_entity_died):
			EventHub.entity_died.connect(_on_entity_died)
		if EventHub.has_signal("entity_despawned") and not EventHub.entity_despawned.is_connected(_on_entity_despawned):
			EventHub.entity_despawned.connect(_on_entity_despawned)
		# Health churn: the damage event's TARGET is the second argument;
		# marking dirty defers the tree write to the 0.5s flush window.
		if EventHub.has_signal("damage_dealt") and not EventHub.damage_dealt.is_connected(_on_damage_dealt):
			EventHub.damage_dealt.connect(_on_damage_dealt)
	GameLog.info("WorldStateProjection: Ready")


func _process(delta: float) -> void:
	if _dirty.is_empty():
		return
	_flush_accum += delta
	if _flush_accum < FLUSH_INTERVAL:
		return
	_flush_accum = 0.0
	flush()


## ---------------------------------------------------------------------------
## Event handlers (all duck-typed; never crash on signal-shape drift)
## ---------------------------------------------------------------------------

func _on_entity_spawned(entity, _metadata = null) -> void:
	if not _is_projectable(entity):
		return
	var data: Dictionary = _extract(entity)
	if data.is_empty():
		return
	write_entity(str(entity.entity_id), data)


func _on_entity_died(entity, _killer = null, _metadata = null) -> void:
	if entity == null or not (entity is Node) or not is_instance_valid(entity):
		return
	if not ("entity_id" in entity):
		return
	# Dead mobs leave the tree (their respawn re-adds them fresh).
	remove_entity(str(entity.entity_id))


func _on_entity_despawned(entity, _metadata = null) -> void:
	_on_entity_died(entity)


func _on_damage_dealt(_source, target, _amount, _type) -> void:
	if _is_projectable(target):
		mark_dirty(str(target.entity_id))


## ---------------------------------------------------------------------------
## Tree writes
## ---------------------------------------------------------------------------

## Project one entity from a plain data Dictionary (the pure core; also
## what the handlers extract). Writes identity + health nodes.
## Returns true when anything was written.
func write_entity(entity_id: String, data: Dictionary) -> bool:
	var eid := entity_id.strip_edges()
	if eid.is_empty() or data.is_empty():
		return false
	var tree := _tree()
	var base := _entity_base(eid)

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
	_touch()
	return true


## Remove every node for one entity (death/despawn/character deletion).
## Returns true when at least one node existed.
func remove_entity(entity_id: String) -> bool:
	var eid := entity_id.strip_edges()
	if eid.is_empty():
		return false
	var tree := _tree()
	var base := _entity_base(eid)
	var removed := false
	for leaf in ["identity", "health"]:
		if tree.delete_state(base + leaf):
			removed = true
	if removed:
		_touch()
	return removed


## Mark an entity's health as changed; the flush window writes it once.
func mark_dirty(entity_id: String) -> void:
	if not entity_id.is_empty():
		_dirty[entity_id] = true


## Write current health for every dirty entity (EntityService resolution;
## unresolvable ids are dropped). Announces at most one tree touch.
func flush() -> int:
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
		# Health-only rewrite: same insert, tree dedupes unchanged nodes.
		var tree := _tree()
		tree.insert_state(_entity_base(str(eid)) + "health", str(eid), "health", {
			"current": int(data.get("current_health", 0)),
			"max": int(data.get("max_health", 0)),
		})
		written += 1
	if written > 0:
		_touch()
	return written


## Read back one entity's projected nodes ({} when absent).
func read_entity(entity_id: String) -> Dictionary:
	var base := _entity_base(entity_id.strip_edges())
	var out: Dictionary = {}
	for leaf in ["identity", "health"]:
		var value: Variant = _tree().get_state(base + leaf)
		if value is Dictionary and not value.is_empty():
			out[leaf] = value.get("payload", {})
	return out


## Diagnostics: the tree this service writes into.
func state_tree() -> StateTreeScript:
	return _tree()


## ---------------------------------------------------------------------------
## Helpers
## ---------------------------------------------------------------------------

## Projectable: a live Node carrying enemy_data (mobs). The player is
## PlayerProgress's job; signal shapes that pass ids/strings are ignored.
func _is_projectable(entity) -> bool:
	if entity == null or not (entity is Node) or not is_instance_valid(entity):
		return false
	if not ("entity_id" in entity) or str(entity.entity_id) == "":
		return false
	if not ("enemy_data" in entity) or entity.enemy_data == null:
		return false
	return true


## Snapshot the projectable fields of an entity. enemy_data may be a
## full EnemyData Resource or a stub Dictionary; both duck via .get().
func _extract(entity) -> Dictionary:
	if not _is_projectable(entity):
		return {}
	var ed = entity.enemy_data
	var data := {
		"kind": "enemy",
		"display_name": str(ed.get("display_name", "") if ed != null else ""),
		"level": int(ed.get("level", 1) if ed != null else 1),
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


static func _entity_base(entity_id: String) -> String:
	# Guard the path namespace: no slashes in ids.
	var safe := entity_id.replace("/", "_")
	return "/world/entities/%s/" % safe


## The shared world state tree on FrameService; script-mode fallback is
## a private tree with identical semantics (tests still exercise the
## real insert/read/delete paths).
func _tree() -> StateTreeScript:
	var fs := _frame_service()
	if fs != null and fs.has_method("get_world_state_tree"):
		return fs.get_world_state_tree()
	if _private_tree == null:
		_private_tree = StateTreeScript.new()
	return _private_tree


## Announce a mutation: FrameService re-folds the root hash and emits
## world_state_changed (client resync keys off it).
func _touch() -> void:
	var fs := _frame_service()
	if fs != null and fs.has_method("touch_world_tree"):
		fs.touch_world_tree()


func _frame_service() -> Node:
	if get_tree() == null:
		return null
	return get_tree().root.get_node_or_null("FrameService")


func _entity_service() -> Node:
	if get_tree() == null:
		return null
	return get_tree().root.get_node_or_null("EntityService")
