## GlobeTerrainStreamer - icosahedral face patch streaming (S5b)
## The planet's visuals stream as 20 spherical-triangle REGIONS (the
## icosahedron faces, via IcosahedralFaces). The active set is always
## the player's current face plus its 3 edge-neighbors (max 4 patches);
## crossing a face border swaps exactly the stale patches out.
## Visual-only: the globe's sphere StaticBody stays the physics truth
## at prototype scale; at planet scale the globe scene's re-anchored
## surface pad carries the collision (see globe_world._build_surface_pad).
##
## TERRAIN ARC (v2): patches are no longer flat. Each tile vertex is
## displaced radially by TerrainGen.terrain_height -- the seeded
## heightfield (one big continent, hills, inland mountains, a lake,
## the offshore island plateau, an ocean floor). Props pose onto the
## displaced surface, boulders join as big climbable colliders, and
## the scene reads walk_surface_h() for the pad lift and the snap
## provider, so visuals and physics share ONE ground law.
## S8 FLOATING ORIGIN: patches are planet-relative children of the
## scene's world_root, and all patch vertices are LOCAL to the patch
## node (world-space vertices at |r| ~20 km silently break Godot's
## physics import even for visuals-adjacent paths; rendering is fine).
## RefCounted helper (preloaded by the globe scene; no autoload).
extends RefCounted

const FacePatches = preload("res://core/frame/math/icosahedral_faces.gd")
const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
## One-law prop collision + climbable registration (play-day:
## "stuff shouldn't be walk-through"). RefCounted helper, no autoload.
const PropCollider = preload("res://entities/prop_collider.gd")

## Tiles render just above the scene's visual sphere shell (which sits
## at radius + SKIN_THICKNESS = +0.5) so they never hide inside it.
## Mirrored by globe_world.STREAMER_TILE_LIFT (spawn / snap / pad).
const TILE_LIFT: float = 0.52

## WATER (terrain arc): at planet scale the scene paints a water shell
## at the terrain sea line. Patches below the waterline dim to a wet
## seabed tint (foreshortening cheat: the shell renders the water
## body; the dimmed ground reads as depth through it).
const WATER_ON: bool = true
## Height-band tints (read like a map): deep seabed -> sand -> grass
## -> forest green -> rock -> snow.
const TINT_DEEP: Color = Color(0.24, 0.30, 0.34)
const TINT_SAND: Color = Color(0.62, 0.55, 0.40)
const TINT_GRASS: Color = Color(0.34, 0.52, 0.30)
const TINT_FOREST: Color = Color(0.22, 0.42, 0.24)
const TINT_ROCK: Color = Color(0.44, 0.42, 0.40)
const TINT_SNOW: Color = Color(0.88, 0.90, 0.93)

signal face_changed(old_face: int, new_face: int)
signal patch_loaded(face: int)
signal patch_unloaded(face: int)

var radius: float = 100.0
## Target patch tile edge in meters; subdivision level derives from it.
var target_patch_edge: float = 7.0

var current_face: int = -1
var parent: Node3D
## World seed bytes for deterministic content (TerrainGen).
var world_seed: PackedByteArray = PackedByteArray()

var _patches := {}  # int face -> MeshInstance3D
var _face_tints := {}  # int face -> Color (deterministic per face)
var _patch_rocks := {}  # int face -> Array of rock MeshInstance3D
var _patch_boulders := {}  # int face -> Array of boulder MeshInstance3D
var _patch_mats := {}  # int face -> StandardMaterial3D (per-face cache)
## Terrain arc: the heightfield displaces tile vertices when on
## (planet scale -- the scene flips it; prototype stays the flat
## shell so every S5b/S8 probe contract keeps its geometry).
var terrain_on: bool = false


## The wade law's seam (globe_player.terrain_on_local resolves this
## up the parent chain): one truthful answer, no re-derivation.
func terrain_on_flag() -> bool:
	return terrain_on
var _patch_walk_h := {}  # int face -> Callable(dir) -> walk height

## ---- Terrain LOD (distance-based patch levels) ---------------------------
## The NEAR law replaces the ownership law: a patch stays FULL detail
## while its ground reaches within LOD_NEAR_ANG of the player; it
## drops LOD_NEIGHBOR_DROP levels otherwise (at streaming distance
## those patches are horizon geometry). The ownership law (face ==
## current_face) is NOT the gate: the spawn shore (lat 0, lon 0) sits
## EXACTLY on the equatorial edge two faces share (their center dots
## agree to 15 decimals), so a micron of drift flips which face the
## player "owns" -- and with an ownership gate, the flip DEMOTES the
## face the boot plaza lives in (the plaza-resolution pin failed in
## exactly that way). Angular, scale-free: one law for every radius.
## The walk law is untouched by the level: walk_surface_h() reads
## the analytic heightfield, never the mesh, so coarser patches can
## never desync physics.
var lod_on: bool = true
const LOD_NEIGHBOR_DROP: int = 1
const LOD_MIN_LEVEL: int = 2
## NEAR threshold (radians): face-center distance minus the face's own
## angular reach (the largest center-angle among its vertices) <= this
## means SOME ground of the face is within one tile-edge of standing
## next to the player. One tile edge at unit sphere ~ the icosahedron
## edge chord 1.0515 (the same constant _level_for_edge uses; over
## radius R the ground distance is 1.0515 * R_at_edge / 2^level, so
## the near band rides the CURRENT level, not a world-size constant).
## TWO bands (the hysteresis repair): PROMOTE when the face enters
## the inner band; DEMOTE only after leaving the outer band for
## LOD_FAR_TICKS consecutive updates. A player loitering ON the old
## single band edge flipped a face in/out every frame -- the reload
## seam re-created the patch (its rocks/trees/boulders respawned)
## several times a second. Now: an intermediate band means NO law
## change at the edge, and a dwell means a slow walk cannot pump
## reloads either. Promote is always instant (detail underfoot wins).
const LOD_NEAR_BAND: float = 1.0515 * 1.05  # a hair past one tile edge
const LOD_HYSTERESIS_MARGIN: float = 0.35   # outer band = inner x (1 + margin)
const LOD_FAR_TICKS: int = 12               # ~0.2 s of consecutive far frames
var _patch_lvl := {}  # int face -> int (the level the mesh was built at)
var _patch_far_ticks := {}  # int face -> int (consecutive far frames)
var _face_reach_cache := {}  # int face -> float (center-angle reach, radians)

## Skirts (the T-junction repair): every patch's PERIMETER edges get
## a drop strip on mesh surface 1 (cull-disabled) hanging SKIRT_DEPTH
## below the surface. Where a level-5 neighbor abuts a level-6, the
## coarse neighbor skips the midpoint vertices the fine mesh splits
## -- the horizon reads a one-triangle LIGHT-COLORED CRACK to the
## base shell underneath. The skirt paints that gap with ground-
## colored geometry cheaper than crack-filling per seam (which needs
## neighbor-aware stitching across reloads). Skirts cost 6 verts per
## perimeter tile edge (~2 tri per edge); the main surface (0) keeps
## its exact vertex law (the probes' radial-line contract).
const SKIRT_TAPER_SAMPLES: int = 3      # interior arc probes per border edge
const SKIRT_MIN_DEPTH_FACTOR: float = 0.05  # clamp floor (x tile edge)
const SKIRT_MAX_DEPTH_FACTOR: float = 0.85  # clamp ceiling (x tile edge)
var _patch_skirt_tris := {}  # int face -> int (surface-1 tri count)
var _patch_water_tris := {}  # int face -> int (surface-2 tri count, v3 slice 3)
## The prop holder per face (the hot-reload graft): rocks/boulders/
## trees live under it, so a mesh-level rebuild moves them wholesale
## (colliders, climb groups, and services keyed on those bodies never
## notice the swap).
var _prop_holders := {}  # int face -> Node3D
## The skirt material (same vertex-color albedo, cull DISABLED -- the
## strip's outward winding is ambiguous along the three border arcs;
## a double-sided strip is airtight whatever order the endpoints sit
## in). Cached per face like the ground material.
var _skirt_mats := {}  # int face -> StandardMaterial3D


## Wire the streamer to a scene. Call before the first update().
## Ground support is NOT the streamer's job: at planet scale the globe
## scene's re-anchored surface pad carries collision (single authority
## for physics; the streamer stays visual-only).
func configure(p_radius: float, p_target_edge: float, p_parent: Node3D) -> void:
	radius = p_radius
	target_patch_edge = p_target_edge
	parent = p_parent
	world_seed = TerrainGen.world_seed_bytes()
	terrain_on = false


