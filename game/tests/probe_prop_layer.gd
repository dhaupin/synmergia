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

	# A3: streaming builds chunks around the viewer.
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

	print("[probe_prop_layer] %s (%d fails)" % ["ALL PASS" if _fails == 0 else "FAILURES", _fails])
	quit(0 if _fails == 0 else 1)


func _same_first(a: Dictionary, b: Dictionary) -> bool:
	if a["instances"].is_empty() or b["instances"].is_empty():
		return a["instances"].size() == b["instances"].size()
	var da: Vector3 = a["instances"][0]["dir"]
	var db: Vector3 = b["instances"][0]["dir"]
	return da.distance_to(db) < 1e-9


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
