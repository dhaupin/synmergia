## ChunkInterest - the canonical-chunk interest reader (the gameplay
## consumer of the multi-iso index's chunk axis).
##
## labs/prd-perf-bridges.md Facet 5 landed the READ side of the Julia
## orchestrator index: `MultiIsoService.query_chunk` answers "which
## entities the index holds in THIS canonical clipmap cell". Until now
## only receipts and the admin `/chunk` command read it; gameplay
## proximity still rode `EntityInterest` alone. This helper is the
## documented "next multi-round item" -- it wires the canonical chunk
## query into a gameplay interest read, so a caller can ask "who is in
## my canonical cell" and reconcile the INDEX answer (server-side roster,
## spans processes) against the LOCAL answer (EntityService physics
## truth). The chunk is the canonical layer's unit (labs/prd-clipmap.md
## sec. 12), so both answers speak the same addressing.
##
## The index is best-effort: when the sidecar is down (or the service is
## absent) `query_index_cell` reports `available=false` and an empty
## list rather than fabricating an answer. The local read always works.
##
## Autoload-free static helper (the EntityInterest pattern): resolves the
## services through the scene tree so deep script-mode probes keep working.
extends RefCounted
class_name ChunkInterest

const PropChunk = preload("res://core/frame/geometry/prop_chunk.gd")
const EntityInterest = preload("res://core/services/entity_interest.gd")


## The canonical clipmap cell (PropChunk key) a body stands in, or -1 when
## it has no resolvable position. Uses the planet-radial direction -- the
## SAME frame the prop layer and the index use -- so the cell matches the
## one the server indexed and a client derives.
static func canonical_chunk_of(body, depth: int = PropChunk.DEFAULT_DEPTH) -> int:
	var dir: Vector3 = planet_dir(body)
	if dir.length_squared() <= 0.000001:
		return -1
	return PropChunk.chunk_for_dir(dir, depth)


## The entity ids the multi-iso INDEX holds in this canonical cell.
## Returns {available: bool, ids: Array}. Best-effort: `available` is
## false (and ids empty) when the service/sidecar is absent or the cell
## is unresolved -- never a fabricated answer.
static func query_index_cell(chunk_key: int) -> Dictionary:
	if chunk_key < 0:
		return {"available": false, "ids": []}
	var iso = _multi_iso()
	if iso == null or not iso.has_method("query_chunk"):
		return {"available": false, "ids": []}
	# A disabled service answers with an empty array, which is
	# indistinguishable from an empty cell. Report it as unavailable
	# instead of fabricating a confident zero.
	if "enabled" in iso and not bool(iso.enabled):
		return {"available": false, "ids": []}
	# The sidecar can also be down while the autoload is enabled. Probe
	# health before trusting the chunk answer; query_chunk() returns []
	# on transport failure, so without this a down index would look
	# like an empty cell.
	if iso.has_method("is_healthy") and not await iso.is_healthy():
		return {"available": false, "ids": []}
	var ids: Array = await iso.query_chunk(chunk_key)
	return {"available": true, "ids": ids}


## Local (EntityService physics-truth) players sharing the body's canonical
## cell, resolved by the cell's own angular radius -- the cross-check
## against the index answer. Excludes the body itself.
static func local_players_in_cell(body, depth: int = PropChunk.DEFAULT_DEPTH) -> Array:
	var dir: Vector3 = planet_dir(body)
	if dir.length_squared() <= 0.000001:
		return []
	var radius: float = float(ProjectSettings.get_setting("synmergia/world/planet_radius", 20000.0))
	var arc: float = PropChunk.chunk_angular_radius(depth) * radius
	var origin: Vector3 = _world_position(body)
	var exclude: Array = [body] if body != null else []
	return EntityInterest.query_players(origin, arc, exclude)


## The entity's planet-radial unit direction, or Vector3.ZERO when the
## position is unavailable. planet_center is honored when present (the
## globe frame); otherwise the world origin is the center.
static func planet_dir(body) -> Vector3:
	var pos: Vector3 = _world_position(body)
	if pos == Vector3.ZERO:
		return Vector3.ZERO
	var center := Vector3.ZERO
	if body != null and "planet_center" in body and body.planet_center is Vector3:
		center = body.planet_center
	var rel: Vector3 = pos - center
	if rel.length_squared() < 0.000001:
		return Vector3.ZERO
	return rel.normalized()


static func _world_position(body) -> Vector3:
	if body is Node3D and body.is_inside_tree():
		return body.global_position
	if body != null and "position" in body and body.position is Vector3:
		return body.position
	return Vector3.ZERO


static func _multi_iso() -> Node:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("MultiIsoService")