## Call every physics frame with the player position. Loads the
## current face + neighbors, unloads stale patches, emits signals on
## changes. Returns a stats dict for probes/tests. The LOD law: a
## live patch whose demanded level differs from its built level is
## reloaded at the demanded level (the SAME load/unload seam, so a
## patch's mesh never 'mutates' in place under the camera).
func update(player_pos: Vector3) -> Dictionary:
	# player_pos must be PLANET-RELATIVE (the globe scene passes
	# player.global_position - planet_center). Planet-relative coords
	# are invariant under floating-origin shifts, so face addressing
	# never sees the shift at all.
	var f: int = FacePatches.face_for_position(player_pos, radius)
	var player_dir: Vector3 = player_pos.normalized()  # the NEAR law's direction (not the face center)
	var lod_changed: Array = []
	if f == current_face:
		_lod_enforce(player_dir, lod_changed)
		return {"face": f, "loaded": lod_changed, "unloaded": [], "active": _patches.keys()}
	var old: int = current_face
	current_face = f

	var want := {f: true}
	for n in FacePatches.neighbors(f):
		want[n] = true

	var loaded: Array = []
	var unloaded: Array = []
	for face in want:
		if not _patches.has(face):
			_load_patch(face, _demanded_level(face, player_dir, int(_patch_lvl.get(face, -1))))
			loaded.append(face)
	_lod_enforce(player_dir, loaded)
	for face in _patches.keys():
		if not want.has(face):
			_unload_patch(face)
			unloaded.append(face)
	if old >= 0:
		face_changed.emit(old, f)
	return {"face": f, "loaded": loaded, "unloaded": unloaded, "active": _patches.keys()}


## Number of live patch nodes (steady state: 4).
func patch_count() -> int:
	return _patches.size()


func is_loaded(face: int) -> bool:
	return _patches.has(face)


## -- Terrain arc ground law --------------------------------------------

## The WALK SURFACE (meters above the base shell) at world direction
## `dir`: the displaced terrain (terrain arc, planet scale) with the
## small-rock walk-over caps on top. Boulder tops are NOT included:
## boulders block (their collider carries that) and are climbed, not
## ridden. The scene feeds this to the pad lift and the snap provider
## -- one ground law for visuals and physics.
func walk_surface_h(dir: Vector3) -> float:
	var d: Vector3 = dir.normalized()
	var face: int = FacePatches.face_for_direction(d)
	if not is_loaded(face):
		# Not streamed (should not happen: the walker streams its own
		# face): the analytic terrain alone is still the truth.
		var base: float = TerrainGen.terrain_height(d, world_seed) if terrain_on else 0.0
		return base
	return _patch_walk_h[face].call(d)


## Terrain height at a direction, live value of the streamer's flag.
func terrain_h(dir: Vector3) -> float:
	return TerrainGen.terrain_height(dir.normalized(), world_seed) if terrain_on else 0.0


## All live face ids.
func active_faces() -> Array:
	return _patches.keys()


var _patch_tris := {}


## Total triangles across live patches (probe/observability).
func triangle_count() -> int:
	var total := 0
	for face in _patch_tris:
		total += _patch_tris[face]
	return total


# -- internals ---------------------------------------------------------

### LOD level for a face under the NEAR law: full detail while the
## face's ground reaches within LOD_NEAR_BAND * one tile edge of the
## player direction; dropped levels past that (clamped to the floor).
## `level` is the player's OWN face's level, so the near band scales
## with detail: finer tiles draw a finer near-faces band.
## Legacy one-band law: callers that want the instant decision (no
## dwell) delegate to the two-band version with hysteresis collapsed.
func _level_for_face(face: int, player_dir: Vector3, level: int) -> int:
	if not lod_on or not terrain_on:
		return level
	var base: int = _level_for_edge()
	var reach: float = _face_reach(face)
	var center_ang: float = FacePatches.angular_distance_to_center(player_dir, face)
	if center_ang <= reach + _near_band(base):
		return base
	return maxi(LOD_MIN_LEVEL, base - LOD_NEIGHBOR_DROP)


## A face's angular reach: the largest center-angle over its three
## vertices (the maximum ground distance from the center direction to
## any point of the face, in radians on the unit sphere).
func _face_reach(face: int) -> float:
	if _face_reach_cache.has(face):
		return _face_reach_cache[face]
	var center: Vector3 = FacePatches.face_center(face)
	var best := 0.0
	for vi in FacePatches.face_vertices(face):
		best = maxf(best, center.angle_to(Icosahedral.VERTICES[vi]))
	_face_reach_cache[face] = best
	return best


## The player-adjacent band (radians): one tile edge ON THE CURRENT
## LEVEL, measured on the unit sphere. Tile edge chord is 1.0515 /
## 2^level over the face radius; the player's own face's reach is
## 2x its tile edge, so a chord-based band keeps the arithmetic
## sphere-local and scale-free.
func _near_band(level: int) -> float:
	return LOD_NEAR_BAND / float(1 << maxi(level, 1))


## Enforce the LOD law on every live patch: a patch whose built level
## differs from its demanded level is rebuilt at the demanded level
## (load/unload seam, never in-place mutation). Neighbors demote in
## the SAME frame they enter the active set (want-time _load_patch
## already built them at the demanded level); this sweep catches a
## stale patch after a re-promote (e.g. a face re-becoming the
## current one must climb back to full detail).
func _lod_enforce(player_dir: Vector3, out_loaded: Array) -> void:
	if not lod_on or not terrain_on:
		return
	for face in _patches.keys():
		var cur: int = int(_patch_lvl.get(face, -1))
		var want_lvl: int = _demanded_level(face, player_dir, cur)
		if want_lvl != cur:
			# HOT PATH: level changes rebuild ONLY the mesh; the prop
			# holder (rocks/trees/boulders/colliders) grafts across
			# corpse-free. The cold path (full spawn) only fires when the
			# hot path has no holder (a true unload/visit cycle).
			_load_patch(face, want_lvl)
			out_loaded.append(face)


## The demanded level for `face`, now WITH hysteresis (`cur` = the
## level built so far): PROMOTE instantly when the face enters the
## inner near band; DEMOTE only when it has LEFT the outer band for
## LOD_FAR_TICKS consecutive frames; between the bands (or before the
## dwell elapses) the CURRENT level stands -- the edge cannot pump
## reloads. `demote_floor` keeps the clamp honest while dwelling.
func _demanded_level(face: int, player_dir: Vector3, cur: int = -1) -> int:
	var base: int = _level_for_edge()
	if not lod_on or not terrain_on:
		return base
	var reach: float = _face_reach(face)
	var center_ang: float = FacePatches.angular_distance_to_center(player_dir, face)
	var band_in: float = _near_band(base)
	var band_out: float = band_in * (1.0 + LOD_HYSTERESIS_MARGIN)
	var floor_lvl: int = maxi(LOD_MIN_LEVEL, base - LOD_NEIGHBOR_DROP)
	if center_ang <= reach + band_in:
		_patch_far_ticks.erase(face)
		return base
	if center_ang > reach + band_out and cur > floor_lvl:
		var ticks: int = int(_patch_far_ticks.get(face, 0)) + 1
		if ticks >= LOD_FAR_TICKS:
			_patch_far_ticks.erase(face)
			return maxi(LOD_MIN_LEVEL, base - LOD_NEIGHBOR_DROP)
		_patch_far_ticks[face] = ticks
		return cur
	# Between the bands (or dwelling): the CURRENT law stands.
	_patch_far_ticks.erase(face)
	return cur if cur >= 0 else base


## ----------------------------------------------------------------
## Hot reload (the pump-vs-repair distinction): the dwell removed the
## PUMP (constant flip-flopping), but a level change still paid a FULL
## patch reload -- mesh, rocks, trees, boulders, colliders -- every
## near/far crossing. But the props pose onto the ANALYTIC terrain
## (level-independent: `_prop_ground_h` reads the heightfield, never
## the mesh), so a level change has nothing to say about a rock's
## position. The hot path: rebuild ONLY the mesh node; the prop
## holder (packing rock/boulder/tree/law-closure state under one
## child) is MOVED CORPSE-FREE to the fresh mesh node -- colliders,
## climb groups, and services keyed on those bodies never notice.
## A DEMOTION even skips the mesh rebuild's skirt surface only...
## no: skirts depend on the level too, so the mesh rebuild covers
## both; the props stay put through every kind of level change.
## ----------------------------------------------------------------

