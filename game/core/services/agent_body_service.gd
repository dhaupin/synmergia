## AgentBodyService - the agent bodies (labs/prd-agent-play.md sec 1/7).
##
## THE KEYSTONE (the gap this service closes): "an agent is a player" was true
## in every layer EXCEPT the body. The world builds exactly ONE player body,
## the agent driver drives it, and an agent's character id resolved to no live
## body -- so an agent could only ever be a test double. This service builds,
## registers, links, and tears down REAL agent bodies: a second GlobeWorldPlayer
## in the same world as the human, driven by its OWN input (set_virtual_input),
## so two players share one process without steering each other.
##
## Ownership: this service owns the BODY. AgentRoster owns the SEAT (the
## pairing + party membership); AgentCoordinator owns the LOOP (work items).
## The roster asks this service to spawn when a seat has no body, and to
## despawn when the seat is dropped (the sec 17.2 save/despawn leg).
##
## Autoload: NO class_name (AGENTS rule). The world is resolved from the
## human's LIVE body (its parent is the globe scene), so nothing here depends
## on the scene name -- a probe with a fabricated body parent works the same
## as the real globe.
extends Node

const Layers = preload("res://core/schemas/layer_profile.gd")

## The body script (globe_player.gd). Loaded at runtime, not preloaded: a
## parse-time preload of a game script fights the autoload registration order
## (the script-mode law the agent receipts document).
const BODY_SCRIPT := "res://entities/globe_player.gd"

## How far from the human a fresh agent body seats, so the two do not spawn
## inside each other (a party member arrives BESIDE the leader).
const SEAT_OFFSET_M: float = 1.6

## handle -> live body node.
var _bodies: Dictionary = {}
## entity_id -> handle (reverse lookup for despawn-by-id / observability).
var _by_entity: Dictionary = {}


func _ready() -> void:
	GameLog.info("AgentBodyService: Ready")


# == Public API =========================================================

## The live body for an agent handle, or null. A freed/stale node resolves to
## null (never a dangling reference).
func body_for(handle: String) -> Node:
	var b = _bodies.get(handle, null)
	if b is Node and is_instance_valid(b):
		return b
	if _bodies.has(handle):
		_bodies.erase(handle)
	return null


## Every live agent body: {handle: entity_id}.
func board() -> Dictionary:
	var out: Dictionary = {}
	for h in _bodies.keys():
		var b = body_for(h)
		if b != null:
			out[h] = str(b.entity_id) if "entity_id" in b else ""
	return out


## Spawn a real agent body for `handle`, in the world the human stands in.
## Idempotent: a handle with a live body returns that body. The body is a
## full player (PlayerBase fields: display_name/level/faction/experience/gold),
## registered with EntityService, riding the SAME walk law as the human, and
## linked into AgentCoordinator so the loop can drive it by handle.
##   opts: {display_name, entity_id, position}
## Refuses by name when there is no world to seat into (the honest "the world
## is not up yet"), never a silent no-op.
func spawn(account_id: String, handle: String, opts: Dictionary = {}) -> Dictionary:
	if handle.strip_edges() == "":
		return {"ok": false, "reason": "a body needs a handle"}
	var existing := body_for(handle)
	if existing != null:
		return {"ok": true, "handle": handle, "entity_id": str(existing.entity_id), "already": true}
	var world := _world()
	if world == null:
		return {"ok": false, "reason": "no world to seat an agent in (the human is not in-world)"}
	var human := _human_body()
	var script: GDScript = load(BODY_SCRIPT)
	if script == null or not script.can_instantiate():
		return {"ok": false, "reason": "agent body script unavailable"}

	var body: CharacterBody3D = CharacterBody3D.new()
	body.set_script(script)
	body.name = "AgentBody_%s" % _safe(handle)
	# An agent body is NOT the local player: it never reads the global
	# Input singleton and never receives the input fan-out. Its input
	# arrives through set_virtual_input (the driver's move verb).
	body.is_local_player = false
	body.allow_jump_input = false
	body.collision_layer = Layers.layer_bit("entity")
	body.collision_mask = Layers.group_mask("entity_solid")
	body.add_child(_collision_shape())
	body.add_child(_mesh(handle))

	# The body inherits the world's law from the human's own body: the same
	# planet center/radius, the same ground offset, the same walk-surface
	# provider closure. One world, one walk law -- no re-derivation.
	if human != null and is_instance_valid(human):
		body.planet_center = human.planet_center if "planet_center" in human else Vector3.ZERO
		body.planet_radius = human.planet_radius if "planet_radius" in human else 100.0
		body.ground_offset = human.ground_offset if "ground_offset" in human else 0.0
		if "snap_height_provider" in human:
			body.snap_height_provider = human.snap_height_provider

	# Identity: a stable entity id (opts override, else derived from the
	# handle). This is the id the roster/coordinator/party all key on.
	var eid: String = String(opts.get("entity_id", "")).strip_edges()
	if eid == "":
		eid = "agent_%s" % _safe(handle)
	body.entity_id = eid
	body.display_name = String(opts.get("display_name", handle.capitalize()))
	body.entity_type = Entity.EntityType.PLAYER

	# Place beside the human (a party member arrives next to the leader),
	# else at the world origin lifted to the shell.
	var pos: Vector3 = opts.get("position", Vector3.INF)
	if pos == Vector3.INF:
		if human != null and is_instance_valid(human):
			var away: Vector3 = (human.global_position - body.planet_center).normalized()
			pos = human.global_position + away * SEAT_OFFSET_M
		else:
			pos = body.planet_center + Vector3.UP * (body.planet_radius + 2.0)
	body.position = pos

	# Add to the world FIRST: EntityService.register_entity reads the body's
	# global_position (via SpawnMetadata), which is only valid inside the tree.
	world.add_child(body)

	# Register with EntityService (the live registry every consumer reads), so
	# the party/targeting paths can resolve it on the next tick.
	var es := get_node_or_null("/root/EntityService")
	if es != null and es.has_method("register_entity"):
		var meta = _metadata(body)
		es.register_entity(body, meta, eid)
	_bodies[handle] = body
	_by_entity[eid] = handle

	# Link the body into the coordinator's record for this handle (the
	# honest handle -> character link sec 7 records), so the loop and the
	# roster both resolve the same body.
	var coord := get_node_or_null("/root/AgentCoordinator")
	if coord != null and coord.has_method("link_entity"):
		coord.link_entity(handle, eid)

	GameLog.info("AgentBodyService: spawned body '%s' for %s at %s" % [eid, handle, str(pos)])
	return {"ok": true, "handle": handle, "entity_id": eid}


