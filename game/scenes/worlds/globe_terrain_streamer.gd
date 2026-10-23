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
const MESH_CACHE = preload("res://core/frame/kv/lru_cache.gd")

## Tiles render just above the scene's visual sphere shell (which sits
## at radius + SKIN_THICKNESS = +0.5) so they never hide inside it.
## Mirrored by globe_world.STREAMER_TILE_LIFT (spawn / snap / pad).
const TILE_LIFT: float = 0.52

## THE VISIBILITY DENSITY RAISE (the visibility fix for the play-day
## report "I haven't seen trees or rocks on the starter plains"): the
## old scatter paid its sites once per FACE, but at the 20 km planet
## scale one face spans ~250 km2 -- 8-13 tree-sites over 250 km2 put
## the nearest prop ~6.4 km from the boot (measured by
## tests/probe_prop_density.gd), so the starter plains read bare.
## Tree site counts now carry the face's real geometry (hundreds of
## sites), cheap because the batch MultiMesh path absorbs the mass.
## TREE_NODE_ANG bounds the band around the player direction where a
## tree is a REAL Node3D with a trunk collider (the walk/climb law);
## NODE_TREE_CAP bounds how many node trees one face may place even
## there (draw-call ceiling), so every other site rides the batch
## paint -- horizon detail, no collider.
const TREE_NODE_ANG: float = 0.12   # ~2.4 km ground arc at the 20 km scale
const NODE_TREE_CAP: int = 24       # collided node-tree ceiling per face
const BLOOM_NODE_CAP: int = 150     # the wildflower drift's per-face node ceiling (v14)

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
## Bench metric (cumulative ms spent inside update() -- the boot
## bench isolates the mesh law from the fixed non-mesh boot block).
var last_update_ms: int = 0
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
## THE GRADED LOD LAW (web round 18, "resource heavy"): round 17 raised
## the planet-scale cap to 7 to resolve the near hills -- but EVERY
## live patch then demanded base (4x 65536 = 262k tris on the phone;
## the truth line's mesh:fN x4/65536 tag). Only the PLAYER'S face is
## ever at arm's length: a neighbor is at least a half-face away, so
## its ground detail halves again without a visible loss (the eye
## cannot resolve a 165 m hill from 10+ km of arc). The graded law:
## the near band keeps base (7); the FAR floor is an absolute LAW
## constant (4) that does NOT fall with the base (the old
## base-answer-1 law let every patch ride at 6 when base is 7 -- four
## max-detail patches). Far patches carry the horizon silhouette, not
## vertex detail (the skirt + tint carry the shape there).
## Round 18b: floor CAME UP one level (4 -> 5). The first graded push
## exposed its own edge: the starter village's houses ride the WALK
## LAW pedestal (analytic heightfield), while a far face's level-4
## mesh (1.3 km tile edge) sagged meters below the law between samples
## -- "houses on a flat plane, the model gets higher as terrain
## sinks". Level 5 (660 m edge) keeps the ped-vised silhouettes
## honest; the near band still owns the fine detail underfoot.
const LOD_FLOOR_LEVEL: int = 5
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
var _last_player_dir := Vector3.ZERO  # the tree node/batch split's viewer read (zero until first _update_stream)
## Last known player direction (the NEAR law's own read): the tree
## node/batch split below asks where the VIEWER is, so the collided
## trees cluster where the player can actually reach them. Zero until
## the first _update_stream (cold namespace: all sites go node path
## under the cap, the old pre-split behavior).
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
	# THE FIELD-2 SPLIT (the decorative slice's salt): anchored culture
	# (village core, docks, quest anchors, the harvest-backed detail
	# kinds) derives from the WORLD SEED forever -- the test/probe
	# laws pin it. The DECORATIVE slice (tree canopies, grass fields)
	# mixes a SESSION SALT -- the Concord day the boot runs on -- so
	# nature recombines between sessions the way the field report
	# expects, while every session is internally deterministic (the
	# rng-for-rng twin laws apply the SAME salt, day-granularity: two
	# boots on one day agree position-for-position).
	_decor_salt = int(Time.get_unix_time_from_system()) / 86400


## DECORATIVE BANDS ONLY (see the configure() split note): the salt
## must NEVER ride the detail chain (the ore/mooncap/anchor kinds
## derive from the world seed alone) or the harvest respawn ledger
## drifts across sessions.
var _decor_salt: int = 0


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
	# The bench metric: the streamer's OWN wall time per call (the
	# boot's non-mesh block -- villages, HUD, GLBs -- is not this).
	var _t_ms: int = Time.get_ticks_msec()
	var f: int = FacePatches.face_for_position(player_pos, radius)
	var player_dir: Vector3 = player_pos.normalized()  # the NEAR law's direction (not the face center)
	_last_player_dir = player_dir
	var lod_changed: Array = []
	if f == current_face:
		_lod_enforce(player_dir, lod_changed)
		last_update_ms += Time.get_ticks_msec() - _t_ms
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
			var dem: int = _demanded_level(face, player_dir, int(_patch_lvl.get(face, -1)))
			# v9 MESH THREAD: the boot's OWN face installs SYNC (the walk
			# pad's ground is underfoot in this frame); the 3 non-current
			# faces derive on the worker lanes and install as they land,
			# so the cold boot wall pays ONE cold build, not four.
			# Threadless/prototype hosts collapse to the sync law.
			if face == f or not _mesh_async():
				_load_patch(face, dem)
				loaded.append(face)
			else:
				_kick_mesh_derivation(face, dem)
				loaded.append(face)
	_lod_enforce(player_dir, loaded)
	for face in _patches.keys():
		if not want.has(face):
			_unload_patch(face)
			unloaded.append(face)
	if old >= 0:
		face_changed.emit(old, f)
	last_update_ms += Time.get_ticks_msec() - _t_ms
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
	return LOD_FLOOR_LEVEL


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
			# v9 MESH THREAD: a live patch's level change rides the worker
			# lane when it owns a prop holder (the hot graft at apply
			# time -- the old node stays underfoot until the swap). The
			# current-face and threadless laws keep the sync rebuild.
			if _mesh_async() and _prop_holders.has(face):
				_kick_mesh_derivation(face, want_lvl)
				out_loaded.append(face)
				continue
			# THE PERF-LEG STASH: the demoting/re-promoting node's built
			# geometry lands in the (face, level) ring before the
			# rebuild runs, so the ping-pong climb-back is a graft,
			# not a corner re-derivation.
			_mesh_cache_stash(face, _patches.get(face))
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
	var floor_lvl: int = LOD_FLOOR_LEVEL
	if center_ang <= reach + band_in:
		_patch_far_ticks.erase(face)
		return base
	if center_ang > reach + band_out and cur > floor_lvl:
		var ticks: int = int(_patch_far_ticks.get(face, 0)) + 1
		if ticks >= LOD_FAR_TICKS:
			_patch_far_ticks.erase(face)
			return floor_lvl
		_patch_far_ticks[face] = ticks
		return cur
	# Between the bands (or dwelling): the CURRENT law stands.
	_patch_far_ticks.erase(face)
	return cur if cur >= 0 else floor_lvl


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
	# THE PERF-LEG STASH: the old level's built geometry lands in the
	# (face, level) ring before its replacement builds, so a level
	# ping-pong never re-derives corners for content this machine
	# already built this session.
	_mesh_cache_stash(face, old_mi)
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
	if fresh.has_meta("tris"):
		# v9 bookkeeping fix: the fresh node carries its tris meta; the
		# old hot path left _patch_tris at the OLD level's count.
		_patch_tris[face] = int(fresh.get_meta("tris"))
		fresh.remove_meta("tris")
	old_mi.queue_free()
	return true


## Move the prop holder onto a fresh mesh node (the ONLY lifecycle
## boundary the hot path touches).
func _props_move(face: int, new_mesh_node: MeshInstance3D) -> Node3D:
	return _prop_holder(face, new_mesh_node)


## Build the patch mesh at a level (the pure geometry; no props, no
## bookkeeping). The full _load_patch now delegates here + spawns.
## ===== THE MESH DERIVE / ERECT SPLIT (v9 threading) ============
## ONE geometry law, TWO lanes. The derive (corner sweep + tint
## surface + skirts + water + deck arrays) is a PURE function of
## (face, level, seed, law): it touches no streamer dict -- so it
## runs on a worker thread exactly like the v6 prop derive. The
## ERECTION (ArrayMesh attach, face materials, overrides, meta) has
## node/dict laws only the main thread may touch, so it stays there.
## The sync path is derive+erect back to back: the SAME bytes whichever
## lane ran (a worker-built patch installs identical to a synchronously
## built one -- which is what makes the warm ring and the hot graft
## safe across both). Terrain reads ride the LOCKED sector caches,
## shared with the prop derive legs.
##
## Sync callers (boot's own face, the warm-ring stock misses, benches)
## keep the exact old signature; async callers go
## _kick -> _derive_mesh_data (worker) -> _apply_derived_mesh (main).
func _build_mesh(face: int, use_lvl: int) -> MeshInstance3D:
	## One face's MESH at a level (geometry + skirts; no props, no
	## bookkeeping). Returns a node NOT yet in the tree -- the caller
	## decides its parent (cold spawn vs hot swap).
	_patch_lvl[face] = use_lvl
	return _erect_mesh(face, use_lvl, _derive_mesh_data(face, use_lvl))


## The PURE derive: everything about the patch's geometry that does
## not touch a streamer dict. Worker-legal by construction.
func _derive_mesh_data(face: int, use_lvl: int) -> Dictionary:
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
	# THE SLOPE CACHE (the fusion's second half): the gradient math
	# also runs once per UNIQUE key; the tint pass picks up its vertex
	# slope from here.
	var dir_slope := {}  # Vector3 (quantized globe dir) -> slope seed [0,1]
	var sea: float = TerrainGen.sea_level(world_seed)
	## THE CORNER FUSION (perf leg v8.2): one sweep over the UNIQUE
	## quantized corners populates dir_h with the corner's height AND
	## its three slope-neighbor heights, BEFORE the triangle walk --
	## the tint pass below never calls terrain_height, it only reads
	## dict keys. The old inline law re-built the same corner→neighbor
	## pairs per RAW triangle corner (49,152 raw to ~8,358 unique);
	## the fused sweep does ~4 height fields per UNIQUE corner
	## (deduped), and a quantized neighbor key that collides with a
	## neighboring corner rides the same dict entry.
	if terrain_on:
		for tri in verts:
			for i in range(3):
				var vc: Vector3 = tri[i]
				var dc: Vector3 = (vc + center).normalized()
				var kc: Vector3 = (dc * 4096.0).floor()
				if not dir_h.has(kc):
					dir_h[kc] = tile_r + TerrainGen.terrain_height(dc, world_seed)
				# THE NEIGHBOR SWEEP IS NOT SKIPPED: a corner whose own
				# height was populated as an earlier corner's neighbor
				# STILL owns its three slope-neighbors (the tint pass
				# reads dir_h[nkey] at EVERY corner; skipping the sweep
				# for aliased corners leaves holes the build dies on).
				for n_vec in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]:
					var nd: Vector3 = (dc + n_vec * 0.0012).normalized()
					var nkey: Vector3 = (nd * 4096.0).floor()
					if not dir_h.has(nkey):
						dir_h[nkey] = tile_r + TerrainGen.terrain_height(nd, world_seed)
				# THE SLOPE FUSION (once per UNIQUE corner): the gradient
				# runs here, against the fully populated dir_h, so the
				# triangle walk below just reads dict keys.
				if not dir_slope.has(kc):
					var h_here_f: float = float(dir_h[kc]) - tile_r
					var grad_f: float = 0.0
					for n_vec in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]:
						var nd_f: Vector3 = (dc + n_vec * 0.0012).normalized()
						var nkey_f: Vector3 = (nd_f * 4096.0).floor()
						grad_f = maxf(grad_f, absf((float(dir_h[nkey_f]) - tile_r) - h_here_f))
					dir_slope[kc] = clampf(grad_f / 1.8, 0.0, 1.0)
	## v3 CLIMATE ARC (slice 2): slope for the color law -- the local
	## height gradient per vertex. THE FUSED PASS: slopes derive from
	## the QUANTIZED key reads (the pre-pass above populated them), so
	## the tint pass is dict-only.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in verts:
		for i in range(3):
			var v: Vector3 = tri[i]
			var d_abs: Vector3 = (v + center).normalized()
			var r_abs: float = tile_r
			# THE CORNER KEY (hoisted: both terrain blocks read it).
			var key: Vector3 = (d_abs * 4096.0).floor()
			if terrain_on:
				r_abs = dir_h[key]
			st.set_normal(d_abs)
			## v3 CLIMATE ARC (slice 2): the BIOME palette owns the terrain-
		## on vertex tint (blend + slope + temperature snowline + wet
		## dimming all in one law); the prototype (terrain off) keeps the
		## S7 face tints. Slope comes from the height cache: gradient of
		## the two nearest sampled neighbors.
			var col: Color = _tint_for_pure(face)
			if terrain_on:
				# Slope: read from the fused per-corner cache (dict-only
				# after the corner fusion above).
				var h_here: float = r_abs - tile_r
				var slope_seed: float = dir_slope[key]
				col = TerrainGen.vertex_color(d_abs, world_seed, h_here, slope_seed)
			st.set_color(col)
			# Planar UVs wrapped to [0,1) (the round-12 web law).
			st.set_uv(Vector2(fposmod(v.x * 0.0015, 1.0), fposmod(v.z * 0.0015, 1.0)))
			st.add_vertex(d_abs * r_abs - center)
	var main_arrays: Array = st.commit_to_arrays()

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
		var c0: Color = _tint_for_pure(face)
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
	# The skirt arrays pass through as-is when the border existed.
	var skirt_arrays: Variant = null
	if skirt_tris > 0:
		var skirt_mesh: ArrayMesh = st2.commit()
		skirt_arrays = skirt_mesh.surface_get_arrays(0)

	## v3 HYDROLOGY (slice 3): the WATER SURFACE surfaces under the
	## gated table law and v7's road deck both derive as pure arrays
	## here; the erection adds them to the node later.
	var water_d: Dictionary = _derive_water(face, verts, center, dir_h)
	var deck_d: Dictionary = _derive_deck(face, center)
	return {
		"center": center,
		"tris": verts.size(),
		"main_arrays": main_arrays,
		"skirt_arrays": skirt_arrays,
		"skirt_tris": skirt_tris,
		"water_arrays": water_d.get("arrays"),
		"water_tris": int(water_d.get("tris", 0)),
		"deck_arrays": deck_d.get("arrays"),
		"deck_quads": int(deck_d.get("quads", 0)),
	}


## The ERECTION (main-thread half): builds MeshInstance3D from the
## derive result. All streamer-dict and material/object laws live
## HERE. Called by the sync path AND the async applier -- one node
## law, two lanes. NOTE: it does NOT stamp _patch_lvl -- the stale
## branches erect nodes whose level must not overwrite the LIVE
## stamp; callers stamp explicitly (_build_mesh, the applier swap).
func _erect_mesh(face: int, use_lvl: int, d: Dictionary) -> MeshInstance3D:
	_patch_skirt_tris[face] = int(d["skirt_tris"])
	_patch_water_tris[face] = int(d["water_tris"])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, d["main_arrays"])
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
	mi.position = d["center"]
	if d["skirt_arrays"] != null:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, d["skirt_arrays"])
		mi.set_surface_override_material(1, _skirt_material(face))
	if d["water_arrays"] != null:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, d["water_arrays"])
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.24, 0.42, 0.50)
		wmat.roughness = 0.1
		mi.set_surface_override_material(2, wmat)
	if d["deck_arrays"] != null:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, d["deck_arrays"])
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = DECK_PLANK_COLOR
		dmat.roughness = 0.95
		mi.set_surface_override_material(3, dmat)
	mi.set_meta("deck_quads", int(d["deck_quads"]))
	mi.set_meta("tris", int(d["tris"]))
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
	# SYNC COMPAT WRAPPER: the derive phase now lives in _derive_water
	# (pure, worker-legal); this keeps the old surface-on-a-node shape
	# for any caller of the pre-split signature. Same tables, same
	# law (the erection of the water surface + its material rides the
	# caller, exactly as before).
	var d: Dictionary = _derive_water(face, verts, center, dir_h)
	if d.get("arrays") == null:
		return 0
	mi.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, d["arrays"])
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.24, 0.42, 0.50)
	wmat.roughness = 0.1
	mi.set_surface_override_material(2, wmat)
	return int(d["tris"])