## The prop holder for a face: one child of the mesh node that packs
## every prop (rocks/boulders/trees) so a mesh-level rebuild can move
## it wholesale. Created on first spawn, re-parented on hot reload.
func _prop_holder(face: int, mesh_node: MeshInstance3D) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Props%d" % face
	if _prop_holders.has(face):
		var old: Node3D = _prop_holders[face]
		if is_instance_valid(old) and old.get_child_count() > 0:
			for child in old.get_children():
				child.get_parent().remove_child(child)
				holder.add_child(child)
		if is_instance_valid(old) and old != holder:
			old.queue_free()
	_prop_holders[face] = holder
	mesh_node.add_child(holder)
	return holder


## FAST path: only the mesh's level changes. Rebuild the mesh node,
## graft the prop holder across, keep every bookkeeping dict the
## props use (rocks/boulders KEEP their arrays and services). Returns
## true when the fast path ran (the caller skips the full spawn).
func _hot_reload(face: int, use_lvl: int) -> bool:
	if not _prop_holders.has(face):
		return false
	var old_mi: MeshInstance3D = _patches.get(face)
	if old_mi == null or not is_instance_valid(old_mi):
		_prop_holders.erase(face)
		return false
	var fresh := _build_mesh(face, use_lvl)
	# Re-parent the holder (props + colliders) corpse-free: the rock
	# positions ride the ANALYTIC law, so they are identical on the
	# fresh node's frame (same center derivation).
	_props_move(face, fresh)
	# Swap in the tree: the old node's under-collider children (props
	# live under the holder only; everything else was mesh surface
	# state) die with the node.
	var at: Node = old_mi.get_parent()
	if at != null:
		at.add_child(fresh)
		fresh.global_transform = old_mi.global_transform if old_mi.is_inside_tree() else fresh.global_transform
	_patches[face] = fresh
	old_mi.queue_free()
	return true


## Move the prop holder onto a fresh mesh node (the ONLY lifecycle
## boundary the hot path touches).
func _props_move(face: int, new_mesh_node: MeshInstance3D) -> Node3D:
	return _prop_holder(face, new_mesh_node)


## Build the patch mesh at a level (the pure geometry; no props, no
## bookkeeping). The full _load_patch now delegates here + spawns.
func _build_mesh(face: int, use_lvl: int) -> MeshInstance3D:
	## One face's MESH at a level (geometry + skirts; no props, no
	## bookkeeping). Returns a node NOT yet in the tree -- the caller
	## decides its parent (cold spawn vs hot swap).
	_patch_lvl[face] = use_lvl
	var fv: PackedInt32Array = FacePatches.face_vertices(face)
	var tile_r: float = radius + TILE_LIFT
	var center: Vector3 = FacePatches.face_center(face) * tile_r
	# WINDING (web play-test round 15): Godot's front face is CLOCKWISE,
	# but the icosahedral face order is COUNTER-clockwise from outside
	# (the math convention) -- corners emit in (0, 2, 1) order.
	var a: Vector3 = Icosahedral.VERTICES[fv[0]].normalized() * tile_r - center
	var b: Vector3 = Icosahedral.VERTICES[fv[2]].normalized() * tile_r - center
	var c: Vector3 = Icosahedral.VERTICES[fv[1]].normalized() * tile_r - center

	var verts: Array = []  # tile corner triples, LOCAL to the patch node
	_subdivide(a, b, c, use_lvl, verts)

	# -- Terrain arc: radial displacement per vertex --------------------
	# Corner directions reconstruct as (v + center).normalized() (the
	# round-5 debris lesson); the cache is keyed on the QUANTIZED
	# globe direction, so shared tile corners read identical heights
	# (no border cracks).
	var dir_h := {}  # Vector3 (quantized globe dir) -> displaced radius
	var sea: float = TerrainGen.sea_level(world_seed)
	## v3 CLIMATE ARC (slice 2): slope for the color law -- the local
	## height gradient per vertex (from the quantized neighbors of the
	## same cache) maps radially to a [0, 1] steep factor.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in verts:
		for i in range(3):
			var v: Vector3 = tri[i]
			var d_abs: Vector3 = (v + center).normalized()
			var r_abs: float = tile_r
			if terrain_on:
				var key: Vector3 = (d_abs * 4096.0).floor()
				if not dir_h.has(key):
					dir_h[key] = tile_r + TerrainGen.terrain_height(d_abs, world_seed)
				r_abs = dir_h[key]
			st.set_normal(d_abs)
			## v3 CLIMATE ARC (slice 2): the BIOME palette owns the terrain-
		## on vertex tint (blend + slope + temperature snowline + wet
		## dimming all in one law); the prototype (terrain off) keeps the
		## S7 face tints. Slope comes from the height cache: gradient of
		## the two nearest sampled neighbors.
			var col: Color = _tint_for(face)
			if terrain_on:
				# Slope: compare vs radial neighbors in the cache.
				var step_m: float = tile_r * 0.0012
				var slope_seed: float = 0.0
				var h_here: float = r_abs - tile_r
				var grad: float = 0.0
				for n_vec in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]:
					var nd: Vector3 = (d_abs + n_vec * 0.0012).normalized()
					var nkey: Vector3 = (nd * 4096.0).floor()
					var nh: float = 0.0
					if not dir_h.has(nkey):
						dir_h[nkey] = tile_r + TerrainGen.terrain_height(nd, world_seed)
					nh = float(dir_h[nkey]) - tile_r
					grad = maxf(grad, absf(nh - h_here))
				slope_seed = clampf(grad / 1.8, 0.0, 1.0)
				col = TerrainGen.vertex_color(d_abs, world_seed, h_here, slope_seed)
			st.set_color(col)
			# Planar UVs wrapped to [0,1) (the round-12 web law).
			st.set_uv(Vector2(fposmod(v.x * 0.0015, 1.0), fposmod(v.z * 0.0015, 1.0)))
			st.add_vertex(d_abs * r_abs - center)
	var mesh: ArrayMesh = st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Patch%d" % face
	var mat: StandardMaterial3D = _patch_mats.get(face)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.95
		mat.albedo_texture = _make_checker_texture()
		mat.uv1_scale = Vector3(1, 1, 1)
		_patch_mats[face] = mat
	mi.set_surface_override_material(0, mat)
	mi.position = center

	# -- Skirts (the T-junction repair, TAPERED) --------------------------
	# Border edges = triangle edges used by exactly ONE triangle. The
	# TAPER law: a flat skirt hid under gentle seams but showed a lip
	# at the MOUNTAINTOP seams (the coarse neighbor's chord misses the
	# fine mesh's sampled bump by the heightfield's real amplitude
	# across the skipped midpoints). Per border edge: sample the
	# heightfield at the UNSAMPLED arc midpoints (the fine level's
	# spacing), take the max deviation from the CHORD formed by the
	# two endpoint heights, and hang the skirt 1.0x that depth (clamped
	# to [MIN, MAX] band: never shallower than a sample step, never
	# deeper than half a coarse tile edge -- the crack's actual need).
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge_use := {}  # String key -> [dir0, dir1, use_count]
	for tri in verts:
		for i2 in range(3):
			var e0: Vector3 = tri[i2]
			var e1: Vector3 = tri[(i2 + 1) % 3]
			var d0: Vector3 = (e0 + center).normalized()
			var d1: Vector3 = (e1 + center).normalized()
			var k0: Vector3 = (d0 * 4096.0).floor()
			var k1: Vector3 = (d1 * 4096.0).floor()
			var ek: String = str(k0) + "|" + str(k1) if k0 < k1 else str(k1) + "|" + str(k0)
			if not edge_use.has(ek):
				edge_use[ek] = [d0, d1, 0]
			edge_use[ek][2] = int(edge_use[ek][2]) + 1
	var skirt_tris: int = 0
	var edge_len: float = 1.0515 * tile_r / float(1 << use_lvl)
	for ek in edge_use:
		if int(edge_use[ek][2]) != 1:
			continue  # interior edge: two triangles share it
		var sd0: Vector3 = edge_use[ek][0]
		var sd1: Vector3 = edge_use[ek][1]
		var sr0: float = float(dir_h.get((sd0 * 4096.0).floor(), tile_r))
		var sr1: float = float(dir_h.get((sd1 * 4096.0).floor(), tile_r))
		# The coarse mesh's chord misses the terrain BY the sampled
		# amplitude along the arc: probe SKIRT_TAPER_SAMPLES interior
		# directions, compare each height to the linear chord estimate.
		var chord_drop: float = absf(sr0 - sr1)
		var bump: float = 0.0
		for si in range(1, SKIRT_TAPER_SAMPLES + 1):
			var t: float = float(si) / float(SKIRT_TAPER_SAMPLES + 1)
			# Slerp-ish midpoint direction: orthonormal-frame lerp on the
			# sphere (slerp() needs the same-length vectors; build it).
			var axis: Vector3 = sd0.cross(sd1)
			if axis.length() > 0.000001:
				axis = axis.normalized()
				var ang: float = sd0.angle_to(sd1)
				var rot_q: Vector3 = sd0.rotated(axis, ang * t)
				var r_mid_base: float = tile_r + TerrainGen.terrain_height(rot_q, world_seed) if terrain_on else tile_r
				var chord_est: float = lerpf(sr0, sr1, t)
				bump = maxf(bump, absf(r_mid_base - chord_est))
			bump = maxf(bump, chord_drop * 0.5)
		# Depth = the missed amplitude x a generous multiplier, clamped.
		var depth: float = clampf(bump * 1.4 + edge_len * SKIRT_MIN_DEPTH_FACTOR, edge_len * SKIRT_MIN_DEPTH_FACTOR, edge_len * SKIRT_MAX_DEPTH_FACTOR)
		var v0: Vector3 = sd0 * sr0 - center
		var v1: Vector3 = sd1 * sr1 - center
		var v0d: Vector3 = sd0 * (sr0 - depth) - center
		var v1d: Vector3 = sd1 * (sr1 - depth) - center
		var c0: Color = _tint_for(face)
		if terrain_on:
			## v3 CLIMATE ARC (slice 2): the skirt's top color rides the
		## SAME biome vertex law (its bottom fades dark like today).
			c0 = TerrainGen.vertex_color(sd0, world_seed, sr0 - tile_r, 0.0)
		var c0d: Color = c0.darkened(0.45)
		st2.set_normal(sd0); st2.set_color(c0); st2.add_vertex(v0)
		st2.set_normal(sd1); st2.set_color(c0); st2.add_vertex(v1)
		st2.set_normal(sd1); st2.set_color(c0d); st2.add_vertex(v1d)
		st2.set_normal(sd0); st2.set_color(c0); st2.add_vertex(v0)
		st2.set_normal(sd1); st2.set_color(c0d); st2.add_vertex(v1d)
		st2.set_normal(sd0); st2.set_color(c0d); st2.add_vertex(v0d)
		skirt_tris += 2
	_patch_skirt_tris[face] = skirt_tris
	if skirt_tris > 0:
		var skirt_mesh: ArrayMesh = st2.commit()
		mi.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, skirt_mesh.surface_get_arrays(0))
		mi.set_surface_override_material(1, _skirt_material(face))
	## v3 HYDROLOGY (slice 3): the WATER SURFACE (surface 2) -- the
	## standing-water law the height law holds (gated table over carved
	## bed), tiled at the patch's own tile triangulation; vertices ABOVE
	## water are dropped (no sheet over dry land). -1e9 dirs are dry:
	## the quad collapses out of the surface.
	var water_tris: int = _water_surface(face, mi, verts, center, dir_h)
	_patch_water_tris[face] = water_tris
	mi.set_meta("tris", verts.size())
	return mi


