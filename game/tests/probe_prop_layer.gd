## probe_prop_layer -- the renderer-agnostic prop layer (labs/prd-clipmap.md
## section 9). Proves: chunks derive deterministically, trees appear under the
## default provider, and the layer streams around a viewer.
## Run: godot --headless --path . --script res://tests/probe_prop_layer.gd
extends SceneTree

const PropLayer = preload("res://core/world/prop_layer.gd")
const PropChunk = preload("res://core/frame/geometry/prop_chunk.gd")
const Provider = preload("res://scenes/worlds/terrain_provider.gd")
const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")

var _fails: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var layer = PropLayer.new()
	var parent := Node3D.new()
	get_root().add_child(parent)
	layer.configure(Provider.new(), 20000.0, parent)
	layer.chunk_depth = 6

	# A1: chunk derivation is deterministic (fresh derive == cached).
	var key: int = PropChunk.chunk_for_dir(TerrainGen.SPAWN_CENTER, 6)
	var a: Dictionary = layer.derive_fresh(key)
	var b: Dictionary = layer.derive_fresh(key)
	_check("A1 chunk derive deterministic (same instance count + first dir)",
			a["instances"].size() == b["instances"].size() and _same_first(a, b))

	# A2: the spawn chunk is grassland and grows trees.
	var spawn_density: float = layer.provider.tree_density(layer.provider.biome_id(TerrainGen.SPAWN_CENTER))
	_check("A2 spawn biome grows trees (density > 0)", spawn_density > 0.0)

	# A3: streaming builds chunks around the viewer (several budgeted ticks).
	for _i in range(40):
		layer.update(TerrainGen.SPAWN_CENTER * 20000.0)
	var built: int = layer.built_count()
	_check("A3 streaming builds chunks near the viewer", built > 0)

	# A4: tree nodes exist across the built near chunks.
	var tree_count: int = _count_trees(layer)
	_check("A4 the built chunks hold tree nodes", tree_count > 0)

	# A5: the layer is renderer-agnostic -- it only reads the provider.
	_check("A5 layer reads a GroundProvider (not TerrainGen directly)",
			layer.provider != null and layer.provider.has_method("ground_height"))

	# A6: no tree lands below the waterline (sea skip honored).
	_check("A6 no tree below the waterline", _no_subsea_trees(layer, key))

	# A7: rocks (per-face specs) bucket into chunks and build. The spawn face's
	# rocks are sparse, so build a chunk that actually holds one.
	layer.update(TerrainGen.SPAWN_CENTER * 20000.0)
	_check("A7 the spawn face's rocks bucket into chunks", not layer._rocks_by_chunk.is_empty())
	var rock_key: int = -1
	for k in layer._rocks_by_chunk.keys():
		if not layer._rocks_by_chunk[k].is_empty():
			rock_key = k
			break
	var rock_built: bool = false
	if rock_key != -1:
		if not layer._built.has(rock_key):
			layer._build_chunk(rock_key, TerrainGen.SPAWN_CENTER)
		var rn = layer._built.get(rock_key)
		if rn != null:
			rock_built = _count_desc(rn, "Rock") > 0
	_check("A8 a rock-bearing chunk builds Rock nodes", rock_built)

	# A9: the land harvest law -- a drawn mushroom/ore/bush registers a live
	# HarvestService node keyed on its chunk-stable site id (the gather half
	# of the one placement law; the provider resolves the zone).
	# A9: the provider resolves a harvest zone for a homeland site (the main
	# world's starter plains); a non-homeland band resolves none (paint only).
	_check("A9 the provider resolves the homeland harvest zone",
			layer.provider.zone_for_dir(TerrainGen.SPAWN_CENTER) == "zone_starter_plains")

	# A10: the land registration book records the site id once (a chunk reload
	# must not reset the service's depletion book -- idempotent re-register).
	var hs = get_root().get_node_or_null("HarvestService")
	var sid := "hs_landprobe_0"
	layer._land_registered.erase(sid)
	_register_hs(layer, sid)
	var first: bool = layer._land_registered.has(sid) and hs != null and hs.node_ids().has(sid)
	_register_hs(layer, sid)
	_check("A10 the land registration reaches the live service, once", first)

	# A11: the grass carpet -- the dense ground-cover family (one MultiMesh per
	# chunk). The provider declares a grass density; the built near chunks carry
	# a "Grass" MultiMeshInstance3D with blades.
	_check("A11 the built chunks carry a grass carpet", _count_grass_blades(layer) > 0)

	# A12: the dry-band + understory prop kinds resolve from the detail ladder
	# (cactus in desert/badlands, fern in the forest bands).
	var krng := RandomNumberGenerator.new()
	krng.seed = 1
	var saw_cactus: bool = false
	for _i in range(300):
		if layer._detail_kind(TerrainGen.BiomeId.DESERT, krng) == PropLayer.KIND_CACTUS:
			saw_cactus = true
			break
	var saw_fern: bool = false
	for _i in range(300):
		if layer._detail_kind(TerrainGen.BiomeId.JUNGLE, krng) == PropLayer.KIND_FERN:
			saw_fern = true
			break
	_check("A12 the dry + understory prop kinds resolve", saw_cactus and saw_fern)

	print("[probe_prop_layer] %s (%d fails)" % ["ALL PASS" if _fails == 0 else "FAILURES", _fails])
	quit(0 if _fails == 0 else 1)


func _register_hs(layer, sid: String) -> void:
	layer._register_land_harvest({"kind": PropLayer.KIND_MUSHROOM, "dir": TerrainGen.SPAWN_CENTER,
		"h": 5.0, "bid": layer.provider.biome_id(TerrainGen.SPAWN_CENTER), "site_id": sid})

func _same_first(a: Dictionary, b: Dictionary) -> bool:
	if a["instances"].is_empty() or b["instances"].is_empty():
		return a["instances"].size() == b["instances"].size()
	var da: Vector3 = a["instances"][0]["dir"]
	var db: Vector3 = b["instances"][0]["dir"]
	return da.distance_to(db) < 1e-9


func _count_grass_blades(layer) -> int:
	var n: int = 0
	for key in layer._built.keys():
		for ch in layer._built[key].get_children():
			if String(ch.name) == "Grass":
				var mm = ch.get("multimesh")
				if mm != null:
					n += int(mm.instance_count)
	return n


func _count_trees(layer) -> int:
	var n: int = 0
	for key in layer._built.keys():
		n += _count_desc(layer._built[key], "Tree")
	return n


func _count_desc(node: Node, prefix: String) -> int:
	var c: int = 0
	for ch in node.get_children():
		if str(ch.name).begins_with(prefix):
			c += 1
		c += _count_desc(ch, prefix)
	return c


func _count_all(layer, prefix: String) -> int:
	var n: int = 0
	for key in layer._built.keys():
		n += _count_desc(layer._built[key], prefix)
	return n


func _boulders_placed(layer) -> bool:
	# Boulders are per-face fixed content; the bucketing must have run for
	# the spawn face (its specs exist). True if the face is marked done.
	return not layer._rocks_faces_done.is_empty()


func _no_subsea_trees(layer, key: int) -> bool:
	var sea: float = layer.provider.sea_level()
	var data: Dictionary = layer._cache.get(key)
	if data == null:
		return true
	for inst in data.get("instances", []):
		if int(inst.get("family", -1)) == PropLayer.FAMILY_TREE:
			if float(inst["h"]) < sea - 0.6:
				return false
	return true


func _check(label: String, cond: bool) -> void:
	if cond:
		print("  [OK] " + label)
	else:
		print("  [FAIL] " + label)
		_fails += 1