## The PURE water derive: the same standing-water law, packaged as a
## result dict. No node, no dict writes -- worker-legal.
func _derive_water(face: int, verts: Array, center: Vector3, dir_h: Dictionary) -> Dictionary:
	var empty := {"arrays": null, "tris": 0}
	if not terrain_on:
		return empty  # prototype: the shell owns water (no standing lakes yet)
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
		# THE ARRAYS LAW (the perf-budget probe cornered it): commit()
		# returns an ArrayMesh OBJECT -- add_surface_from_arrays wanted
		# the arrays, so every sheet since slice 3 died at this line
		# (the engine's Object-to-Array complaint). commit_to_arrays()
		# hands over the actual primitive arrays.
		return {"arrays": st_w.commit_to_arrays(), "tris": water_tris}
	return empty


## THE RAISED ROAD DECK (v7 polish): the deck segments the carved
## law already walks on become real 3D strips -- a quad ribbon per
## road node inside this face's angular reach, sitting at the bed/deck
## height the WALK law answers (so feet and planks agree exactly).
## TRIANGLE STRIP law: it adds the 4-vertex quad per node as two
## tris (like the water sheet's tile law), not SurfaceTool strips.
## Bridge segments (deck weight high) get plank posts at the rails --
## small dark cylinders -- so a crossing reads as a built thing.
## ADDS surface 3 on the patch mesh; the law is PURE per (face, seed)
## so re-derivation is deterministic. Nothing touches the walk law.
const DECK_RIBBON_HALF: float = 0.0032  # ~64 m cartway half-width (arc)
const DECK_PLANK_COLOR := Color(0.44, 0.33, 0.22)

func _raised_road_deck(face: int, mi: MeshInstance3D, center: Vector3) -> int:
	# SYNC COMPAT WRAPPER: the derive phase lives in _derive_deck
	# (pure, worker-legal); this keeps the old surface-on-a-node shape
	# for the pre-split signature (same ribbon law, same counts).
	var d: Dictionary = _derive_deck(face, center)
	if d.get("arrays") == null:
		return 0
	mi.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, d["arrays"])
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = DECK_PLANK_COLOR
	dmat.roughness = 0.95
	mi.set_surface_override_material(3, dmat)
	return int(d["quads"])


## The PURE deck derive: the ribbon law as arrays. No node writes.
func _derive_deck(face: int, center: Vector3) -> Dictionary:
	var empty := {"arrays": null, "quads": 0}
	if not terrain_on:
		return empty
	var spec: TerrainGen.RoadSpec = TerrainGen.road_spec_cached(world_seed)
	var path: PackedVector3Array = spec.path
	var t_r: float = radius + TILE_LIFT
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 0
	var n: int = path.size()
	for i in range(n - 1):
		var p0: Vector3 = path[i]
		var p1: Vector3 = path[i + 1]
		# The ribbon segment spans this face's angular reach only.
		if p0.angle_to(center) > 0.30 and p1.angle_to(center) > 0.30:
			continue
		var h0: float = spec.beds[i]
		var h1: float = spec.beds[i + 1]
		var is_bridge: bool = spec.bridges[i] > 0.4 or spec.bridges[i + 1] > 0.4
		# Segment axis + its surface tangent (the rail direction).
		var seg: Vector3 = p0.cross(p1).normalized()  # segment normal axis
		var half: float = DECK_RIBBON_HALF
		var a0: Vector3 = p0.rotated(seg, half).normalized()
		var b0: Vector3 = p0.rotated(seg, -half).normalized()
		var a1: Vector3 = p1.rotated(seg, half).normalized()
		var b1: Vector3 = p1.rotated(seg, -half).normalized()
		var va0: Vector3 = a0 * (t_r + h0) - center
		var vb0: Vector3 = b0 * (t_r + h0) - center
		var va1: Vector3 = a1 * (t_r + h1) - center
		var vb1: Vector3 = b1 * (t_r + h1) - center
		# Two triangles: (a0, b0, a1) and (b0, b1, a1). The face
		# normal is the outward radial mid (up-ish on a road deck).
		var mid: Vector3 = ((a0 + b0 + a1 + b1) * 0.25).normalized()
		var col: Color = DECK_PLANK_COLOR
		# Bridge segments read lighter (rail planks weather above the
		# water; road bed planks stay earth-dark).
		if is_bridge:
			col = col.lightened(0.25)
		var quad_pts: Array = [va0, vb0, va1, vb0, vb1, va1]
		for p in quad_pts:
			st.set_normal(mid)
			st.set_color(col)
			st.add_vertex(p)
		quads += 1
	if quads > 0:
		return {"arrays": st.commit_to_arrays(), "quads": quads}
	return empty


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
	# THE WARM-MESH CACHE (the perf-leg law): a face's BUILT MESH NODE
	# (geometry + skirts + deck) is kept on a bounded ring keyed
	# (face, level) when it streams out or demotes, and re-stocked
	# wholesale on the revisit. The heavy mesh pass (corner derivation
	# + subdivision + vertex tint) never runs twice for the same
	# content; the ring bounds memory so the walk evicts the tail
	# instead of holding the planet. The stock rewrites the
	# bookkeeping like _hot_reload does.
	var mi: MeshInstance3D = _mesh_cache_stock(face, use_lvl)
	_install_loaded_mesh(face, use_lvl, mi)


## The install tail shared by the COLD path (fresh mesh node straight
## into the tree) and the v9 ASYNC APPLIER (a worker-derived mesh
## landing while the walk moved on): bookkeeping, walk law closure,
## prop holder + spawns. One install law, both lanes.
func _install_loaded_mesh(face: int, use_lvl: int, mi: MeshInstance3D) -> void:
	parent.add_child(mi)
	_patches[face] = mi
	if mi.has_meta("tris"):
		_patch_tris[face] = int(mi.get_meta("tris"))
		mi.remove_meta("tris")
	_patch_lvl[face] = use_lvl
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


## ===== THE SHARED PROP MESH LAW (the prop-byte follow-up) =====
## The honest audit found the live set's real memory driver: every
## prop built its OWN primitive mesh (identical sphere/cylinder
## geometries at continuously random sizes -- the VERTEX DATA is the
## same shape at every size). The registry shares ONE resource per
## quantized size class: riddling to 1/64 m steps gives <=8 mm slop
## (sub-glitch at every prop scale the walk sees) while the vertex
## buffer count drops from "per prop" to "per distinct size".
##
## CENSUS LAW: spheres keep their EXACT aspect -- the height derives
## from the QUANTIZED radius, so the 2.0x rock law and the per-species
## canopy ratios never drift (the biodiversity census pins h/r). The
## quantization is a MESH-RESOURCE decision only: rng laws, node
## positions, and placements are untouched, so sync and async content
## stays identical and every prop keeps its name-resolvable census.
## Registry is MAIN-THREAD-ONLY state: prop nodes are built in fresh
## spawns and the deferred appliers, never in a worker.
var _prop_mesh_registry := {}  # kind@dims -> shared PrimitiveMesh

func _q64(x: float) -> float:
	return float(int(round(x * 64.0))) / 64.0


## radius quantized; height = radius x the exact multiplier (the
## census's h/r law rides the q64 radius, un-drifted).
func _shared_prop_sphere(radius: float, height_mult: float) -> SphereMesh:
	var r_q: float = _q64(radius)
	var h: float = r_q * height_mult
	var key: String = "s@%d@%d" % [int(round(r_q * 64.0)), int(round(height_mult * 4096.0))]
	var hit = _prop_mesh_registry.get(key)
	if hit != null:
		return hit
	var sm := SphereMesh.new()
	sm.radius = r_q
	sm.height = h
	_prop_mesh_registry[key] = sm
	return sm


## Cylinders carry no census ratio pins: every dim quantizes onto its
## own 1/64 bucket (the stored height matches its key bucket).
func _shared_prop_cyl(top_r: float, bottom_r: float, height: float) -> CylinderMesh:
	var key: String = "c@%d@%d@%d" % [int(round(top_r * 64.0)), int(round(bottom_r * 64.0)), int(round(height * 64.0))]
	var hit = _prop_mesh_registry.get(key)
	if hit != null:
		return hit
	var cm := CylinderMesh.new()
	cm.top_radius = _q64(top_r)
	cm.bottom_radius = _q64(bottom_r)
	cm.height = _q64(height)
	_prop_mesh_registry[key] = cm
	return cm


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
		# THE ROCK VARIETY LAW (v7): the rock's kind follows the BIOME
		# it sits in -- alpine/tundra cap gray-blue granite, badlands
		# roast rust-red, desert bakes pale sandstone, swamp greens
		# mossy, shores keep the weathered default. The S7 look stays
		# for every green band, so existing pins read unchanged.
		var rbid: int = TerrainGen.climate_biome_id(s.dir, world_seed) if terrain_on else -1
		var rock_col: Color = Color(0.45, 0.42, 0.40)
		match rbid:
			TerrainGen.BiomeId.ALPINE, TerrainGen.BiomeId.TUNDRA:
				rock_col = Color(0.52, 0.54, 0.58)
			TerrainGen.BiomeId.BADLANDS:
				rock_col = Color(0.52, 0.33, 0.24)
			TerrainGen.BiomeId.DESERT:
				rock_col = Color(0.60, 0.52, 0.38)
			TerrainGen.BiomeId.SWAMP:
				rock_col = Color(0.36, 0.40, 0.30)
		var rmi := MeshInstance3D.new()
		# THE SHARED PROP MESH LAW: a registry entry, not a per-prop
		# resource. The tint rides the INSTANCE (a material set on a
		# shared mesh would restyle the whole size class).
		var rock_geo_r: float = TerrainGen.ROCK_RADIUS * s.scale
		rmi.mesh = _shared_prop_sphere(rock_geo_r, 2.0)
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = rock_col
		rmat.roughness = 1.0
		rmi.material_override = rmat
		# Radial placement: the rock rides its own direction at (scaled
		# + terrain), ROCKS EXCLUDING their own walk-over cap (walk_height
		# would double-count it). At prototype scale (terrain 0) this
		# reduces to the S7 formula exactly (probe-pinned).
		var rock_r: float = scaled + TerrainGen.terrain_height(s.dir, world_seed) if terrain_on else scaled
		rmi.position = _tangent_patch_local(s.dir, patch_center, rock_r + TerrainGen.ROCK_EMBED)
		rmi.rotation.y = s.yaw
		patch_node.add_child(rmi)
		rmi.name = "Rock%d" % nodes.size()  # census/debug law: every prop stays name-resolvable
		nodes.append(rmi)
		# THE SCREE LAW (v7): in alpine/tundra/badlands each rock drops
		# a seeded 2..4-rubble collar on its downhill rim -- the scree
		# field the rocky bands owed. Same mesh family as the rock,
		# two tints darker; NO walk-cap change (rubble sits below the
		# cap the rock itself already raises, so the walk law is
		# untouched -- pure paint).
		if rbid == TerrainGen.BiomeId.ALPINE or rbid == TerrainGen.BiomeId.TUNDRA \
				or rbid == TerrainGen.BiomeId.BADLANDS:
			var scree_acc: int = 0
			for b in TerrainGen.face_seed_bytes(world_seed, face):
				scree_acc = (scree_acc * 131 + b) % 9007199254740991
				scree_acc = (scree_acc * 257 + nodes.size()) % 9007199254740991
			var scree_rng := RandomNumberGenerator.new()
			scree_rng.seed = scree_acc
			var scree_n: int = scree_rng.randi_range(2, 4)
			for k in range(scree_n):
				var s_hint: Vector3 = Vector3(0, 1, 0) if abs(s.dir.dot(Vector3(0, 1, 0))) < 0.9 else Vector3(1, 0, 0)
				var s_axis: Vector3 = s.dir.cross(s_hint).normalized()
				var s_dir: Vector3 = s.dir.rotated(s_axis, \
					(TerrainGen.ROCK_RADIUS * s.scale * (1.25 + 0.4 * scree_rng.randf())) / maxf(rock_r, 1.0) \
					+ scree_rng.randf_range(0.0, 0.03))
				var sr := MeshInstance3D.new()
				var scree_r: float = TerrainGen.ROCK_RADIUS * scree_rng.randf_range(0.22, 0.45)
				sr.mesh = _shared_prop_sphere(scree_r, 2.0)
				var srm_mat := StandardMaterial3D.new()
				srm_mat.albedo_color = rock_col.darkened(0.25)
				srm_mat.roughness = 1.0
				sr.material_override = srm_mat
				sr.name = "Scree%d_%d" % [nodes.size(), k]
				sr.position = _tangent_patch_local(s_dir, patch_center, rock_r + TerrainGen.ROCK_EMBED * 0.4)
				patch_node.add_child(sr)
	if terrain_on:
		_spawn_boulders(face, patch_node)
	# TREES / DETAILS / GRASS: the derive-heavy laws ride the worker
	# thread when the terrain arc is on (web boot law -- the mesh pass
	# never stalls on thousands of site reads); threadless hosts take
	# the sync path. The collider pass moved into the appliers (the
	# tree build may finish frames later than this call).
	if _prop_async():
		_kick_prop_derivation(face)
	else:
		if terrain_on:
			_prop_register_freight(face)
		_spawn_trees(face, patch_node)
		_spawn_detail_props(face, patch_node)
		_spawn_grass_field(face, patch_node)
		for tree in patch_node.get_children():
			if tree is Node3D and str(tree.name).begins_with("Tree"):
				PropCollider.attach_trunk(tree)
	_patch_rocks[face] = nodes


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
		bmi.mesh = _shared_prop_sphere(s.radius, 1.7)  # squat, not a perfect ball
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.40, 0.38, 0.37)
		bmat.roughness = 1.0
		bmi.material_override = bmat
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
			crmi.mesh = _shared_prop_sphere(TerrainGen.ROCK_RADIUS, 2.0)
			crmi.material_override = bmat
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
	var node_left: int = NODE_TREE_CAP
	var pdir_known: bool = _last_player_dir != Vector3.ZERO
	var bytes: PackedByteArray = TerrainGen.face_seed_bytes(world_seed, face)
	var acc: int = 0
	for b in bytes:
		acc = (acc * 131 + b) % 9007199254740991
	var rng := RandomNumberGenerator.new()
	# THE DECO SALT (the FIELD-2 split, sync twin): the decorative
	# canopy chain recombines per session (see configure()); every
	# other rng input stays the world seed's own.
	rng.seed = (acc + _decor_salt) % 9007199254740991
	var count: int = rng.randi_range(4, 8)
	# THE DENSITY LAW (the owner's order: tree density per variety
	# band): the face's own biome scales the site ask -- canopies
	# quadruple, meadows thicken, the dry pans thin to a straggle,
	# and the past-the-line bands barely brush. The per-site species
	# law below still gates every planted tree; this only sets HOW
	# MANY sites the face walks. Reads the face CENTER's band (the
	# same quantized climate read the tints cache), so all faces of
	# one band answer identically.
	if terrain_on:
		var cbid: int = TerrainGen.climate_biome_id(FacePatches.face_center(face).normalized(), world_seed)
		if cbid == TerrainGen.BiomeId.FOREST or cbid == TerrainGen.BiomeId.TAIGA \
			or cbid == TerrainGen.BiomeId.JUNGLE:
			count = rng.randi_range(1400, 2100)
		elif cbid == TerrainGen.BiomeId.SWAMP:
			count = rng.randi_range(300, 460)
		elif cbid == TerrainGen.BiomeId.GRASSLAND:
			count = rng.randi_range(2200, 3000)
		elif cbid == TerrainGen.BiomeId.SAVANNA:
			count = rng.randi_range(400, 640)
		elif cbid == TerrainGen.BiomeId.SHORE:
			count = rng.randi_range(400, 640)
		elif cbid == TerrainGen.BiomeId.DESERT or cbid == TerrainGen.BiomeId.TUNDRA \
				or cbid == TerrainGen.BiomeId.STEPPE or cbid == TerrainGen.BiomeId.BADLANDS:
			count = rng.randi_range(80, 140)
		else:
			count = rng.randi_range(12, 24)  # alpine / lake / ocean center: site floor
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
		var v2: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var dir: Vector3 = (FacePatches.face_center(face) * 0.25 + v * 0.35 + v2 * 0.40).normalized()
		# THE AUTHORED NECK (v11): the Sun Pans atoll is a small island
		# inside a giant face -- the raw barycentric scatter misses it
		# for a lifetime of attempts. A pans-bearing face pours ALL its
		# detail attempts through the atoll's cone (the tight splay
		# keeps the rim ring and beach covered); the rest of the face
		# is empty ocean and correctly stays bare.
		if FacePatches.face_center(face).angle_to(TerrainGen.sun_pans_dir()) \
				<= _face_reach(face) + TerrainGen.SUN_PANS_ANG:
			dir = dir.slerp(TerrainGen.sun_pans_dir(), rng.randf_range(0.955, 0.985))
		# THE BOOT GROVE PULL (v4): inside the homeland reach the tree
		# site rotates 62% along the surface toward the boot, so the
		# starter country carries a WALKABLE grove (the belt census
		# measured zero trees inside 2.1 km while 55 sat just past the
		# rim). SPAWN_CENTER is a world constant, so the law stays pure.
		if FacePatches.face_center(face).angle_to(TerrainGen.SPAWN_CENTER) \
				< TerrainGen.HOMELAND_ANGULAR_REACH:
			dir = dir.slerp(TerrainGen.SPAWN_CENTER, 0.62)
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
		var take_node: bool = not batched and node_left > 0 \
			and (not pdir_known or dir.angle_to(_last_player_dir) <= TREE_NODE_ANG)
		if take_node:
			node_left -= 1
		if not take_node:
			# BATCHED (far face AND near overflow): accumulate the same deterministic tree
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
		trunk.mesh = _shared_prop_cyl(trunk_radius_top, trunk_radius_bottom, trunk_height)
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = trunk_tint
		tmat.roughness = 1.0
		trunk.material_override = tmat
		trunk.position = Vector3(0, trunk_height * 0.5, 0)
		tree.add_child(trunk)
		var canopy := MeshInstance3D.new()
		# aspect = crown x 1.8 like today; the sphere helper keeps h/r EXACT
		canopy.mesh = _shared_prop_sphere(canopy_crown, 1.8)
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = canopy_tint
		cmat.roughness = 1.0
		canopy.material_override = cmat
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
	if batch_xforms.size() > 0:
		# TRUNKS
		var tmesh2 := MultiMesh.new()
		tmesh2.transform_format = MultiMesh.TRANSFORM_3D
		# Unit trunk: per-instance scale stretches it (shared, taken from
		# the registry so every face's batch reuses one buffer).
		tmesh2.mesh = _shared_prop_cyl(0.14, 0.22, 1.0) # Godot: multimesh.mesh takes the source mesh directly
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
		var mmesh2 := MultiMesh.new()
		mmesh2.transform_format = MultiMesh.TRANSFORM_3D
		mmesh2.mesh = _shared_prop_sphere(1.0, 1.0)  # unit: per-instance scale = crown
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