## The standing-water surface for one patch (surface 2): for every
## tile triangle whose three corners all sit under a gated water
## surface (TerrainGen.hydro_water_surface, the SAME definition the
## biome law reads), emit a horizontal triangle at the table. Mixed
## wet/dry tiles emit nothing yet (barycentric splitting is a later
## pass; the lake SHORE rim reads wet via the biome color -- an
## underwater patch floor + a slightly-too-small pond reads better
## than paper-thin sheets). Returns water tri count (probe/debug).
func _water_surface(face: int, mi: MeshInstance3D, verts: Array, center: Vector3, dir_h: Dictionary) -> int:
	if not terrain_on:
		return 0  # prototype: the shell owns water (no standing lakes yet)
	var t_r: float = radius + TILE_LIFT
	var st_w := SurfaceTool.new()
	st_w.begin(Mesh.PRIMITIVE_TRIANGLES)
	var water_tris := 0
	var cached_surface := {}  # quantized dir -> water surface lift (or -1e9)
	for tri in verts:
		var lifts: Array = []
		var surf: Array = []
		var any_dry := false
		var all_wet := true
		for i in range(3):
			var v: Vector3 = tri[i]
			var d_abs: Vector3 = (v + center).normalized()
			var key: Vector3 = (d_abs * 4096.0).floor()
			if not cached_surface.has(key):
				var table: float = TerrainGen.hydro_water_surface(d_abs, world_seed)
				cached_surface[key] = t_r + table if table > -1e8 else -1e9
			var s_abs: float = float(cached_surface[key])
			var g_r: float = float(dir_h.get(key, t_r))
			var wet: bool = s_abs > -1e8 and s_abs > g_r + TerrainGen.Hydro.BEACH_MIN
			lifts.append(g_r)
			surf.append(s_abs)
			any_dry = any_dry or not wet
			all_wet = all_wet and wet
		if not all_wet or any_dry:
			continue  # dry or shore tile: no sheet (see doc comment)
		# The tile's water plane: average table height (the three
		# gated tables differ by millimeters inside one tile).
		var t_h: float = (float(surf[0]) + float(surf[1]) + float(surf[2])) / 3.0
		# THE WATER TINT (visual polish): the sheet color reads the
		# tile's own climate -- shallow film is pale cyan (rivers/ponds
		# read as running water), depth beyond ~2 m desaturates toward
		# deep blue, the freeze band turns the sheet icy pale, and a
		# swamp basin goes murk green-brown (the biome law chooses).
		var d_mid: Vector3 = ((tri[0] + tri[1] + tri[2]) / 3.0 + center).normalized()
		var g_mid: float = (float(lifts[0]) + float(lifts[1]) + float(lifts[2])) / 3.0 - t_r
		var depth: float = t_h - g_mid
		var wcol: Color = Color(0.72, 0.82, 0.86).lerp( \
			Color(0.42, 0.62, 0.68), clampf(depth / 2.0, 0.0, 1.0))
		if depth > 2.0:
			wcol = wcol.lerp(Color(0.30, 0.44, 0.55), clampf((depth - 2.0) / 4.0, 0.0, 1.0))
		var w_temp: float = TerrainGen.climate_temperature(d_mid, world_seed)
		if w_temp < TerrainGen.SNOWLINE_T:
			wcol = wcol.lerp(Color(0.86, 0.90, 0.94), 0.8)  # frozen sheet
		elif TerrainGen.climate_biome_id(d_mid, world_seed) == TerrainGen.BiomeId.SWAMP:
			wcol = wcol.lerp(Color(0.42, 0.46, 0.30), 0.7)  # the marsh murk
		_emit_water_tri(st_w, tri, center, t_h, wcol)
		water_tris += 1
	if water_tris > 0:
		mi.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st_w.commit())
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.24, 0.42, 0.50)
		wmat.roughness = 0.1
		mi.set_surface_override_material(2, wmat)
	return water_tris


## Emit ONE water triangle for tile `tri` at radius (tile_r + t_h)
## with the tile's own lens color (the water tint law).
func _emit_water_tri(st_w: SurfaceTool, tri: Array, center: Vector3, t_h: float, tint: Color) -> void:
	var grand_r: float = radius + TILE_LIFT + t_h
	var pts: Array = []
	for i in range(3):
		var d_c: Vector3 = (tri[i] + center).normalized()
		pts.append(d_c * grand_r - center)
	var n: Vector3 = ((pts[0] + center) + (pts[1] + center) + (pts[2] + center)).normalized()
	for p in pts:
		st_w.set_normal(n)
		st_w.set_color(tint)
		st_w.add_vertex(p)


