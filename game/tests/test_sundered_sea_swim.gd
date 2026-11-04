# test_sundered_sea_swim.gd - S14.7.2: the deep garden gets a world AND
# a body (labs/prd-ocean-depths.md sec 3, 8-10).
#
#   A. THE BEDS ARE REAL: the streamer's authored strait beds resolve
#      through the chart onto the sea sphere, and every bed's own face
#      owns it -- the same lookup at registration and draw time, so the
#      gather you see is the gather you can take. A face can own more
#      than one bed (the chart is not face-aligned); each bed keeps its
#      own identity.
#   B. THE DRAW: a shelf bed paints fourteen kelp strands + reef
#      boulders, a trench bed paints six vent spires + drowned stones,
#      each with a material; a face with no bed paints nothing.
#   C. THE GATHER: registration produces three live HarvestService
#      nodes per bed, seed-stable ids, at the authored depth band (kelp
#      30-45, pearl 50-58) on the res_ ids the S14.7.1 economy reads,
#      with the SEA LINE from OceanService (not a second derivation).
#   D. THE BODY: globe_player's sea step hands the body to the water --
#      a dry body keeps the walk (false), a body 38 m down returns true,
#      floats toward the waterline, and carries the volume's current
#      (the ferry lane) at its declared flow.
#
# Script mode law: autoloads at runtime (HarvestService, OceanService);
# the streamer (RefCounted), player and terrain scripts load in the
# body, never preloaded.
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)