## THE GRASS + BLOOM TIER (v5 detail): the meadow's ground furniture.
## The tuft is ONE shared three-blade ArrayMesh (vertex-graded green
## base -> sun-tipped blades), one draw per tuft, no collider -- the
## vertex-color "grass expression" underneath stays the far-view
## carpet, the tufts are the near-view flesh. A bloom is a stem + a
## saturated head (four-color shared palette) on grassland only: the
## pretty law the owner asked for, budget-priced.
var _tuft_mesh_res: Mesh = null
var _tuft_mat_res: StandardMaterial3D = null
var _bloom_mats_res: Array = []

func _tuft_mesh() -> Mesh:
	if _tuft_mesh_res != null:
		return _tuft_mesh_res
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_col := Color(0.38, 0.50, 0.24)
	var tip_col := Color(0.66, 0.72, 0.34)
	for b in range(3):
		var ang: float = TAU * float(b) / 3.0
		var bx: float = cos(ang)
		var bz: float = sin(ang)
		var wide: float = 0.085
		var lean: float = 0.13
		var tip: float = 0.55 + 0.12 * float(b) * 0.0  # uniform blade height; scale varies per node
		var a := Vector3(bx * wide, 0.0, bz * wide)
		var c := Vector3(bx * -wide, 0.0, bz * -wide)
		var t := Vector3(bx * lean, 0.55, bz * lean)
		st.set_color(base_col)
		st.add_vertex(a)
		st.set_color(base_col)
		st.add_vertex(c)
		st.set_color(tip_col)
		st.add_vertex(t)
	_tuft_mesh_res = st.commit()
	return _tuft_mesh_res

func _tuft_material() -> StandardMaterial3D:
	if _tuft_mat_res != null:
		return _tuft_mat_res
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tuft_mat_res = m
	return m

## The bloom palette (shared; per-flower the node just picks one).
static func _bloom_palette() -> Array:
	if _bloom_palette_cache.is_empty():
		_bloom_palette_cache = [
			Color(0.86, 0.44, 0.58),
			Color(0.92, 0.75, 0.32),
			Color(0.93, 0.93, 0.86),
			Color(0.55, 0.50, 0.90),
		]
	return _bloom_palette_cache

static var _bloom_palette_cache: Array = []
var _bloom_stem_mat_res: StandardMaterial3D = null

func _bloom_stem_material() -> StandardMaterial3D:
	if _bloom_stem_mat_res != null:
		return _bloom_stem_mat_res
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.32, 0.48, 0.22)
	m.roughness = 1.0
	_bloom_stem_mat_res = m
	return m

## The shared tuft helpers (one cached mesh + material for ALL tufts:
## per-tuft variance rides the node transform: scale splay + yaw).

var _bloom_head_mats_res: Array = []

func _bloom_head_material(idx: int) -> StandardMaterial3D:
	var palette: Array = _bloom_palette()
	if _bloom_head_mats_res.size() != palette.size():
		_bloom_head_mats_res.resize(0)
		for pal_col in palette:
			var gm := StandardMaterial3D.new()
			gm.albedo_color = pal_col
			gm.roughness = 0.85
			_bloom_head_mats_res.append(gm)
	return _bloom_head_mats_res[clampi(idx, 0, palette.size() - 1)]

## Biome detail props (slice 4, step B): the GROUND FURNITURE law --
## bushes and cattails BY BIOME -- SWAMP grows cattails (reeds) at its
## wet sites, GRASSLAND/FOREST grow bushes, SHORE grows none (spray
## zone), and everything past the parse bands stays bare -- plus the
## v5 GRASS TIER: the meadow bands pay tufts (grassland mostly tuft,
## bush ~18%, bloom ~10%; dry bands a straggle), so the starter
## country reads lived-in ground instead of flat vertex paint. The
## PROP BUDGET (v9): the patch's level rides the LOD tier law --
## NEAR (base level): the full band ask; one dropped level: a quarter;
## the floor band (drop 2, the LOD_FLOOR_LEVEL set): an eighth,
## batch-heavy (the tuft mass is one MultiMesh per face); past that:
## NOTHING (the biome-colored ground does the work, so the far patch
## never pays its detail pass).
func _spawn_detail_props(face: int, patch_node: Node3D) -> void:
	if not terrain_on:
		return  # prototype keeps its S7 set
	var lvl: int = int(_patch_lvl.get(face, 99))
	var base_lvl: int = _level_for_edge()
	var drop: int = base_lvl - lvl
	if drop >= 3:
		return  # FAR: no detail pass at all (the budget law)
	# THE FLOOR BAND (v9, sync twin -- see the derive law above): the
	# drop-2 floor faces pay a reduced ask instead of nothing.
	# THE REAL-GEOMETRY BUDGET (v8, sync twin of the derive law above).
	var budget_full: int = _face_band_ask(face)
	# THE LADDER GATE (sync twin -- see the derive law above): the
	# homeland-reach faces pay the GRASSLAND ask even when their center
	# resolves a bare shore/lake band.
	if budget_full <= 0:
		if FacePatches.face_center(face).angle_to(TerrainGen.SPAWN_CENTER) \
				>= TerrainGen.HOMELAND_ANGULAR_REACH:
			return  # beach/ocean/water center faces stay bare
		budget_full = int(_DETAIL_BUDGETS.get(TerrainGen.BiomeId.GRASSLAND, 0))
	# THE TIER ASK (v9): NEAR faces pay the full ask; drop-1 (a live
	# demote in flight) pays a quarter; the floor band pays 1/8 -- the
	# tuft mass is MultiMesh-batched, so a floor face's dressing costs
	# ~1 draw + a couple dozen nodes instead of zero.
	var mid_div: int = 4 if drop == 1 else 8
	var budget: int = budget_full if drop <= 0 else int(budget_full / mid_div)  # NEAR: full, floor: 1/8
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
	var bloom_count: int = 0  # THE WILDFLOWER DRIFT's node ceiling (v14)
	var tuft_xforms: Array = []  # THE TUFT BATCH: one MultiMesh paints the field
	var tuft_bids: Array = []  # the batch material is the MAJORITY band's tint
	for i in range(budget * 2):  # 2x the ask absorbs the water/bare rejects
		if spawned >= budget:
			break  # the tuft-batch flush runs after the loop
		var v: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var v2: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var dir: Vector3 = (FacePatches.face_center(face) * 0.25 + v * 0.35 + v2 * 0.40).normalized()
		# THE AUTHORED NECK (v11): the Sun Pans atoll is a small island
		# inside a giant face -- the raw barycentric scatter misses it
		# for a lifetime of attempts. A pans-bearing face pours ALL its
		# detail attempts through the atoll's cone (the tight splay
		# keeps the rim ring and beach covered); the rest of the face
		# is empty ocean and correctly stays bare.
		if FacePatches.face_center(face).angle_to(TerrainGen.sun_pans_dir()) \
				<= _face_reach(face) + TerrainGen.SUN_PANS_ANG:
			dir = dir.slerp(TerrainGen.sun_pans_dir(), rng.randf_range(0.955, 0.985))
		# THE BOOT GROVE PULL (v8 tightened, sync twin -- see the
		# derive law above): 0.88 leaves the boot belt,
		# not a 4-5 km drag.
		if FacePatches.face_center(face).angle_to(TerrainGen.SPAWN_CENTER) \
				< TerrainGen.HOMELAND_ANGULAR_REACH:
			dir = dir.slerp(TerrainGen.SPAWN_CENTER, 0.88)
		var base_h: float = _prop_ground_h(face, dir)
		if base_h < sea - 0.2:
			continue  # no props in the water band
		var bid: int = TerrainGen.climate_biome_id(dir, world_seed)
		var is_cattail: bool = bid == TerrainGen.BiomeId.SWAMP \
			or bid == TerrainGen.BiomeId.RIVER  # the river banks carry the reeds too (v10)
		# THE MEADOW SET (v5 grass tier): the grass-family bands -- the
		# homeland belt is grassland, savanna/steppe/taiga straggle.
		var meadow: bool = bid == TerrainGen.BiomeId.GRASSLAND \
			or bid == TerrainGen.BiomeId.SAVANNA or bid == TerrainGen.BiomeId.STEPPE \
			or bid == TerrainGen.BiomeId.TAIGA
		var is_bush: bool = bid == TerrainGen.BiomeId.FOREST \
			or bid == TerrainGen.BiomeId.ALPINE_MEADOW \
			or bid == TerrainGen.BiomeId.JUNGLE
		var is_ore: bool = bid == TerrainGen.BiomeId.ALPINE or bid == TerrainGen.BiomeId.TUNDRA \
			or bid == TerrainGen.BiomeId.BADLANDS
		# THE DRY RANGE LAW (v9, sync twin -- see the derive law above):
		# the range bands carry dry brush (straw/frost/rust tufts).
		var is_dry_band: bool = bid == TerrainGen.BiomeId.DESERT or is_ore
		var is_shore: bool = bid == TerrainGen.BiomeId.SHORE  # the beach law's band gate
		if not is_cattail and not is_bush and not is_dry_band and not meadow \
				and not is_shore:
			continue  # beach/ocean/water bands stay bare (FOREST/TUNDRA/ALPINE carry the ore)
		# THE KIND ROLL (deterministic): one draw per site decides the
			# meadow mix -- tufts ~72%, shrubs ~18%, blooms ~10% (grassland
			# only; the dry bands never bloom, the forest bands never tuft).
		var meadow_roll: float = rng.randf()
		# THE WILDFLOWER DRIFT (v14): the meadow's bloom gate rides the
		# land's own drift signal -- a PURE read (no rng draw, the twin
		# draw counts hold) -- so a strong cell carries up to ~50% of its
		# sites in bloom while the open meadow keeps the v5 sprinkle.
		var flower_gate: float = 0.10
		if meadow and bid == TerrainGen.BiomeId.GRASSLAND:
			flower_gate = 0.10 + 0.40 * TerrainGen.wildflower_drift(dir)
		var is_flower: bool = meadow and bid == TerrainGen.BiomeId.GRASSLAND \
				and meadow_roll < flower_gate
		# THE BLOOM NODE CAP (the perf law): the raise is paid by the
		# per-face node ceiling -- past it the site stays meadow (the
		# field stops growing, the budget does not explode).
		if is_flower and bloom_count >= BLOOM_NODE_CAP:
			is_flower = false
		var is_bush_kept: bool = meadow and not is_flower and meadow_roll > 0.82
		var is_tuft: bool = meadow and not is_flower and not is_bush_kept
		# THE FUNGAL TIER (v7): the sync twin of the derive law above.
		# A second roll (own draw) keeps the two streams independent.
		var fungal: bool = bid == TerrainGen.BiomeId.SWAMP \
			or bid == TerrainGen.BiomeId.FOREST or bid == TerrainGen.BiomeId.JUNGLE \
			or bid == TerrainGen.BiomeId.TAIGA
		var fungal_roll: float = rng.randf()
		var is_mushroom: bool = fungal and fungal_roll < 0.14
		var is_mycelium: bool = fungal and not is_mushroom and fungal_roll < 0.22
		# THE DRY RANGE ROLL (v9): one draw per dry site splits the
		# range's ask -- ~55% dry brush (the straw/frost/rust tuft),
		# the rest keeps the boulder-ore vein. Own draw: the
		# rng-for-rng twin law carries the same draw in both paths.
		var is_dry_tuft: bool = is_dry_band and rng.randf() < 0.55
		# THE BEACH LAW (v10): the shore band is the planet's ring of
		# contact -- the beach map scan measures 11.4% of the globe's
		# surface and it rendered NOTHING before. Shore sites split:
		# ~60% shells (pale half-buried seams), ~17% kelp wrack (brown
		# squat balls), the rest bare sand. Own draws: the rng-for-rng
		# twin law carries the same two draws in both paths.
		var is_shell: bool = false
		var is_wrack: bool = false
		if is_shore:
			var shore_roll: float = rng.randf()
			is_shell = shore_roll < 0.60
			is_wrack = not is_shell and shore_roll < 0.77
		var prop := MeshInstance3D.new()
		var mesh: Mesh
		var mat := StandardMaterial3D.new()
		mat.roughness = 1.0
		if is_tuft:
			# THE TUFT LAW (v8 batched, sync twin of the derive law):
			# ONE shared three-blade mesh, vertex-graded (dark base ->
			# sun-tipped), no collider (the walk law treats grass as
			# ground, not prop). Per-tuft variance rides the instance
			# transform: yaw + a gentle scale splay. The whole field
			# paints as one MultiMesh per face (the flush below) -- the
			# raised budget never pays a node per blade.
			var tpos: Vector3 = _tangent_patch_local(dir, patch_center, scaled + base_h)
			var up_t: Vector3 = dir
			var hint_t: Vector3 = Vector3(0, 1, 0) if abs(up_t.dot(Vector3(0, 1, 0))) < 0.999 else Vector3(1, 0, 0)
			var east_t: Vector3 = (hint_t - up_t * hint_t.dot(up_t)).normalized()
			var tyaw: float = rng.randf_range(0.0, TAU)
			var tscl: float = rng.randf_range(0.7, 1.6)
			tuft_xforms.append(Transform3D(
				Basis(east_t, up_t, east_t.cross(up_t)).rotated(up_t, tyaw).scaled(Vector3.ONE * tscl), tpos))
			tuft_bids.append(bid)
			spawned += 1
			continue
		if is_flower:
			bloom_count += 1
			# THE BLOOM LAW (the pretty tier): a stem + a saturated head
			# from the shared four-color palette. Pure paint -- no
			# harvest registration (the meadow keeps its herb law on
			# ALPINE_MEADOW bushes only).
			var bloom := Node3D.new()
			bloom.name = "Flower%d" % i
			bloom.position = _tangent_patch_local(dir, patch_center, scaled + base_h)
			var stem := MeshInstance3D.new()
			var stem_h: float = rng.randf_range(0.20, 0.38)
			stem.mesh = _shared_prop_cyl(0.02, 0.03, stem_h)
			stem.material_override = _bloom_stem_material()
			stem.position = Vector3(0.0, stem_h * 0.5, 0.0)
			var head := MeshInstance3D.new()
			var r_h: float = rng.randf_range(0.055, 0.105)
			head.mesh = _shared_prop_sphere(r_h, 1.3)
			# THE DRIFT SPECIES (v14): the palette rides the drift band -- a
			# patch blooms as ONE wildflower kind, with a rare intruder (the
			# same single randi() draw, so the twin draw counts hold).
			var species: int = int(TerrainGen.wildflower_drift(dir) * 7.0) % _bloom_palette().size()
			var pal: int = species if (rng.randi() % 6) != 0 else (species + 1) % _bloom_palette().size()
			head.material_override = _bloom_head_material(pal)
			head.position = Vector3(0.0, stem_h + r_h * 0.25, 0.0)
			bloom.add_child(stem)
			bloom.add_child(head)
			var up_f: Vector3 = dir
			var hint_f: Vector3 = Vector3(0, 1, 0) if abs(up_f.dot(Vector3(0, 1, 0))) < 0.999 else Vector3(1, 0, 0)
			var east_f: Vector3 = (hint_f - up_f * hint_f.dot(up_f)).normalized()
			bloom.basis = Basis(east_f, up_f, east_f.cross(up_f)).rotated(up_f, rng.randf_range(0.0, TAU))
			patch_node.add_child(bloom)
			spawned += 1
			continue
		if is_mushroom:
			# THE FUNGAL BUILD (v7, sync twin of the derive build). See
			# the _apply_detail_sites twin above for the shape law.
			var fungi_s := Node3D.new()
			fungi_s.name = "Mushroom%d" % i
			fungi_s.position = _tangent_patch_local(dir, patch_center, scaled + base_h)
			var pal_idx_s: int = rng.randi() % 4
			var fungal_c_s: Color = [
				Color(0.70, 0.30, 0.36),
				Color(0.72, 0.54, 0.28),
				Color(0.80, 0.78, 0.70),
				Color(0.55, 0.36, 0.62),
			][pal_idx_s]
			var stem_h_s: float = rng.randf_range(0.18, 0.55)
			var stem_mat_s := StandardMaterial3D.new()
			stem_mat_s.albedo_color = Color(0.78, 0.74, 0.66)
			stem_mat_s.roughness = 1.0
			var stem_node := MeshInstance3D.new()
			stem_node.mesh = _shared_prop_cyl(0.035, 0.055, stem_h_s)
			stem_node.material_override = stem_mat_s
			stem_node.position = Vector3(0.0, stem_h_s * 0.5, 0.0)
			fungi_s.add_child(stem_node)
			var cap_r_s: float = rng.randf_range(0.10, 0.30)
			var cap_mat_s := StandardMaterial3D.new()
			cap_mat_s.albedo_color = fungal_c_s
			cap_mat_s.roughness = 0.8
			var cap_node := MeshInstance3D.new()
			cap_node.mesh = _shared_prop_sphere(cap_r_s, 0.9)
			cap_node.material_override = cap_mat_s
			cap_node.position = Vector3(0.0, stem_h_s + cap_r_s * 0.2, 0.0)
			fungi_s.add_child(cap_node)
			# THE FUNGAL HARVEST LAW (sync twin -- see the apply branch).
			_register_harvest_node(face, i, "res_mooncap", dir, 240.0)
			var up_ms: Vector3 = dir
			var hint_ms: Vector3 = Vector3(0, 1, 0) if abs(up_ms.dot(Vector3(0, 1, 0))) < 0.999 else Vector3(1, 0, 0)
			var east_ms: Vector3 = (hint_ms - up_ms * hint_ms.dot(up_ms)).normalized()
			fungi_s.basis = Basis(east_ms, up_ms, east_ms.cross(up_ms))
			patch_node.add_child(fungi_s)
			spawned += 1
			continue
		if is_mycelium:
			var pr_s: float = rng.randf_range(0.5, 1.3)
			var patch_s := MeshInstance3D.new()
			patch_s.mesh = _shared_prop_sphere(pr_s, 0.12)
			var mat_s := StandardMaterial3D.new()
			mat_s.roughness = 0.55
			var pv_s: float = rng.randf()
			mat_s.albedo_color = Color(0.5 + 0.2 * pv_s, 0.3 + 0.1 * pv_s, 0.6 + 0.2 * (1.0 - pv_s))
			mat_s.emission_enabled = true
			mat_s.emission = Color(0.42, 0.22, 0.55).lerp(Color(0.20, 0.55, 0.50), pv_s)
			mat_s.emission_energy_multiplier = 1.2
			patch_s.material_override = mat_s
			patch_s.name = "Mycelium%d" % i
			patch_s.position = _tangent_patch_local(dir, patch_center, scaled + base_h + 0.03)
			patch_node.add_child(patch_s)
			spawned += 1
			continue
		if is_dry_tuft:
			# THE DRY BRUSH (v9, sync twin -- see the derive law above):
			# the range band's dry tuft, the hunker scale, the band's
			# own tint via the batch majority law.
			var dpos: Vector3 = _tangent_patch_local(dir, patch_center, scaled + base_h)
			var up_d: Vector3 = dir
			var hint_d: Vector3 = Vector3(0, 1, 0) if abs(up_d.dot(Vector3(0, 1, 0))) < 0.999 else Vector3(1, 0, 0)
			var east_d: Vector3 = (hint_d - up_d * hint_d.dot(up_d)).normalized()
			var dyaw: float = rng.randf_range(0.0, TAU)
			var dscl: float = rng.randf_range(0.4, 0.9)
			tuft_xforms.append(Transform3D(
				Basis(east_d, up_d, east_d.cross(up_d)).rotated(up_d, dyaw).scaled(Vector3.ONE * dscl), dpos))
			tuft_bids.append(bid)
			spawned += 1
			continue
		if is_ore:
			# ORE VEIN (prd-gathering build order 2): the mountain/tundra
			# band carries the mine. A dark boulder-chunk, registered as
			# an iron-ore gather node (the gather->forge leg below the
			# visual: what you SEE is what you can harvest).
			var r_o: float = rng.randf_range(0.35, 0.7)
			mesh = _shared_prop_sphere(r_o, 1.6)
			mat.albedo_color = Color(0.35, 0.33, 0.36)
			prop.mesh = mesh
			prop.material_override = mat
			prop.name = "Ore%d" % i
			prop.position = _tangent_patch_local(dir, patch_center, scaled + base_h + r_o * 0.2)
			_register_harvest_node(face, i, "res_iron_ore", dir, 90.0)
			spawned += 1
			patch_node.add_child(prop)
			continue
		if is_shell:
			# THE SHELL (v10 beach law, sync twin -- see the derive rec):
			# a small pale seam half-buried -- pure paint.
			var rs_s: float = rng.randf_range(0.05, 0.12)
			prop.mesh = _shared_prop_sphere(rs_s, 1.3)
			mat.albedo_color = Color(0.90, 0.86, 0.79)
			mat.roughness = 0.55
			prop.material_override = mat
			prop.name = "Shell%d" % i
			prop.position = _tangent_patch_local(dir, patch_center, scaled + base_h + rs_s * 0.35)
			patch_node.add_child(prop)
			spawned += 1
			continue
		if is_wrack:
			# THE WRACK LAW (v10 beach law, sync twin): the kelp ball,
			# the beach's spoor line -- brown splay.
			var rw_s: float = rng.randf_range(0.25, 0.55)
			var wd_s: float = rng.randf()
			prop.mesh = _shared_prop_sphere(rw_s, 1.4)
			mat.albedo_color = Color(0.20 + 0.06 * wd_s, 0.28 + 0.05 * wd_s, 0.24)
			mat.roughness = 1.0
			prop.material_override = mat
			prop.name = "Wrack%d" % i
			prop.basis = Basis()
			prop.position = _tangent_patch_local(dir, patch_center, scaled + base_h + rw_s * 0.25)
			patch_node.add_child(prop)
			spawned += 1
			continue
		if is_cattail:
			# Reed: a thin dark-green cylinder with a brown head.
			var h_c: float = rng.randf_range(0.9, 1.4)
			mesh = _shared_prop_cyl(0.03, 0.05, h_c)
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
		if not is_bush and not is_bush_kept:
			continue  # shore bare sand + any unclaimed band: no prop (v10)
		# Bush: a squat green sphere.
			var r_b: float = rng.randf_range(0.4, 0.9)
			mesh = _shared_prop_sphere(r_b, 1.4)
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
	# THE TUFT BATCH FLUSH: the deferred MultiMesh painter.
	_apply_tuft_batch(tuft_xforms, tuft_bids, patch_node)