## The full lifecycle: mesh at a level + props onto it + bookkeeping
## (cold spawn path; the hot path grafts instead).
func _load_patch(face: int, level: int = -1) -> void:
	if parent == null:
		return
	var use_lvl: int = level if level >= 0 else _level_for_edge()
	if _hot_reload(face, use_lvl):
		patch_loaded.emit(face)
		return
	var mi := _build_mesh(face, use_lvl)
	parent.add_child(mi)
	_patches[face] = mi
	_patch_tris[face] = int(mi.get_meta("tris"))
	mi.remove_meta("tris")
	# Terrain arc: the per-face walk law (level-INDEPENDENT: the
	# closure reads the analytic heightfield, so the hot swap never
	# rewrites it -- physics and visuals hold one ground law through
	# every kind of level change).
	var captured_seed: PackedByteArray = world_seed
	var captured_on: bool = terrain_on
	var captured_radius: float = radius
	var holder := _prop_holder(face, mi)
	_patch_walk_h[face] = func(d: Vector3) -> float:
		var base: float = TerrainGen.terrain_height(d, captured_seed) if captured_on else 0.0
		return base + TerrainGen.rock_top_height(d, captured_seed, face, captured_radius)
	# Props spawn ONCE per face visit (the holder grafted on hot
	# reloads keeps them; the cold path spawns fresh -- the holder is
	# empty there by construction).
	if holder.get_child_count() == 0:
		_spawn_rocks(face)
	patch_loaded.emit(face)


## The skirt material: vertex-color albedo like the ground, rough,
## cull DISABLED (double-sided: one strip, both arcs visible).
func _skirt_material(face: int) -> StandardMaterial3D:
	if _skirt_mats.has(face):
		return _skirt_mats[face]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_skirt_mats[face] = m
	return m


## 64x64 POT grass checker with generated mipmaps. Strict
## GLES3/WebGL2 drivers draw mip-less textures BLACK under a
## mipmap-requiring filter (the round-12 web tiles vanished -- the
## user was looking at the water shell through the hole). The 8x8
## checker cell keeps the walking parallax cue at [0,1) UVs.
func _make_checker_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var cell := ((x / 8) + (y / 8)) % 2 == 0
			img.set_pixel(x, y, Color(0.42, 0.55, 0.30) if cell else Color(0.38, 0.51, 0.27))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Height-band ground color (the map you walk on): seabed through
## snowline. Blend bands overlap so no hard rings. Wet tint below the
## waterline (the shell paints the water; dimmed ground reads as
## depth through it).
## v3 CLIMATE ARC: the BIOME look owns the land palette now -- delegating
## to TerrainGen.vertex_color (biome blend + slope + temperature
## snowline + wet dimming). The band ladder remains for the
## terrain-OFF paths (prototype shell tinting).
func _band_color(lift: float, sea: float) -> Color:
	var c: Color
	if lift < sea - 4.0:
		c = TINT_DEEP
	elif lift < sea - 0.8:
		c = TINT_DEEP.lerp(TINT_SAND, (lift - (sea - 4.0)) / 3.2)
	elif lift < sea + 1.2:
		c = TINT_SAND
	elif lift < sea + 9.0:
		c = TINT_SAND.lerp(TINT_GRASS, (lift - (sea + 1.2)) / 7.8)
	elif lift < sea + 20.0:
		c = TINT_GRASS.lerp(TINT_FOREST, (lift - (sea + 9.0)) / 11.0)
	elif lift < sea + 30.0:
		c = TINT_FOREST.lerp(TINT_ROCK, (lift - (sea + 20.0)) / 10.0)
	else:
		c = TINT_ROCK.lerp(TINT_SNOW, clampf((lift - (sea + 30.0)) / 8.0, 0.0, 1.0))
	if lift < sea - 0.2:
		c = c.darkened(0.45)
	return c


## Seeded rocks + trees + boulders for one face: deterministic
## content (S7), parented under the patch node so unload is free.
## TERRAIN ARC (v2):
##  - every prop poses ONTO the displaced surface (its base rides the
##    terrain law + the small-rock walk-over cap),
##  - props below the waterline are SKIPPED (no kelp forests yet --
##    the shelf is honest water),
##  - BOULDERS join: big climbable colliders (PropCollider.attach)
##    -- they block, the climb law grabs them, and their collar ring
##    of small rocks decorates the base.
## WALK-OVER LAW (unchanged): small rocks stay collider-less; the
## snap provider carries their tops. TUNNEL LAW: nothing is buried;
## tree trunks get colliders via PropCollider.attach_trunk.
func _spawn_rocks(face: int) -> void:
	var specs: Array = TerrainGen.rock_specs(world_seed, face)
	var nodes: Array = []
	# Props live under the PROP HOLDER (not the mesh node): the hot-
	# reload path grafts the holder wholesale, so colliders and climb
	# groups survive every level change (and the probe's boulder audit
	# never holds a corpse). The holder rides the fresh mesh node's
	# transform frame (same center derivation, so prop positions in
	# mesh-local space read identically).
	var patch_node: Node3D = _prop_holder(face, _patches[face])
	# The patch node's offset (same derivation as _load_patch).
	var patch_center: Vector3 = FacePatches.face_center(face) * (radius + TILE_LIFT)
	var sea: float = TerrainGen.sea_level(world_seed)
	var scaled: float = radius + TILE_LIFT
	for s in specs:
		var base_h: float = _prop_ground_h(face, s.dir)
		# WATER SKIP (terrain arc only): no props in the ocean yet. The
		# prototype (terrain off) keeps its S7 greenery untouched.
		if terrain_on and base_h < sea - 0.6:
			continue
		var rmi := MeshInstance3D.new()
		var rmesh := SphereMesh.new()
		rmesh.radius = TerrainGen.ROCK_RADIUS * s.scale
		rmesh.height = rmesh.radius * 2.0
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.45, 0.42, 0.40)
		rmat.roughness = 1.0
		rmesh.material = rmat
		rmi.mesh = rmesh
		# Radial placement: the rock rides its own direction at (scaled
		# + terrain), ROCKS EXCLUDING their own walk-over cap (walk_height
		# would double-count it). At prototype scale (terrain 0) this
		# reduces to the S7 formula exactly (probe-pinned).
		var rock_r: float = scaled + TerrainGen.terrain_height(s.dir, world_seed) if terrain_on else scaled
		rmi.position = _tangent_patch_local(s.dir, patch_center, rock_r + TerrainGen.ROCK_EMBED)
		rmi.rotation.y = s.yaw
		patch_node.add_child(rmi)
		nodes.append(rmi)
	if terrain_on:
		_spawn_boulders(face, patch_node)
	_spawn_trees(face, patch_node)
	_spawn_detail_props(face, patch_node)
	_patch_rocks[face] = nodes
	# One-law collision (play-day: "stuff shouldn't be walk-through"):
	# tree TRUNKS block movement and join the climbable group so the
	# climb law can grab them. Canopies stay intangible (walking under
	# a crown must not feel like a ceiling). Bodies are tree children,
	# so streamed-out faces drop theirs for free.
	for tree in patch_node.get_children():
		if tree is Node3D and str(tree.name).begins_with("Tree"):
			PropCollider.attach_trunk(tree)


