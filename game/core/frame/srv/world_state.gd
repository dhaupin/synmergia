## WorldState - world-scoped STATE deltas (V1 world-state engine slice).
##
## Frame primitive (no autoload, no class_name -- the core/frame law).
## WorldRegistry owns world GEOMETRY + physics truth (derived, clock
## thesis: nothing stored that a seed did not choose). This primitive
## owns world STATE: the deltas players and agents actually cause --
## harvested nodes, opened gates, weather rolls, siege marks. The two
## are different layers: geometry is a function of the universe seed,
## state is a function of what happened.
##
## Storage lives in a StateTree passed at construction (one book, no
## side doors -- the agent-citizen law). WorldStateProjection owns the
## shared instance so every world-state write lands in the SAME tree
## zone/instance state flows through. Paths:
##
##   /world/w/<world_id>/state/<key>   one state delta (type "other")
##   /world/w/<world_id>/summary       registry truth mirror (readable
##                                     without WorldRegistry access;
##                                     written by stamp_world_summary)
##
## Every state write carries PROVENANCE: who set it and at what epoch.
## Humans, synthetics, and future services all ride this one chain --
## the value is the delta, the ledger remembers the hand that made it.
## No write is special-cased by species or role.
##
## Key contract: keys are free-form strings (safe zone chars only --
## "/" is rejected, it is the path separator). Values are payload
## Dictionaries. A delete (erase) is itself a delta: a "cleared"
## provenance record is written so the erasure is auditable, then the
## live node is removed.
extends RefCounted

const StateTreeScript = preload("res://core/frame/kv/state_tree.gd")
const T3Script = preload("res://core/frame/kv/t3.gd")## Safe zone chars for keys (mirrors WorldStateProjection._safe_zone
## naming law): letters, digits, underscore, hyphen, dot -- PLUS "/",
## which is the DELIBERATE hierarchy separator ("harvest/iron_1"
## nests under harvest/ in the tree; T3 normalizes the path).
const SAFE_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./"

var _state_tree: StateTreeScript = null

## tree is optional: pass the shared StateTree when one exists (the
## projection passes its own); probes and script mode may pass none
## and get a standalone tree.
func _init(tree: StateTreeScript = null) -> void:
	_state_tree = tree


func _ensure_tree() -> StateTreeScript:
	if _state_tree == null:
		_state_tree = StateTreeScript.new(T3Script.new())
	return _state_tree


static func safe_key(key: String) -> String:
	var out := ""
	for ch in key:
		if SAFE_CHARS.contains(ch):
			out += ch
	return out


## Set one world-state delta. Returns the sanitized key ("" refused:
## empty world/key/payload never writes).
func set_world_state(world_id: String, key: String, payload: Dictionary, actor_id: String, epoch_days: float = -1.0) -> String:
	var wid := safe_key(world_id)
	var k := safe_key(key)
	var actor := safe_key(actor_id)
	if wid.is_empty() or k.is_empty() or payload.is_empty():
		return ""
	if epoch_days < 0.0:
		epoch_days = Time.get_unix_time_from_system() / 86400.0
	var value: Dictionary = {
		"payload": payload,
		"actor": actor,
		"epoch": epoch_days,
	}
	_ensure_tree().insert_state(_state_base(wid) + k, actor, "other", value)
	return k


## Read one world-state delta. Returns {} when absent. Shape: the
## provenance envelope {payload, actor, epoch} plus the key.
func get_world_state(world_id: String, key: String) -> Dictionary:
	var wid := safe_key(world_id)
	var k := safe_key(key)
	if wid.is_empty() or k.is_empty():
		return {}
	var got: Dictionary = _ensure_tree().get_state(_state_base(wid) + k)
	if got.is_empty():
		return {}
	# StateTree stores {type, entity_id, payload}; the provenance
	# envelope IS the payload (set_world_state wrote it as such).
	var env: Variant = got.get("payload", null)
	if env is Dictionary:
		var out: Dictionary = (env as Dictionary).duplicate()
		out["key"] = k
		return out
	return {}


## Every delta key currently held for one world (sorted; diagnostics
## + tests). Hierarchical keys ("harvest/iron_1") list as-is.
func world_state_keys(world_id: String) -> Array:
	var wid := safe_key(world_id)
	if wid.is_empty():
		return []
	var keys: Array = []
	var snap: Array = _ensure_tree().get_full_scope_snapshot(_state_base(wid))
	# T3 normalizes paths: no leading slash. Compare accordingly.
	var prefix := "world/w/%s/state/" % wid
	for entry in snap:
		if entry is Array and entry.size() >= 1:
			var p := str(entry[0])
			if p.begins_with("/"):
				p = p.substr(1)
			if p.begins_with(prefix):
				keys.append(p.substr(prefix.length()))
	keys.sort()
	return keys


## Clear one delta: the cleared RECORD replaces the live value at the
## same key ({cleared: true, actor, epoch}) so an audited world can
## answer who cleared what and when. A later set_world_state
## overwrites it (a re-harvestable node comes back to life). Returns
## the key or "" when refused.
func erase_world_state(world_id: String, key: String, actor_id: String, epoch_days: float = -1.0) -> String:
	var wid := safe_key(world_id)
	var k := safe_key(key)
	if wid.is_empty() or k.is_empty():
		return ""
	if epoch_days < 0.0:
		epoch_days = Time.get_unix_time_from_system() / 86400.0
	set_world_state(wid, k, {"cleared": true}, actor_id, epoch_days)
	return k


## Registry-truth mirror under the same world prefix. Dev/ops
## convenience + probe seeding: world truth readable straight out of
## the state tree.
func stamp_world_summary(world_id: String, summary: Dictionary) -> bool:
	var wid := safe_key(world_id)
	if wid.is_empty() or summary.is_empty():
		return false
	_ensure_tree().insert_state(_base(wid) + "summary", "registry", "other", summary)
	return true


## Read the stamped summary. {} when absent.
func world_summary(world_id: String) -> Dictionary:
	var wid := safe_key(world_id)
	if wid.is_empty():
		return {}
	var got: Dictionary = _ensure_tree().get_state(_base(wid) + "summary")
	if got.is_empty():
		return {}
	var payload: Variant = got.get("payload", null)
	return (payload as Dictionary).duplicate() if payload is Dictionary else {}


static func _base(world_id: String) -> String:
	return "/world/w/%s/" % [world_id]


## State deltas live one level deeper: /world/w/<id>/state/<key>.
static func _state_base(world_id: String) -> String:
	return "/world/w/%s/state/" % [world_id]