## ===== THE PROP DERIVE / APPLY SPLIT (v6 threading) ============
## _spawn_trees/_spawn_detail_props keep their SYNC bodies (one-shot
## cold spawns, probes, and any threadless host run them today). The
## web boot path kicks the derivation to a background thread so the
## mesh pass never stalls on thousands of site reads. The derive
## pair below MIRRORS the sync law rng-for-rng (same site formulas,
## same draw order) so async content equals sync content on every
## machine -- edits to one copy must edit the other (the parity IS
## the determinism law of this split).
##
## THE WORKER LAW: the thread touches NO mutable streamer state.
## Ground reads bypass the patch-walk dictionary with the closure's
## own pure law (terrain + rock-top provider, both on the LOCKED
## sector caches); rng chains are job-local; results cross back via
## the mutex; every node build happens on the main thread in the
## deferred apply.
var _prop_mutex := Mutex.new()
var _prop_jobs := {}     # face -> true while a derive is in flight
var _prop_results := {}  # face -> packed derive arrays (set in thread)
var _prop_threads := {}  # face -> Thread (reaped in the apply pass)

## Threading gate: the terrain arc's content only (the prototype's
## S7 greenery keeps the sync path -- cheap and law-pinned).
func _prop_async() -> bool:
	return lod_on and terrain_on

## Probe/test surface: jobs still deriving in flight.
func _prop_pending() -> int:
	return _prop_threads.size()

func _kick_prop_derivation(face: int) -> void:
	_prop_mutex.lock()
	var busy: bool = _prop_jobs.has(face) or _prop_results.has(face)
	_prop_mutex.unlock()
	if busy:
		return  # already deriving (the guard survives a face revisit)
	_prop_jobs[face] = true
	if terrain_on:
		# The strait freight is a service registration (main-thread
		# side effect) -- it stays on the caller, not the worker.
		_prop_register_freight(face)
	var t := Thread.new()
	_prop_threads[face] = t
	t.start(Callable(self, "_prop_derive_job").bind(face, _decor_salt), Thread.PRIORITY_LOW)

func _prop_register_freight(face: int) -> void:
	_register_strait_freight(face, FacePatches.face_center(face).normalized(), world_seed)

func _prop_derive_job(face: int, salt: int = 0) -> void:
	# Runs OFF the main thread. Pure derive only; the packed result
	# crosses the mutex; the apply is queued back to the main thread.
	var packed := {
		"trees": _derive_tree_sites(face, salt),
		"details": _derive_detail_sites(face),
		"grass": _derive_grass_field(face, salt),
	}
	_prop_mutex.lock()
	_prop_results[face] = packed
	_prop_mutex.unlock()
	Callable(self, "_apply_derived_props").call_deferred(face)

func _apply_derived_props(face: int) -> void:
	var th = _prop_threads.get(face)
	_prop_mutex.lock()
	var packed = _prop_results.get(face)
	_prop_results.erase(face)
	_prop_mutex.unlock()
	if th != null:
		th.wait_to_finish()  # the job has returned by the time the deferral fires
		_prop_threads.erase(face)
	if packed == null:
		return
	if not _patches.has(face) or _patches[face] == null:
		# Streamed out mid-derive: drop the content (a revisit re-kicks).
		_prop_jobs.erase(face)
		return
	var patch_node: Node3D = _prop_holder(face, _patches[face])
	var tree_nodes: Array = _apply_tree_sites(face, packed["trees"], patch_node)
	_apply_detail_sites(face, packed["details"], patch_node)
	_apply_grass_field(packed["grass"], patch_node)
	# The collider law (moved from _spawn_rocks -- the tree build is
	# async now, so the new node trees carry it in this pass):
	# trunk bodies block + join the climbable group; canopies stay
	# intangible (walking under a crown must not feel like a ceiling).
	for tree in tree_nodes:
		PropCollider.attach_trunk(tree)
	_prop_jobs.erase(face)

func _prop_site_ground_h(dir: Vector3, face: int) -> float:
	# THE THREAD-SAFE GROUND READ: the patch-walk closure's body,
	# without the dictionary touch (both laws are pure on the locked
	# sector caches).
	var base: float = TerrainGen.terrain_height(dir, world_seed) if terrain_on else 0.0
	return base + TerrainGen.rock_top_height(dir, world_seed, face, radius)

## --- tree derive / apply (mirrors _spawn_trees rng-for-rng) ------
func _derive_tree_sites(face: int, salt: int = 0) -> Array:
	var sites: Array = []
	var bytes: PackedByteArray = TerrainGen.face_seed_bytes(world_seed, face)
	var acc: int = 0
	for b in bytes:
		acc = (acc * 131 + b) % 9007199254740991
	var rng := RandomNumberGenerator.new()
	# THE DECO SALT (the FIELD-2 split, derive twin): the decorative
	# canopy chain recombines per session (see configure()); the
	# worker reads the BOUND salt (no member touch off-thread) and
	# every other rng input stays the world seed's own.
	rng.seed = (acc + salt) % 9007199254740991
	var count: int = rng.randi_range(4, 8)
	# THE DENSITY LAW (mirror: see _spawn_trees for the band ladder).
	if terrain_on:
		var cbid: int = TerrainGen.climate_biome_id(FacePatches.face_center(face).normalized(), world_seed)
		if cbid == TerrainGen.BiomeId.FOREST or cbid == TerrainGen.BiomeId.TAIGA \
			or cbid == TerrainGen.BiomeId.JUNGLE:
			count = rng.randi_range(1400, 2100)
		elif cbid == TerrainGen.BiomeId.SWAMP:
			count = rng.randi_range(300, 460)
		elif cbid == TerrainGen.BiomeId.GRASSLAND:
			count = rng.randi_range(2200, 3000)
		elif cbid == TerrainGen.BiomeId.SAVANNA:
			count = rng.randi_range(400, 640)
		elif cbid == TerrainGen.BiomeId.SHORE:
			count = rng.randi_range(400, 640)
		elif cbid == TerrainGen.BiomeId.DESERT or cbid == TerrainGen.BiomeId.TUNDRA \
				or cbid == TerrainGen.BiomeId.STEPPE or cbid == TerrainGen.BiomeId.BADLANDS:
			count = rng.randi_range(80, 140)
		else:
			count = rng.randi_range(12, 24)  # alpine / lake / ocean center: site floor
	var verts: PackedInt32Array = FacePatches.face_vertices(face)
	var patch_center: Vector3 = FacePatches.face_center(face) * (radius + TILE_LIFT)
	var scaled: float = radius + TILE_LIFT
	var sea: float = TerrainGen.sea_level(world_seed)
	for i in range(count):
		var v: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var v2: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var dir: Vector3 = (FacePatches.face_center(face) * 0.25 + v * 0.35 + v2 * 0.40).normalized()
		# THE AUTHORED NECK (v11): the Sun Pans atoll is a small island
		# inside a giant face -- the raw barycentric scatter misses it
		# for a lifetime of attempts. A pans-bearing face pours ALL its
		# detail attempts through the atoll's cone (the tight splay
		# keeps the rim ring and beach covered); the rest of the face
		# is empty ocean and correctly stays bare.
		if FacePatches.face_center(face).angle_to(TerrainGen.sun_pans_dir()) \
				<= _face_reach(face) + TerrainGen.SUN_PANS_ANG:
			dir = dir.slerp(TerrainGen.sun_pans_dir(), rng.randf_range(0.955, 0.985))
		# THE BOOT GROVE PULL (grid the sync law rides; see it above).
		if FacePatches.face_center(face).angle_to(TerrainGen.SPAWN_CENTER) \
				< TerrainGen.HOMELAND_ANGULAR_REACH:
			dir = dir.slerp(TerrainGen.SPAWN_CENTER, 0.62)
		var base_h: float = _prop_site_ground_h(dir, face)
		if terrain_on and base_h < sea - 0.6:
			continue
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
		var trunk_h: float = rng.randf_range(1.8, 3.2)
		var crown: float = rng.randf_range(1.1, 2.0)
		var gval: float = 0.3 + 0.14 * rng.randf()
		var tint_r: float = 0.18 + 0.06 * rng.randf()
		var yaw: float = rng.randf_range(0.0, TAU)
		var sp: int = 0
		if terrain_on:
			sp = TerrainGen.tree_species_at(dir, world_seed)
		sites.append({
			"dir": dir, "pos": _tangent_patch_local(dir, patch_center, scaled + base_h),
			"trunk_h": trunk_h, "crown": crown, "tint_r": tint_r, "gval": gval,
			"yaw": yaw, "sp": sp,
		})
	return sites