## Big climbable boulders (terrain arc): PropCollider-carried, so they
## BLOCK movement and join the climbable group. A decorative collar of
## small rocks (1-2, seeded) decorates the base -- and their walk-over
## caps are already part of the ground law, so the ring never tunnels
## the boulder (a cap rises to >= collar top at the boulder rim).
func _spawn_boulders(face: int, patch_node: Node3D) -> void:
	var specs: Array = TerrainGen.boulder_specs(world_seed, face)
	var nodes: Array = []
	var patch_center: Vector3 = FacePatches.face_center(face) * (radius + TILE_LIFT)
	var scaled: float = radius + TILE_LIFT
	var sea: float = TerrainGen.sea_level(world_seed)
	for s in specs:
		var base_h: float = _prop_ground_h(face, s.dir)
		if base_h < sea - 0.6:
			continue  # boulders are land content (for now)
		var bmi := MeshInstance3D.new()
		var bmesh := SphereMesh.new()
		bmesh.radius = s.radius
		bmesh.height = s.radius * 1.7  # squat, not a perfect ball
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.40, 0.38, 0.37)
		bmat.roughness = 1.0
		bmesh.material = bmat
		bmi.mesh = bmesh
		bmi.name = "Boulder%d" % nodes.size()
		# Sink the squat ellipsoid by ~1/3 radius: a believable embed
		# whose visible top is 1.13*radius above the ground (center sits
		# 0.28*radius above the surface; the lower 0.57*radius is buried).
		# Placement is RADIAL (height baked into the arc distance along
		# the boulder's own direction), and the basis stands the squash
		# axis along the local radial up (world +y is TANGENT at the
		# spawn face -- an identity basis would squash sideways).
		var bdir_r: float = scaled + TerrainGen.terrain_height(s.dir, world_seed) if terrain_on else scaled
		bmi.position = _tangent_patch_local(s.dir, patch_center, bdir_r + s.radius * 0.28)
		var bup: Vector3 = s.dir
		var bhint := Vector3(0, 1, 0)
		if abs(bup.dot(bhint)) > 0.999:
			bhint = Vector3(0, 0, -1)
		var beast: Vector3 = (bhint - bup * bhint.dot(bup)).normalized()
		var bnorth: Vector3 = beast.cross(bup)
		bmi.basis = Basis(beast, bup, bnorth)
		patch_node.add_child(bmi)
		nodes.append(bmi)
		PropCollider.attach(bmi)
		# Decorative collar: 1-2 small rocks at the rim (seeded from the
		# face stream + boulder index -- same fold discipline as rocks).
		var acc: int = 0
		for b in TerrainGen.face_seed_bytes(world_seed, face):
			acc = (acc * 256 + b) % 9007199254740991
		acc = (acc * 131 + nodes.size()) % 9007199254740991
		var rng := RandomNumberGenerator.new()
		rng.seed = acc
		var collar_n: int = rng.randi_range(1, 2)
		for k in range(collar_n):
			var rim_hint: Vector3 = Vector3(0, 1, 0) if abs(s.dir.dot(Vector3(0, 1, 0))) < 0.9 else Vector3(1, 0, 0)
			var rim_axis: Vector3 = s.dir.cross(rim_hint).normalized()
			var rim_dir: Vector3 = s.dir.rotated(rim_axis, \
				(s.radius * 0.95) / maxf(bdir_r, 1.0) + rng.randf_range(0.0, 0.02))
			var crmi := MeshInstance3D.new()
			var crm := SphereMesh.new()
			crm.radius = TerrainGen.ROCK_RADIUS
			crm.height = crm.radius * 2.0
			crm.material = bmat
			crmi.mesh = crm
			crmi.position = _tangent_patch_local(rim_dir, patch_center, bdir_r + TerrainGen.ROCK_EMBED)
			patch_node.add_child(crmi)
	_patch_boulders[face] = nodes


## Trees: BIOME-DRIVEN seeded scatters per face -- trunk cylinder +
## canopy sphere on the displaced surface. TERRAIN ARC: the scatter
## direction (patch-tangent arc placement, like the rocks) rides
## terrain_height; trees below the waterline are skipped and mountain
## tops (above the tree line) grow no trees. SPECIES LAW (slice 4):
## the biome at each site chooses -- FOREST/TAIGA always grow,
## GRASSLAND grows a 40% draw, SHORE 25%, SWAMP 50%; DESERT, TUNDRA
## and ALPINE are past the tree line (nothing). The canopy greens
## shift subtly per tree (same hash family as the face tints).
func _spawn_trees(face: int, patch_node: Node3D) -> void:
	## TREE DRAW-CALL LOD (the harness slice): a tree at the BASE level
	## (NEAR faces) is a real Node3D -- its trunk collider is the
	## walk/climb law. A tree on a DEMOTED face (far/horizon) is pure
	## horizon detail: the SAME deterministic scatter is batched into
	## two MultiMeshInstances (one for trunks, one for canopies),
	## cutting up to 2xN draw calls per far face down to 2 total with
	## zero visual law change (identical transforms, tint range, and
	## seed stream -- the batch is the same trees). Far trunks carry
	## NO collider: the horizon can't be walked to, and the collider
	## law re-arms for free when the face promotes and re-spawns
	## per-tree props.
	var lvl: int = int(_patch_lvl.get(face, -1))
	var base: int = _level_for_edge()
	var batched: bool = lod_on and terrain_on and lvl != -1 and lvl != base
	var bytes: PackedByteArray = TerrainGen.face_seed_bytes(world_seed, face)
	var acc: int = 0
	for b in bytes:
		acc = (acc * 131 + b) % 9007199254740991
	var rng := RandomNumberGenerator.new()
	rng.seed = acc
	var count: int = rng.randi_range(4, 8)
	var verts: PackedInt32Array = FacePatches.face_vertices(face)
	# Scaled patch offset (matches _load_patch), for patch-local trees.
	var patch_center: Vector3 = FacePatches.face_center(face) * (radius + TILE_LIFT)
	var scaled: float = radius + TILE_LIFT
	var sea: float = TerrainGen.sea_level(world_seed)
	# THE STRAIT FREIGHT SEED (quest_shoal_freight): faces whose CENTER
	# lies on the authored corridor chart near the shoal carry Mag's
	# marked crates as gatherable nodes (the quest's world presence the
	# strait owed). Chalk-marked, chamber-dry, always the harvest.
	if terrain_on:
		_register_strait_freight(face, FacePatches.face_center(face).normalized(), world_seed)
	# Batch accumulators (only used when batched).
	var batch_xforms: Array = []
	var canopy_batch_xforms: Array = []
	for i in range(count):
		var v: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var dir: Vector3 = (FacePatches.face_center(face) * 0.55 + v * 0.45).normalized()
		var base_h: float = _prop_ground_h(face, dir)
		# WATER SKIP (terrain arc only; the prototype keeps its S7
		# greenery untouched). THE TREE LINE IS THE BIOME now (the
		# lapse retune made the old flat 24 m cap a mid-altitude tree
		# DROUGHT: temperate foothills above 24 m were treeless while
		# green; the species law below already bars ALPINE/TUNDRA and
		# the hot dry bands).
		if terrain_on and base_h < sea - 0.6:
			continue
		# SPECIES LAW: the biome at the site chooses (water law, desert
		# and pole bands grow; the dry hardpans do not). VARIETY LAW:
		# JUNGLE grows dense like the forest band, SAVANNA grows sparse
		# (30%) -- scattered acacias; STEPPE/BADLANDS stay bare like
		# the high dry bands. The prototype (terrain off) keeps its S7
		# greenery untouched.
		if terrain_on:
			var bid: int = TerrainGen.climate_biome_id(dir, world_seed)
			var draw: float = rng.randf()
			if bid == TerrainGen.BiomeId.FOREST or bid == TerrainGen.BiomeId.TAIGA \
					or bid == TerrainGen.BiomeId.JUNGLE:
				pass  # always grows
			elif bid == TerrainGen.BiomeId.SWAMP:
				if draw > 0.5:
					continue
			elif bid == TerrainGen.BiomeId.GRASSLAND:
				if draw > 0.4:
					continue
			elif bid == TerrainGen.BiomeId.SHORE:
				if draw > 0.25:
					continue
			elif bid == TerrainGen.BiomeId.SAVANNA:
				if draw > 0.3:
					continue
			else:
				continue  # desert / steppe / badlands / tundra / alpine / water: no trees
		var tree_name_idx := i
		var trunk_height: float = rng.randf_range(1.8, 3.2)
		var trunk_radius_top := 0.14
		var trunk_radius_bottom := 0.22
		var trunk_tint := Color(0.36, 0.26, 0.17)
		var crown: float = rng.randf_range(1.1, 2.0)
		var g: float = 0.3 + 0.14 * rng.randf()
		var canopy_tint := Color(0.18 + 0.06 * rng.randf(), g, 0.16)
		var canopy_crown: float = crown
		var canopy_h: float = crown * 1.8
		if batched:
			# BATCHED (far face): accumulate the same deterministic tree
			# into a MultiMesh transform instead of a Node3D. The tree
			# pose math (radial placement + radial-up basis) is shared:
			# compute the tree-local origin/orientation first, then use
			# it for either path.
			var pos: Vector3 = _tangent_patch_local(dir, patch_center, scaled + base_h)
			var up: Vector3 = dir
			var hint0 := Vector3(0, 1, 0)
			if abs(up.dot(hint0)) > 0.999:
				hint0 = Vector3(0, 0, -1)
			var east0: Vector3 = (hint0 - up * hint0.dot(up)).normalized()
			var north0: Vector3 = east0.cross(up)
			var tpose: Transform3D = Transform3D(
				Basis(east0, up, north0).rotated(up, rng.randf_range(0.0, TAU)), pos)
			# Trunk: one shared cylinder mesh, per-instance transform =
			# tree pose x trunk-local offset (scaled by the height).
			batch_xforms.append(tpose * Transform3D(Basis.IDENTITY.scaled(Vector3(1, trunk_height, 1)), Vector3(0, trunk_height * 0.5, 0)))
			# Canopy: shared sphere, per-instance scale = crown.
			canopy_batch_xforms.append(tpose * Transform3D(Basis.IDENTITY.scaled(Vector3(canopy_crown, canopy_h, canopy_crown)), Vector3(0, trunk_height + canopy_crown * 0.55, 0)))
			continue
		var tree := Node3D.new()
		tree.name = "Tree%d" % tree_name_idx
		var trunk := MeshInstance3D.new()
		var tmesh := CylinderMesh.new()
		tmesh.top_radius = trunk_radius_top
		tmesh.bottom_radius = trunk_radius_bottom
		tmesh.height = trunk_height
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = trunk_tint
		tmat.roughness = 1.0
		tmesh.material = tmat
		trunk.mesh = tmesh
		trunk.position = Vector3(0, trunk_height * 0.5, 0)
		tree.add_child(trunk)
		var canopy := MeshInstance3D.new()
		var cmesh := SphereMesh.new()
		cmesh.radius = canopy_crown
		cmesh.height = canopy_h
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = canopy_tint
		cmat.roughness = 1.0
		cmesh.material = cmat
		canopy.mesh = cmesh
		canopy.position = Vector3(0, trunk_height + canopy_crown * 0.55, 0)
		tree.add_child(canopy)
		# Radial placement riding the displaced ground: the walk-surface
		# height (terrain + any rock cap beneath) is baked into the
		# RADIAL distance so the tree rides its own direction exactly
		# (patch-local +y is world up, not surface up).
		tree.position = _tangent_patch_local(dir, patch_center, scaled + base_h)
		# Stand the trunk along the local radial up.
		var up: Vector3 = dir
		var hint := Vector3(0, 1, 0)
		if abs(up.dot(hint)) > 0.999:
			hint = Vector3(0, 0, -1)
		var east: Vector3 = (hint - up * hint.dot(up)).normalized()
		var north: Vector3 = east.cross(up)
		tree.basis = Basis(east, up, north).rotated(up, rng.randf_range(0.0, TAU))
		patch_node.add_child(tree)
	# -- Flush the batch (far faces) ------------------------------------
	if batched and batch_xforms.size() > 0:
		# TRUNKS
		var cu := CylinderMesh.new()
		cu.top_radius = 0.14
		cu.bottom_radius = 0.22
		cu.height = 1.0  # unit: per-instance scale stretches it
		var tmesh2 := MultiMesh.new()
		tmesh2.transform_format = MultiMesh.TRANSFORM_3D
		tmesh2.mesh = cu # Godot: multimesh.mesh takes the source mesh directly
		tmesh2.instance_count = batch_xforms.size()
		for t in range(batch_xforms.size()):
			tmesh2.set_instance_transform(t, batch_xforms[t])
		var tmi := MultiMeshInstance3D.new()
		tmi.name = "BatchedTrunks"
		tmi.multimesh = tmesh2
		var tmt := StandardMaterial3D.new()
		tmt.albedo_color = Color(0.36, 0.26, 0.17)
		tmt.roughness = 1.0
		tmi.material_override = tmt
		patch_node.add_child(tmi)
		# CANOPIES (billboard-style: cheap sphere batch, shared mat)
		var sm := SphereMesh.new()
		sm.radius = 1.0  # unit: per-instance scale = crown
		sm.height = 1.0
		var mmesh2 := MultiMesh.new()
		mmesh2.transform_format = MultiMesh.TRANSFORM_3D
		mmesh2.mesh = sm
		mmesh2.instance_count = canopy_batch_xforms.size()
		for t in range(canopy_batch_xforms.size()):
			mmesh2.set_instance_transform(t, canopy_batch_xforms[t])
		var cmi := MultiMeshInstance3D.new()
		cmi.name = "BatchedCanopies"
		cmi.multimesh = mmesh2
		var cmt := StandardMaterial3D.new()
		cmt.albedo_color = Color(0.22, 0.42, 0.18)
		cmt.roughness = 1.0
		cmi.material_override = cmt
		patch_node.add_child(cmi)