func _run() -> void:
	print("=== SUNDERED SEA SWIM RECEIPT (S14.7.2) ===")
	var FP = load("res://core/frame/math/icosahedral_faces.gd")
	var Chart = load("res://core/services/strait_chart.gd")
	var streamer_script = load("res://scenes/worlds/globe_terrain_streamer.gd")
	var os = root.get_node_or_null("OceanService")
	var hs = root.get_node_or_null("HarvestService")
	_check("OceanService present", os != null)
	_check("HarvestService present", hs != null)
	if os == null or hs == null:
		_finish("MISSING AUTOLOAD")
		return
	os.ensure_loaded()
	var sea_r: float = os.sea_surface_radius()
	_check("sea line is the radial law", sea_r > 20000.0)

	var streamer = streamer_script.new()
	streamer.terrain_on = true
	streamer.world_seed = _world_seed()
	var beds: Array = streamer.DEEP_BEDS
	_check("six authored beds", beds.size() == 6)

	# --- A. BEDS AND THEIR OWNING FACES -----------------------------------
	var owned_total := 0
	var face_beds: Dictionary = {}   # face -> Array of bed indices
	var shelf_face: int = -1
	var trench_face: int = -1
	for f in range(20):
		var mine: Array = streamer._deep_beds_for_face(f)
		if not mine.is_empty():
			face_beds[f] = mine
		owned_total += mine.size()
		for bed in mine:
			if int(bed["kind"]) == 1 and shelf_face < 0:
				shelf_face = f
			elif int(bed["kind"]) == 2 and trench_face < 0:
				trench_face = f
	_check("every authored bed is owned exactly once", owned_total == beds.size())
	_check("the beds land on real faces", face_beds.size() > 0)
	_check("a shelf face and a trench face resolve", shelf_face >= 0 and trench_face >= 0)
	var empty_face: int = -1
	for f in range(20):
		if not face_beds.has(f):
			empty_face = f
			break
	_check("a non-bed face exists", empty_face >= 0)
	_check("non-bed face owns no bed", streamer._deep_beds_for_face(empty_face).is_empty())

	# --- B. THE DRAW ------------------------------------------------------
	var shelf_beds: Array = face_beds.get(shelf_face, [])
	var trench_beds: Array = face_beds.get(trench_face, [])
	var shelf_kind: int = _count_kind(shelf_beds, 1)
	var trench_kind: int = _count_kind(trench_beds, 2)
	var shelf_node := Node3D.new()
	streamer._apply_sundered_deep(shelf_face, shelf_node)
	_check("shelf face paints one garden per bed", shelf_node.get_child_count() == shelf_beds.size())
	_check("shelf gardens are named for their face and bed",
		shelf_node.get_child_count() > 0 and str(shelf_node.get_child(0).name).begins_with("DeepGarden%d_" % shelf_face))
	_check("shelf paints fourteen kelp strands", _count_material(shelf_node, streamer._kelp_material()) == 14 * shelf_kind)
	_check("shelf paints reef boulders", _count_material(shelf_node, streamer._reef_material()) > 0)
	shelf_node.queue_free()
	var trench_node := Node3D.new()
	streamer._apply_sundered_deep(trench_face, trench_node)
	var spires := 0
	for child in _all_meshes(trench_node):
		if str(child.name).begins_with("Spire"):
			spires += 1
	_check("trench paints six vent spires per bed", spires == 6 * trench_kind)
	_check("trench face draws only its own shelf kelp", _count_material(trench_node, streamer._kelp_material()) == 14 * _count_kind(trench_beds, 1))
	trench_node.queue_free()
	var empty_node := Node3D.new()
	streamer._apply_sundered_deep(empty_face, empty_node)
	_check("non-bed face draws nothing", empty_node.get_child_count() == 0)
	empty_node.queue_free()

	# --- C. THE GATHER ----------------------------------------------------
	streamer._register_sundered_deep(shelf_face)
	streamer._register_sundered_deep(trench_face)
	var kelp_ids: Array = []
	var pearl_ids: Array = []
	for nid in hs.node_ids():
		if str(nid).begins_with("deep_kelp"):
			kelp_ids.append(str(nid))
		elif str(nid).begins_with("deep_pearl"):
			pearl_ids.append(str(nid))
	_check("shelf beds register three kelp nodes each", kelp_ids.size() == 3 * shelf_kind)
	_check("trench beds register three pearl nodes each", pearl_ids.size() == 3 * trench_kind)
	var kelp_ok := true
	for nid in kelp_ids:
		var node: Dictionary = hs._nodes.get(nid, {})
		if node.is_empty() or str(node.get("item_id", "")) != "res_kelp_fiber":
			kelp_ok = false
		elif float(node.get("min_depth_m", 0.0)) != 30.0 or float(node.get("max_depth_m", 0.0)) != 45.0:
			kelp_ok = false
		else:
			var depth: float = sea_r - (node.get("pos", Vector3.ZERO) as Vector3).length()
			if depth < 29.0 or depth > 46.0:
				kelp_ok = false
	_check("kelp nodes sit on the sea line in the 30-45 band", kelp_ok)
	var pearl_ok := true
	for nid in pearl_ids:
		var node2: Dictionary = hs._nodes.get(nid, {})
		if node2.is_empty() or str(node2.get("item_id", "")) != "res_abyss_pearl":
			pearl_ok = false
		elif float(node2.get("min_depth_m", 0.0)) != 50.0 or float(node2.get("max_depth_m", 0.0)) != 58.0:
			pearl_ok = false
		else:
			var depth2: float = sea_r - (node2.get("pos", Vector3.ZERO) as Vector3).length()
			if depth2 < 49.0 or depth2 > 59.0:
				pearl_ok = false
	_check("pearl nodes sit on the sea line in the 50-58 band", pearl_ok)
	var before: int = kelp_ids.size()
	streamer._register_sundered_deep(shelf_face)
	var after: int = 0
	for nid in hs.node_ids():
		if str(nid).begins_with("deep_kelp"):
			after += 1
	_check("re-registering a face keeps the same nodes", after == before)

	# --- D. THE BODY ------------------------------------------------------
	var player = load("res://entities/globe_player.gd").new()
	root.add_child(player)
	player.entity_id = "sea_receipt_body"
	var up: Vector3 = Chart.dir_from_chart(0.45, 0.0).normalized()
	# Dry: far above the sea line.
	player.global_position = up * (sea_r + 25.0)
	_check("a dry body keeps the walk", not player._sea_swim_step(0.2, up, Vector3.ZERO))
	_check("a dry body is not wet-flagged", not player._sea_wet)
	# The shelf's own depth, inside the world sea volume.
	player.global_position = up * (sea_r - 38.0)
	var swam: bool = player._sea_swim_step(0.2, up, Vector3.ZERO)
	_check("a body 38 m down is taken by the water", swam)
	_check("the body reads the swim band", player._sea_band >= 2)
	_check("the body reads its depth", absf(player._sea_depth - 38.0) < 0.5)
	var flow: Vector3 = os.current_at(player.global_position)
	_check("the volume declares its ferry current", flow.length() > 0.4)
	_check("the sea law carries the body at the volume's flow", player._sea_carry.distance_to(flow) < 0.01)
	_check("the body floats upward when idle", player.velocity.dot(up) > 0.0)
	_check("the current runs along the RUN tangent", flow.normalized().dot(_run_dir()) > 0.95)
	# A current-immune breather reads ZERO from the service (one seam).
	_check("current immunity zeroes the flow", os.effective_current(player.global_position, true) == Vector3.ZERO)
	# Forgetting: back to dry clears the swimmer book.
	player.global_position = up * (sea_r + 25.0)
	player._sea_swim_step(0.2, up, Vector3.ZERO)
	_check("leaving the water clears the swimmer book", os.swim_state("sea_receipt_body") == null)
	player.queue_free()

	_finish("SUNDERED SEA SWIM RECEIPT")


func _count_kind(beds: Array, kind: int) -> int:
	var n := 0
	for bed in beds:
		if int(bed["kind"]) == kind:
			n += 1
	return n


func _all_meshes(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_all_meshes(child))
	return out


func _count_material(node: Node, mat) -> int:
	var n := 0
	for child in _all_meshes(node):
		if child.material_override == mat:
			n += 1
	return n


func _world_seed() -> PackedByteArray:
	var wd = load("res://data/worlds/world_main.tres")
	if wd != null and "seed" in wd:
		return wd.seed
	return PackedByteArray()


func _run_dir() -> Vector3:
	var BS = load("res://scenes/worlds/backend_sundered.gd")
	return (BS.RUN_DIR as Vector3).normalized()


func _finish(label: String) -> void:
	print("=== %s: %d checks, %d failed ===" % [label, _checks, _fails])
	if _fails == 0:
		print("SUNDERED SEA SWIM RECEIPT PASSED")
		quit(0)
	else:
		print("SUNDERED SEA SWIM RECEIPT FAILED")
		quit(1)