func _apply_tree_sites(face: int, sites: Array, patch_node: Node3D) -> Array:
	var lvl: int = int(_patch_lvl.get(face, -1))
	var base_lvl: int = _level_for_edge()
	var batched: bool = lod_on and terrain_on and lvl != -1 and lvl != base_lvl
	var node_left: int = NODE_TREE_CAP
	var pdir_known: bool = _last_player_dir != Vector3.ZERO
	var nodes_out: Array = []
	var batch_xforms: Array = []
	var canopy_batch_xforms: Array = []
	var name_idx: int = 0
	for s in sites:
		var up: Vector3 = s["dir"]
		var hint := Vector3(0, 1, 0)
		if abs(up.dot(hint)) > 0.999:
			hint = Vector3(0, 0, -1)
		var east: Vector3 = (hint - up * hint.dot(up)).normalized()
		var north: Vector3 = east.cross(up)
		var tree_basis := Basis(east, up, north).rotated(up, s["yaw"])
		# THE SPECIES LAW (v7): read the site's species once, then let
		# both build paths (node + batched) branch on it. Conifer
		# stacks a cone; acacia flattens the crown wider; palm thins
		# the trunk and lifts a small head (fronds read at near level);
		# mangrove muddies the tint and squashes the crown low; snag
		# kills the canopy (bare gray); baobab fattens the trunk base.
		var species: int = int(s.get("sp", 0))
		var trunk_w_mult: float = 1.0
		var trunk_tint: Color = Color(0.36, 0.26, 0.17)
		var canopy_h_mult: float = 1.8
		var canopy_w_mult: float = 1.0
		var canopy_tint_extra: float = 0.0
		var bare: bool = false  # dead snag: no canopy at all
		match species:
			TerrainGen.TreeSpecies.CONIFER:
				canopy_h_mult = 2.6
				canopy_w_mult = 0.62
				canopy_tint_extra = -0.06
			TerrainGen.TreeSpecies.ACACIA:
				canopy_h_mult = 0.9
				canopy_w_mult = 1.55
				canopy_tint_extra = 0.05
			TerrainGen.TreeSpecies.PALM:
				trunk_w_mult = 0.5
				canopy_h_mult = 0.55
				canopy_w_mult = 0.85
				canopy_tint_extra = 0.12
				trunk_tint = Color(0.46, 0.37, 0.24)
			TerrainGen.TreeSpecies.MANGROVE:
				canopy_h_mult = 1.1
				canopy_w_mult = 1.25
				trunk_tint = Color(0.28, 0.24, 0.18)
				canopy_tint_extra = -0.08
			TerrainGen.TreeSpecies.DEAD_SNAG:
				bare = true
				trunk_tint = Color(0.5, 0.47, 0.44)
			TerrainGen.TreeSpecies.BAOBAB:
				trunk_w_mult = 2.6
				trunk_tint = Color(0.45, 0.34, 0.24)
				canopy_w_mult = 1.35
				canopy_tint_extra = 0.04
		var take_node: bool = not batched and node_left > 0 \
			and (not pdir_known or up.angle_to(_last_player_dir) <= TREE_NODE_ANG)
		if take_node:
			node_left -= 1
			var tree := Node3D.new()
			tree.name = "Tree%d" % name_idx  # census/collider law: name-resolvable
			name_idx += 1
			var trunk := MeshInstance3D.new()
			trunk.mesh = _shared_prop_cyl(0.14 * (trunk_w_mult if trunk_w_mult >= 1.0 else 1.0), 0.22 * trunk_w_mult, s["trunk_h"])
			var tmat := StandardMaterial3D.new()
			tmat.albedo_color = trunk_tint
			tmat.roughness = 1.0
			trunk.material_override = tmat
			trunk.position = Vector3(0, s["trunk_h"] * 0.5, 0)
			tree.add_child(trunk)
			if not bare:
				var canopy := MeshInstance3D.new()
				# Same species dims; the aspect rides the helper (h/r law kept).
				canopy.mesh = _shared_prop_sphere(s["crown"] * canopy_w_mult, canopy_h_mult / canopy_w_mult)
				var cmat := StandardMaterial3D.new()
				cmat.albedo_color = Color(
					clampf(s["tint_r"] + canopy_tint_extra, 0.0, 0.6),
					clampf(s["gval"] + canopy_tint_extra * 0.5, 0.1, 0.7), 0.16)
				cmat.roughness = 1.0
				canopy.material_override = cmat
				canopy.position = Vector3(0, s["trunk_h"] + s["crown"] * canopy_h_mult * 0.35, 0)
				tree.add_child(canopy)
			tree.position = s["pos"]
			tree.basis = tree_basis
			# THE VINE LAW (v7): wood-creeper threads hang from the wet
			# bands' canopies -- JUNGLE dense (2..4 hangs), FOREST sparse
			# (0..2), SWAMP mossy (1..3). Pure paint: no collider, no
			# harvest tag; the twin batched far-face path skips vines
			# (the horizon can't afford threads). Each vine is a thin
			# tapered cylinder chained down the canopy's rim by yaw.
			var site_bid: int = TerrainGen.climate_biome_id(s["dir"], world_seed)
			var vine_n: int = 0
			if site_bid == TerrainGen.BiomeId.JUNGLE:
				vine_n = 2 + (name_idx % 3)
			elif site_bid == TerrainGen.BiomeId.FOREST:
				vine_n = name_idx % 3
			elif site_bid == TerrainGen.BiomeId.SWAMP:
				vine_n = 1 + (name_idx % 3)
			if not bare and vine_n > 0:
				var canopy_rim: float = s["trunk_h"] + s["crown"] * canopy_h_mult * 0.35
				var vine_top: Vector3 = Vector3(0, canopy_rim, 0)
				for kv in range(vine_n):
					var hang := MeshInstance3D.new()
					var hang_len: float = s["crown"] * 0.9 + 0.3
					hang.mesh = _shared_prop_cyl(0.035, 0.012, hang_len)
					var hang_mat := StandardMaterial3D.new()
					hang_mat.albedo_color = Color(0.24, 0.40, 0.20)
					hang_mat.roughness = 1.0
					hang.material_override = hang_mat
					var vang: float = TAU * float(kv) / float(vine_n) + 0.4
					hang.position = vine_top + Vector3(cos(vang) * s["crown"] * canopy_w_mult * 0.55, -hang_len * 0.5, sin(vang) * s["crown"] * canopy_w_mult * 0.55)
					tree.add_child(hang)
			patch_node.add_child(tree)
			nodes_out.append(tree)
		else:
			var tpose: Transform3D = Transform3D(tree_basis, s["pos"])
			batch_xforms.append(tpose * Transform3D(Basis.IDENTITY.scaled(Vector3(trunk_w_mult, s["trunk_h"], trunk_w_mult)), Vector3(0, s["trunk_h"] * 0.5, 0)))
			if not bare:
				canopy_batch_xforms.append(tpose * Transform3D(Basis.IDENTITY.scaled(Vector3(s["crown"] * canopy_w_mult, s["crown"] * canopy_h_mult, s["crown"] * canopy_w_mult)), Vector3(0, s["trunk_h"] + s["crown"] * canopy_h_mult * 0.35, 0)))
	# -- Flush the batch (far faces AND near overflow) ------------------
	if batch_xforms.size() > 0:
		var tmesh2 := MultiMesh.new()
		tmesh2.transform_format = MultiMesh.TRANSFORM_3D
		tmesh2.mesh = _shared_prop_cyl(0.14, 0.22, 1.0)  # unit: per-instance scale stretches it
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
		var mmesh2 := MultiMesh.new()
		mmesh2.transform_format = MultiMesh.TRANSFORM_3D
		mmesh2.mesh = _shared_prop_sphere(1.0, 1.0)
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
	return nodes_out

## --- detail derive / apply (mirrors _spawn_detail_props rng-for-rng)
## Kind codes: 0 ore, 1 cattail, 2 bush, 3 tuft, 4 flower.
const _DPROP_ORE: int = 0
const _DPROP_CATTAIL: int = 1
const _DPROP_BUSH: int = 2
const _DPROP_TUFT: int = 3
const _DPROP_FLOWER: int = 4
const _DPROP_MUSHROOM: int = 5   # v7: fungal cap (swamp/forest/jungle)
const _DPROP_MYECLIUM: int = 6   # v7: glowing mycelium patch (same bands)
const _DPROP_SHELL: int = 7     # v10: beach shell seam (SHORE band)
const _DPROP_WRACK: int = 8     # v10: kelp wrack ball (SHORE band)

## THE FACE BAND ASK (v9, the travel law): "when a biome is there and
## a player gets to it, it renders" -- so a face pays what its
## CONTAINED bands need, not just its center band. The travel census
## proved the center-band read starves sliver-dressed faces (forest
## swamps/desert pans inside lake-center faces derived EMPTY). Seven
## pure climate reads (center + 3 verts + 3 edge midpoints) resolve
## the face's band set; the ask is the MAX ladder entry the bands
## carry. Thread-safe: climate reads are pure (the worker law).
func _face_band_ask(face: int) -> int:
	var center: Vector3 = FacePatches.face_center(face).normalized()
	var verts: PackedInt32Array = FacePatches.face_vertices(face)
	var asks: Array = [center]
	for vi in range(3):
		asks.append(Icosahedral.VERTICES[verts[vi]].normalized())
		asks.append((center + Icosahedral.VERTICES[verts[vi]].normalized()).normalized())
	# THE AUTHORED CONTENT (v11): the Sun Pans atoll's own bands are
	# far smaller than the face's sample grid -- the bearing face pays
	# the atoll's band ask so the desert island dresses + renders.
	var pans: Vector3 = TerrainGen.sun_pans_dir()
	if center.angle_to(pans) <= _face_reach(face) + TerrainGen.SUN_PANS_ANG:
		asks.append(pans)
	var best: int = 0
	for d in asks:
		var a: int = int(_DETAIL_BUDGETS.get(TerrainGen.climate_biome_id(d, world_seed), 0))
		if a > best:
			best = a
	return best


## THE DETAIL DENSITY LADDER (v8, FIELD-1 closure): the real-geometry
## port of the tree-tier law. A streamed icosahedral face is ~21 km of
## ground at the planet scale, so the old 18/4 one-size budget starved
## whole boot walks (probe_prop_density on the shipped tree: ZERO props
## within 600 m of spawn, nearest node 2127 m). The ladder pays
## band-appropriate attempt pools (see THE FACE BAND ASK for how a
## face's ask is resolved: the max its contained bands carry). NEAR
## faces pay the full ask; MID faces a quarter; FAR stays skip. Tufts
## (the ~72% meadow mass) are MultiMesh-batched (THE TUFT BATCH LAW)
## so the raise is paid in instance counts, not scene nodes.
const _DETAIL_BUDGETS := {
	TerrainGen.BiomeId.GRASSLAND: 700,
	TerrainGen.BiomeId.SAVANNA: 420,
	TerrainGen.BiomeId.STEPPE: 420,
	TerrainGen.BiomeId.TAIGA: 420,
	TerrainGen.BiomeId.FOREST: 480,
	TerrainGen.BiomeId.ALPINE_MEADOW: 340,
	TerrainGen.BiomeId.JUNGLE: 480,
	TerrainGen.BiomeId.SWAMP: 240,
	TerrainGen.BiomeId.ALPINE: 200,
	TerrainGen.BiomeId.TUNDRA: 200,
	TerrainGen.BiomeId.BADLANDS: 200,
	# THE DESERT LADDER (v11): the Sun Pans atoll's core band -- the
	# ask ladder missed it, so the island-bearing face's ask
	# back-resolved to 0 and the budget gate bailed before the
	# scatter ever rolled. Same tier as the other dry bands.
	TerrainGen.BiomeId.DESERT: 200,
	TerrainGen.BiomeId.SHORE: 160,
}