## Biome detail props (slice 4, step B): bushes and cattails BY BIOME
## -- SWAMP grows cattails (reeds) at its wet sites, GRASSLAND/FOREST
## grow bushes, SHORE grows none (spray zone), and everything past the
## parse bands stays bare. The PROP BUDGET: this patch's level rides
## the LOD budget law -- NEAR (base level): budget up to 6 details;
## one dropped level: 2; drops past that (or LOD off at far faces):
## NOTHING (the biome-colored ground does the work, so the far patch
## never pays its detail pass).
func _spawn_detail_props(face: int, patch_node: Node3D) -> void:
	if not terrain_on:
		return  # prototype keeps its S7 set
	var lvl: int = int(_patch_lvl.get(face, 99))
	var base_lvl: int = _level_for_edge()
	var drop: int = base_lvl - lvl
	if drop >= 2:
		return  # FAR: no detail pass at all (the budget law)
	var budget: int = 6 if drop <= 0 else 2  # NEAR: 6, MID: 2
	var bytes: PackedByteArray = TerrainGen.face_seed_bytes(world_seed, face)
	var acc: int = 0
	for b in bytes:
		acc = (acc * 256 + b) % 9007199254740991
	var rng := RandomNumberGenerator.new()
	rng.seed = acc + 777  # independent stream (never reshuffles rocks)
	var verts: PackedInt32Array = FacePatches.face_vertices(face)
	var patch_center: Vector3 = FacePatches.face_center(face) * (radius + TILE_LIFT)
	var scaled: float = radius + TILE_LIFT
	var sea: float = TerrainGen.sea_level(world_seed)
	var spawned := 0
	for i in range(10):
		if spawned >= budget:
			return
		var v: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var dir: Vector3 = (FacePatches.face_center(face) * 0.5 + v * 0.5).normalized()
		var base_h: float = _prop_ground_h(face, dir)
		if base_h < sea - 0.2:
			continue  # no props in the water band
		var bid: int = TerrainGen.climate_biome_id(dir, world_seed)
		var is_cattail: bool = bid == TerrainGen.BiomeId.SWAMP
		var is_bush: bool = bid == TerrainGen.BiomeId.GRASSLAND \
			or bid == TerrainGen.BiomeId.FOREST or bid == TerrainGen.BiomeId.TAIGA \
			or bid == TerrainGen.BiomeId.ALPINE_MEADOW \
			or bid == TerrainGen.BiomeId.JUNGLE or bid == TerrainGen.BiomeId.SAVANNA \
			or bid == TerrainGen.BiomeId.STEPPE
		var is_ore: bool = bid == TerrainGen.BiomeId.ALPINE or bid == TerrainGen.BiomeId.TUNDRA \
			or bid == TerrainGen.BiomeId.BADLANDS
		if not is_cattail and not is_bush and not is_ore:
			continue  # beach/ocean/water bands stay bare (FOREST/TUNDRA/ALPINE carry the ore)
		var prop := MeshInstance3D.new()
		var mesh: Mesh
		var mat := StandardMaterial3D.new()
		mat.roughness = 1.0
		if is_ore:
			# ORE VEIN (prd-gathering build order 2): the mountain/tundra
			# band carries the mine. A dark boulder-chunk, registered as
			# an iron-ore gather node (the gather->forge leg below the
			# visual: what you SEE is what you can harvest).
			var om := SphereMesh.new()
			var r_o: float = rng.randf_range(0.35, 0.7)
			om.radius = r_o
			om.height = r_o * 1.6
			mesh = om
			mat.albedo_color = Color(0.35, 0.33, 0.36)
			prop.mesh = mesh
			prop.material_override = mat
			prop.name = "Ore%d" % i
			prop.position = _tangent_patch_local(dir, patch_center, scaled + base_h + r_o * 0.2)
			_register_harvest_node(face, i, "res_iron_ore", dir, 90.0)
			spawned += 1
			patch_node.add_child(prop)
			continue
		if is_cattail:
			# Reed: a thin dark-green cylinder with a brown head.
			var cm := CylinderMesh.new()
			cm.top_radius = 0.03
			cm.bottom_radius = 0.05
			cm.height = rng.randf_range(0.9, 1.4)
			mesh = cm
			mat.albedo_color = Color(0.30, 0.38, 0.20)
			prop.position = _tangent_patch_local(dir, patch_center, scaled + base_h)
			prop.mesh = mesh
			prop.material_override = mat
			prop.name = "Cattail%d" % i
			var up_c: Vector3 = dir
			var hint_c: Vector3 = Vector3(0, 1, 0) if abs(up_c.dot(Vector3(0, 1, 0))) < 0.999 else Vector3(1, 0, 0)
			var east_c: Vector3 = (hint_c - up_c * hint_c.dot(up_c)).normalized()
			prop.basis = Basis(east_c, up_c, east_c.cross(up_c))
			prop.position = _tangent_patch_local(dir, patch_center, scaled + base_h + 0.05)
		else:
			# Bush: a squat green sphere.
			var bm := SphereMesh.new()
			var r_b: float = rng.randf_range(0.4, 0.9)
			bm.radius = r_b
			bm.height = r_b * 1.4
			mesh = bm
			mat.albedo_color = Color(0.22 + 0.1 * rng.randf(), 0.42 + 0.1 * rng.randf(), 0.18)
			prop.mesh = mesh
			prop.material_override = mat
			prop.name = "Bush%d" % i
			prop.position = _tangent_patch_local(dir, patch_center, scaled + base_h + r_b * 0.25)
			# THE LIVE HARVEST SEED (prd-gathering): the placement law is
			# one law -- the drawn bush is a gatherable, and the BUSH YIELDS
			# THE BIOME'S OWN GROWTH: a meadow bush is the Moonpetal patch
			# the herb quest asks the world for (was: every bush yielded
			# "res_iron_ore" -- shrubs pretending to be a mine). Seed-stable
			# id: a face reload re-registers the same node identity.
			var bush_item := "res_iron_ore"
			if bid == TerrainGen.BiomeId.ALPINE_MEADOW:
				bush_item = "res_moonpetal"  # the meadow's herb law
			_register_harvest_node(face, i, bush_item, dir, 45.0)
		var up: Vector3 = dir
		if is_bush:
			prop.basis = Basis()
		patch_node.add_child(prop)
		spawned += 1


