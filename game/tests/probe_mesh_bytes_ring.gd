## probe_mesh_bytes_ring - the ring byte audit the v8 probe owed.
## The prior RAM audit could only prove LIFECYCLE because
## MEMORY_STATIC does not see mesh vertex data (RenderingServer-side).
## This probe measures the exact BYTES instead, by arithmetic law:
## every Packed* array here has a fixed element width, so summing the
## surface arrays' sizes gives the real GPU-side payload per entry.
##   mesh surface bytes = vertices*12 + normals*12 + colors*16
##                      + uv*8 + indices*4   (float32/int32 element data)
## plus the PROP layer per entry (the holder grafts with the node):
##   each prop child MeshInstance3D pays its own primitive-mesh bytes
##   (v9 law: props SHARE one registry mesh per quantized size class --
##   so the probe reports BOTH ledgers: LOGICAL = per-node bytes as if
##   every mesh were private (the pre-registry cost), PHYSICAL = each
##   distinct mesh resource counted ONCE (what the engine really
##   uploads). The gap IS the sharing win; the registry stats pin it.
## Reports per LIVE face and per RING entry, plus the totals -- the
## honest per-entry byte cost of the warm mesh cache.
## Run:  godot --headless --path game --script res://tests/probe_mesh_bytes_ring.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING: String = "synmergia/world/planet_radius"
const RADIUS := 20000.0
const DRAIN_CAP := 2400

var _globe: Node3D
var _counted := {}  # mesh instance id -> true (PHYSICAL ledger: once)


func _init() -> void:
	call_deferred("_run")


## Bytes of one mesh's arrays. `physical` counts each distinct mesh
## resource exactly once per census (shared registry entries pay at
## their first sighting; repeats read 0).
func _mesh_bytes(m: Mesh, physical: bool = false) -> int:
	if m == null:
		return 0
	if physical:
		var mid: int = m.get_instance_id()
		if _counted.has(mid):
			return 0
		_counted[mid] = true
	var total := 0
	for si in range(m.get_surface_count()):
		var arrays: Array = m.surface_get_arrays(si)
		if arrays == null:
			continue
		var v = arrays[Mesh.ARRAY_VERTEX]
		if v != null:
			total += v.size() * 12
		for slot in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV]:
			var a = arrays[slot]
			if a != null:
				total += a.size() * (16 if slot == Mesh.ARRAY_COLOR else (12 if slot == Mesh.ARRAY_NORMAL else 8))
		var idx = arrays[Mesh.ARRAY_INDEX]
		if idx != null:
			total += idx.size() * 4
	return total


## {mesh_bytes, prop_meshes, mm_instances, node_count} for one tree.
## Both ledgers ride every call: `b` logical, `pb` physical.
func _node_bytes(n: Node) -> Dictionary:
	var out := {"b": 0, "pb": 0, "props": 0, "mmi": 0, "nodes": 0}
	for child in n.get_children():
		out.nodes += 1
		if child is MeshInstance3D:
			out.b += _mesh_bytes(child.mesh)
			out.pb += _mesh_bytes(child.mesh, true)
			out.props += 1
		elif child is MultiMeshInstance3D:
			var mm: MultiMesh = child.multimesh
			if mm != null:
				out.b += _mesh_bytes(mm.mesh)
				out.pb += _mesh_bytes(mm.mesh, true)
				var per: int = 48 + (16 if mm.use_colors else 0)
				out.b += mm.instance_count * per
				out.pb += mm.instance_count * per
				out.mmi += mm.instance_count
		# The holder nests one level deep for grouped props (none
		# today, but the law must not charge deeper trees as free).
		for gc in child.get_children():
			out.nodes += 1
			if gc is MeshInstance3D:
				out.b += _mesh_bytes(gc.mesh)
				out.pb += _mesh_bytes(gc.mesh, true)
				out.props += 1
			elif gc is MultiMeshInstance3D:
				var mm2: MultiMesh = gc.multimesh
				if mm2 != null:
					out.b += _mesh_bytes(mm2.mesh)
					out.pb += _mesh_bytes(mm2.mesh, true)
					var per2: int = 48 + (16 if mm2.use_colors else 0)
					out.b += mm2.instance_count * per2
					out.pb += mm2.instance_count * per2
					out.mmi += mm2.instance_count
	return out