func _derive_detail_sites(face: int) -> Array:
	var sites: Array = []
	var lvl: int = int(_patch_lvl.get(face, 99))
	# THE BUDGET LAW is level-derived (pure per face -- not a viewer
	# read), so the derive phase can pay it.
	var base_lvl: int = _level_for_edge()
	var drop: int = base_lvl - lvl
	if drop >= 3:
		return sites  # FAR: no detail pass at all (the budget law)
	# THE FLOOR BAND (v9): the LOD ladder is binary (base or floor
	# level), so the old drop>=2 kill left the floor-band faces (the
	# boot window's other slots + every horizon interior) COMPLETELY
	# bare -- the "land past the belt is empty" report. The floor band
	# now pays a reduced, batch-heavy ask instead of zero.
	# THE REAL-GEOMETRY BUDGET (v8): the ladder reads the face CENTER's
	# band -- a 21 km face pays a real-face count, not 18 sites.
	var budget_full: int = _face_band_ask(face)
	# THE LADDER GATE (the galaxy-tier mirror of the FIELD GATE lesson):
	# the boot faces resolve shore/lake CENTERS while hosting the
	# homeland's grassland slivers -- a bare center-band read would
	# leave the homeland detail-bare again. Any homeland-reach face
	# pays the GRASSLAND ask (the meadow band); past the homeland the
	# center-band ladder rules alone.
	if budget_full <= 0:
		if FacePatches.face_center(face).angle_to(TerrainGen.SPAWN_CENTER) \
				>= TerrainGen.HOMELAND_ANGULAR_REACH:
			return sites  # beach/ocean/water center faces stay bare
		budget_full = int(_DETAIL_BUDGETS.get(TerrainGen.BiomeId.GRASSLAND, 0))
	# THE TIER ASK (v9): NEAR faces pay the full ask; drop-1 (a live
	# demote in flight) pays a quarter; the floor band pays 1/8 -- the
	# tuft mass is MultiMesh-batched, so a floor face's dressing costs
	# ~1 draw + a couple dozen nodes instead of zero.
	var mid_div: int = 4 if drop == 1 else 8
	var budget: int = budget_full if drop <= 0 else int(budget_full / mid_div)  # NEAR: full, floor: 1/8
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
	var spawned: int = 0
	var bloom_count: int = 0  # THE WILDFLOWER DRIFT's node ceiling (v14)
	for i in range(budget * 2):  # 2x the ask absorbs the water/bare rejects
		if spawned >= budget:
			break
		var v: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var v2: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var dir: Vector3 = (FacePatches.face_center(face) * 0.25 + v * 0.35 + v2 * 0.40).normalized()
		# THE AUTHORED NECK (v11): the Sun Pans atoll is a small island
		# inside a giant face -- the raw barycentric scatter misses it
		# for a lifetime of attempts. A pans-bearing face pours ALL its
		# detail attempts through the atoll's cone (the tight splay
		# keeps the rim ring and beach covered); the rest of the face
		# is empty ocean and correctly stays bare.
		if FacePatches.face_center(face).angle_to(TerrainGen.sun_pans_dir()) \
				<= _face_reach(face) + TerrainGen.SUN_PANS_ANG:
			dir = dir.slerp(TerrainGen.sun_pans_dir(), rng.randf_range(0.955, 0.985))
		# THE BOOT GROVE PULL (v8 tightened): the homeland-reach faces
		# CONCENTRATE their furniture near the boot belt, not just drag
		# it toward it. At planet scale a face spans ~0.6 rad; the old
		# 0.62 drag left a ~4-5 km residual (the boot's 600 m walk
		# stayed bare while the fields painted 2 km away). 0.88 leaves
		# a ~0.07 rad residual (~70 m) -- the detail band the walk
		# reads. The detail tier's own copy; the grass tier carries its
		# own (same law, same strength).
		if FacePatches.face_center(face).angle_to(TerrainGen.SPAWN_CENTER) \
				< TerrainGen.HOMELAND_ANGULAR_REACH:
			dir = dir.slerp(TerrainGen.SPAWN_CENTER, 0.88)
		var base_h: float = _prop_site_ground_h(dir, face)
		if base_h < sea - 0.2:
			continue  # no props in the water band
		var bid: int = TerrainGen.climate_biome_id(dir, world_seed)
		var is_cattail: bool = bid == TerrainGen.BiomeId.SWAMP \
			or bid == TerrainGen.BiomeId.RIVER  # the river banks carry the reeds too (v10)
		var meadow: bool = bid == TerrainGen.BiomeId.GRASSLAND \
				or bid == TerrainGen.BiomeId.SAVANNA or bid == TerrainGen.BiomeId.STEPPE \
				or bid == TerrainGen.BiomeId.TAIGA
		var is_bush: bool = bid == TerrainGen.BiomeId.FOREST \
			or bid == TerrainGen.BiomeId.ALPINE_MEADOW \
			or bid == TerrainGen.BiomeId.JUNGLE
		var is_ore: bool = bid == TerrainGen.BiomeId.ALPINE or bid == TerrainGen.BiomeId.TUNDRA \
			or bid == TerrainGen.BiomeId.BADLANDS
		# THE DRY RANGE LAW (v9): the range bands (desert + the ladder's
		# ALPINE/TUNDRA/BADLANDS) are not stone-only any more -- the
		# range carries dry brush now (straw/frost/rust tufts).
		var is_dry_band: bool = bid == TerrainGen.BiomeId.DESERT or is_ore
		var is_shore: bool = bid == TerrainGen.BiomeId.SHORE  # the beach law's band gate
		if not is_cattail and not is_bush and not is_dry_band and not meadow \
				and not is_shore:
			continue  # beach/ocean/water bands stay bare
		var meadow_roll: float = rng.randf()
		# THE WILDFLOWER DRIFT (v14): the meadow's bloom gate rides the
		# land's own drift signal -- a PURE read (no rng draw, the twin
		# draw counts hold) -- so a strong cell carries up to ~50% of its
		# sites in bloom while the open meadow keeps the v5 sprinkle.
		var flower_gate: float = 0.10
		if meadow and bid == TerrainGen.BiomeId.GRASSLAND:
			flower_gate = 0.10 + 0.40 * TerrainGen.wildflower_drift(dir)
		var is_flower: bool = meadow and bid == TerrainGen.BiomeId.GRASSLAND \
				and meadow_roll < flower_gate
		# THE BLOOM NODE CAP (the perf law): the raise is paid by the
		# per-face node ceiling -- past it the site stays meadow (the
		# field stops growing, the budget does not explode).
		if is_flower and bloom_count >= BLOOM_NODE_CAP:
			is_flower = false
		var is_bush_kept: bool = meadow and not is_flower and meadow_roll > 0.82
		var is_tuft: bool = meadow and not is_flower and not is_bush_kept
		# THE FUNGAL TIER (v7, mycelial-sync law): the wet+dark bands
		# carry mushrooms and glowing mycelium patches -- a drum-roll
		# after the meadow roll keeps the draw order stable: in the
		# fungal bands ~14% of sites grow a cap cluster and ~8% a
		# mycelium patch (the sum never crowds out all bush sites,
		# the roll order stays untouched).
		var fungal: bool = bid == TerrainGen.BiomeId.SWAMP \
			or bid == TerrainGen.BiomeId.FOREST or bid == TerrainGen.BiomeId.JUNGLE \
			or bid == TerrainGen.BiomeId.TAIGA
		var fungal_roll: float = rng.randf()
		var is_mushroom: bool = fungal and fungal_roll < 0.14
		var is_mycelium: bool = fungal and not is_mushroom and fungal_roll < 0.22
		# THE DRY RANGE ROLL (v9): one draw per dry site splits the
		# range's ask -- ~55% dry brush (the straw/frost/rust tuft),
		# the rest keeps the boulder-ore vein. Own draw: the
		# rng-for-rng twin law carries the same draw in both paths.
		var is_dry_tuft: bool = is_dry_band and rng.randf() < 0.55
		# THE BEACH LAW (v10): the shore band is the planet's ring of
		# contact -- the beach map scan measures 11.4% of the globe's
		# surface and it rendered NOTHING before. Shore sites split:
		# ~60% shells (pale half-buried seams), ~17% kelp wrack (brown
		# squat balls), the rest bare sand. Own draws: the rng-for-rng
		# twin law carries the same two draws in both paths.
		var is_shell: bool = false
		var is_wrack: bool = false
		if is_shore:
			var shore_roll: float = rng.randf()
			is_shell = shore_roll < 0.60
			is_wrack = not is_shell and shore_roll < 0.77
		var rec := {"i": i, "dir": dir, "kind": -1, "bid": bid}  # every kind carries its band
		if is_tuft:
			rec["kind"] = _DPROP_TUFT
			rec["pos"] = _tangent_patch_local(dir, patch_center, scaled + base_h)
			rec["yaw"] = rng.randf_range(0.0, TAU)
			rec["scale"] = rng.randf_range(0.7, 1.6)
			rec["bid"] = bid  # the batch tint rides the majority band
			spawned += 1
		elif is_flower:
			bloom_count += 1
			rec["kind"] = _DPROP_FLOWER
			rec["pos"] = _tangent_patch_local(dir, patch_center, scaled + base_h)
			rec["stem_h"] = rng.randf_range(0.20, 0.38)
			rec["r_h"] = rng.randf_range(0.055, 0.105)
			# THE DRIFT SPECIES (the sync twin): the palette rides the drift
			# band -- one kind per patch, a rare intruder (the same single
			# randi() draw, so the twin draw counts hold).
			var species: int = int(TerrainGen.wildflower_drift(dir) * 7.0) % _bloom_palette().size()
			rec["pal"] = species if (rng.randi() % 6) != 0 else (species + 1) % _bloom_palette().size()
			rec["yaw"] = rng.randf_range(0.0, TAU)
			spawned += 1
		elif is_mushroom:
			rec["kind"] = _DPROP_MUSHROOM
			rec["cap_r"] = rng.randf_range(0.10, 0.30)
			rec["stem_h"] = rng.randf_range(0.18, 0.55)
			rec["pal"] = rng.randi() % 4  # fungal palette (apply twin)
			rec["pos"] = _tangent_patch_local(dir, patch_center, scaled + base_h)
			rec["yaw"] = rng.randf_range(0.0, TAU)
			spawned += 1
		elif is_mycelium:
			rec["kind"] = _DPROP_MYECLIUM
			rec["patch_r"] = rng.randf_range(0.5, 1.3)
			rec["hue"] = rng.randf()  # pale violet <-> teal (apply twin)
			rec["pos"] = _tangent_patch_local(dir, patch_center, scaled + base_h + 0.03)
			spawned += 1
		elif is_dry_tuft:
			# THE DRY BRUSH REC (v9): the range band's dry tuft -- the
			# same tuft family, the hunker scale, the band's own tint
			# (straw/frost/rust) carried by the batch's majority law.
			rec["kind"] = _DPROP_TUFT
			rec["pos"] = _tangent_patch_local(dir, patch_center, scaled + base_h)
			rec["yaw"] = rng.randf_range(0.0, TAU)
			rec["scale"] = rng.randf_range(0.4, 0.9)  # the dry hunker law
			rec["bid"] = bid
			spawned += 1
		elif is_ore:
			rec["kind"] = _DPROP_ORE
			rec["r_o"] = rng.randf_range(0.35, 0.7)
			rec["pos"] = _tangent_patch_local(dir, patch_center, scaled + base_h + rec["r_o"] * 0.2)
			spawned += 1
		elif is_shell:
			# THE SHELL REC (v10 beach law): a small pale seam
			# half-buried -- pure paint, no collider, no harvest (the
			# beach keeps its walk-pretty law).
			rec["kind"] = _DPROP_SHELL
			rec["r_s"] = rng.randf_range(0.05, 0.12)
			rec["pos"] = _tangent_patch_local(dir, patch_center, scaled + base_h + rec["r_s"] * 0.35)
			spawned += 1
		elif is_wrack:
			# THE WRACK REC (v10 beach law): the kelp ball, the beach's
			# spoor line -- brown splay, same squat-ball build as the
			# bush tier.
			rec["kind"] = _DPROP_WRACK
			rec["r_w"] = rng.randf_range(0.25, 0.55)
			rec["tint"] = rng.randf()
			rec["pos"] = _tangent_patch_local(dir, patch_center, scaled + base_h + rec["r_w"] * 0.25)
			spawned += 1
		elif is_cattail:
			rec["kind"] = _DPROP_CATTAIL
			rec["h"] = rng.randf_range(0.9, 1.4)
			rec["pos"] = _tangent_patch_local(dir, patch_center, scaled + base_h + 0.05)
			spawned += 1
		elif is_bush or is_bush_kept:
			# THE BUSH REC (v10): the catch-all is no longer a catch-all
			# -- the beach law lets bare-sand shore sites fall through
			# every branch, and only the bush BANDS (or the meadow's
			# bush_kept shrubs) grow a bush.
			rec["kind"] = _DPROP_BUSH
			rec["r_b"] = rng.randf_range(0.4, 0.9)
			rec["tint_r"] = 0.22 + 0.1 * rng.randf()
			rec["tint_g"] = 0.42 + 0.1 * rng.randf()
			rec["pos"] = _tangent_patch_local(dir, patch_center, scaled + base_h + rec["r_b"] * 0.25)
			spawned += 1
		if rec["kind"] != -1:
			sites.append(rec)  # THE CLAIM LAW (v10): bare-sand sites append nothing
	return sites

func _apply_detail_sites(face: int, sites: Array, patch_node: Node3D) -> void:
	var tuft_xforms: Array = []  # THE TUFT BATCH: one MultiMesh paints the field
	var tuft_bids: Array = []  # the batch material is the MAJORITY band's tint
	for rec in sites:
		var i: int = int(rec["i"])
		var dir: Vector3 = rec["dir"]
		if int(rec["kind"]) == _DPROP_TUFT:
			# THE TUFT LAW (v9 tinted batch -- the grass-field paint
			# law): one shared MultiMesh paints the face's whole tuft
			# field (the flush below); per-tuft variance rides the
			# instance transform and the batch material is the MAJORITY
			# band's tint. No node per blade.
			var up_t: Vector3 = dir
			var hint_t: Vector3 = Vector3(0, 1, 0) if abs(up_t.dot(Vector3(0, 1, 0))) < 0.999 else Vector3(1, 0, 0)
			var east_t: Vector3 = (hint_t - up_t * hint_t.dot(up_t)).normalized()
			var tscl: float = float(rec["scale"])
			tuft_xforms.append(Transform3D(
				Basis(east_t, up_t, east_t.cross(up_t)).rotated(up_t, float(rec["yaw"])).scaled(Vector3.ONE * tscl),
				rec["pos"]))
			tuft_bids.append(int(rec.get("bid", -1)))
		elif int(rec["kind"]) == _DPROP_FLOWER:
			var bloom := Node3D.new()
			bloom.name = "Flower%d" % i
			bloom.position = rec["pos"]
			var stem := MeshInstance3D.new()
			var stem_h: float = float(rec["stem_h"])
			stem.mesh = _shared_prop_cyl(0.02, 0.03, stem_h)
			stem.material_override = _bloom_stem_material()
			stem.position = Vector3(0.0, stem_h * 0.5, 0.0)
			var head := MeshInstance3D.new()
			var r_h: float = float(rec["r_h"])
			head.mesh = _shared_prop_sphere(r_h, 1.3)
			head.material_override = _bloom_head_material(int(rec["pal"]))
			head.position = Vector3(0.0, stem_h + r_h * 0.25, 0.0)
			bloom.add_child(stem)
			bloom.add_child(head)
			var up_f: Vector3 = dir
			var hint_f: Vector3 = Vector3(0, 1, 0) if abs(up_f.dot(Vector3(0, 1, 0))) < 0.999 else Vector3(1, 0, 0)
			var east_f: Vector3 = (hint_f - up_f * hint_f.dot(up_f)).normalized()
			bloom.basis = Basis(east_f, up_f, east_f.cross(up_f)).rotated(up_f, rec["yaw"])
			patch_node.add_child(bloom)
		elif int(rec["kind"]) == _DPROP_MUSHROOM:
			# THE FUNGAL BUILD (v7): a stem + broad cap, one of four
			# palette tints (blush, honey, ivory, violet-rimmed); a
			# clay beach never grows one (the meadow keeps the blooms,
			# the fungal bands keep the caps). Pure paint -- no
			# harvest registration (the fungal harvest rides the
			# same law as the bush: only what a quest asks for).
			var fungi := Node3D.new()
			fungi.name = "Mushroom%d" % i
			fungi.position = rec["pos"]
			var pal_idx: int = int(rec["pal"])
			var fungal_c: Color = [
				Color(0.70, 0.30, 0.36),
				Color(0.72, 0.54, 0.28),
				Color(0.80, 0.78, 0.70),
				Color(0.55, 0.36, 0.62),
			][pal_idx]
			var cpp_stem := MeshInstance3D.new()
			var stem_h_m: float = float(rec["stem_h"])
			var stem_mat := StandardMaterial3D.new()
			stem_mat.albedo_color = Color(0.78, 0.74, 0.66)
			stem_mat.roughness = 1.0
			cpp_stem.mesh = _shared_prop_cyl(0.035, 0.055, stem_h_m)
			cpp_stem.material_override = stem_mat
			cpp_stem.position = Vector3(0.0, stem_h_m * 0.5, 0.0)
			fungi.add_child(cpp_stem)
			var cpp_cap := MeshInstance3D.new()
			var cap_r_m: float = float(rec["cap_r"])
			var cap_mat := StandardMaterial3D.new()
			cap_mat.albedo_color = fungal_c
			cap_mat.roughness = 0.8
			cpp_cap.mesh = _shared_prop_sphere(cap_r_m, 0.9)  # squat cap, not a full ball
			cpp_cap.material_override = cap_mat
			cpp_cap.position = Vector3(0.0, stem_h_m + cap_r_m * 0.2, 0.0)
			fungi.add_child(cpp_cap)
			var up_m: Vector3 = dir
			var hint_m: Vector3 = Vector3(0, 1, 0) if abs(up_m.dot(Vector3(0, 1, 0))) < 0.999 else Vector3(1, 0, 0)
			var east_m: Vector3 = (hint_m - up_m * hint_m.dot(up_m)).normalized()
			fungi.basis = Basis(east_m, up_m, east_m.cross(up_m)).rotated(up_m, float(rec["yaw"]))
			patch_node.add_child(fungi)
			# THE FUNGAL HARVEST LAW (v7 polish): what you see is what you
			# gather -- the drawn cap cluster registers as a live
			# HarvestService node yielding the grove's own mooncap (the
			# drawn bush registers the same way; the ore branch too).
			# Respawn slow: groves regenerate on the mycelial clock.
			_register_harvest_node(face, i, "res_mooncap", dir, 240.0)
		elif int(rec["kind"]) == _DPROP_MYECLIUM:
			var patch_n := MeshInstance3D.new()
			var pr_m: float = float(rec["patch_r"])
			var mat_p := StandardMaterial3D.new()
			mat_p.roughness = 0.55
			var pv: float = float(rec["hue"])
			mat_p.albedo_color = Color(0.5 + 0.2 * pv, 0.3 + 0.1 * pv, 0.6 + 0.2 * (1.0 - pv))
			mat_p.emission_enabled = true
			mat_p.emission = Color(0.42, 0.22, 0.55).lerp(Color(0.20, 0.55, 0.50), pv)
			mat_p.emission_energy_multiplier = 1.2
			patch_n.mesh = _shared_prop_sphere(pr_m, 0.12)  # a pancake on the ground
			patch_n.material_override = mat_p
			patch_n.name = "Mycelium%d" % i
			patch_n.position = rec["pos"]
			patch_node.add_child(patch_n)
		elif int(rec["kind"]) == _DPROP_ORE:
			var prop_o := MeshInstance3D.new()
			var r_o: float = float(rec["r_o"])
			var mat_o := StandardMaterial3D.new()
			mat_o.roughness = 1.0
			mat_o.albedo_color = Color(0.35, 0.33, 0.36)
			prop_o.mesh = _shared_prop_sphere(r_o, 1.6)
			prop_o.material_override = mat_o
			prop_o.name = "Ore%d" % i
			prop_o.position = rec["pos"]
			patch_node.add_child(prop_o)
			_register_harvest_node(face, i, "res_iron_ore", dir, 90.0)
		elif int(rec["kind"]) == _DPROP_SHELL:
			var prop_sh := MeshInstance3D.new()
			var r_sh: float = float(rec["r_s"])
			var mat_sh := StandardMaterial3D.new()
			mat_sh.albedo_color = Color(0.90, 0.86, 0.79)
			mat_sh.roughness = 0.55
			prop_sh.mesh = _shared_prop_sphere(r_sh, 1.3)
			prop_sh.material_override = mat_sh
			prop_sh.name = "Shell%d" % i
			prop_sh.position = rec["pos"]
			patch_node.add_child(prop_sh)
		elif int(rec["kind"]) == _DPROP_WRACK:
			var prop_wr := MeshInstance3D.new()
			var r_wr: float = float(rec["r_w"])
			var wd_a: float = float(rec["tint"])
			var mat_wr := StandardMaterial3D.new()
			mat_wr.albedo_color = Color(0.20 + 0.06 * wd_a, 0.28 + 0.05 * wd_a, 0.24)
			mat_wr.roughness = 1.0
			prop_wr.mesh = _shared_prop_sphere(r_wr, 1.4)
			prop_wr.material_override = mat_wr
			prop_wr.name = "Wrack%d" % i
			prop_wr.position = rec["pos"]
			patch_node.add_child(prop_wr)
		elif int(rec["kind"]) == _DPROP_CATTAIL:
			var prop_c := MeshInstance3D.new()
			var mat_c := StandardMaterial3D.new()
			mat_c.roughness = 1.0
			mat_c.albedo_color = Color(0.30, 0.38, 0.20)
			prop_c.mesh = _shared_prop_cyl(0.03, 0.05, float(rec["h"]))
			prop_c.material_override = mat_c
			prop_c.name = "Cattail%d" % i
			prop_c.position = rec["pos"]
			var up_c: Vector3 = dir
			var hint_c: Vector3 = Vector3(0, 1, 0) if abs(up_c.dot(Vector3(0, 1, 0))) < 0.999 else Vector3(1, 0, 0)
			var east_c: Vector3 = (hint_c - up_c * hint_c.dot(up_c)).normalized()
			prop_c.basis = Basis(east_c, up_c, east_c.cross(up_c))
			patch_node.add_child(prop_c)
		elif int(rec["kind"]) == _DPROP_BUSH:
			# Bush: a squat green sphere (the gather law rides the apply
			# pass -- service registration is a main-thread side effect).
			var prop_b := MeshInstance3D.new()
			var r_b: float = float(rec["r_b"])
			var mat_b := StandardMaterial3D.new()
			mat_b.roughness = 1.0
			mat_b.albedo_color = Color(rec["tint_r"], rec["tint_g"], 0.18)
			prop_b.mesh = _shared_prop_sphere(r_b, 1.4)
			prop_b.material_override = mat_b
			prop_b.name = "Bush%d" % i
			prop_b.position = rec["pos"]
			patch_node.add_child(prop_b)
			var bush_item := "res_iron_ore"
			var bid_recheck: int = TerrainGen.climate_biome_id(dir, world_seed)
			if bid_recheck == TerrainGen.BiomeId.ALPINE_MEADOW:
				bush_item = "res_moonpetal"  # the meadow's herb law
			_register_harvest_node(face, i, bush_item, dir, 45.0)
	# THE TUFT BATCH FLUSH (v8): one MultiMesh paints the face's tuft field.
	_apply_tuft_batch(tuft_xforms, tuft_bids, patch_node)