## Register the drawn prop as a live HarvestService node (prd-
## gathering build order 2: seed-derived placement, one placement law
## for draw + gather). Node id: seed-stable "hs_<face>_<idx>" so a
## face reload re-registers the SAME node identity (depletion/respawn
## ownership survives level changes). Silent no-op in script mode:
## the service may not exist there (probes own their own nodes).
func _register_harvest_node(face: int, idx: int, item_id: String, dir: Vector3, respawn_sec: float) -> void:
	var hs = Engine.get_main_loop()
	if hs == null or not (hs is SceneTree):
		return
	var svc = (hs as SceneTree).root.get_node_or_null(NodePath("HarvestService"))
	if svc != null and svc.has_method("register_node"):
		svc.register_node("hs_%d_%d" % [face, idx], "zone_starter_plains", item_id, dir * radius, 1, respawn_sec)

## THE STRAIT FREIGHT (quest_shoal_freight's world presence): a face
## whose center lies ON the authored corridor chart gets Mag's
## chalk-marked crates as gather nodes (seed-stable id, respawn well
## past the tide turn). Chart x in the corridor band + the strait zone:
## the ford and the channel bottom are the crates' tide-line. Silent
## no-op when BackpackService/HarvestService is absent (script mode).
func _register_strait_freight(face: int, center_dir: Vector3, world_seed_v: PackedByteArray) -> void:
	var Chart = load("res://core/services/strait_chart.gd")
	if Chart == null:
		return
	var ch: Vector2 = Chart.Backend._chart(center_dir)
	# Corridor band: walkable ford approach (before RUN_LO the moat
	# holds the crates' wet feet; past run_hi it is open sea).3 to
	# PAST half-past the shoal (x ~ .55 binge) — the tide moves them.
	if ch.x < 0.02 or ch.x > 0.34 or absf(ch.y) > 0.05:
		return
	var hs = Engine.get_main_loop()
	if hs == null or not (hs is SceneTree):
		return
	var svc = (hs as SceneTree).root.get_node_or_null(NodePath("HarvestService"))
	if svc == null or not svc.has_method("register_node"):
		return
	# Three crates along the corridor (the quest's count), seeded
	# stably so a reload re-claims the SAME node identity.
	var acc := 0
	for b in TerrainGen.face_seed_bytes(world_seed_v, face):
		acc = (acc * 131 + b) % 9007199254740991
	var rng := RandomNumberGenerator.new()
	rng.seed = acc
	for k in range(3):
		var crate_x: float = lerpf(0.05, 0.30, 0.15 + 0.3 * k)
		var crate_y: float = 0.0
		var crate_dir: Vector3 = Chart.dir_from_chart(crate_x, crate_y)
		var nid := "freight_%d_%d" % [face, k]
		svc.register_node(nid, "zone_sundered_sea", "item_sealed_crate", \
			crate_dir * radius, 1, 620.0)

## How many loaded patches are actually VISIBLE in the tree right now
## (the round-12 web question: truth line said dry + meshes loaded, but
## pixels showed ocean -- if visible patches > 0 while the screen shows
## water, the tiles ARE in the tree and the break is in the draw).
func visible_patch_count() -> int:
	var n := 0
	for f in _patches:
		var mi = _patches[f]
		if is_instance_valid(mi) and mi.is_visible_in_tree():
			n += 1
	return n


func _unload_patch(face: int) -> void:
	var mi: MeshInstance3D = _patches.get(face)
	if mi and is_instance_valid(mi):
		mi.queue_free()
	_patches.erase(face)
	_patch_tris.erase(face)
	_patch_rocks.erase(face)
	_patch_boulders.erase(face)
	_patch_mats.erase(face)
	_patch_walk_h.erase(face)
	_patch_lvl.erase(face)
	_patch_skirt_tris.erase(face)
	_skirt_mats.erase(face)
	_prop_holders.erase(face)
	patch_unloaded.emit(face)


## The currently-live per-patch LOD levels (debug/HUD surface).
func lod_levels() -> Dictionary:
	return _patch_lvl.duplicate()


## Radial prop placement: the patch-LOCAL position of the point at
## radius `r` along direction `dir` (the patch node sits at the
## face-center offset, so local = absolute point minus that offset).
## This is the S7 chord formula and it is EXACT for a radial point:
## the rotated-arc construction it replaced reduces to this identity.
func _tangent_patch_local(dir: Vector3, patch_center: Vector3, r: float) -> Vector3:
	return dir.normalized() * r - patch_center


## Prop ground law: the walk-surface height (terrain + small-rock
## cap) at the prop's direction via the face's captured closure.
func _prop_ground_h(face: int, dir: Vector3) -> float:
	var closure = _patch_walk_h.get(face)
	if closure != null:
		return float(closure.call(dir))
	return TerrainGen.terrain_height(dir, world_seed) if terrain_on else 0.0


## Subdivision level so tile edges land near target_patch_edge.
## Unit-icosahedron edge chord is ~1.0515; each level halves the edge.
func _level_for_edge() -> int:
	var edge_full: float = 1.0515 * radius
	# GDScript has no log2 builtin: log(x) is the natural log.
	var lvl: float = log(edge_full / maxf(target_patch_edge, 0.001)) / log(2.0)
	return clampi(int(round(lvl)), 1, 6)


## Recursive spherical midpoint subdivision; preserves outward winding.
func _subdivide(a: Vector3, b: Vector3, c: Vector3, depth: int, out: Array) -> void:
	if depth <= 0:
		out.append([a, b, c])
		return
	var r: float = a.length()
	var mab: Vector3 = (a + b).normalized() * r
	var mbc: Vector3 = (b + c).normalized() * r
	var mca: Vector3 = (c + a).normalized() * r
	_subdivide(a, mab, mca, depth - 1, out)
	_subdivide(mab, b, mbc, depth - 1, out)
	_subdivide(mca, mbc, c, depth - 1, out)
	_subdivide(mab, mbc, mca, depth - 1, out)


## Deterministic per-face tint (visible patch boundaries for streaming
## verification; subtle enough to read as natural ground variation).
func _tint_for(face: int) -> Color:
	if not _face_tints.has(face):
		var h: float = float((face * 2654435761) % 997) / 997.0
		var k: float = 0.85 + 0.3 * h
		_face_tints[face] = Color(0.32 * k, 0.55 * k, 0.35 * k)
	return _face_tints[face]
