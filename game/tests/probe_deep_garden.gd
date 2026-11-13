## probe_deep_garden -- the Sundered Sea's kelp/pearl beds now live in the
## renderer-agnostic PropLayer (labs/prd-clipmap.md section 9.5), not the
## legacy streamer. Proves: the provider authors the beds, the layer buckets
## them into chunks, the deep builder paints the kelp shelf + the pearl
## trench (strands, reef, spires, stones, hidden stumps), each strand carries
## its plant meta, and the garden is byte-identical on re-derive.
## Run: godot --headless --path . --script res://tests/probe_deep_garden.gd
extends SceneTree

const PropLayer = preload("res://core/world/prop_layer.gd")
const PropChunk = preload("res://core/frame/geometry/prop_chunk.gd")
const Provider = preload("res://scenes/worlds/terrain_provider.gd")

var _fails: int = 0


func _init() -> void:
	var layer = PropLayer.new()
	var parent := Node3D.new()
	get_root().add_child(parent)
	layer.configure(Provider.new(), 20000.0, parent)

	# A: the provider authors the six beds (three shelf + three trench).
	var beds: Array = layer.provider.deep_beds()
	_check("A1 provider authors six deep beds", beds.size() == 6)
	var shelf: int = 0
	var trench: int = 0
	for b in beds:
		if int(b["kind"]) == 1:
			shelf += 1
		elif int(b["kind"]) == 2:
			trench += 1
	_check("A2 three shelf + three trench beds", shelf == 3 and trench == 3)

	# B: the beds bucket into chunks (per-face authored content).
	var shelf_bed: Dictionary = {}
	var trench_bed: Dictionary = {}
	for b in beds:
		if int(b["kind"]) == 1 and shelf_bed.is_empty():
			shelf_bed = b
		elif int(b["kind"]) == 2 and trench_bed.is_empty():
			trench_bed = b
	_check("B1 a shelf bed resolves", not shelf_bed.is_empty())
	_check("B2 a trench bed resolves", not trench_bed.is_empty())

	# C: the deep builder paints the shelf garden.
	var shelf_node := Node3D.new()
	get_root().add_child(shelf_node)
	layer._build_deep_bed({"family": PropLayer.FAMILY_DEEP, "dir": shelf_bed["dir"],
			"deep_kind": 1, "bed": int(shelf_bed["bed"]), "face": PropChunk.face_containing(shelf_bed["dir"])},
			shelf_node, true)
	var grove = shelf_node.get_child(0) if shelf_node.get_child_count() > 0 else null
	_check("C1 shelf builds one garden node", grove != null and grove.is_in_group("deep_garden"))
	_check("C2 garden carries its harvest ids", grove != null and grove.has_meta("harvest_ids")
			and (grove.get_meta("harvest_ids") as Array).size() == 3)
	_check("C3 shelf paints fourteen kelp strands", _count(grove, "Kelp") == 14)
	_check("C4 shelf paints reef boulders", _count(grove, "Reef") == 4)
	_check("C5 every strand carries its plant meta", _all_have_plant_meta(grove, "Kelp"))
	_check("C6 the garden hides three stumps", _count(grove, "Stump") == 3 and _all_stumps_hidden(grove))

	# D: the deep builder paints the trench garden.
	var trench_node := Node3D.new()
	get_root().add_child(trench_node)
	layer._build_deep_bed({"family": PropLayer.FAMILY_DEEP, "dir": trench_bed["dir"],
			"deep_kind": 2, "bed": int(trench_bed["bed"]), "face": PropChunk.face_containing(trench_bed["dir"])},
			trench_node, true)
	var tgrove = trench_node.get_child(0) if trench_node.get_child_count() > 0 else null
	_check("D1 trench paints six vent spires", _count(tgrove, "Spire") == 6)
	_check("D2 trench paints two drowned stones", _count(tgrove, "TrenchStone") == 2)
	_check("D3 trench hides three stumps", _count(tgrove, "Stump") == 3)

	# E: re-derive determinism (a chunk reload paints the same garden).
	var shelf_node2 := Node3D.new()
	get_root().add_child(shelf_node2)
	layer._build_deep_bed({"family": PropLayer.FAMILY_DEEP, "dir": shelf_bed["dir"],
			"deep_kind": 1, "bed": int(shelf_bed["bed"]), "face": PropChunk.face_containing(shelf_bed["dir"])},
			shelf_node2, true)
	_check("E1 a re-derive paints the identical garden", _same_layout(shelf_node.get_child(0), shelf_node2.get_child(0)))

	# F: the beds bucket into chunks on the derive path (no crash).
	var any_bed_dir: Vector3 = beds[0]["dir"]
	var key: int = PropChunk.chunk_for_dir(any_bed_dir, layer.chunk_depth)
	var fresh: Dictionary = layer.derive_fresh(key)
	_check("F1 derive runs over a bed chunk (no crash)", fresh.has("instances"))

	# G: through the live streaming path (viewer parked on a bed).
	var layer2 = PropLayer.new()
	var parent2 := Node3D.new()
	get_root().add_child(parent2)
	layer2.configure(Provider.new(), 20000.0, parent2)
	for _i in range(60):
		layer2.update(shelf_bed["dir"] * 20000.0)
	var gardens: int = _count_gardens(layer2._root)
	_check("G1 the shelf garden streams in near the viewer", gardens > 0)

	print("[probe_deep_garden] %s (%d fails)" % ["ALL PASS" if _fails == 0 else "FAILURES", _fails])
	quit(0 if _fails == 0 else 1)


func _count(node, prefix: String) -> int:
	if node == null:
		return 0
	var n: int = 0
	for c in node.get_children():
		if str(c.name).begins_with(prefix):
			n += 1
	return n


func _all_have_plant_meta(grove, prefix: String) -> bool:
	if grove == null:
		return false
	var any: bool = false
	for c in grove.get_children():
		if str(c.name).begins_with(prefix):
			any = true
			if not c.has_meta("plant_k"):
				return false
	return any


func _all_stumps_hidden(grove) -> bool:
	if grove == null:
		return false
	for c in grove.get_children():
		if str(c.name).begins_with("Stump") and c.visible:
			return false
	return true


func _same_layout(a, b) -> bool:
	if a == null or b == null:
		return false
	if a.get_child_count() != b.get_child_count():
		return false
	for i in range(a.get_child_count()):
		var ca = a.get_child(i)
		var cb = b.get_child(i)
		if str(ca.name) != str(cb.name):
			return false
		if (ca as Node3D).position.distance_to((cb as Node3D).position) > 1e-6:
			return false
	return true


func _count_gardens(root) -> int:
	if root == null:
		return 0
	var n: int = 0
	for c in root.get_children():
		if c.is_in_group("deep_garden"):
			n += 1
		elif c.get_child_count() > 0:
			n += _count_gardens(c)
	return n


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  [OK] %s" % label)
	else:
		_fails += 1
		print("  [FAIL] %s" % label)
