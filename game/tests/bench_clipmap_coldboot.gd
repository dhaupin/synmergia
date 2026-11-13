## bench_clipmap_coldboot - the cold-boot cost of the CLIPMAP renderer.
## ONE BOOT PER PROCESS (the terrain sector caches are process-static, so
## a second build in the same process is WARM and not comparable).
##
## Reports:
##   BUILD_ALL_MS  - clipmap.build_all() wall ms (the cold build)
##   VERT_DERIVES  - distinct ground_sample derives the build paid
##   CAP_MS / RING_MS[L] - per-stage wall ms
##   SAMPLE_COLD_US - a fresh (never-seen) ground_sample cold cost
##   SAMPLE_WARM_US - a re-read of the same direction (memo hit)
##   VERTEX_COUNT  - cap + ring vertices the mesh holds
##
## Run: godot --headless --path game --script res://tests/bench_clipmap_coldboot.gd
extends SceneTree

const CLIPMAP := "res://scenes/worlds/globe_clipmap.gd"
const TerrainGen := preload("res://scenes/worlds/terrain_gen.gd")
const RADIUS := 20000.0

var _globe: Node = null


func _init() -> void:
	call_deferred("_run")


func _fresh_dir(i: int) -> Vector3:
	# Fibonacci sphere rotated per bench so every call is a fresh sector.
	var ga: float = PI * (3.0 - sqrt(5.0))
	var y: float = 1.0 - 2.0 * (float(i) + 0.5) / 4096.0
	var r: float = sqrt(maxf(0.0, 1.0 - y * y))
	var th: float = ga * float(i)
	var v := Vector3(cos(th) * r, y, sin(th) * r)
	return (v + Vector3(0.137, 0.211, 0.093) * float(i)).normalized()


func _seed() -> PackedByteArray:
	var s := PackedByteArray()
	for i in range(8):
		s.append((i * 37 + 11) & 0xFF)
	return s


func _run() -> void:
	var seed_b: PackedByteArray = _seed()
	# A/B leg: ASYNC_MESH=off forces the serial cold build (the gate the
	# parallel path reads), so both laws run in the same bench.
	var leg: String = OS.get_environment("ASYNC_MESH")
	if leg != "":
		ProjectSettings.set_setting("synmergia/world/async_mesh", leg != "off")

	# -- cold per-sample cost (fresh sectors, no warm memo) --
	var n: int = 512
	var t0: int = Time.get_ticks_usec()
	for i in range(n):
		TerrainGen.ground_sample(_fresh_dir(i), seed_b)
	var cold_us: float = float(Time.get_ticks_usec() - t0) / float(n)
	var d0: Vector3 = _fresh_dir(999999)
	TerrainGen.ground_sample(d0, seed_b)
	t0 = Time.get_ticks_usec()
	for i in range(n):
		TerrainGen.ground_sample(d0, seed_b)
	var warm_us: float = float(Time.get_ticks_usec() - t0) / float(n)

	# -- the clipmap cold build --
	var holder := Node3D.new()
	root.add_child(holder)
	var st = load(CLIPMAP).new()
	st.configure(RADIUS, 7.0, holder)
	st.terrain_on = true
	st.world_seed = seed_b
	st._last_player_dir = TerrainGen.SPAWN_CENTER
	var build_ms: int = st.build_all()

	var verts: int = 0
	if st._cap_mesh != null and st._cap_mesh.mesh != null:
		verts += (st._cap_mesh.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	for lvl in range(st._ring_meshes.size()):
		var mi = st._ring_meshes[lvl]
		if mi != null and mi.mesh != null:
			verts += (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()

	print("BENCH_CLIPMAP_COLD:")
	print("  BUILD_ALL_MS=%d" % build_ms)
	print("  VERTEX_COUNT=%d" % verts)
	print("  TRIS=%d" % st.triangle_count())
	print("  GEO_HASH=%d" % _geo_hash(st))
	print("  SAMPLE_COLD_US=%.1f" % cold_us)
	print("  SAMPLE_WARM_US=%.1f" % warm_us)
	print("  EST_DISTINCT_DERIVES=%d" % int(round(float(build_ms) * 1000.0 / maxf(1.0, cold_us))))
	quit(0)


## A content hash over every installed ring/cap mesh vertex array -- the
## determinism tie: serial and parallel builds must hash identically.
func _geo_hash(st) -> int:
	var h: int = 0
	var order: Array = ["cap"]
	for lvl in range(st.N_LEVELS):
		order.append(lvl)
	for key in order:
		var mi = st._cap_mesh if (key is String) else st._ring_meshes[int(key)]
		if mi == null or mi.mesh == null:
			continue
		var arrays: Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in range(v.size()):
			h = (h * 1000003 + int(v[i].x * 1000.0)) & 0x7FFFFFFF
			h = (h * 1000003 + int(v[i].y * 1000.0)) & 0x7FFFFFFF
			h = (h * 1000003 + int(v[i].z * 1000.0)) & 0x7FFFFFFF
	return h