func _live_bytes(st) -> Array:
	var rows: Array = []
	var tot := 0
	var tot_phys := 0
	for face in st.active_faces():
		var mi = st._patches.get(face)
		if mi == null or not is_instance_valid(mi):
			continue
		var mb: int = _mesh_bytes(mi.mesh)
		var mbp: int = _mesh_bytes(mi.mesh, true)
		var holder = mi.get_node_or_null(NodePath("Props%d" % face))
		var pb := 0
		var pbp := 0
		var pn := 0
		var pm := 0
		if holder != null and is_instance_valid(holder):
			var d: Dictionary = _node_bytes(holder)
			pb = d.b
			pbp = d.pb
			pn = d.props
			pm = d.mmi
		rows.append([face, int(st._patch_lvl.get(face, -1)), mb, pb, pn, pm])
		tot += mb + pb
		tot_phys += mbp + pbp
	return [rows, tot, tot_phys]


func _ring_bytes(st) -> Array:
	var rows: Array = []
	var tot := 0
	var tot_phys := 0
	for key in st._mesh_cache_order:
		var e = st._mesh_cache.get(key)
		if e == null:
			continue
		var mi = e.get("mi")
		if mi == null or not is_instance_valid(mi):
			continue
		var mb: int = _mesh_bytes(mi.mesh)
		var mbp: int = _mesh_bytes(mi.mesh, true)
		var pb := 0
		var pbp := 0
		var holder = e.get("holder")
		if holder != null and is_instance_valid(holder):
			var d: Dictionary = _node_bytes(holder)
			pb = d.b
			pbp = d.pb
		rows.append([key, mb, pb])
		tot += mb + pb
		tot_phys += mbp + pbp
	return [rows, tot, tot_phys]


func _drain(st) -> int:
	var n := 0
	while st.pending_derive() > 0 and n < DRAIN_CAP:
		await root.get_tree().physics_frame
		n += 1
	return n


func _run() -> void:
	ProjectSettings.set_setting(RADIUS_SETTING, RADIUS)
	var t0: int = Time.get_ticks_msec()
	var packed: PackedScene = load(GLOBE_SCENE)
	_globe = packed.instantiate()
	root.add_child(_globe)
	await process_frame
	var st = _globe.get("streamer")
	var player = _globe.get("player")
	var planet_center: Vector3 = _globe.get("planet_center")

	var dr0: int = await _drain(st)
	print("BOOT: drained=%d ms=%d" % [dr0, Time.get_ticks_msec() - t0])
	var live_a: Array = _live_bytes(st)
	for row in live_a[0]:
		print("  LIVE face=%d lvl=%d mesh_B=%d props_B=%d props=%d mmi=%d" % [row[0], row[1], row[2], row[3], row[4], row[5]])
	print("LIVE_TOTAL_LOGICAL_B=%d  LIVE_TOTAL_PHYSICAL_B=%d" % [live_a[1], live_a[2]])
	print("REGISTRY entries=%d" % st._prop_mesh_registry.size())
	var ring_a: Array = _ring_bytes(st)
	print("RING_AT_BOOT entries=%d B=%d" % [ring_a[0].size(), ring_a[1]])

	# Walk the streamer to the OPPOSITE hemisphere: every live entry
	# streams out (stashed) and the far set derives. Then walk BACK:
	# the current face's sync load stocks the ring (graft) and the
	# neighbors consume their stash in the applier.
	var pdir: Vector3 = (player.global_position - planet_center).normalized()
	var opp: Vector3 = -pdir
	t0 = Time.get_ticks_msec()
	st.update(opp * RADIUS)
	var dr1: int = await _drain(st)
	print("FAR: drained=%d ms=%d ring_entries=%d" % [dr1, Time.get_ticks_msec() - t0, st._mesh_cache_order.size()])
	var far_live: Array = _live_bytes(st)
	for row in far_live[0]:
		print("  FAR-LIVE face=%d lvl=%d mesh_B=%d props_B=%d" % [row[0], row[1], row[2], row[3]])
	print("FAR_LIVE_TOTAL_LOGICAL_B=%d  FAR_LIVE_TOTAL_PHYSICAL_B=%d" % [far_live[1], far_live[2]])
	print("REGISTRY entries=%d" % st._prop_mesh_registry.size())
	var ring_b: Array = _ring_bytes(st)
	for row in ring_b[0]:
		print("  RING %s mesh_B=%d props_B=%d" % [row[0], row[1], row[2]])
	print("RING_TOTAL_LOGICAL_B=%d  RING_TOTAL_PHYSICAL_B=%d" % [ring_b[1], ring_b[2]])

	t0 = Time.get_ticks_msec()
	st.update(pdir * RADIUS)
	var dr2: int = await _drain(st)
	var ring_c: Array = _ring_bytes(st)
	print("BACK drained=%d ms=%d ring=%d B=%d live=%d" % \
		[dr2, Time.get_ticks_msec() - t0, ring_c[0].size(), ring_c[1], st.patch_count()])
	quit(0)
