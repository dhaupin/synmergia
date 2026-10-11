## HarvestService - gatherable world nodes (S16.5.3, the live-delta thread).
##
## The world gives; the ledger remembers. A gatherable node spawns,
## a citizen harvests it, it depletes, the world grows it back. Every
## step is a WORLD DELTA in the one StateTree (the AncientDoor law):
##
##   harvest/<node_id>  set on depletion  {depleted, item_id, qty}
##                      erased on respawn (the cleared record stays
##                      auditable: who took it, and when it returned)
##
## Provenance is the point: actor = the harvester (human or synthetic,
## no special-casing -- the agent-citizen law), epoch = the S16.2 sky
## clock. A node's whole life is readable from its delta history.
##
## Nodes are registered at runtime (world scenes, events, probes);
## data-driven .tres placement comes when world scenes place nodes.
## The item granted is DataService truth (an Item .tres id) -- the
## service invents nothing. All grants ride the InventoryService
## purse chain, exactly like loot pickups.
extends Node

signal harvest_completed(player_id: String, node_id: String, item_id: String, quantity: int)
signal node_respawned(node_id: String)

const WORLD_DEFAULT := "main"

## node_id -> {
##   zone_id, world_id, item_id, quantity, pos, respawn_sec,
##   depleted_until (unix, 0 = ready), last_harvester
## }
var _nodes: Dictionary = {}

func _ready() -> void:
	pass  # autoload; registered-to on demand

## Register one gatherable node. Returns the node id ("" refused:
## unknown item, missing ids). world_id resolves from ZoneData when
## the zone is known, else main.
func register_node(node_id: String, zone_id: String, item_id: String, pos: Vector3, quantity: int = 1, respawn_sec: float = 60.0) -> String:
	var nid := str(node_id).strip_edges()
	if nid.is_empty() or str(item_id).strip_edges().is_empty():
		return ""
	if DataService == null or DataService.get_item(item_id) == null:
		GameLog.warn("HarvestService: node '%s' refused, unknown item '%s'" % [nid, item_id])
		return ""
	_nodes[nid] = {
		"zone_id": str(zone_id),
		"world_id": _world_for_zone(zone_id),
		"item_id": str(item_id),
		"quantity": maxi(1, quantity),
		"pos": pos,
		"respawn_sec": maxf(0.0, respawn_sec),
		"depleted_until": 0.0,
		"last_harvester": "",
	}
	return nid

## The harvest: one gate chain, same shape as every other service
## answer {ok, message}. Depletes the node, grants the item through
## the purse, writes the world delta with provenance.
func harvest(player_id: String, node_id: String) -> Dictionary:
	var pid := str(player_id).strip_edges()
	var nid := str(node_id).strip_edges()
	if pid.is_empty() or not _nodes.has(nid):
		return {"ok": false, "reason": "unknown_node"}
	var node: Dictionary = _nodes[nid]
	var now := _unix_now()
	var until: float = float(node.get("depleted_until", 0.0))
	if until > 0.0 and now < until:
		return {"ok": false, "reason": "depleted", "respawn_in": until - now}
	if QoSService and QoSService.has_method("rate_limit") and not QoSService.rate_limit(pid, "harvest"):
		return {"ok": false, "reason": "rate_limited"}

	# The grant rides the lawful purse chain. A citizen with no bag
	# (deep script mode, logged-out) is refused -- the world does not
	# drop items into the void.
	var inv = _purse(pid)
	if inv == null or not inv.has_method("add_item"):
		return {"ok": false, "reason": "no_inventory"}
	var item = DataService.get_item(str(node["item_id"]))
	if item == null:
		return {"ok": false, "reason": "unknown_item"}
	var qty: int = maxi(1, int(node.get("quantity", 1)))
	if not inv.add_item(item, qty):
		return {"ok": false, "reason": "inventory_full"}

	# Deplete + provenance delta (actor = harvester, epoch = sky clock).
	node["depleted_until"] = now + float(node.get("respawn_sec", 0.0))
	node["last_harvester"] = pid
	_write_delta(nid, node, pid, false)
	_schedule_respawn(nid, float(node.get("respawn_sec", 0.0)))

	harvest_completed.emit(pid, nid, str(node["item_id"]), qty)
	GameLog.info("HarvestService: %s harvested %s (%s x%d)" % [pid, nid, str(node["item_id"]), qty])
	return {"ok": true, "item_id": str(node["item_id"]), "quantity": qty}

## Node state reads (UI + tests).
func is_depleted(node_id: String) -> bool:
	var node: Dictionary = _nodes.get(str(node_id), {})
	var until: float = float(node.get("depleted_until", 0.0))
	return until > 0.0 and _unix_now() < until

func respawn_in(node_id: String) -> float:
	var node: Dictionary = _nodes.get(str(node_id), {})
	var until: float = float(node.get("depleted_until", 0.0))
	var left := until - _unix_now()
	return left if left > 0.0 else 0.0

func node_ids() -> Array:
	return _nodes.keys()

## Test/dev hook: force a node ready now (the probe's clock hand).
func force_ready(node_id: String) -> void:
	var node: Dictionary = _nodes.get(str(node_id), {})
	if not node.is_empty():
		node["depleted_until"] = 0.0

## Respawn = the world gives back. The delta ERASES (cleared record:
## the audit keeps who took it and when it returned).
func _schedule_respawn(nid: String, respawn_sec: float) -> void:
	if respawn_sec <= 0.0:
		return
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(respawn_sec).timeout.connect(func():
		var node: Dictionary = _nodes.get(nid, {})
		if node.is_empty():
			return
		node["depleted_until"] = 0.0
		node["last_harvester"] = ""
		_write_delta(nid, node, "world", true)
		node_respawned.emit(nid))

## The one-book write: same chain as the door. world_id comes from
## the node's registration (ZoneData truth, cached at register).
func _write_delta(nid: String, node: Dictionary, actor: String, cleared: bool) -> void:
	var proj = get_node_or_null("/root/WorldStateProjection")
	if proj == null or not proj.has_method("world_state"):
		return  # deep script mode: the world still gives, the ledger skips
	var ws = proj.world_state()
	var epoch: float = -1.0
	if SignService != null and SignService.has_method("sky_epoch_days"):
		epoch = SignService.sky_epoch_days()
	var key := "harvest/%s" % nid
	if cleared:
		ws.erase_world_state(str(node["world_id"]), key, actor, epoch)
	else:
		ws.set_world_state(str(node["world_id"]), key, {
			"depleted": true,
			"item_id": str(node["item_id"]),
			"qty": maxi(1, int(node.get("quantity", 1))),
		}, actor, epoch)

func _purse(player_id: String):
	var inv_svc = get_node_or_null("/root/InventoryService")
	if inv_svc != null and inv_svc.has_method("get_inventory"):
		return inv_svc.get_inventory(player_id)
	return null

func _world_for_zone(zone_id: String) -> String:
	var zm = get_node_or_null("/root/ZoneManager")
	if zm != null and zm.has_method("get_zone"):
		var zone = zm.get_zone(str(zone_id))
		if zone != null and "world_id" in zone and str(zone.world_id) != "":
			return str(zone.world_id)
	return WORLD_DEFAULT

func _unix_now() -> float:
	return float(Time.get_unix_time_from_system())