## THE TUFT BATCH LAW (both appliers): the face's collected tuft
## transforms paint as ONE MultiMeshInstance3D -- one node, one draw
## call -- reusing the shared tuft mesh + material. Same paint law as
## the grass field: the raised budget buys blade instances, NOT
## scene nodes. No collider (grass is ground, not prop).
func _apply_tuft_batch(xforms: Array, bids: Array, patch_node: Node3D) -> void:
	if xforms.is_empty():
		return
	var gm := MultiMesh.new()
	gm.transform_format = MultiMesh.TRANSFORM_3D
	gm.mesh = _tuft_mesh()
	gm.instance_count = xforms.size()
	for t in range(xforms.size()):
		gm.set_instance_transform(t, xforms[t])
	var gmi := MultiMeshInstance3D.new()
	gmi.name = "DetailTuftBatch"
	gmi.multimesh = gm
	# THE MAJORITY TINT LAW (v9): a face may carry meadow AND dry-range
	# tufts; the batch material is the MAJORITY band's tint (the same
	# per-field species law the grass field pays) -- desert faces read
	# hot dead straw, tundra frost, badlands rust.
	var majority: int = -1
	var tally := {}
	for t in range(bids.size()):
		var bid: int = int(bids[t])
		tally[bid] = int(tally.get(bid, 0)) + 1
		if int(tally[bid]) > int(tally.get(majority, 0)):
			majority = bid
	if majority >= 0:
		gmi.material_override = _grass_material_for(majority)
	else:
		gmi.material_override = _tuft_material()
	patch_node.add_child(gmi)

## --- THE GRASS FIELD (the dense meadow law) ----------------------
## One MultiMesh of blade clumps per grassland face: a handful of
## seed-derived ANCHORS on the meadow (barycentric + the grove pull,
## plaza skirted), each scattering ~40 clump instances in a small
## ground ring. The anchors pay the terrain reads; their blades REUSE
## the anchor height (slope slop is sub-meter in a ~7 m ring -- far
## below the mesh tile's own span). ~40 instances per anchor x ~20
## anchors = near 900 clumps in ONE draw per face: the spaced tufts
## become a proper meadow without ever paying thousands of mesh
## nodes.
const GRASS_ANCHORS: int = 22
const GRASS_BLADES_PER: int = 40
const GRASS_RING: float = 0.00035  # ~7 m ground arc at the 20 km scale

## THE GRASS SPECIES PALETTE (v7 polish: the per-biome meadow tints).
## The tuft mesh carries its vertex-graded greens; the per-biome
## material MODULATES they multiply onto them, so the same three-blade
## geometry reads straw on the savanna, cool blue-green in the taiga,
## frost-pale at the alpine rim, and the homeland green untouched.
## Cached per biome id (one material per meadow band, ever).
const GRASS_TINTS := {
	9: Color(1.0, 1.0, 1.0),        # GRASSLAND: the homeland green
	14: Color(1.0, 0.88, 0.5),      # SAVANNA: dry straw
	15: Color(1.0, 0.95, 0.68),     # STEPPE: pale wheat
	7: Color(0.72, 0.9, 1.0),       # TAIGA: cool blue-green
	10: Color(0.82, 0.94, 1.0),     # ALPINE_MEADOW: frost rim
	5: Color(1.0, 0.90, 0.55),      # DESERT: hot dead straw
	4: Color(0.80, 0.92, 0.86),     # TUNDRA: frost pale
	16: Color(0.88, 0.70, 0.55),    # BADLANDS: rust dry brush
	3: Color(0.85, 0.90, 0.95),     # ALPINE: summit sedge
}
static var _grass_tint_mats := {}  # biome id -> StandardMaterial3D

func _grass_material_for(bid: int) -> StandardMaterial3D:
	if _grass_tint_mats.has(bid):
		return _grass_tint_mats[bid]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = GRASS_TINTS.get(bid, Color(1.0, 1.0, 1.0))
	_grass_tint_mats[bid] = m
	return m

## The blade-scale splay per meadow band (the species SILHOUETTE):
## savanna grass grows tall and lean, alpine hunkers low, the
## homeland keeps its v5 feel.
static func _grass_scale_range(bid: int) -> Vector2:
	match bid:
		14: return Vector2(1.0, 2.1)   # savanna: tall straw
		15: return Vector2(0.7, 1.6)   # steppe: lean wheat
		7: return Vector2(0.5, 1.2)    # taiga: short cool tufts
		10: return Vector2(0.4, 0.95)  # alpine: hunker
		_: return Vector2(0.6, 1.5)    # homeland default

func _derive_grass_field(face: int, salt: int = 0) -> Dictionary:
	if not terrain_on:
		return {}  # prototype keeps its S7 set
	var center: Vector3 = FacePatches.face_center(face)
	var cbid: int = TerrainGen.climate_biome_id(center.normalized(), world_seed)
	# THE FIELD GATE (the measured fix): the boot faces resolve
	# shore/lake CENTERS while hosting big grassland slivers -- the
	# center-band test alone left the homeland field-bare. The gate
	# accepts the meadow band OR any homeland-reach face; each anchor
	# still verifies grassland itself (no field in the cove/sea slivers).
	if cbid != TerrainGen.BiomeId.GRASSLAND \
			and center.angle_to(TerrainGen.SPAWN_CENTER) >= TerrainGen.HOMELAND_ANGULAR_REACH:
		return {}  # the field law: meadow faces (or the homeland set)
	var bytes: PackedByteArray = TerrainGen.face_seed_bytes(world_seed, face)
	var acc: int = 0
	for b in bytes:
		acc = (acc * 256 + b) % 9007199254740991
	var rng := RandomNumberGenerator.new()
	rng.seed = (acc + 555 + salt) % 9007199254740991  # independent stream + the deco salt (never reshuffles trees)
	var verts: PackedInt32Array = FacePatches.face_vertices(face)
	var patch_center: Vector3 = center * (radius + TILE_LIFT)
	var scaled: float = radius + TILE_LIFT
	var sea: float = TerrainGen.sea_level(world_seed)
	var xforms: Array = []
	var bids: Array = []  # per-xform biome (the per-instance tint law)
	var tang_a: Vector3 = Vector3(0, 1, 0).cross(center).normalized()
	# THE MEADOW FAMILY (v7 polish): grass still dominates, but the
	# grass-family bands ride their own species look now -- savanna
	# straw, steppe wheat, taiga cool tufts. The DRIVE-BY MEADOW LAW
	# (the detail tier's set): the field no longer skips the
	# grass-family bands outright; it only refuses water bands.
	var center_meadow: bool = cbid == TerrainGen.BiomeId.GRASSLAND \
		or cbid == TerrainGen.BiomeId.SAVANNA or cbid == TerrainGen.BiomeId.STEPPE \
		or cbid == TerrainGen.BiomeId.TAIGA or cbid == TerrainGen.BiomeId.ALPINE_MEADOW
	if cbid != TerrainGen.BiomeId.GRASSLAND and not center_meadow \
			and center.angle_to(TerrainGen.SPAWN_CENTER) >= TerrainGen.HOMELAND_ANGULAR_REACH:
		return {}  # the field law: meadow faces (or the homeland set)
	for a in range(GRASS_ANCHORS):
		var v: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var v2: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var dir: Vector3 = (center * 0.25 + v * 0.35 + v2 * 0.40).normalized()
		if center.angle_to(TerrainGen.SPAWN_CENTER) < TerrainGen.HOMELAND_ANGULAR_REACH:
			# THE HOMELAND CONCENTRATION (v8: 0.88 leaves the boot belt --
			# the old 0.62 drag spread the carpet ~4-5 km from the plaza).
			dir = dir.slerp(TerrainGen.SPAWN_CENTER, 0.88)
		# THE PLAZA SKIRT: the boot clearing stays law-tidy -- the field
		# nudges out of the spawn-clear ring rather than skipping the
		# anchor (the meadow keeps its anchor count near the boot).
		if dir.angle_to(TerrainGen.SPAWN_CENTER) < TerrainGen.SPAWN_CLEAR_ANG:
			dir = dir.slerp(TerrainGen.SPAWN_CENTER, -0.04)
		var base_h: float = _prop_site_ground_h(dir, face)
		if base_h < sea - 0.2:
			continue
		# THE ANCHOR SPECIES CHECK (v7 polish: per-meadow tints).
		# The meadow FAMILY test replaced the old grassland-only gate,
		# so savanna/steppe/taiga/alpine anchors carry their own
		# species look (the drive-through law above covered the drive;
		# this one per anchor).
		var bid_a: int = TerrainGen.climate_biome_id(dir, world_seed)
		var meadow_a: bool = bid_a == TerrainGen.BiomeId.GRASSLAND \
			or bid_a == TerrainGen.BiomeId.SAVANNA or bid_a == TerrainGen.BiomeId.STEPPE \
			or bid_a == TerrainGen.BiomeId.TAIGA or bid_a == TerrainGen.BiomeId.ALPINE_MEADOW
		if not meadow_a:
			continue
		var arot: float = rng.randf_range(0.0, TAU)
		for k in range(GRASS_BLADES_PER):
			var kfrac: float = TAU * float(k) / float(GRASS_BLADES_PER)
			var brad: float = GRASS_RING * (0.35 + 0.65 * rng.randf())
			var jang: float = arot + kfrac + rng.randf_range(-0.05, 0.05)
			var blade_dir: Vector3 = dir.rotated(tang_a, cos(jang) * brad)
			blade_dir = blade_dir.rotated(center.cross(dir).normalized(), sin(jang) * brad)
			var bpos: Vector3 = _tangent_patch_local(blade_dir, patch_center, scaled + base_h)
			var up_b: Vector3 = blade_dir
			var hint_b: Vector3 = Vector3(0, 1, 0)
			if abs(up_b.dot(hint_b)) > 0.999:
				hint_b = Vector3(0, 0, -1)
			var east_b: Vector3 = (hint_b - up_b * hint_b.dot(up_b)).normalized()
			# THE SPECIES SILHOUETTE: per-meadow scale splay (the band
		# the anchor resolved picks the height band -- tall lean
		# savanna straw, hunkered alpine rim).
			var srange: Vector2 = _grass_scale_range(bid_a)
			var scl: float = rng.randf_range(srange.x, srange.y)
			var pose: Transform3D = Transform3D(
				Basis(east_b, up_b, east_b.cross(up_b)).rotated(up_b, rng.randf_range(0.0, TAU)).scaled(Vector3(scl, scl, scl)), bpos)
			xforms.append(pose)
			bids.append(bid_a)
	return {"xforms": xforms, "bids": bids}

func _apply_grass_field(grass: Dictionary, patch_node: Node3D) -> void:
	var xforms: Array = grass.get("xforms", [])
	if xforms.is_empty():
		return
	var bids: Array = grass.get("bids", [])
	var gm := MultiMesh.new()
	gm.transform_format = MultiMesh.TRANSFORM_3D
	gm.mesh = _tuft_mesh()
	# use_colors must flip while instance_count is still 0 (engine law).
	gm.use_colors = true
	gm.instance_count = xforms.size()
	var majority: int = -1
	var tally := {}  # biome id -> instance count (the majority's material)
	for t in range(xforms.size()):
		gm.set_instance_transform(t, xforms[t])
		var bid: int = int(bids[t]) if t < bids.size() else -1
		tally[bid] = int(tally.get(bid, 0)) + 1
		if int(tally[bid]) > int(tally.get(majority, 0)):
			majority = bid
	var gmi := MultiMeshInstance3D.new()
	gmi.name = "GrassField"
	gmi.multimesh = gm
	# THE PER-FIELD SPECIES LAW (v7 polish): the field's material is
	# the MAJORITY biome's tint (the anchors of one field cluster on
	# the same band), so savanna fields read straw, taiga fields
	# read cool, the homeland reads its v5 green untouched.
	if majority >= 0:
		gmi.material_override = _grass_material_for(majority)
	else:
		gmi.material_override = _tuft_material()
	patch_node.add_child(gmi)

## The sync fallback path (threadless hosts / one-shot offenders).
func _spawn_grass_field(face: int, patch_node: Node3D) -> void:
	_apply_grass_field(_derive_grass_field(face, _decor_salt), patch_node)

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
		# THE WARM-MESH STASH (the perf-leg law): before freeing, offer
		# the built mesh node to the (face, level) LRU -- the walk law
		# re-stocks on the revisit without a rebuild. The node is
		# detached from the tree but ALIVE; its next stock re-grafts
		# it. Cache miss/overflow is invisible: the node frees as
		# before and the next load re-derives (see _mesh_cache_stock).
		_mesh_cache_stash(face, mi)
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


## ===== THE WARM-MESH CACHE (perf leg v8: the built-patch reuse) ===
## A face's built MeshInstance3D is EXPENSIVE (corner derivation rides
## the terrain field; at level 7 that's ~8.4k unique corners + ~17k
## slope reads per face, each ~350 us cold) and the streaming walk
## legitimately rebuilds the SAME geometry when a face unloads and
## revisits, or demotes and re-promotes. The cache keeps the BUILT
## NODE per (face, level) in a bounded ring; a stash on unload/demote
## and a stock on load turn those rebuilds into grafts.
##
## THE DETERMINISM LAW: the node is a pure product of (face, level,
## seed, terrain-law version), so a stock and a fresh build agree
## bit-for-bit. A law change invalidates by construction: the terrain
## reinstall seam clears terrain caches AND this cache (same body).
##
## THE LIFECYCLE LAW: a stashed node is DETACHED from the tree but
## alive under the cache's strong reference; eviction queue_free()s
## the detached node (no leak, no corpse in the tree). A re-stash of
## the same key frees the old held node. The prop holder grafts back
## onto a stocked node; the stock rewrites the bookkeeping exactly
## like _hot_reload does. The caller add_child()s the stocked node.
##
## BOUNDS: 24 entries -- the streamed set + neighbors + margin fit;
## a planet sweep evicts the tail honestly.
const MESH_CACHE_MAX: int = 24