## Tear down an agent body: clear its input, unregister it, free it, drop the
## books, and clear the coordinator link. Idempotent (a missing body is not an
## error -- despawn is called on the save leg where the body may already be
## gone). Returns true when a live body was actually removed.
func despawn(handle: String) -> bool:
	var body := body_for(handle)
	if body == null:
		return false
	var eid: String = str(body.entity_id) if "entity_id" in body else ""
	if body.has_method("clear_virtual_input"):
		body.clear_virtual_input()
	var es := get_node_or_null("/root/EntityService")
	if es != null and es.has_method("unregister_entity"):
		es.unregister_entity(body, "agent_despawn")
	body.queue_free()
	_bodies.erase(handle)
	if eid != "":
		_by_entity.erase(eid)
	# NOTE: the coordinator's entity_id is the agent's CHARACTER (its persistent
	# identity), not this transient body -- leave it in place. The body itself
	# is gone from the registry, so the roster re-seats (and unseats) cleanly on
	# a re-enable. A full detach removes the coordinator record entirely.
	GameLog.info("AgentBodyService: despawned body for %s" % handle)
	return true


## The handle that owns a given entity id, or "".
func handle_for_entity(entity_id: String) -> String:
	return String(_by_entity.get(entity_id, ""))


# == Internals ==========================================================

## The globe world = the human body's parent (the scene that holds the player),
## but ONLY when it is a REAL globe -- a unit probe that parents a fabricated
## body to the tree root must not read as "a world" (that would spawn a body
## into nowhere). The globe is identified by its walk-law seam (terrain_h_at),
## not by a scene name.
func _world() -> Node:
	var human := _human_body()
	if human != null and is_instance_valid(human):
		var parent := human.get_parent()
		if _is_globe(parent):
			return parent
	var tree := get_tree()
	if tree != null and _is_globe(tree.current_scene):
		return tree.current_scene
	return null


## A node is a globe when it carries the walk-law seam (terrain_h_at) the
## player reads; the tree root and a bare Node3D never do.
func _is_globe(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.has_method("terrain_h_at")


## The human's LIVE body (the local seat). "" account handling lives in the
## roster; here we only need the body to inherit law + placement from.
func _human_body() -> Node:
	var pm := get_node_or_null("/root/PlayerManager")
	if pm != null and "local_player" in pm:
		var lp = pm.local_player
		if lp != null and is_instance_valid(lp):
			return lp
	return null


func _collision_shape() -> CollisionShape3D:
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.0
	col.shape = shape
	return col


## A distinguishable body mesh (agents read as a different hue than the human's
## gold). One small sphere; the real model path is a later art question.
func _mesh(handle: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.6
	mesh.height = 1.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _hue_for(handle)
	mesh.material = mat
	mi.mesh = mesh
	return mi


func _hue_for(handle: String) -> Color:
	# Deterministic per handle, in the cyan/violet agent band (never the
	# human's gold), so two agents are visually distinct on a shared screen.
	var h: int = abs(handle.hash()) % 1000
	return Color.from_hsv(0.5 + float(h) / 1000.0 * 0.2, 0.65, 0.85)


func _metadata(body: Node):
	var script: GDScript = load("res://core/events/spawn_metadata.gd")
	if script == null or not script.can_instantiate():
		return null
	var meta = script.new(0, str(body.display_name), "", body.global_position)
	return meta


## A filesystem/Node-name-safe token for a handle (handles are usually plain
## but never trust that for a node name).
func _safe(handle: String) -> String:
	var out: String = ""
	for i in range(handle.length()):
		var c: String = handle.substr(i, 1)
		if c.is_valid_identifier() or c == "_":
			out += c
	return out if out != "" else "agent"