var _mesh_cache: Dictionary = {}   # key -> entry (ring storage)
var _mesh_cache_order: Array = []  # key ring, MRU first
var _mesh_cache_epoch: int = -1    # the law epoch the ring was built under

## THE EPOCH GUARD (the law-change law): any stash/stock checks the
## terrain law's epoch FIRST -- a mismatch means the ring's content
## is a product of a law this process no longer runs, so the ring
## self-flushes before the operation. Covers uninstall (and any
## future backend swap) without wiring a flush into every seam.
func _mesh_cache_epoch_valid() -> bool:
	var epoch: int = TerrainGen.LAW_EPOCH
	if epoch != _mesh_cache_epoch:
		_mesh_cache_epoch = epoch
		for key in _mesh_cache_order.duplicate():
			var e = _mesh_cache.get(key)
			if e != null and is_instance_valid(e.get("mi")):
				e["mi"].queue_free()
		_mesh_cache.clear()
		_mesh_cache_order.clear()
	return true

func _mesh_cache_key(face: int, lvl: int) -> String:
	return "%d@%d" % [face, lvl]

## Offer a built mesh node to the cache. Records its level (the
## builder's stamp), detaches it from the tree, and frees evicted
## ring tails at the bound. `lvl_hint` lets the ASYNC applier bank a
## stale-level node WITHOUT touching the live `_patch_lvl` stamp (the
## live node's level is the truth; the banked node carries its own).
func _mesh_cache_stash(face: int, mi: MeshInstance3D, lvl_hint: int = -1) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	_mesh_cache_epoch_valid()
	var lvl: int = lvl_hint if lvl_hint >= 0 else int(_patch_lvl.get(face, -1))
	if lvl < 0:
		mi.queue_free()
		return  # half-built: nothing stockable
	var key: String = _mesh_cache_key(face, lvl)
	if _mesh_cache.has(key):
		# Same-key re-stash: the held node dies (fresh content won).
		var old = _mesh_cache[key].get("mi")
		_mesh_cache_order.erase(key)
		if old != null and is_instance_valid(old):
			old.queue_free()
	_mesh_cache[key] = {
		"mi": mi,
		"holder": _prop_holders.get(face),
		"patch_tris": int(_patch_tris.get(face, 0)),
		"skirt_tris": int(_patch_skirt_tris.get(face, 0)),
	}
	_mesh_cache_order.push_front(key)
	if mi.get_parent() != null:
		mi.get_parent().remove_child(mi)
	while _mesh_cache_order.size() > MESH_CACHE_MAX:
		var evict: String = _mesh_cache_order.pop_back()
		var e = _mesh_cache.get(evict)
		_mesh_cache.erase(evict)
		if e != null and is_instance_valid(e.get("mi")):
			e["mi"].queue_free()

## THE SEAM HOOK: the terrain backend install/uninstall seam flushes
## the warm-mesh ring too -- the cached nodes are products of the OLD
## law, so a law change must not stock them anywhere. The streamer
## wires this from globe_world (the ring lives on the instance, not
## the class).
func _mesh_cache_flush() -> void:
	for key in _mesh_cache_order.duplicate():
		var e = _mesh_cache.get(key)
		if e != null and is_instance_valid(e.get("mi")):
			e["mi"].queue_free()
	_mesh_cache.clear()
	_mesh_cache_order.clear()

## Stock a face's mesh: a cache hit grafts the node back (with its
## prop holder) and rewrites the bookkeeping exactly like
## _hot_reload; a miss builds fresh. The hit is CONSUMED (no
## double-stock beach). Returns the ready node; the caller
## add_child()s it. NOTE on a miss: _patch_tris is set by the caller
## from the builder's meta (the existing law); the walk closure and
## holder wiring stay the caller's job (same as always).
func _mesh_cache_stock(face: int, use_lvl: int) -> MeshInstance3D:
	_mesh_cache_epoch_valid()
	var key: String = _mesh_cache_key(face, use_lvl)
	var entry = _mesh_cache.get(key)
	if entry != null:
		_mesh_cache.erase(key)
		_mesh_cache_order.erase(key)
		var mi2: MeshInstance3D = entry.get("mi")
		if mi2 != null and is_instance_valid(mi2):
			var holder2 = entry.get("holder")
			var holder_ok: bool = holder2 != null and is_instance_valid(holder2)
			if holder_ok and holder2.get_parent() != null \
					and holder2.get_parent() != mi2:
				holder2.get_parent().remove_child(holder2)
			if holder_ok and holder2.get_parent() != mi2:
				mi2.add_child(holder2)  # already grafted: re-add is an engine ERROR
			_prop_holders[face] = holder2 if holder_ok else null
			_patch_tris[face] = int(entry.get("patch_tris", 0))
			_patch_skirt_tris[face] = int(entry.get("skirt_tris", 0))
			_patch_mats[face] = _patch_mats.get(face)  # untouched on hit
			return mi2
	return _build_mesh(face, use_lvl)


## ===== THE MESH THREAD (v9: the cold-build lane, mirror of v6) =====
## The mesh pass at the planet scale costs SECONDS per face (the
## fused sweep's unique-corner field evals); the sync lane made the
## boot pay FOUR of them back to back on the main thread. This lane
## DERIVES off-thread and ERECTS in a main-thread applier, so the
## streaming walk and the LOD promote/demote swaps never hitch.
##
## THE WORKER LAW (the v6 prop lane's, restated for mesh): the thread
## touches NO mutable streamer state -- every dict write, node law,
## and material creation lives in _erect_mesh/_install_loaded_mesh on
## the main thread. Terrain reads ride the LOCKED sector caches.
## Results cross the mutex; the errection is call_deferred'd.
##
## THE LANE LAW: the boot's OWN face stays SYNC (cold install, ground
## underfoot immediately); every other face (boot neighbors, non-
## current level changes, stream-ins) rides the lane. Threadless/
## prototype hosts collapse to the sync law by _mesh_async().
var _mesh_mutex := Mutex.new()
var _mesh_jobs := {}       # face -> true while a derive is in flight
var _mesh_results := {}    # face -> {"lvl": int, "data": Dictionary}
var _mesh_threads := {}    # face -> Thread (reaped in the applier)
## The lane ledger (per-job derive wall): the >=4-core projection's
## input -- see mesh_lane_stats() and bench_coldboot_wall.
var _mesh_lane_jobs := 0
var _mesh_lane_ms := 0
var _mesh_lane_ms_max := 0

## Lane accounting for the boot-wall bench: jobs derived, total and
## largest worker derive wall in ms.
func mesh_lane_stats() -> Dictionary:
	return {"jobs": _mesh_lane_jobs, "ms": _mesh_lane_ms, "max_ms": _mesh_lane_ms_max}

## Threading gate: same criteria as the prop lane (the LOD terrain
## walk only; the prototype's flat shell keeps the sync law). The
## `synmergia/world/async_mesh` setting (default true) exists for the
## A/B boot-wall bench -- an off flip collapses every caller to the
## sync law in the same process.
func _mesh_async() -> bool:
	var gate: bool = true
	if ProjectSettings.has_setting("synmergia/world/async_mesh"):
		gate = bool(ProjectSettings.get_setting("synmergia/world/async_mesh"))
	return gate and lod_on and terrain_on

## Probe/test + HUD surface: mesh derives still in flight.
func _mesh_pending() -> int:
	return _mesh_threads.size()


## THE PROBE DRAIN (both async lanes): one number for the census
## probes' wait loops -- mesh + prop derives. A probe that boots the
## planet and then counts props/meshes waits on THIS, not on physics
## frame counts; a steady census needs a steady world.
func pending_derive() -> int:
	return _mesh_threads.size() + _prop_threads.size()

func _kick_mesh_derivation(face: int, use_lvl: int) -> void:
	_mesh_mutex.lock()
	var busy: bool = _mesh_jobs.has(face) or _mesh_results.has(face)
	if not busy:
		_mesh_jobs[face] = true
	_mesh_mutex.unlock()
	if busy:
		return  # already deriving (the guard survives a face revisit)
	var t := Thread.new()
	_mesh_threads[face] = t
	t.start(Callable(self, "_mesh_derive_job").bind(face, use_lvl), Thread.PRIORITY_LOW)

func _mesh_derive_job(face: int, use_lvl: int) -> void:
	# Runs OFF the main thread. PURE derive only (the whole reason the
	# split above exists); the result crosses the mutex; the erection
	# is queued back to the main thread. The derive wall is recorded
	# per job -- the >=4-core projection model's input (see
	# bench_coldboot_wall: on a contended 2-core host it OVERSTATES
	# serial work; on real hardware it is the per-face CPU price).
	var t_ms: int = Time.get_ticks_msec()
	var data: Dictionary = _derive_mesh_data(face, use_lvl)
	var job_ms: int = Time.get_ticks_msec() - t_ms
	_mesh_mutex.lock()
	_mesh_results[face] = {"lvl": use_lvl, "data": data, "ms": job_ms}
	_mesh_mutex.unlock()
	Callable(self, "_apply_derived_mesh").call_deferred(face)

## The mesh applier (main thread): erects the derived arrays and
## installs/swaps/stashes by what the walk law wants NOW.
func _apply_derived_mesh(face: int) -> void:
	var th = _mesh_threads.get(face)
	_mesh_mutex.lock()
	var packed = _mesh_results.get(face)
	_mesh_results.erase(face)
	_mesh_mutex.unlock()
	if th != null:
		th.wait_to_finish()  # the job has returned by the time the deferral fires
		_mesh_threads.erase(face)
	if packed == null:
		_mesh_jobs.erase(face)
		return
	# THE LANE LEDGER: per-job derive wall accumulates here (the
	# projection model's raw material -- which face took which).
	var job_ms: int = int(packed.get("ms", 0))
	_mesh_lane_jobs += 1
	_mesh_lane_ms += job_ms
	_mesh_lane_ms_max = maxi(_mesh_lane_ms_max, job_ms)
	var use_lvl: int = int(packed["lvl"])
	# THE STALE-LEVEL LAW: the demand may have moved while the lane
	# was in flight. A stale result is never WASTED -- the node is
	# erected and banked into the warm ring at its built level (the
	# demand eventually re-matches: the graft, not a re-derive). The
	# LIVE node's bookkeeping is untouched (its own level is truth).
	var live_lvl: int = int(_patch_lvl.get(face, -1)) if _patches.has(face) else -1
	var demanded: int = _demanded_level(face, _last_player_dir, live_lvl)
	if _patches.has(face):
		if demanded != use_lvl:
			# Stale hot result: bank it, keep the live node; the next
			# _lod_enforce tick re-kicks at the demanded level.
			var stale_mi: MeshInstance3D = _erect_mesh(face, use_lvl, packed["data"])
			_mesh_cache_stash(face, stale_mi, use_lvl)
			_mesh_jobs.erase(face)
			return
		# THE HOT SWAP: rebuild ONLY the mesh node; the prop holder
		# grafts across (the v6/v8 hot law, async flavor). Stash the
		# OLD built geometry first (the ring law), then swap.
		var old_mi: MeshInstance3D = _patches.get(face)
		if old_mi != null and is_instance_valid(old_mi):
			_mesh_cache_stash(face, old_mi)
		var fresh: MeshInstance3D = _erect_mesh(face, use_lvl, packed["data"])
		_props_move(face, fresh)
		var at: Node = old_mi.get_parent() if old_mi != null and is_instance_valid(old_mi) else parent
		if old_mi != null and is_instance_valid(old_mi) and at != null:
			at.add_child(fresh)
			fresh.global_transform = old_mi.global_transform if old_mi.is_inside_tree() else fresh.global_transform
		else:
			parent.add_child(fresh)
		_patches[face] = fresh
		if fresh.has_meta("tris"):
			_patch_tris[face] = int(fresh.get_meta("tris"))
			fresh.remove_meta("tris")
		_patch_lvl[face] = use_lvl
		if old_mi != null and is_instance_valid(old_mi):
			old_mi.queue_free()
		patch_loaded.emit(face)
	else:
		# COLD LANDING: install only if the face is still WANTED (the
		# walk's current set: the player's face or one of its 3 edge
		# neighbors); otherwise bank the node into the ring for the
		# eventual revisit -- never resurrect an unloaded face.
		var want_face: bool = current_face >= 0 \
			and (current_face == face \
				or FacePatches.neighbors(current_face).has(face))
		if demanded != use_lvl or not want_face:
			var stale_cold: MeshInstance3D = _erect_mesh(face, use_lvl, packed["data"])
			_mesh_cache_stash(face, stale_cold, use_lvl)
			_mesh_jobs.erase(face)
			return
		# THE RING GRAFT ON A COLD LANDING: the revisit flows stock the
		# ring first (the stash+swap legs) -- the lane honors it by
		# consuming the stocked node when one exists; the worker's
		# fresh derive only fills the miss. Same content by the same
		# law, so a stocked graft and a worker erect are identical.
		if _mesh_cache.has(_mesh_cache_key(face, use_lvl)):
			_install_loaded_mesh(face, use_lvl, _mesh_cache_stock(face, use_lvl))
		else:
			_install_loaded_mesh(face, use_lvl, _erect_mesh(face, use_lvl, packed["data"]))
	_mesh_jobs.erase(face)


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
	var lvl_i: int = clampi(int(round(lvl)), 1, _max_level())
	return lvl_i


## THE MESH-RESOLUTION CAP (web round 17, "the fancy terrain vanished"):
## beyond the desktop radius the tile grid SUBSAMPLES the analytic
## relief -- at radius 20000 the level-6 tile edge is ~330 m, so an
## ~800 m ring of ~90 m hills the boot can actually see renders as a
## smooth green pancake while the walk law reads the full field (the
## truth line held the exact legal plaza height over a flat screen --
## sim right, draw starved). The cap is the mesh's Nyquist: it must
## stay small enough that one tile edge spans less than the visible
## relief band. Level 7 (~165 m edge at the planet scale) resolves the
## near-horizon hills; the LOD NEAR law keeps the far patches at
## coarse levels, so the 4x triangle cost lands only on the near band
## (~20k tris per phone frame), not the whole sphere. Desktop-scale
## prototype planets keep the old 6 cap: their tiles already resolve.
const PLANET_MESH_CAPTURE_R: float = 10000.0
func _max_level() -> int:
	return 7 if radius >= PLANET_MESH_CAPTURE_R else 6


## Recursive spherical midpoint subdivision; preserves outward winding.
func _subdivide(a: Vector3, b: Vector3, c: Vector3, depth: int, out: Array) -> void:
	if depth <= 0:
		out.append([a, b, c])
		return
	# THE SHARED-CORNER LAW (sweep round 19): every interior edge is
	# split by TWO recursive calls -- one with this corner as `a`, one
	# with it as `c`. The old per-caller radius (a.length()) made the
	# two copies of every shared midpoint drift by ULPs; the skirt's
	# quantized edge keys papered over most of that, but level 7's
	# fine spacing let two edges slip past the bucket lines (+4
	# phantom strips on the plaza faces). The midpoint radius is the
	# EDGE's symmetric average, so both callers construct the SAME
	# bit-exact corner -- quantization never re-unifies what never
	# drifted.
	var mab: Vector3 = (a + b).normalized() * ((a.length() + b.length()) * 0.5)
	var mbc: Vector3 = (b + c).normalized() * ((b.length() + c.length()) * 0.5)
	var mca: Vector3 = (c + a).normalized() * ((c.length() + a.length()) * 0.5)
	_subdivide(a, mab, mca, depth - 1, out)
	_subdivide(mab, b, mbc, depth - 1, out)
	_subdivide(mca, mbc, c, depth - 1, out)
	_subdivide(mab, mbc, mca, depth - 1, out)


## Deterministic per-face tint (visible patch boundaries for streaming
## verification; subtle enough to read as natural ground variation).
## v9 split: the PURE form has no dict access -- it is the worker's
## tint (identical math); the dict form is the main-thread memo of
## the same law (call-site speed only, no behavior change).
func _tint_for(face: int) -> Color:
	if not _face_tints.has(face):
		_face_tints[face] = _tint_for_pure(face)
	return _face_tints[face]


func _tint_for_pure(face: int) -> Color:
	var h: float = float((face * 2654435761) % 997) / 997.0
	var k: float = 0.85 + 0.3 * h
	return Color(0.32 * k, 0.55 * k, 0.35 * k)
