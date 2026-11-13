## GlobeWorld - spherical-world scene root (prd-spherical-mvp.md S3).
## Builds the shell (visual sphere + sphere-shell collider), the player,
## the sun, and the arena gateway. The playable HUD is installed by the
## shared HudLayer.ensure_installed() init so every playable scene gets
## the same composition.
##
## S8 FLOATING ORIGIN: everything planet-bound (shell, streamed
## patches, surface pad) lives under world_root; the player is a direct
## child of this scene and stays near the world origin. When the player
## drifts past SHIFT_RADIUS, the whole planet is translated back around
## it (_maybe_shift_world). At planet scale ground support is a single
## re-anchored surface pad (see _build_surface_pad) - the megasphere
## SphereShape and face-scale patch trimeshes both degenerate at
## R = 20 km (measured, S8).
extends Node3D

## Named collision bits (round 10): data/physics_layers/ LayerProfile.
const Layers = preload("res://core/schemas/layer_profile.gd")

## Runtime autoload lookups (script-mode-safe; the bare identifiers fail
## to compile when autoloads are absent -- same law as the player bodies).
func _glog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null

func _im() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("InputManager")) if tree and tree.root else null

func _sign() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("SignService")) if tree and tree.root else null

const PLAYER_SKIN: float = 1.0
## Visual shell sits slightly above the collider to avoid z-fighting.
const SKIN_THICKNESS: float = 0.5
## Configurable planet scale: `synmergia/world/planet_radius` (meters).
## Default 100 = the prototype globe; 20000 = the v1 planet scale
## (prd.md). S8 probe verifies systems at both scales.
const PLANET_RADIUS_SETTING: String = "synmergia/world/planet_radius"
## S8: keep in sync with globe_terrain_streamer.TILE_LIFT (0.52) --
## the walk surface sits this far above the base shell when the
## terrain streamer is on. (Constant mirrored rather than preloaded
## to keep the scene's load order simple.)
const STREAMER_TILE_LIFT: float = 0.52
## S8: shells larger than this cannot resolve a 1 m body contact
## (the S8 stall threshold note lives in _build_shell/_surface_lift).
## S8 surface pad geometry: curved disc, outer ring radius in meters
## and ring segment count. Local shape coordinates stay <= PAD_RADIUS
## (physics needs SMALL shape coordinates); the pad hugs the sphere
## via the exact sagitta per ring.
const PAD_RADIUS: float = 64.0
const PAD_SEGMENTS: int = 16
## Terrain-conforming pad grid: radial rings from centre to PAD_RADIUS.
## The flat disc could not follow the walk surface, so on rolling ground
## the body's flat contact plane stood proud of the next rise and stopped
## it dead (the "invisible wall" report). The terrain pad bakes the walk
## height at every vertex instead, so collision and the generated ground
## are the same law.
const PAD_RINGS: int = 8
const SPAWN_LAT_DEG: float = 0.0
const SPAWN_LON_DEG: float = 0.0
const WALK_SECONDS: float = 30.0
## ~40% of a full equator lap at 6 m/s on a 100 m sphere.
const WALK_DISTANCE_METERS: float = 250.0

var planet_radius: float = 100.0
## S8: the shell's CollisionShape3D, always disabled (the megasphere
## cannot support a body); the re-anchored surface pad is physics truth.
var shell_col: CollisionShape3D
## S8: the planet-scale ground collider, re-anchored under the player
## every physics frame (null at prototype scale; see _build_surface_pad).
var surface_pad: StaticBody3D
## Terrain pad shape (planet scale only): rebuilt every physics frame from
## the walk-surface law under the player. Local coords are <= PAD_RADIUS;
## local +Y is the walk-surface height above planet_radius at that offset.
var _pad_shape: ConcavePolygonShape3D
## Direction the terrain pad shape was last baked at (rebuild throttle:
## the shape only follows when the player has moved a few metres).
var _pad_built_dir: Vector3 = Vector3.ZERO
## S8: how many floating-origin rebases have run (probe observability).
var scene_shift_count: int = 0
## S8 FLOATING ORIGIN: everything that lives on the planet (shell,
## streamed patches, probe markers) is a child of this node. When the
## player drifts past SHIFT_RADIUS from the world origin, the whole
## world root is translated by -player_offset so the player re-lands
## near the origin and every float32 transform stays small.
var world_root: Node3D
## World-space position of the planet center == world_root.position
## (the planet is centered on the world root by construction).
var planet_center: Vector3 = Vector3.ZERO
## S8: how far the player may drift from the world origin before the
## world is shifted back. 1500 m is comfortably inside the measured
## stall threshold (~2 km walks free, ~5 km degraded).
const SHIFT_RADIUS: float = 1500.0

## S5: when true the ground visual is STREAMED (the sphere StaticBody
## stays the physics truth either way).
var stream_terrain: bool = true

## THE RENDERER SWITCH (clipmap round): "clipmap" (default) draws the
## ground as a player-centred polar clipmap; "streamer" is the legacy
## icosa face-patch streamer (kept as fallback until the clipmap's probe
## set is green). Both draw the SAME ground law; only the mesh differs.
const TERRAIN_RENDER_SETTING: String = "synmergia/world/terrain_render"
var terrain_render: String = "clipmap"

## The clipmap's ring ladder is tuned for the canon 20 km planet; below this
## radius the prototype bench sphere would re-centre every step, so the
## renderer falls back to the streamer (same line as the world's other
## planet-scale gates).
const PLANET_RENDER_MIN_R: float = 1000.0

## WATER (terrain arc): at planet scale the scene paints a water shell
## at the terrain sea line (TerrainGen.sea_level). The shell is visual
## only -- the floor is the displaced terrain itself (the ocean depth
## law: the sea floor IS the ground law, no second collision truth).
const WATER_ON: bool = true
var water_body: MeshInstance3D = null

## The active ground renderer (GlobeClipmap or GlobeTerrainStreamer);
## untyped - preload-by-path pattern. Both expose the same surface.
var streamer

var player  # GlobeWorldPlayer; untyped on purpose - set_script + dynamic
# dispatch keeps this scene free of parse-time class_name dependencies.

## PLANAR-RETIREMENT STEP 2: the globe's wildlife. One record per
## scene-placed enemy so a kill rebuilds it at its spawn point after
## EnemyData.respawn_time (ported from world_playable's SceneSpawn law).
class GlobeSpawn:
	var template_id: String = ""
	var display_name: String = ""
	var level: int = 1
	var spawn_position: Vector3 = Vector3.ZERO
	var respawn_time: float = 60.0
	var entity_id: String = ""
	var respawn_pending: bool = false

## The spawn roster: (template_id, bearing_deg, reach_rad) placed on the
## spawn plaza's tangent frame via the town-NPC walk law. Kept small and
## lawful (wolves + boars on the village outskirts, a training dummy on
## the plaza so a fresh body can practice).
const GLOBE_ENEMY_BATCH: Array = [
	# template_id, bearing_deg (spawn tangent frame), reach_rad
	["wolf", 250.0, 0.018],
	["wolf", 285.0, 0.022],
	["thistle_boar", 70.0, 0.020],
	["training_dummy", 320.0, 0.010],
]
var _globe_spawns: Array[GlobeSpawn] = []

## THE ZONE SPAWN RUNG (the world's own placement rung): a proximity
## roster built from data/spawn_tables/*.tres. The ZoneSpawner decides
## which authored entries are live for the tracked players; this scene
## does the node work (build/free bodies, keep the respawn records).
## Anchors: most tables ride the spawn frame; a far landmass (the pans,
## the island) passes its own world dir so its bearing/reach is honest.
const ZoneSpawnerRef = preload("res://core/world/zone_spawner.gd")
var _zone_spawner = null
## key -> Array of the live bodies for one spawn entry.
var _zone_bodies: Dictionary = {}
## Throttle: the roster reconciles a few times a second, not every tick.
var _zone_spawn_accum: float = 0.0
const ZONE_SPAWN_TICK_S: float = 0.5

## PLANAR-RETIREMENT STEP 3: the town watch. Each entry is
## (GuardData id in data/guards/, bearing_deg, reach_m). Guards are
## created from their GuardData (the planar scene's authored guards),
## given a GuardAI brain + EntityService registration, and posted at
## their spawn point (the return-to-post law needs a REAL post, so the
## loaded GuardData is duplicated before its post_position is stamped).
const GLOBE_GUARD_BATCH: Array = [
	# guard_data_id, bearing_deg (spawn tangent frame), reach_m
	# (the planar scene's four: the plaza watch + the east-gate watch)
	["guard_town", 15.0, 11.0],
	["guard_town", 345.0, 11.0],
	["guard_gate", 40.0, 15.0],
	["guard_gate", 50.0, 15.0],
]
## The Ascent + the dev Moon Gate stand a short walk from the plaza, on
## their own bearings clear of the Concord props (door -40, stone 40)
## and the village belt (ankh -150, moongate -110, boutstones 120).
const GLOBE_MOON_GATE: Array = ["MoonGate", "Moon Gate", "moon", 92.0, 10.0]
const GLOBE_ASCENT_GATE: Array = ["AscentGate", "The Ascent", "underworld", -92.0, 10.0]
## The dungeon portal (the authored GatewayData the planar scene wires):
## (gateway .tres id, bearing_deg, reach_m).
const GLOBE_DUNGEON_PORTAL: Array = ["dungeon_forest_depths_entrance", 175.0, 12.0]
## The demo housing plot: (plot id, bearing_deg, reach_m, radius, price).
const GLOBE_HOUSING_PLOT: Array = ["plot_haven_1", 60.0, 9.0, 10.0, 50000]
## The zone every globe-placed entity registers under (the spawn plaza's
## zone; matches _register_player's zone entry).
const GLOBE_ZONE_ID: String = "zone_village_center"

## S14-web: the playable HUD. Kept as a thin wrapper for back-compat:
## the real install is the shared HudLayer.ensure_installed() init
## (feedback #5 -- one cohesive playable-HUD system loaded the same way
## on every playable scene).
var hud: CanvasLayer = null
## Spawn-truth throttle (round 7, item 4): the on-screen lat/lon/
## height line refreshes twice a second, not every physics tick.
var _truth_accum: float = 0.0
var _boot_start_ms: int = 0

## THE CORE-STEP RECEIPT (BOOT_TRACE=1): one gated line after each
## core attach, so the ready-wall's cost has a NAME per step -- the
## wall the game-side overlay legally hides behind is exactly this.
func _bt(label: String) -> void:
	if OS.get_environment("BOOT_TRACE") == "1":
		print("[boottrace] %s @ %d ms" % [label, Time.get_ticks_msec() - _boot_start_ms])
## The truth line itself (built into the playable HUD CanvasLayer).
var _truth_label: Label = null

## CHART-LOD GLUE (turn 8): the scene-level wiring -- the adapter feeds
## the player's live lat/lon into the PenroseChartLod policy and turns
## the emitted work orders into REAL MeshInstance3D chart overlays
## under world_root (PenroseMeshBuilder draw + skirt_strip rims).
## Untyped per this scene's preload-by-path dispatch law.
var chart_lod  # PenroseChartAdapter; untyped - preload-by-path pattern
var chart_lod_root: Node3D = null
## chart_index -> MeshInstance3D of the current climb overlay.
var _chart_nodes: Dictionary = {}
## LOD tick throttle: the policy is cheap but the ORDER consumer is a
## mesh build; run at 2 Hz alongside the truth line.
var _chart_accum: float = 0.0
## Last observer lat/lon fed to the adapter (probe readout).
var last_chart_lat: float = 0.0
var last_chart_lon: float = 0.0


func _ready() -> void:
	_boot_start_ms = Time.get_ticks_msec()
	# The canon radius comes from world_main.tres (20000, the v1 planet
	# scale); the project setting must match it (AGENTS data law: the
	# .tres is the declaration). The 100 m prototype is a TEST scale --
	# probes pin it explicitly; the shipped game boots the real planet
	# (terrain heightfield, ocean, island -- all planet-scale systems).
	planet_radius = float(ProjectSettings.get_setting(PLANET_RADIUS_SETTING, 20000.0))
	# S8 floating origin: planet-bound content lives under world_root.
	world_root = Node3D.new()
	world_root.name = "WorldRoot"
	add_child(world_root)
	_build_shell()
	_bt("shell")
	_build_surface_pad()
	_bt("pad")
	_install_world_backend()
	_bt("backend")
	_build_sun()
	_build_sky_sun()
	_build_sky_moon()
	_build_sky_signs()
	_bt("sky")
	# Streamer FIRST: the player spawn height rides the terrain law
	# (walk surface at the spawn direction), so the ground must exist
	# before the boot lands on it.
	_setup_streamer()
	_bt("streamer")
	_build_water()
	_bt("water")
	# THE PLAYABLE-FIRST BOOT (the loading-speed round law): the
	# game-side "Loading world..." overlay can only hide AFTER _ready
	# returns, and the POI/NPC builds cost seconds per attach on wasm
	# -- every synchronous stretch froze the spinner AND the frame
	# loop, which is the whole 3-minute hang. So the boot core stops
	# at PLAYABLE (spawn-ground streamer + player + planet wiring +
	# HUD), and the ensuite builds ride the frame-by-frame boot waves
	# below, after the overlay is already down.
	_build_player()
	_bt("player")
	planet_center = world_root.position
	player.planet_center = planet_center
	_register_player()
	_bt("player-register")
	_install_hud()
	_setup_touch_hud()
	_bt("hud")
	# SPAWN TRUTH (play-test round 7, item 4): the Android reporter
	# cannot read GameLog, so the boot/terrain truth also lives ON
	# SCREEN -- one small line, top-right of the playable HUD: lat/lon,
	# ground height, sea line. The next "I spawned on the ocean" report
	# settles WHERE and WHETHER with one glance (WET vs dry). Built
	# HERE, after _install_hud(): _build_player runs before the HUD
	# exists, and the line parents into it.
	_build_spawn_truth()
	_bt("spawn-truth")
	# THE BOOT WAVES: POIs, NPCs, decor + ambience land frame-by-frame
	# AFTER the scene is current -- the overlay is down, the player
	# stands on law terrain, and the world fills in visibly, like the
	# LOD streams beside it.
	_boot_waves()


## THE DECLARED CONTENT MANIFEST (planar-retirement Step 4). This is the
## globe's content list, ONCE -- the ordered families the world hosts.
## The WorldContentBuilder runs it and reports any declared family with
## no builder LOUD, so "the globe is missing X" can never ship silently
## again (the drift that produced the planar-retirement debt).
const CONTENT_MANIFEST: Array = [
	"arena_gateway",
	"starter_village",
	"capitol_monolith",
	"pans_monolith",
	"pans_ferry",
	"sundered_barque",
	"garden_binder",
	"town_npcs",
	"wildlife",
	"zone_spawns",
	"transit_gates",
	"town_watch",
	"dungeon_portal",
	"housing",
	"starter_quests",
	"concord_loop",
	"blessed_marks",
	"ambience",
]

## The declared content driver (built in _boot_waves; the receipt reads
## its report to prove every declared family is backed by a builder).
var content_builder = null

## THE BOOT WAVES (the loading-speed round): the world's ensuite
## builds land across frames after the playable core, each wave a
## frame apart (the wasm main thread gets its render budget back
## every frame) and each attach tree-guarded so a scene swap or
## teardown mid-wave can never touch a dying tree.
##
## PLANAR-RETIREMENT STEP 4: the wave list is no longer a bare inline
## array -- the globe DECLARES CONTENT_MANIFEST and registers one
## builder per family on a WorldContentBuilder; the builder runs the
## manifest in declared order and reports any family left without a
## builder. The declaration is the single source of truth for what the
## globe contains.
func _boot_waves() -> void:
	var builder = load("res://core/world/world_content_builder.gd").new()
	builder.declare(CONTENT_MANIFEST)
	builder.add_family("arena_gateway", _build_arena_gateway)
	builder.add_family("starter_village", _build_starter_village)
	builder.add_family("capitol_monolith", _build_capitol_monolith)
	builder.add_family("pans_monolith", _build_pans_monolith)
	builder.add_family("pans_ferry", _build_pans_ferry)
	builder.add_family("sundered_barque", _build_sundered_barque)
	builder.add_family("garden_binder", _install_garden_binder)
	builder.add_family("town_npcs", _build_town_npcs)
	builder.add_family("wildlife", _build_globe_enemies)
	builder.add_family("zone_spawns", _load_zone_spawn_tables)
	builder.add_family("transit_gates", _build_globe_gates)
	builder.add_family("town_watch", _build_globe_guards)
	builder.add_family("dungeon_portal", _build_globe_portal)
	builder.add_family("housing", _build_globe_housing)
	builder.add_family("starter_quests", _accept_starter_quests)
	builder.add_family("concord_loop", _build_concord_loop)
	builder.add_family("blessed_marks", _setup_blessed_marks)
	builder.add_family("ambience", _setup_ambience)
	content_builder = builder
	# THE GAP GATE: a declared family with no builder is logged LOUD
	# before the waves even run (the declaration and the placement
	# must agree; a mismatch is a code error, not a lore choice).
	var missing: Array = builder.missing_builders()
	if not missing.is_empty():
		_log_backend("error", "GlobeWorld: content manifest declares %s with NO builder -- the world would ship a gap" % str(missing))
	for family in builder.manifest():
		await get_tree().process_frame
		if not is_inside_tree() or is_queued_for_deletion():
			return
		## THE BOOT-WAVE RECEIPT (the loading-speed round's meter): one
		## gated line per wave attach, so the probe (and the owner's own
		## GameLog watch) can see the world filling in AFTER the overlay
		## is already down.
		if OS.get_environment("BOOT_TRACE") == "1":
			print("[bootwave] + %s (%d ms after ready)" % [str(family), Time.get_ticks_msec() - _boot_start_ms])
		builder.build_one(family)
	## THE WAVES-DONE STAMP: the probe reads this meta as the honest
	## "world is fully dressed" moment; a meta ABSENT after 90 s is the
	## environment verdict (old boots carry no stamp at all).
	set_meta("boot_waves_done_ms", int(Time.get_ticks_msec() - _boot_start_ms))


## THE AUTHORED TERRAFORM (data-driven, backend-seam-first): the
## world's WorldData declares `terrain_backend_id` -- which authored
## heightfield legally reshapes THIS world's raw land. Empty = the
## natural analytic law (no declaration, no install). THE STREAMER
## MUST SEE IT: install BEFORE _setup_streamer() reads its first
## height, so patch 0 renders the authored world, not a two-frame
## flash of the natural one. The id resolves through the BACKEND
## REGISTRY (terrain backends class_name map); an unknown id is a
## DATA error and logs loud (fail the lore, not the boot -- the
## natural law still renders and the world stays playable).
func _install_world_backend() -> void:
	var wd = _world_data()
	if wd == null or str(wd.terrain_backend_id).is_empty():
		return
	var ids := str(wd.terrain_backend_id)
	var script_path := "res://scenes/worlds/backend_%s.gd" % ids
	if not ResourceLoader.exists(script_path):
		_log_backend("error", "world '%s' declares terrain_backend_id '%s' -- no res://scenes/worlds/backend_%s.gd. Natural law renders; fix the declaration or ship the backend." % [wd.id, ids, ids])
		return
	var backend_script = load(script_path)
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	Gen.install_terrain_backend(Callable(backend_script, "field"))
	_log_backend("info", "authored terrain backend '%s' installed for world '%s' (the strait is real)" % [ids, wd.id])


## The islands-suite law: bare autoload reads fail --script-mode
## compilation, so every autoload touch goes through root lookup.
func _log_backend(level: String, msg: String) -> void:
	var log4 = get_node_or_null("/root/GameLog")
	if log4 == null:
		return
	var callable: Callable = Callable(log4, level)
	if callable.is_valid():
		callable.call(msg)


## This scene's WorldData: probed via the boot sequence's world id if
## available (meta "world_id" set by the boot/lobby journey), else
## the MAIN world (the playable home is world_main's declaration).
func _world_data():
	var wid := str(get_meta("world_id", "main"))
	var reg = get_node_or_null("/root/WorldRegistry")
	if reg != null and reg.has_method("get_world"):
		return reg.get_world(wid)
	var packed = load("res://data/worlds/world_%s.tres" % wid)
	return packed if packed != null else null


## S8 floating-origin rebase: when the player has drifted SHIFT_RADIUS
## from the world origin, translate world_root (the whole planet) by
## -player_offset. The player's next global transform is then near
## origin (small float32 magnitude) while the planet geometry is
## unchanged. The player's planet_center reference is re-read from the
## moved world_root; nothing else needs to know.
func _maybe_shift_world() -> void:
	if player == null:
		return
	var offset: Vector3 = player.global_position
	if offset.length() < SHIFT_RADIUS:
		return
	# Translate the planet so the player's next position re-lands near
	# the world origin...
	world_root.position -= offset
	planet_center = world_root.position
	# ...and move the player body by the SAME delta. The body's own
	# transform is exactly what floating origin fixes (measured: at
	# |r| ~20 km the body's float32 integration stalls locomotion even
	# on a perfect local floor); the planet geometry is what "moves".
	# Zeroing velocity drops the pre-shift motion so no stale slide
	# survives the teleport.
	player.global_position -= offset
	player.velocity = Vector3.ZERO
	player.planet_center = planet_center
	scene_shift_count += 1
	# Streamer patches are planet-relative children of world_root, so
	# the shift moves them for free. Re-anchor the pad under the moved
	# player now (its next move_and_slide must find ground) and reset
	# the loop metrics for honest post-shift walk measurements.
	_update_surface_pad()
	player.begin_loop()


## S14-web: instantiate the playable HUD. The globe previously booted
## bare (no menus, no bars, no touch controls) because the HUD lived
## only inside world_playable.tscn and this scene builds itself at
## runtime. Same composition, one CanvasLayer, added last so it draws
## above the world.
func _install_hud() -> void:
	if hud != null:
		return
	HudLayer.ensure_installed(self)
	hud = get_node_or_null("HudLayer") as CanvasLayer
	if hud != null:
		var _gl := _glog()
		if _gl:
			_gl.info("GlobeWorld: playable HUD installed")


## Bridge the touch HUD into the globe player's camera (same shape as
## WorldPlayable._setup_touch_hud): the VirtualJoystick emits
## camera_look in raw pixel deltas; the player's orbit_camera turns
## them into yaw/pitch on the local tangent frame.
func _setup_touch_hud() -> void:
	if player == null or not player.has_method("orbit_camera"):
		return
	var im := _im()
	var joystick = im.get_virtual_joystick() if im else null
	if joystick == null:
		return
	var cam_speed: float = 0.003
	var sensitivity: float = 1.0
	if "sensitivity" in player:
		sensitivity = float(player.sensitivity)
	var look_handler := func(delta_px: Vector2) -> void:
		player.orbit_camera(delta_px.x * cam_speed * 1.5 * sensitivity, \
			delta_px.y * cam_speed * 1.5 * sensitivity)
	if not joystick.camera_look.is_connected(look_handler):
		joystick.camera_look.connect(look_handler)
	var _gl := _glog()
	if _gl:
		_gl.info("GlobeWorld: touch HUD wired to orbit_camera")


## THE STREAMER FENCE (issue #19): when the world leaves the tree --
## scene swap, probe exit, teardown -- stop the streamer AND reap it:
## the fence's sync part is a FAST quick lap (finished threads only,
## never a wait on a busy worker); the non-blocking frame drain runs
## ON THE ORPHANED STREAMER OBJECT after this returns, so _exit_tree
## is instant and the derives finish through the next frames' applies.
## The unjoined threads were the source of the teardown stderr spam
## ("Nonexistent function", "get_ticks_msec on null", "Thread
## destroyed without wait_to_finish"). Guarded so a fence-less (or
## mock) streamer stays silent.
func _exit_tree() -> void:
	var streamer = get("streamer")
	if streamer != null and streamer.has_method("async_shutdown"):
		streamer.async_shutdown()

func _setup_streamer() -> void:
	if not stream_terrain:
		return
	# THE RENDERER SWITCH (clipmap round): clipmap (default) or the legacy
	# streamer. Both draw the SAME ground law through the same public surface.
	terrain_render = str(ProjectSettings.get_setting(TERRAIN_RENDER_SETTING, terrain_render))
	# SCALE GATE: the clipmap's ring ladder (inner radius, hysteresis, cell
	# sizes) is tuned for the canon 20 km planet. Below planet scale the
	# prototype bench sphere (R=100) would re-centre every step, so it falls
	# back to the streamer -- the same 1000 m line the world's other
	# planet-scale gates use.
	if terrain_render == "clipmap" and planet_radius < PLANET_RENDER_MIN_R:
		terrain_render = "streamer"
	if terrain_render == "clipmap":
		streamer = load("res://scenes/worlds/globe_clipmap.gd").new()
		streamer.configure(planet_radius, 7.0, world_root)
		streamer.terrain_on = true
		streamer.update(_spawn_dir() * planet_radius)
		streamer.build_all()
	else:
		streamer = load("res://scenes/worlds/globe_terrain_streamer.gd").new()
		streamer.configure(planet_radius, 7.0, world_root)
		# Terrain arc: the heightfield joins the tiles at planet scale. The
		# planar prototype mode is GONE (the cache-lane/planar cull round):
		# every globe is a terrain globe.
		streamer.terrain_on = true
		streamer.update(_spawn_dir() * planet_radius)
		_setup_chart_lod()
	# SPAWN MESH GATE (round 10): the boot must be able to SEE its own
	# ground. The first update is synchronous, so an unloaded spawn face
	# means the streamer is broken -- fail LOUD here instead of booting
	# over a bare water shell (the round-5/9 "spawned on the ocean"
	# reports were render-side; this gate splits loader failure from
	# renderer failure with one log line).
	var log4 = get_node_or_null("/root/GameLog")
	if streamer.is_loaded(streamer.current_face):
		if log4:
			log4.info("GlobeWorld: spawn face %d mesh-ready at boot (%d faces, %d tris) [%s]" % [streamer.current_face, streamer.active_faces().size(), streamer.triangle_count(), terrain_render])
	else:
		if log4:
			log4.error("GlobeWorld: spawn face %d did NOT load at boot -- the world will render as bare shell/water. %s load path is broken." % [streamer.current_face, terrain_render])


## CHART-LOD GLUE setup: the adapter + the overlay root under
## world_root. Kept SEPARATE from the terrain streamer's heightfield
## patches: the chart overlays are the penrose lattice climbing
## beside it, occasionally denser but never competing with the
## heightfield's own seam laws (same takeaway as the prd's
## "rendering-engine heartbeat" scoping).
func _setup_chart_lod() -> void:
	# The adapter owns the policy chain (it preloads the LOD policy +
	# the pentagrid frame script itself).
	chart_lod = load("res://scenes/worlds/penrose_chart_adapter.gd").new()
	chart_lod_root = Node3D.new()
	chart_lod_root.name = "ChartLodRoot"
	world_root.add_child(chart_lod_root)


## The player's radial snap rides the WALK SURFACE (displaced terrain
## + seeded rock caps) via the streamer's single ground law. Callable
## receives the player's WORLD position; directions are derived
## relative to planet_center (floating origin: the world origin is
## NOT the planet center after the first shift). Installed by
## _build_player (the streamer is built first; the player second).
func _install_walk_provider() -> void:
	if streamer == null or player == null:
		return
	player.snap_height_provider = func(wpos: Vector3) -> float:
		var dir: Vector3 = (wpos - planet_center).normalized()
		return streamer.walk_surface_h(dir)


## Terrain-only read at a world position (the player's mobility law
## samples this seam so walk-over rock caps never read as hills).
func terrain_h_at(wpos: Vector3) -> float:
	if streamer == null:
		return 0.0
	return streamer.terrain_h((wpos - planet_center).normalized())


## The ford law's flag seam (globe_player.terrain_on_local resolves
## this up the parent chain): one truthful answer, no re-derivation.
func terrain_on_flag() -> bool:
	return streamer != null and streamer.terrain_on


## CHART-LOD GLUE tick (2 Hz alongside the truth line): feed the
## player's live lat/lon to the adapter, apply the padded skirts to
## the plan BEFORE ordering, then funnel each work order into a real
## mesh build (PenroseMeshBuilder for the surface + skirt_strip data
## appended as a third, darker surface). Empty delta = no-op.
##
## BOOT CRASH LAW (the play-day crash report: playable loads ~60 s,
## then dies; cold-start figure: ONE tick meshes ~42 chart overlays
## synchronously -- build_region + sphere projection + skirt PER
## CHART -- a multi-second main-thread hang in the boot window that
## starves the engine's progress signal and trips the shell watchdog).
## FIX, two layers:
##   1. GATE: overlay builds are OFF by default (chart_overlays_on =
##      false). The Turn-9 ground backend now carries the Penrose
##      identity on the REAL terrain, so the overlays are redundant
##      decoration; the policy/adapter probes still exercise the full
##      path by driving the funnel directly (probe_chart_lod_scene
##      flips the gate on).
##   2. BUDGET: when the gate is on, at most MAX_ORDERS_PER_TICK
##      meshes build per tick; the adapter's last_plan state only
##      advances for the orders actually APPLIED, so the rest re-queue
##      next tick (trickle, never a spike).
var chart_overlays_on: bool = false
const MAX_ORDERS_PER_TICK: int = 2
var _chart_room_x: float = 0.0
var _chart_room_y: float = 0.0
func _update_chart_lod(delta: float) -> void:
	if chart_lod == null or player == null:
		return
	_chart_accum += delta
	if _chart_accum < 0.5:
		return
	_chart_accum = 0.0
	var Sph = load("res://core/frame/math/spherical.gd")
	var dir: Vector3 = (player.global_position - planet_center).normalized()
	var ll: Vector2 = Sph.cartesian_to_spherical(dir * planet_radius, planet_radius)
	last_chart_lat = ll.x
	last_chart_lon = ll.y
	# The padded plan: settle seams first, then pad trailing rims so
	# orders carry the REAL skirt depth the seam needs right now.
	var policy = load("res://scenes/worlds/penrose_chart_lod.gd")
	var plan: Dictionary = policy.plan_safe(ll.x, ll.y, 1)
	var orders: Array = chart_lod.apply_plan(plan, 1)
	if orders.is_empty():
		return
	# BUDGET (the cold-start trickle): only the first
	# MAX_ORDERS_PER_TICK orders build this tick. The adapter's state
	# advances ONLY for what we apply, so unapplied orders re-queue on
	# the next 2 Hz tick — the boot window stays smooth and the shell
	# watchdog never starves.
	var applied: Array = orders.slice(0, MAX_ORDERS_PER_TICK)
	var deferred: Array = orders.slice(MAX_ORDERS_PER_TICK)
	if not deferred.is_empty():
		# Roll last_plan back to cover only the applied prefix, so the
		# deferred half re-emerges as the delta next tick.
		var partial: Dictionary = {}
		var applied_ids := {}
		for o in applied:
			applied_ids[int(o["chart_index"])] = true
		for i in chart_lod.last_plan:
			if applied_ids.has(int(i)):
				partial[i] = chart_lod.last_plan[i]
		chart_lod.last_plan = partial
	var builder = load("res://scenes/worlds/penrose_mesh_builder.gd")
	for o in applied:
		var idx: int = int(o["chart_index"])
		var center: Vector2 = load("res://core/frame/math/pentagrid.gd").atlas_centers_dense(1)[idx]
		var patch: Array = policy.PentagridScript.build_region(
			policy.PentagridScript.GAMMA, float(o["half_extent"]))
		var mi: MeshInstance3D = builder.build_instance(
			patch, "ChartLod_%d" % idx, false, 1.0, center.x, center.y, planet_radius)
		# Skirt rim: same patch, padded depth, sphere-projected -- append
		# as an extra darkened surface so the rim reads as seam fabric,
		# not terrain.
		var padded: float = chart_lod.padded_skirt(idx, plan, 1)
		var skirt: Dictionary = policy.PentagridScript.skirt_strip(patch, padded, 1.0, 0.0)
		if not (skirt["positions"] as PackedVector3Array).is_empty():
			var skirt_arrays := []
			skirt_arrays.resize(Mesh.ARRAY_MAX)
			skirt_arrays[Mesh.ARRAY_VERTEX] = _project_skirt(skirt["positions"], center, planet_radius)
			skirt_arrays[Mesh.ARRAY_NORMAL] = skirt_arrays[Mesh.ARRAY_VERTEX]
			skirt_arrays[Mesh.ARRAY_COLOR] = _skirt_colors((skirt_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), Color(0.16, 0.13, 0.10))
			mi.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, skirt_arrays)
		# Swap in the overlay root (planet-relative parent chain).
		var old: MeshInstance3D = _chart_nodes.get(idx, null)
		if old != null and is_instance_valid(old):
			old.queue_free()
		mi.name = "ChartLod_%d" % idx
		chart_lod_root.add_child(mi)
		_chart_nodes[idx] = mi


## Project skirt positions (planar tiling coords) onto the sphere via
## the chart's tangent plane, matching PenroseMeshBuilder's gnomonic
## path (the skirt lands exactly where the surface's rim dropped).
func _project_skirt(pos: PackedVector3Array, center: Vector2, radius: float) -> PackedVector3Array:
	var PG = load("res://core/frame/math/pentagrid.gd")
	var out := PackedVector3Array()
	for p in pos:
		# skirt_strip emits (x*scale, y*scale, z) in tiling units where
		# x,y already carry the scale: unpack to the planar Vector2 the
		# gnomonic path expects by undoing the z-only split.
		out.append(PG.gnomonic_project(Vector2(p.x, p.y), center.x, center.y, radius))
	return out


## Flat skirt colors (one authored color; the tag nuance is a
## future material pass).
func _skirt_colors(count: int, color: Color) -> PackedColorArray:
	var out := PackedColorArray()
	for _i in range(count):
		out.append(color)
	return out


func _physics_process(delta: float) -> void:
	if player == null:
		return
	# Pad first: the player's move_and_slide this frame must find
	# ground at its CURRENT position (this scene node processes before
	# its player child).
	_update_surface_pad()
	if streamer:
		# Planet-relative position: patches are parented planet-relative
		# under world_root, so face addressing uses the direction from
		# the planet CENTER, never the world origin (invariant across
		# floating-origin shifts).
		streamer.update(player.global_position - planet_center)
		_tick_zone_spawns(delta)
		if chart_overlays_on:
			_update_chart_lod(delta)
		else:
			_chart_accum = 0.0
	_maybe_shift_world()
	# SPAWN TRUTH (round 7, item 4): keep the on-screen position line
	# fresh at 2 Hz. No-op until _build_spawn_truth() made the label
	# (terrain globes with a playable HUD only).
	_truth_accum += delta
	if _truth_accum >= 0.5:
		_truth_accum = 0.0
		_update_spawn_truth()


func _build_shell() -> void:
	var shell := StaticBody3D.new()
	shell.name = "GlobeShell"
	shell.physics_material_override = PhysicsMaterial.new()
	shell.physics_material_override.friction = 1.0
	shell.physics_material_override.bounce = 0.0

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = planet_radius
	col.shape = sphere
	shell.add_child(col)
	# S8 fix: the megasphere contact cannot support a 1 m body (solver
	# precision; the body sinks through at |v_r| ~2.7 m/s). The
	# re-anchored surface pad (see _build_surface_pad) is the physics
	# truth, so the sphere collider is never the ground.
	shell_col = col
	col.disabled = true

	var mesh_inst := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = planet_radius + SKIN_THICKNESS
	mesh.height = (planet_radius + SKIN_THICKNESS) * 2.0
	mesh.radial_segments = 96
	mesh.rings = 48
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.55, 0.35)  # grass green
	mat.roughness = 0.95
	mesh.material = mat
	mesh_inst.mesh = mesh
	# THE SHELL-VISUAL LAW (ground-law audit round): the flat green base
	# sphere would read as a second ground under the streamer's patches,
	# so its DRAW is never shown (node + collider bookkeeping untouched).
	# The planar prototype that used it as the ground is gone.
	mesh_inst.name = "ShellVisual"
	mesh_inst.visible = false
	shell.add_child(mesh_inst)

	world_root.add_child(shell)


## S8 planet-scale ground support: ONE re-anchored surface pad.
## Measured (S8 experiments): the megasphere SphereShape cannot
## support a 1 m body at R = 20 km, and per-patch trimesh colliders
## carry face-scale local coordinates (a whole icosahedron face spans
## ~10 km at R = 20 km) that the concave solver also handles badly.
## The reliable primitive is a SMALL local collider with meter-scale
## coordinates re-anchored under the body every frame. The pad is a
## fixed curved disc (local coords <= PAD_RADIUS) whose rings dip by
## the exact spherical sagitta; only its transform ever changes.
func _build_surface_pad() -> void:
	var body := StaticBody3D.new()
	body.name = "SurfacePad"
	body.physics_material_override = PhysicsMaterial.new()
	body.physics_material_override.friction = 1.0
	body.physics_material_override.bounce = 0.0
	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	# Winding-independent: the pad is contacted from above only.
	shape.backface_collision = true
	shape.set_faces(_pad_faces())
	col.shape = shape
	body.add_child(col)
	world_root.add_child(body)
	surface_pad = body
	_pad_shape = shape
	_update_surface_pad()


## The pad's fixed local-space triangles: center vertex ON the walk
## surface, two rings dipped by the sphere's sagitta at their chord
## distance (local y is radial: negative = below the surface).
func _pad_faces() -> PackedVector3Array:
	var faces: PackedVector3Array = PackedVector3Array()
	var ring_radii: Array = [PAD_RADIUS * 0.5, PAD_RADIUS]
	var rings: Array = []
	for d in ring_radii:
		var dip: float = planet_radius - sqrt(planet_radius * planet_radius - d * d)
		var ring: PackedVector3Array = PackedVector3Array()
		for i in range(PAD_SEGMENTS):
			var a: float = TAU * float(i) / float(PAD_SEGMENTS)
			ring.append(Vector3(cos(a) * d, -dip, sin(a) * d))
		rings.append(ring)
	var inner: PackedVector3Array = rings[0]
	var outer: PackedVector3Array = rings[1]
	for i in range(PAD_SEGMENTS):
		var j: int = (i + 1) % PAD_SEGMENTS
		faces.append(Vector3.ZERO)
		faces.append(inner[i])
		faces.append(inner[j])
		faces.append(inner[i])
		faces.append(outer[i])
		faces.append(outer[j])
		faces.append(inner[i])
		faces.append(outer[j])
		faces.append(inner[j])
	return faces


## Terrain-conforming pad faces: a centre vertex plus PAD_RINGS rings out
## to PAD_RADIUS. Each vertex's local +Y is the WALK-SURFACE height above
## planet_radius sampled along the vertex's own radial direction (the
## sphere sagitta is added per ring so the disc hugs the curvature between
## samples). Physics needs SMALL shape coordinates, so local coords stay
## <= PAD_RADIUS. `dir` is the pad's unit direction and `basis` its
## orientation; the walk law is the SAME one the snap provider and props
## ride, so the collided ground matches the drawn ground by construction.
func _terrain_pad_faces(dir: Vector3, basis: Basis) -> PackedVector3Array:
	var faces: PackedVector3Array = PackedVector3Array()
	var cols: int = maxi(PAD_SEGMENTS, 8)
	var h_center: float = streamer.walk_surface_h(dir) if streamer != null else 0.0
	var center_v := Vector3(0.0, h_center, 0.0)
	var rings: Array = []
	for r in range(1, PAD_RINGS + 1):
		var d: float = PAD_RADIUS * float(r) / float(PAD_RINGS)
		var sag: float = planet_radius - sqrt(maxf(planet_radius * planet_radius - d * d, 0.0))
		var ring: PackedVector3Array = PackedVector3Array()
		for i in range(cols):
			var a: float = TAU * float(i) / float(cols)
			var lx: float = cos(a) * d
			var lz: float = sin(a) * d
			# The pad's world position is dir * planet_radius; offset in the
			# pad's own plane, then renormalize to a direction for the law.
			var wdir: Vector3 = (dir * planet_radius + basis * Vector3(lx, 0.0, lz)).normalized()
			var h: float = streamer.walk_surface_h(wdir) if streamer != null else 0.0
			ring.append(Vector3(lx, h - sag, lz))
		rings.append(ring)
	# Fan from the centre vertex to the first ring (the centre is a single
	# point, never a zero-radius ring -- a degenerate ring leaves a hole the
	# body can fall through when the radial snap is off).
	var first: PackedVector3Array = rings[0]
	for i in range(cols):
		var j: int = (i + 1) % cols
		faces.append(center_v)
		faces.append(first[i])
		faces.append(first[j])
	for r in range(1, PAD_RINGS):
		var inner: PackedVector3Array = rings[r - 1]
		var outer: PackedVector3Array = rings[r]
		for i in range(cols):
			var j: int = (i + 1) % cols
			faces.append(inner[i])
			faces.append(outer[i])
			faces.append(outer[j])
			faces.append(inner[i])
			faces.append(outer[j])
			faces.append(inner[j])
	return faces


## Re-anchor the pad under the player: set the planet-relative
## transform from the player's current radial direction. Runs every
## physics frame BEFORE the player's move_and_slide, and again after
## every floating-origin shift.
func _update_surface_pad() -> void:
	if surface_pad == null or player == null:
		return
	var dir: Vector3 = (player.global_position - planet_center).normalized()
	surface_pad.position = dir * (planet_radius + _surface_lift())
	# Align local +Y with radial up. The disc is rotationally
	# symmetric, so only the up axis matters; keep the basis proper
	# (right-handed, same convention as the player camera).
	var north: Vector3 = Vector3(0, 1, 0)
	if abs(dir.dot(north)) > 0.999:
		north = Vector3(0, 0, -1)
	north = (north - dir * north.dot(dir)).normalized()
	var east: Vector3 = north.cross(dir)
	var basis := Basis(east, dir, -north)
	surface_pad.basis = basis
	# Terrain scale: rebuild the shape so the collided ground FOLLOWS
	# the walk-surface law under the player (a flat disc stands proud of
	# the next rise and stops the walk dead). The pad origin already
	# rides the terrain (via _surface_lift), so each vertex's local +Y is
	# its walk height relative to the pad origin.
	# Rebuild throttle: the walk law is smooth, so re-baking only every few
	# metres keeps the collider flush without rebuilding the shape (and its
	# broadphase) on every physics frame while standing still.
	var rebuild: bool = _pad_built_dir == Vector3.ZERO \
			or dir.angle_to(_pad_built_dir) * planet_radius > 3.0
	if streamer != null and _pad_shape != null and rebuild:
		_pad_built_dir = dir
		# The origin sits at planet_radius + TILE_LIFT + terrain_h(dir), so
		# subtract that terrain term to express each vertex relative to it;
		# the remaining local +Y is the walk-surface lift over the terrain
		# (plus any walk-over cap), keeping collision flush with the ground.
		var terrain_center: float = streamer.terrain_h(dir)
		var faces: PackedVector3Array = _terrain_pad_faces(dir, basis)
		var i := 0
		while i < faces.size():
			faces[i].y -= terrain_center
			i += 1
		_pad_shape.set_faces(faces)


## Height of the WALKABLE SURFACE above planet_radius. At prototype
## scale the collision shell IS the walk surface (lift 0): the
## streamed tiles are visual-only there (no colliders, S5b) and the
## player must keep shell contact (probe_globe_world asserts radial
## rest). At planet scale the re-anchored pad carries the collision
## at planet_radius + TILE_LIFT + TERRAIN: the walk surface is the
## displaced terrain under the player (the streamer's ground law --
## the same law the snap provider rides), so hills lift the pad and
## the sea floor drops it.
func _surface_lift() -> float:
	if streamer == null:
		return STREAMER_TILE_LIFT
	var dir: Vector3 = _spawn_dir()
	if player != null:
		dir = (player.global_position - planet_center).normalized()
	return STREAMER_TILE_LIFT + streamer.terrain_h(dir)


## The spawn direction (unit) -- the scene's lat/lon convention.
func _spawn_dir() -> Vector3:
	var Sph = load("res://core/frame/math/spherical.gd")
	return Sph.spherical_to_cartesian(SPAWN_LAT_DEG, SPAWN_LON_DEG, 0.0, 1.0)


## WATER (terrain arc): one translucent shell at the sea line. Visual
## only: the ocean floor is the displaced terrain (one ground law; the
## sea floor IS the ground). The water gate is WATER_ON alone (the
## planar prototype is gone).
func _build_water() -> void:
	if not WATER_ON:
		return
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var sea: float = Gen.sea_level(streamer.world_seed)
	water_body = MeshInstance3D.new()
	water_body.name = "WaterShell"
	var wmesh := SphereMesh.new()
	wmesh.radius = planet_radius + STREAMER_TILE_LIFT + sea
	wmesh.height = wmesh.radius * 2.0
	wmesh.radial_segments = 96
	wmesh.rings = 48
	var wmat := StandardMaterial3D.new()
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.albedo_color = Color(0.12, 0.35, 0.5, 0.62)
	wmat.roughness = 0.15
	wmat.metallic = 0.1
	wmesh.material = wmat
	water_body.mesh = wmesh
	world_root.add_child(water_body)


## Play-day feedback #8: the visible sun on the globe too (the clock
## arc rides on top of the scene's static fill light).
## CELESTIAL FRAME: the sun node is a child of the PLAYER, not the
## scene/world_root -- at planet scale the floating origin slides the
## world under the player, and a scene-anchored disc swung across the
## sky with every step (round 5). As a player child it rides the
## rebase for free and stays a fixed star overhead.
func _build_sky_sun() -> void:
	var sun_script: GDScript = load("res://entities/sky_sun.gd")
	if sun_script == null:
		return
	var sun := Node3D.new()
	sun.name = "SkySun"
	sun.set_script(sun_script)
	if player != null:
		player.add_child(sun)
	else:
		# Player not built yet (build order); fall back to the scene
		# and let the player adopt it after _build_player.
		add_child(sun)
		sun.set_meta("adopt_by_player", true)


## The moon in the globe sky: same entity the planar world mounts
## (disc + synodic phase shading + moonlight). Built beside the sun
## so the player adoption re-parents them together.
func _build_sky_moon() -> void:
	var moon_script: GDScript = load("res://entities/sky_moon.gd")
	if moon_script == null:
		return
	var moon := Node3D.new()
	moon.name = "SkyMoon"
	moon.set_script(moon_script)
	if player != null:
		player.add_child(moon)
	else:
		# Player not built yet (build order); fall back to the scene
		# and let the player adopt it after _build_player (the sun's
		# fallback pattern; the adopt block re-parents it).
		add_child(moon)


## THE SKY SIGNS (planar-retirement Step 1): the Skyward Concord
## constellation renderer -- purely visual, one per world. The planar
## scene mounted it under itself; on the globe it rides under the
## player (the sun/moon school) so it follows the local body. Sealed
## windows render dim + patternless until the tribe reveals the glyph.
func _build_sky_signs() -> void:
	var sky_script: GDScript = load("res://entities/sky_sign_renderer.gd")
	if sky_script == null:
		return
	var sky := Node3D.new()
	sky.name = "SkySigns"
	sky.set_script(sky_script)
	if player != null:
		player.add_child(sky)
	else:
		add_child(sky)
		sky.set_meta("adopt_by_player", true)


## THE CONCORD LOOP ON THE GLOBE (planar-retirement Step 1, the
## flagship): the Ancient Door + the Concord Stone. Before this the
## globe built neither, so `ActsService` (which scans the
## "ancient_doors" group) never saw a door and the whole
## watch-the-sky -> solve-the-day -> the-door-opens-at-dawn loop was
## dead on the planet the player actually plays. The props ride the
## village prop belt's own placement law (spawn tangent frame, lifted
## by the walk surface) via VillageProps.build_concord.
func _build_concord_loop() -> void:
	var VP: GDScript = load("res://entities/village_props.gd")
	VP.build_concord(world_root, planet_radius, STREAMER_TILE_LIFT, \
		Callable(streamer, "walk_surface_h"))
	var gl := _glog()
	if gl:
		gl.info("GlobeWorld: the Concord loop is live (Ancient Door + Concord Stone on the spawn plaza)")


## THE BLESSED MARKS (planar-retirement Step 1): the shard's chosen
## class wears the sky's favor (mote ring + halo) -- one BlessedMark
## per player body, live-checked on a cadence inside the mark. Ported
## from world_playable._setup_blessed_marks; the mark is parented to
## the body so it rides the player.
func _setup_blessed_marks() -> void:
	var mark_script: GDScript = load("res://entities/blessed_mark.gd")
	if mark_script == null:
		return
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p) or not ("character_class" in p):
			continue
		if p.get_node_or_null("BlessedMark") != null:
			continue
		var mark := Node3D.new()
		mark.name = "BlessedMark"
		mark.set_script(mark_script)
		p.add_child(mark)
		mark.set_wearer(str(p.character_class), p)
		var gl := _glog()
		if gl:
			gl.info("GlobeWorld: BlessedMark on %s (%s)" % [str(p.entity_id), str(p.character_class)])



## The surface point for a prop placed at `bearing_deg` on `center`'s
## tangent frame, `reach_m` METERS of arc out (angular = reach_m/radius),
## riding the walk law's lift. Interact props need a fixed short walk at
## every planet scale, which a radian reach cannot give (the same reason
## village_props._build_batch_meters exists).
func _globe_meter_surface(center: Vector3, bearing_deg: float, reach_m: float) -> Vector3:
	var east: Vector3 = Vector3(0, 1, 0).cross(center).normalized()
	var north: Vector3 = center.cross(east).normalized()
	var reach_rad: float = reach_m / maxf(planet_radius, 1.0)
	var rad: float = deg_to_rad(bearing_deg)
	var dir: Vector3 = (center + east * (reach_rad * cos(rad)) \
		+ north * (reach_rad * sin(rad))).normalized()
	return dir * (planet_radius + STREAMER_TILE_LIFT \
		+ float(streamer.walk_surface_h(dir)) + 0.4)


## Radial-align a prop to the planet surface at `dir` (the village_props
## _align_radial law: local +Y is the surface up).
func _align_radial(node: Node3D, dir: Vector3) -> void:
	var east: Vector3 = Vector3(0, 1, 0).cross(dir).normalized()
	node.basis = Basis(east, dir, east.cross(dir).normalized())


## PLANAR-RETIREMENT STEP 3: the transit gates (S16 multiworld). The
## Moon Gate (dev hatch to the pale stone) + the Ascent (dev hatch to
## the Deep Root) stand a short walk off the plaza, mirroring
## world_playable._setup_moon_gate / _setup_ascent_gate. Both carry
## dev_hatch so probes + dev work can transit; players still read the
## sealed mystery shell (the entry law refuses OFFLINE worlds).
func _build_globe_gates() -> void:
	var gate_script: GDScript = load("res://entities/moon_gate.gd")
	if gate_script == null:
		return
	var center: Vector3 = TerrainGenRef.SPAWN_CENTER
	for entry in [GLOBE_MOON_GATE, GLOBE_ASCENT_GATE]:
		var gate: Node3D = gate_script.new()
		gate.name = str(entry[0])
		gate.set("display_name", str(entry[1]))
		gate.set("target_world", str(entry[2]))
		gate.set("dev_hatch", true)
		world_root.add_child(gate)
		var dir: Vector3 = _globe_meter_surface(center, float(entry[3]), float(entry[4])).normalized()
		gate.global_position = world_root.global_position \
			+ _globe_meter_surface(center, float(entry[3]), float(entry[4]))
		_align_radial(gate, dir)
	_log_backend("info", "GlobeWorld: the transit gates stand (Moon Gate + the Ascent)")


## PLANAR-RETIREMENT STEP 3: the town watch, ported from
## world_playable._setup_guards. Each guard loads its GuardData, gets a
## GuardAI brain (attach AFTER the tree add so Enemy._ready's health
## component exists -- the planar scene's order), registers with
## EntityService, and is posted at its spawn point.
func _build_globe_guards() -> void:
	var guard_script: GDScript = load("res://entities/guard.gd")
	if guard_script == null:
		return
	var es = get_node_or_null("/root/EntityService")
	var tm = get_node_or_null("/root/TargetingManager")
	var center: Vector3 = TerrainGenRef.SPAWN_CENTER
	var placed: int = 0
	for entry in GLOBE_GUARD_BATCH:
		var data = load("res://data/guards/%s.tres" % str(entry[0]))
		if data == null:
			_log_backend("warn", "GlobeWorld: guard data '%s' missing" % str(entry[0]))
			continue
		# Duplicate so the post position can be stamped without
		# mutating the shared .tres resource (the return-to-post
		# law needs a REAL post at the guard's own spawn point).
		data = data.duplicate()
		var surface: Vector3 = _globe_meter_surface(center, float(entry[1]), float(entry[2]))
		data.post_position = surface
		var guard: Node3D = guard_script.new()
		guard.display_name = str(data.display_name)
		guard.set("guard_data", data)
		# Visuals BEFORE the tree add: Enemy._ready's _apply_hitbox_profile
		# reuses a scene-authored CollisionShape3D instead of creating a
		# deferred StaticBody3D/Hitbox, so the guard never carries two
		# colliders.
		_build_guard_visuals(guard)
		world_root.add_child(guard)
		guard.global_position = world_root.global_position + surface
		guard.attach_guard_ai(data)
		if es != null and es.has_method("register_entity"):
			var SpawnMetadataScript = load("res://core/events/spawn_metadata.gd")
			var metadata = SpawnMetadataScript.enemy(guard.display_name, \
				GLOBE_ZONE_ID, guard.global_position, guard.level)
			es.register_entity(guard, metadata)
		var gid: String = str(guard.entity_id)
		if tm != null and tm.has_method("register_targetable") and gid != "":
			tm.register_targetable(gid, "npc", guard, \
				guard.display_name, guard.global_position, int(guard.entity_type))
		placed += 1
	_log_backend("info", "GlobeWorld: %d guards on the watch" % placed)


## Placeholder guard body (the planar scene's capsule: blue capsule mesh
## + a matching CapsuleShape3D). Enemy._ready would create a hitbox from
## the creature profile, but a scene-less guard has no EnemyData, so the
## body authors its own shape + visual (the planar .tscn's exact setup).
func _build_guard_visuals(guard: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.35, 0.85)
	mat.metallic = 0.4
	mat.roughness = 0.5
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.45
	mesh.height = 1.8
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(0, 0.9, 0)
	guard.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.8
	col.shape = shape
	col.position = Vector3(0, 0.9, 0)
	guard.add_child(col)


## PLANAR-RETIREMENT STEP 3: the dungeon portal, ported from
## world_playable._setup_portal. A visual portal node + the authored
## GatewayData registered with WorldService, targetable as TELEPORT so
## the walk-up Enter path resolves it. Entry lands in the dungeon zone
## (whose horde_config_id auto-starts vault_seal).
func _build_globe_portal() -> void:
	var gateway_data = load("res://data/gateways/%s.tres" % str(GLOBE_DUNGEON_PORTAL[0]))
	if gateway_data == null:
		_log_backend("warn", "GlobeWorld: dungeon gateway data missing; the portal stays dark")
		return
	var ws = get_node_or_null("/root/WorldService")
	var tm = get_node_or_null("/root/TargetingManager")
	if ws == null or not ws.has_method("register_gateway"):
		return
	var center: Vector3 = TerrainGenRef.SPAWN_CENTER
	var surface: Vector3 = _globe_meter_surface(center, float(GLOBE_DUNGEON_PORTAL[1]), float(GLOBE_DUNGEON_PORTAL[2]))
	var portal := Node3D.new()
	portal.name = "DungeonPortal"
	world_root.add_child(portal)
	portal.global_position = world_root.global_position + surface
	_align_radial(portal, surface.normalized())
	_build_portal_visuals(portal)
	var gateway_id: String = ws.register_gateway({
		"display_name": str(gateway_data.display_name),
		"position": portal.global_position,
		"from_zone": GLOBE_ZONE_ID,
		"to_zone": str(gateway_data.destination_zone_id),
		"to_position": gateway_data.destination_position,
		"required_level": int(gateway_data.min_level),
		"radius": 5.0,
		"activation_radius": 6.0,
	})
	if tm != null and tm.has_method("register_targetable"):
		tm.register_targetable(gateway_id, "gateway", portal, \
			str(gateway_data.display_name), portal.global_position, \
			Entity.EntityType.TELEPORT)
	_log_backend("info", "GlobeWorld: dungeon portal active (%s -> %s)" \
		% [gateway_id, str(gateway_data.destination_zone_id)])


## Placeholder portal geometry (a dark green ring + a warm core light);
## a skinned model would drive the same gateway registration.
func _build_portal_visuals(portal: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.35, 0.22)
	mat.emission_enabled = true
	mat.emission = Color(0.10, 0.55, 0.28)
	mat.emission_energy_multiplier = 1.4
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.1
	torus.outer_radius = 1.5
	ring.mesh = torus
	ring.material_override = mat
	ring.position = Vector3(0, 1.6, 0)
	portal.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = Color(0.30, 0.85, 0.45)
	light.light_energy = 1.6
	light.omni_range = 8.0
	light.position = Vector3(0, 1.6, 0)
	portal.add_child(light)


## PLANAR-RETIREMENT STEP 3: the demo housing plot, ported from
## world_playable._setup_housing -- registers the purchasable plot with
## DwellingService so /buyplot, /placeguard and /placeankh have
## something to act on.
func _build_globe_housing() -> void:
	var dw = get_node_or_null("/root/DwellingService")
	if dw == null or not dw.has_method("register_plot"):
		return
	var center: Vector3 = TerrainGenRef.SPAWN_CENTER
	var plot_center: Vector3 = _globe_meter_surface(center, float(GLOBE_HOUSING_PLOT[1]), float(GLOBE_HOUSING_PLOT[2]))
	dw.register_plot(str(GLOBE_HOUSING_PLOT[0]), GLOBE_ZONE_ID, plot_center, \
		float(GLOBE_HOUSING_PLOT[3]), int(GLOBE_HOUSING_PLOT[4]))
	_log_backend("info", "GlobeWorld: demo plot registered (stand near it, /buyplot)")



func _build_sun() -> void:
	# THE ONE-SUN LAW: the static fixed sun light is retired -- the
	# re-parented SkySun owns the arc-tracking DirectionalLight that
	# dims to the night floor on the clock (globe sun build, round 5).
	# This node owns the SKY SHADE: background + ambient, driven per
	# frame by the same day curve the bodies ride.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = NIGHT_BG
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.45, 0.5)
	e.ambient_light_energy = NIGHT_AMBIENT
	add_child(env)
	env.environment = e
	_env = e


# THE SKY SHADE LAW (one clock): the background gradient and the
# ambient energy are pure functions of the Concord epoch's day phase
# (the SAME clock SkySun/SkyMoon/SignService read -- no second clock)
# through three keyed ramps: deep blue-black night, amber dusk band,
# clean blue day.
# Night readability (the "sky is black" report): 0.015,0.025,0.055
# rendered as near-void. The night floor is a deep STARLIGHT blue --
# clearly night, never a blank black sheet.
const NIGHT_BG: Color = Color(0.055, 0.085, 0.16)
const DAY_BG: Color = Color(0.30, 0.48, 0.66)
const DUSK_BG: Color = Color(0.52, 0.24, 0.18)
const NIGHT_AMBIENT: float = 0.32
const DAY_AMBIENT: float = 0.60

var _env: Environment = null


func _process(_delta: float) -> void:
	if _env == null:
		return
	var svc := get_node_or_null("/root/SignService")
	var epoch: float = svc.sky_epoch_days() if svc != null and svc.has_method("sky_epoch_days") \
		else float(Time.get_unix_time_from_system()) / 86400.0
	var phase := fposmod(epoch, 1.0)
	# The day curve mirrors sky_sun's (0 = dawn, 0.25 = noon, 0.5 =
	# dusk); the dusk band fires mid-ramp only.
	var day := clampf(sin(phase * TAU) * 1.6 + 0.08, 0.0, 1.0)
	var dusk := smoothstep(0.0, 0.45, day) * (1.0 - smoothstep(0.45, 0.95, day))
	var bg: Color = NIGHT_BG.lerp(DAY_BG, day)
	_env.background_color = bg.lerp(DUSK_BG, dusk * 0.55)
	_env.ambient_light_energy = NIGHT_AMBIENT + (DAY_AMBIENT - NIGHT_AMBIENT) * day


## S10: the arena gateway trigger at the village edge. An Area3D under
## world_root (shift-invariant: it rides the world rebase like every
## other planet-bound node) whose body_entered fires InstanceService.
func _build_arena_gateway() -> void:
	var GatewayScript = load("res://scenes/worlds/arena_gateway.gd")
	var gateway: Area3D = GatewayScript.new()
	gateway.zone_id = "zone_arena_coliseum"
	gateway.name = "ArenaGateway"
	# East of spawn on the sand line: tangent-east, just above the
	# shell so walking through it fires the join once.
	# ON the walk surface: the trigger rides the walk law at its
	# placement direction (a fixed radius + 1 would be buried under
	# the plaza at planet scale -- 9 m of terrain above the bare
	# shell), lifted a body-height so the walking player crosses it.
	var gw_dir: Vector3 = Vector3(14.0, 0.0, 0.0).normalized()
	var gw_r: float = planet_radius + STREAMER_TILE_LIFT \
		+ (streamer.walk_surface_h(gw_dir) if streamer else 0.0) + 1.0
	gateway.position = gw_dir * gw_r
	world_root.add_child(gateway)
	arena_gateway = gateway


var arena_gateway: Node3D = null


## THE STARTER VILLAGE PROTO (the ledger's parked build): the authored
## boots-and-stalls village on the spawn plaza flats -- hall, forge
## stall, signpost riding the plaza's own laws (exact flat ground,
## dry apron, cartway bent around the ring). Placed on the SAME frame
## the gateway rides, colliders via the one-law prop belt.
func _build_starter_village() -> void:
	var SV: GDScript = load("res://entities/starter_village.gd")
	starter_village = SV.build(world_root, planet_radius, STREAMER_TILE_LIFT, \
		Callable(streamer, "walk_surface_h"))
	# THE GAME-FUNCTION PROPS (turn 15, the owner's law): the ankh
	# shrine, moon gate, and bout queue stones ride the same walk-law
	# frame under the village's own root (the props' dir-bearing
	# block sits 120..-150 deg around the plaza, so they clear the
	# authored structures' bearings).
	var VP: GDScript = load("res://entities/village_props.gd")
	VP.build_village(starter_village, planet_radius, STREAMER_TILE_LIFT, \
		Callable(streamer, "walk_surface_h"))


## THE CAPITOL MONOLITH (the ledger's coast build): the authored
## megalith the road law walks the cart to -- the arrival anchor ring
## points here; the structure rides the same authored-install frame
## the village carries.
func _build_capitol_monolith() -> void:
	var CM: GDScript = load("res://entities/capitol_monolith.gd")
	capitol_monolith = CM.build(world_root, planet_radius, STREAMER_TILE_LIFT, \
		Callable(streamer, "walk_surface_h"))
	# THE CAPITOL PROPS (same turn-15 law): ankh, moon gate, bout
	# stones -- the plaza beats ride the plaza flat in the strand's
	# own tangent frame so the city plaza carries them too.
	var VP2: GDScript = load("res://entities/village_props.gd")
	VP2.build_capitol(capitol_monolith, planet_radius, STREAMER_TILE_LIFT, \
		Callable(streamer, "walk_surface_h"))


var starter_village: Node3D = null
var capitol_monolith: Node3D = null
var pans_monolith: Node3D = null
var pans_ferry_vessel: Node3D = null
var pier_beacon: Node3D = null
var moor_guide: Node3D = null


const FERRY_VESSEL_LAW = preload("res://entities/ferry_vessel.gd")
const HARBOR_LIGHTS = preload("res://entities/harbor_lights.gd")

## THE PANS MONOLITH (the far country's marker): the Sun Pans
## waypoint's own installation -- a sunbaked obelisk + mooring flank
## standing on the atoll's outer bank, riding the same authored
## install frame the capitol carries. The gateway pin
## (data/gateways/waypoint_sun_pans.tres) registers the walk-up law;
## this is the ART the pin points at.
func _build_pans_monolith() -> void:
	var PM: GDScript = load("res://entities/pans_monolith.gd")
	pans_monolith = PM.build(world_root, planet_radius, STREAMER_TILE_LIFT, \
		Callable(streamer, "walk_surface_h"))


## THE PANS RUNNER (S14.5's boat): the vessel physically rides the
## harbor pier <-> Sun Pans lane. The route + schedule are closed
## form (FerrySchedule off the Concord epoch -- the same math the
## almanac's sailing page and FerryService read); a one-second timer
## tick drives the ride law: berthed at the pier in port, visibly at
## sea during a crossing -- and whoever stands on her deck rides the
## lane with her (the S14.6 carry, one law in place()).
func _build_pans_ferry() -> void:
	var FS = get_node_or_null("/root/FerryService")
	var FV: GDScript = load("res://entities/ferry_vessel.gd")
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var sea: float = Gen.sea_level(streamer.world_seed) if streamer else 0.0
	pans_ferry_vessel = FV.build(world_root, planet_radius, STREAMER_TILE_LIFT, \
		Callable(streamer, "walk_surface_h"), sea)
	var logb = get_node_or_null("/root/GameLog")
	if FS == null:
		if logb:
			logb.warn("GlobeWorld: FerryService absent -- the Pans Runner stays berthed")
		return
	var ferry = FS.call("get_ferry", "veh_pans_ferry")
	if ferry == null:
		if logb:
			logb.warn("GlobeWorld: veh_pans_ferry not loaded -- the Pans Runner stays berthed")
		return
	# THE DECK WAKE IDENTITY: the vehicle's own route data names the
	# two ports (stamped once at the boot read; the raw .tres stays
	# the one truth -- no magic strings here).
	_wake_vehicle_id = str(ferry.id)
	if ferry.route_gateways != null and ferry.route_gateways.size() >= 2:
		_wake_pier_gateway = str(ferry.route_gateways[0])
		_wake_pans_gateway = str(ferry.route_gateways[ferry.route_gateways.size() - 1])
	# THE WAKE WARP (tier 3): the world owns the placement -- listen
	# for validated warps and put the local body ashore.
	FS.connect("wake_warped", _execute_wake_warp)
	# THE HARBOR LIGHTS (the coast's answer to the stern lantern): a
	# caged beacon beside the pier head and a moor ember guide at the
	# pans bank. Both landings ride the SAME night law
	# (HarborLights.place_night) off the epoch this tick already
	# holds -- lit dusk to dawn, dark to the sun.
	var lane: Array = FERRY_VESSEL_LAW.lane_dirs()
	var HLB = load("res://entities/harbor_lights.gd")
	pier_beacon = HLB.build_pier_beacon(world_root, planet_radius, STREAMER_TILE_LIFT, \
		Callable(streamer, "walk_surface_h"), lane[0], sea)
	moor_guide = HLB.build_moor_guide(world_root, planet_radius, STREAMER_TILE_LIFT, \
		Callable(streamer, "walk_surface_h"), lane[1], sea)
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	tick.timeout.connect(_pans_ferry_tick.bind(int(ferry.ferries_per_day), \
		float(ferry.first_departure_hour), float(ferry.crossing_hours)))
	add_child(tick)


## ---- THE SUNDERED BARQUE (S14.7.3): the strait's own scheduled ride --
## the data route veh_sundered_barque already declares (6 cast-offs/day,
## first at 5.5 h, a 0.6 h crossing) and the physical hull was the one
## thing missing: the boat now rides the same closed-form FerrySchedule
## law the runner rides, between the two pin dirs ITS OWN gateway data
## names (DataService truth -- never an in-file bearing), carrying who
## stands on her deck (place()'s one carry law) and paying the deck
## wake the same ledger law pays. The 0.5 m/s RUN current stays the
## sea's own flow (the swim step's lane); the crossed arc the BARQUE
## law runs is the wakes'/pins' law.
const BARQUE_VEHICLE := "veh_sundered_barque"
const BARQUE_MOOR_GATEWAY := "waypoint_strait_moor"
const BARQUE_SEAWARD_GATEWAY := "waypoint_strait_seaward"
var sund_ferry_vessel: Node3D = null
var _barque_buoy_moor: Node3D = null
var _barque_buoy_seaward: Node3D = null
var _barque_vehicle_id: String = BARQUE_VEHICLE
var _barque_pier_gateway: String = BARQUE_MOOR_GATEWAY
var _barque_pans_gateway: String = BARQUE_SEAWARD_GATEWAY
var _barque_wake_seen: Dictionary = {}
var _barque_wake_last_t: float = -1.0

func _build_sundered_barque() -> void:
	var FS = get_node_or_null("/root/FerryService")
	var FV: GDScript = load("res://entities/ferry_vessel.gd")
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var sea: float = Gen.sea_level(streamer.world_seed) if streamer else 0.0
	var DS = get_node_or_null("/root/DataService")
	var moor: Vector3 = Vector3.ZERO
	var seaward: Vector3 = Vector3.ZERO
	var ok_pins := false
	if DS != null and DS.has_method("get_gateway"):
		var g1 = DS.get_gateway(BARQUE_MOOR_GATEWAY)
		var g2 = DS.get_gateway(BARQUE_SEAWARD_GATEWAY)
		if g1 != null and g2 != null:
			moor = (g1.source_position as Vector3).normalized()
			seaward = (g2.source_position as Vector3).normalized()
			ok_pins = true
	var logb = get_node_or_null("/root/GameLog")
	var ferry = null
	if FS != null:
		ferry = FS.call("get_ferry", BARQUE_VEHICLE)
	if ferry != null and ferry.route_gateways != null and ferry.route_gateways.size() >= 2:
		_barque_vehicle_id = str(ferry.id)
		_barque_pier_gateway = str(ferry.route_gateways[0])
		_barque_pans_gateway = str(ferry.route_gateways[ferry.route_gateways.size() - 1])
	if not ok_pins or ferry == null:
		if logb:
			logb.warn("GlobeWorld: the Sundered barque stays tied up (gateway data or ferry data absent)")
		return
	sund_ferry_vessel = FV.build_barque(world_root, moor, seaward,
		planet_radius, STREAMER_TILE_LIFT,
		Callable(streamer, "walk_surface_h"), sea)
	# THE HARBOR BUOYS (S14.7.4): the two pins get their floating marks
	# the runner's landings already have lights for -- drum + mast + amber
	# lamp ON the sea line, one flank step off each berth. They ride the
	# SAME night law the other harbor lights do (place_night off the
	# epoch this route's tick already holds).
	var HLB = load("res://entities/harbor_lights.gd")
	if HLB != null and HLB.has_method("build_strait_buoys"):
		var buoys: Array = HLB.call("build_strait_buoys", world_root,
			planet_radius, STREAMER_TILE_LIFT, moor, seaward, sea)
		if buoys.size() == 2:
			_barque_buoy_moor = buoys[0]
			_barque_buoy_seaward = buoys[1]
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	tick.timeout.connect(_barque_ferry_tick.bind(int(ferry.ferries_per_day),
		float(ferry.first_departure_hour), float(ferry.crossing_hours)))
	add_child(tick)


## The barque's ride-law tick: the SAME closed form the runner runs
## (FerrySchedule.vessel_t off the Concord epoch), place()'s one carry
## law, and its OWN wake text -- the berthing glue stamps the standing
## roster once per berth through record_deck_wake, exactly the ledger
## the dock path and the runner pay.
func _barque_ferry_tick(per_day: int, first_h: float, cross_h: float) -> void:
	if sund_ferry_vessel == null:
		return
	var Schedule = load("res://core/frame/srv/ferry_schedule.gd")
	var sign_svc := _sign()
	var epoch: float = sign_svc.sky_epoch_days() if sign_svc else \
		float(Time.get_unix_time_from_system()) / 86400.0
	var t: float = Schedule.vessel_t(per_day, first_h, cross_h, epoch)
	FERRY_VESSEL_LAW.place(sund_ferry_vessel, t)
	_barque_credit_deck_riders(t)
	# THE BUOY LIGHTS: night law off the same epoch (the runner's harbor
	# law, second route).
	HARBOR_LIGHTS.place_night(_barque_buoy_moor, epoch)
	HARBOR_LIGHTS.place_night(_barque_buoy_seaward, epoch)

func _barque_credit_deck_riders(t: float) -> void:
	var fs = get_node_or_null("/root/FerryService")
	if fs == null or not fs.has_method("record_deck_wake"):
		return
	var sea_before: bool = _barque_wake_last_t > 0.02 and _barque_wake_last_t < 0.98
	if sea_before:
		var end_id: String = _barque_pier_gateway if t <= 0.5 else _barque_pans_gateway
		for id in _barque_wake_seen:
			fs.call("record_deck_wake", str(_barque_wake_seen[id]), _barque_vehicle_id, end_id)
		_barque_wake_seen.clear()
	var at_sea: bool = t > 0.02 and t < 0.98
	if at_sea:
		var roster: Dictionary = sund_ferry_vessel.get_meta("ride_roster") \
			if sund_ferry_vessel.has_meta("ride_roster") else {}
		for id in roster:
			var b: Node = instance_from_id(id)
			if b == null or not is_instance_valid(b):
				continue
			# Players ride as physics bodies; NPC rosters (code-moved
			# Entities) are never credited -- no purse.
			if not (b is CharacterBody3D):
				continue
			var pid = b.get("entity_id")
			if pid == null or str(pid) == "":
				continue
			_barque_wake_seen[id] = str(pid)
	_barque_wake_last_t = t


## THE DEEP GARDEN BINDER (S14.7.3): the paint now follows the truth --
## one world-side listener joins HarvestService's harvest/respawn
## signals and hides each bed's grove while ALL three of its plants are
## depleted (the cove stands empty), reveals it when any respawn lands.
func _install_garden_binder() -> void:
	var BGB = load("res://entities/deep_garden_binder.gd")
	if BGB != null and BGB.has_method("bind"):
		BGB.call("bind", world_root)


## The ride law's tick: FerrySchedule.vessel_t is the ONE law -- the
## closed-form berth alternation. Mid-crossing it rides the crossing
## clock (mirrored on the return run); in port the boat WAITS at the
## next cast-off's origin, so the boarding end always has her and the
## pans moor visibly holds her between sailings (the boat never
## teleport-returns unseen). After the carry, the DECK WAKE glue: a
## body who stood the sea ticks earns the wake when the boat next
## berths (the same ledger the dock path pays).
func _pans_ferry_tick(per_day: int, first_h: float, cross_h: float) -> void:
	if pans_ferry_vessel == null:
		return
	var Schedule = load("res://core/frame/srv/ferry_schedule.gd")
	var sign_svc := _sign()
	var epoch: float = sign_svc.sky_epoch_days() if sign_svc else \
		float(Time.get_unix_time_from_system()) / 86400.0
	var t: float = Schedule.vessel_t(per_day, first_h, cross_h, epoch)
	FERRY_VESSEL_LAW.place(pans_ferry_vessel, t)
	_wake_credit_deck_riders(t)
	# THE HARBOR LIGHTS: the night law's tick (same epoch, one sky).
	HARBOR_LIGHTS.place_night(pier_beacon, epoch)
	HARBOR_LIGHTS.place_night(moor_guide, epoch)


## THE DECK WAKE (S14.6): the tick glue. Riders standing on the deck
## are marked on every SEA tick (the carry law's roster); the tick
## AFTER a sea tick that lands on a berth credits every marked player
## ONCE through FerryService.record_deck_wake. A pier-standing idle
## between cast-offs never earns (no sea tick preceded); a step-off
## before the berth never earns (never marked at the berthing tick).
## Identity comes from the VEHICLE'S OWN ROUTE DATA (stamped at the
## boot read; the fallback vehicle id is the pans runner's).
const WAKE_FALLBACK_VEHICLE := "veh_pans_ferry"
var _wake_vehicle_id: String = WAKE_FALLBACK_VEHICLE
var _wake_pier_gateway: String = "waypoint_capitol_pier"
var _wake_pans_gateway: String = "waypoint_sun_pans"
var _deck_wake_seen: Dictionary = {}
var _deck_wake_last_t: float = -1.0

func _wake_credit_deck_riders(t: float) -> void:
	var fs = get_node_or_null("/root/FerryService")
	if fs == null or not fs.has_method("record_deck_wake"):
		return
	var sea_before: bool = _deck_wake_last_t > 0.02 and _deck_wake_last_t < 0.98
	if sea_before:
		var end_id: String = _wake_pier_gateway if t <= 0.5 else _wake_pans_gateway
		for id in _deck_wake_seen:
			fs.call("record_deck_wake", str(_deck_wake_seen[id]), _wake_vehicle_id, end_id)
		_deck_wake_seen.clear()
	var at_sea: bool = t > 0.02 and t < 0.98
	if at_sea:
		var roster: Dictionary = pans_ferry_vessel.get_meta("ride_roster") \
			if pans_ferry_vessel.has_meta("ride_roster") else {}
		for id in roster:
			var b: Node = instance_from_id(id)
			if b == null or not is_instance_valid(b):
				continue
			# Players ride as physics bodies; NPC rosters (# carried
			# code-moved Entities) are never credited -- no purse.
			if not (b is CharacterBody3D):
				continue
			var pid = b.get("entity_id")
			if pid == null or str(pid) == "":
				continue
			_deck_wake_seen[id] = str(pid)
	_deck_wake_last_t = t


## THE WAKE WARP (tier 3): the world owns the placement. Only the
## LOCAL body moves (a foreign player id is a warning, never a
## yank); the landing is the destination pin's own spot: the pier
## head's deck top at the pier gateway, the moor bank at the pans
## gateway. World-root-local coords converted through the root's
## global transform -- the floating origin law handled once.
func _execute_wake_warp(player_id: String, vehicle_id: String, gateway_id: String) -> void:
	var logb = get_node_or_null("/root/GameLog")
	if player == null:
		return
	if str(player.entity_id) != str(player_id):
		if logb:
			logb.warn("GlobeWorld: wake warp ignored for non-local body %s" % player_id)
		return
	# The route owns its landing law: the runner's two landings are the
	# capitol pier and the pans moor bank; the barque's are HER OWN two
	# pins (the strait's moor and seaward marks). One wake signal, one
	# vehicle-true landing.
	var local: Vector3 = _barque_wake_landing(gateway_id) \
		if vehicle_id == _barque_vehicle_id else _wake_landing(gateway_id)
	if local == Vector3.INF:
		if logb:
			logb.warn("GlobeWorld: wake warp has no landing for %s" % gateway_id)
		return
	player.global_position = world_root.global_transform * local
	player.velocity = Vector3.ZERO
	if logb:
		logb.info("GlobeWorld: the wake carries %s ashore at %s" % [player_id, gateway_id])


## The landing spot (WORLD-ROOT-LOCAL) for a wake-warp gateway: the
## vessel law's own lane dirs keep both ends one derivation; walk
## height comes from the streamer's single ground law.
func _wake_landing(gateway_id: String) -> Vector3:
	var lane: Array = FERRY_VESSEL_LAW.lane_dirs()
	var dir: Vector3
	var stand_extra: float
	if gateway_id == _wake_pier_gateway:
		dir = lane[0]
		stand_extra = 1.125 + 0.95  # the pier head deck top + body center
	elif gateway_id == _wake_pans_gateway:
		dir = lane[1]
		stand_extra = 0.6 + 0.95    # the moor bank + body center
	else:
		return Vector3.INF
	var walk: float = float(streamer.walk_surface_h(dir.normalized())) if streamer else 0.0
	return dir.normalized() * (planet_radius + walk + stand_extra)


## THE BARQUE'S LANDINGS (the dock-warp tier's second route): the wake
## steps between her two pins. The dir comes from the VESSEL'S OWN
## metas (the lane the hull rides is the lane the sailor lands on --
## never a re-derived bearing), and the body never spawns UNDER the
## sea: the vessel law's own max(walk, sea) clamp keeps the landing at
## or above the water line, drowning takes the body only by its own
## swim, never by a warp.
func _barque_wake_landing(gateway_id: String) -> Vector3:
	if sund_ferry_vessel == null:
		return Vector3.INF
	var lane_a: Vector3 = sund_ferry_vessel.get_meta("lane_a")
	var lane_b: Vector3 = sund_ferry_vessel.get_meta("lane_b")
	var dir: Vector3
	if gateway_id == _barque_pier_gateway:
		dir = lane_a.normalized()
	elif gateway_id == _barque_pans_gateway:
		dir = lane_b.normalized()
	else:
		return Vector3.INF
	var walk: float = float(streamer.walk_surface_h(dir)) if streamer else 0.0
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var sea: float = Gen.sea_level(streamer.world_seed) if streamer else 0.0
	# the moor-bank law's stand (bank + body center) + the sea clamp
	return dir * (planet_radius + maxf(walk, sea) + 0.6 + 0.95)


## THE TOWN ROSTERS (the owner's turn-15 law: "the starter village
## should have all the NPCs; capitol too"). On the PLANAR world the
## spawn_all_offering_npcs path places NPCs from zone bind points;
## on the GLOBE planar coords are meaningless (the underworld's own
## camp-keeper law answers this: the owning globe scene spawns its
## NPCs itself in its own frame). The village four stand around the
## spawn plaza's tangent frame; the capitol two stand in the strand
## frame -- each riding its dir's walk lift + a stall raise.
## Ducks SpawnService like the underworld does (script-mode safe).
const TerrainGenRef = preload("res://scenes/worlds/terrain_gen.gd")
const VILLAGE_NPC_BATCH: Array = [
	# npc_id, bearing_deg (spawn tangent frame), reach_rad
	["npc_village_elder", 200.0, 0.009],
	["npc_blacksmith_village", 44.0, 0.012],
	["npc_merchant_general", -14.0, 0.013],
	["npc_herbalist_village", 20.0, 0.012],
	["npc_banker_village", -60.0, 0.011],
	["npc_skill_academy_village", 160.0, 0.012],
	# The Haven Jeweler (Marsh Piper): the shore's pearl-cutter, the
	# jewelry line's own stall on the plaza arc (the pearl industry
	# learned a face). Bearing 110 keeps an open lane: off the
	# smithy's 44 and the academy's 160, clear sky between stalls.	
	["npc_jeweler_haven", 110.0, 0.012],
	# Old Fenwick, the Haven Tidewright: the shore's plankwright, the
	# fence & plank yard's own stall on the plaza arc. Bearing 135
	# keeps the ring lawful: off the jeweler's 110 and the academy's
	# 160, one open sky-lane between the three.
	["npc_tidewright_fenwick", 135.0, 0.012],
]
const CAPITOL_NPC_BATCH: Array = [
	# npc_id, bearing_deg (capitol strand frame), reach_rad
	["npc_armory_capital", 60.0, 0.005],
	["npc_skill_academy_capital", -120.0, 0.005],
	["npc_black_market_fixer", -30.0, 0.007],
	["npc_banker_capital", 0.0, 0.007],
	["npc_blacksmith_capital", 95.0, 0.006],
	["npc_merchant_capital", 25.0, 0.006],
	["npc_herbalist_capital", -70.0, 0.006],
	["npc_elder_capital", 150.0, 0.006],
	# The Concord Herald: the sink shrine's keeper (village_props
	# CAPITOL_BATCH carries the pillar itself at the same bearing,
	# one step out; the herald stands plaza-side of it).
	["npc_concord_herald", -95.0, 0.006],
]


func _build_town_npcs() -> void:
	var SS = get_node_or_null("/root/SpawnService")
	var DS = get_node_or_null("/root/DataService")
	if SS == null or DS == null or not SS.has_method("spawn_npc_entity"):
		_log_backend("warn", "GlobeWorld: town NPCs idle (SpawnService/DataService absent)")
		return
	for entry in VILLAGE_NPC_BATCH:
		_spawn_town_npc(str(entry[0]), TerrainGenRef.SPAWN_CENTER, \
			float(entry[1]), float(entry[2]), SS, DS, starter_village)
	for entry in CAPITOL_NPC_BATCH:
		_spawn_town_npc(str(entry[0]), TerrainGenRef.capitol_plaza_dir(), \
			float(entry[1]), float(entry[2]), SS, DS, capitol_monolith)
	_log_backend("info", "GlobeWorld: town rosters placed (%d village, %d capitol)" \
		% [VILLAGE_NPC_BATCH.size(), CAPITOL_NPC_BATCH.size()])


## One town NPC at `center`'s tangent bearing `reach` out, riding the
## walk law's lift; reparented under `parent_root` so it folds away
## with the globe (the underworld's reparent law). Zone bookkeeping
## rides the NPCData's own zone_id (quest TALK credit stays lawful).
func _spawn_town_npc(npc_id: String, center: Vector3, bearing_deg: float,
		reach: float, SS, DS, parent_root: Node3D) -> void:
	var npc_data = DS.get_npc(npc_id) if DS.has_method("get_npc") else null
	if npc_data == null:
		_log_backend("warn", "GlobeWorld: %s missing; the beat stays empty" % npc_id)
		return
	var east: Vector3 = Vector3(0, 1, 0).cross(center).normalized()
	var north: Vector3 = center.cross(east).normalized()
	# THE BENCH-CLEAR REACH (the same law starter_village.build carries):
	# the authored reaches are ANGULAR (the planet-scale layout), but a
	# bench/prototype radius collapses them to ~1 m -- 17 solid NPC bodies
	# piled on the spawn and boxed the player in (the globe probe's auto-
	# walk wedged at 6.5 m against a town merchant). Pad every reach out to
	# a scale-free 8 m floor when the radius is a bench; the planet keeps
	# the authored layout (floor 0 above 1000 m).
	var reach_floor: float = maxf(0.0, 8.0 / maxf(planet_radius, 1.0))
	if planet_radius > 1000.0:
		reach_floor = 0.0
	var eff_reach: float = maxf(reach, reach_floor)
	var rad: float = deg_to_rad(bearing_deg)
	var dir: Vector3 = (center + east * (eff_reach * cos(rad)) \
		+ north * (eff_reach * sin(rad))).normalized()
	var surface: Vector3 = dir * (planet_radius + STREAMER_TILE_LIFT \
		+ float(streamer.walk_surface_h(dir)) + 0.4)
	var zone_id: String = str(npc_data.get("zone_id")) if "zone_id" in npc_data else ""
	var entity = SS.spawn_npc_entity(zone_id, surface, npc_data)
	if entity == null:
		return
	# Reparent under the town root (globe content, not persistent
	# world state) -- the underworld's fold-away law.
	if entity.get_parent() != parent_root and entity.get_parent() != null:
		entity.get_parent().remove_child(entity)
		parent_root.add_child(entity)
	entity.global_position = world_root.global_position + surface


## PLANAR-RETIREMENT STEP 2: the globe's wildlife. Places each roster
## enemy on the spawn plaza's tangent frame via the town-NPC walk law
## (bearing + reach out, riding the terrain walk surface), attaches an
## EnemyAI brain (EnemyAI already carries the spherical up/tangent law),
## registers it with EntityService/TargetingManager, and captures a
## GlobeSpawn record so a kill respawns it. Ducks SpawnService (the
## scene owns placement; the town-NPC path does the same).
func _build_globe_enemies() -> void:
	var DS = get_node_or_null("/root/DataService")
	if DS == null or streamer == null:
		_log_backend("warn", "GlobeWorld: wildlife idle (DataService/streamer absent)")
		return
	var es = get_node_or_null("/root/EntityService")
	var tm = get_node_or_null("/root/TargetingManager")
	var center: Vector3 = TerrainGenRef.SPAWN_CENTER
	for entry in GLOBE_ENEMY_BATCH:
		var template_id: String = str(entry[0])
		var surface: Vector3 = _globe_enemy_surface(center, float(entry[1]), float(entry[2]))
		var enemy = _spawn_globe_enemy(template_id, surface, DS, es, tm)
		if enemy == null:
			continue
		var record := GlobeSpawn.new()
		record.template_id = template_id
		record.display_name = str(enemy.display_name)
		record.level = int(enemy.level)
		record.spawn_position = surface
		if enemy.enemy_data != null and "respawn_time" in enemy.enemy_data:
			record.respawn_time = float(enemy.enemy_data.respawn_time)
		record.entity_id = str(enemy.entity_id)
		_globe_spawns.append(record)
	# Death hook via root lookup (bare autoload identifiers fail script-mode
	# compilation, the same reason every other autoload touch here resolves
	# through /root).
	var hub = get_node_or_null("/root/EventHub")
	if hub != null and hub.has_signal("entity_died") \
			and not hub.entity_died.is_connected(_on_globe_enemy_died):
		hub.entity_died.connect(_on_globe_enemy_died)
	_log_backend("info", "GlobeWorld: %d wildlife placed + tracked for respawn" \
		% _globe_spawns.size())


## THE ZONE SPAWN RUNG: load the authored spawn tables and register
## each at its honest anchor. Most zones ride the spawn tangent frame;
## the far landmasses (the Sun Pans atoll, Gull Island) ride their own
## world dir so their bearing/reach frames are true to that place. The
## bridge/sea tables (the Sundered channel) ride the strait centre.
func _load_zone_spawn_tables() -> void:
	var DS = get_node_or_null("/root/DataService")
	if DS == null or not DS.has_method("get_all_spawn_tables"):
		_log_backend("warn", "GlobeWorld: zone spawn rung idle (DataService absent)")
		return
	_zone_spawner = ZoneSpawnerRef.new()
	_zone_spawner.configure(TerrainGenRef.SPAWN_CENTER, planet_radius)
	# Anchor map: a table id -> the world dir its bearing/reach frame
	# rides. Anything unlisted rides the spawn frame (the homeland).
	var anchors: Dictionary = {
		"spawn_sun_pans": TerrainGenRef.sun_pans_dir(),
		"spawn_gull_island": TerrainGenRef.ISLAND_CENTER.normalized(),
		"spawn_sundered_sea": TerrainGenRef.strait_center_dir(),
	}
	var placed: int = 0
	for table in DS.get_all_spawn_tables():
		if table == null:
			continue
		var tid: String = str(table.id)
		var anchor: Vector3 = anchors.get(tid, Vector3.ZERO)
		_zone_spawner.add_table(table, anchor)
		placed += 1
	_log_backend("info", "GlobeWorld: zone spawn rung loaded (%d tables)" % placed)


## THE ZONE SPAWN TICK: reconcile the proximity roster against the
## tracked players' directions and materialise/retire bodies. Runs on a
## throttle (a few times a second), never per frame -- the roster is
## interest, not simulation.
func _tick_zone_spawns(delta: float) -> void:
	if _zone_spawner == null:
		return
	_zone_spawn_accum += delta
	if _zone_spawn_accum < ZONE_SPAWN_TICK_S:
		return
	_zone_spawn_accum = 0.0
	var dirs := _tracked_player_dirs()
	if dirs.is_empty():
		return
	var DS = get_node_or_null("/root/DataService")
	var es = get_node_or_null("/root/EntityService")
	var tm = get_node_or_null("/root/TargetingManager")
	var plan: Dictionary = _zone_spawner.reconcile(dirs)
	for key in plan.get("retire", []):
		_retire_zone_bodies(str(key))
	for rec in plan.get("spawn", []):
		_materialize_zone_entry(rec, DS, es, tm)


## The directions of every player the scene tracks (the local player plus
## any remote bodies under the world root). MMO interest reads them all:
## a region lives because someone is in it.
func _tracked_player_dirs() -> Array:
	var out: Array = []
	if player != null and is_instance_valid(player):
		var pdir: Vector3 = player.global_position - planet_center
		if pdir.length_squared() > 0.000001:
			out.append(pdir.normalized())
	var es = get_node_or_null("/root/EntityService")
	if es != null and es.has_method("get_all_players"):
		for p in es.get_all_players():
			if p == player or p == null or not is_instance_valid(p):
				continue
			var d: Vector3 = p.global_position - planet_center
			if d.length_squared() > 0.000001:
				out.append(d.normalized())
	return out


## Build the bodies for one live spawn entry: `count` enemies scattered
## deterministically around the point (server + every client agree on the
## positions), each tracked for respawn exactly like the boot roster.
func _materialize_zone_entry(rec: Dictionary, DS, es, tm) -> void:
	var key: String = str(rec.get("key", ""))
	if key.is_empty() or _zone_bodies.has(key):
		return
	var template_id: String = str(rec.get("template_id", ""))
	var point: Vector3 = rec.get("position", Vector3.ZERO)
	var count: int = maxi(1, int(rec.get("count", 1)))
	var radius_m: float = float(rec.get("radius_m", 6.0))
	var lvl: int = int(rec.get("level", 0))
	var bodies: Array = []
	for i in range(count):
		var pos: Vector3 = _zone_spawner.body_position(point, key, i, count, radius_m)
		var enemy = _spawn_globe_enemy(template_id, pos, DS, es, tm, lvl)
		if enemy == null:
			continue
		var record := GlobeSpawn.new()
		record.template_id = template_id
		record.display_name = str(enemy.display_name)
		record.level = int(enemy.level)
		record.spawn_position = pos
		if enemy.enemy_data != null and "respawn_time" in enemy.enemy_data:
			record.respawn_time = float(enemy.enemy_data.respawn_time)
		record.entity_id = str(enemy.entity_id)
		_globe_spawns.append(record)
		bodies.append(enemy)
	if not bodies.is_empty():
		_zone_bodies[key] = bodies


## Retire a live entry: free its bodies and drop the respawn records so a
## retire never resurrects into an unloaded region.
func _retire_zone_bodies(key: String) -> void:
	var bodies: Array = _zone_bodies.get(key, [])
	var ids := {}
	for b in bodies:
		if b != null and is_instance_valid(b):
			if "entity_id" in b:
				ids[str(b.entity_id)] = true
			b.queue_free()
	_zone_bodies.erase(key)
	_zone_spawner.forget(key)
	if not ids.is_empty():
		var kept: Array[GlobeSpawn] = []
		for record in _globe_spawns:
			if not ids.has(record.entity_id):
				kept.append(record)
		_globe_spawns = kept


## Auto-accept the Wolf Hunt quest and the Watch-the-sky daily for the
## local player (planar-retirement Step 2, ported from world_playable):
## the kill + insight objective bridges need live quests to credit. The
## player accepts the hunt through the elder in the full flow; the daily
## rides the Concord loop (prd-psy.md section 10).
func _accept_starter_quests() -> void:
	if player == null or not ("entity_id" in player):
		return
	var player_id := str(player.entity_id)
	if player_id.is_empty():
		return
	var qs = get_node_or_null("/root/QuestService")
	if qs == null or not qs.has_method("accept_quest"):
		return
	var active: Array = qs.get_active_quests(player_id) if qs.has_method("get_active_quests") else []
	if not active.has("quest_wolves_hunt"):
		qs.accept_quest(player_id, "quest_wolves_hunt")
	if not active.has("quest_watch_the_sky"):
		qs.accept_quest(player_id, "quest_watch_the_sky")


## The spawn surface for a wildlife entry: the town-NPC walk law
## (bearing + reach on the spawn tangent frame, riding the streamer's
## walk surface). Reach is padded for a bench radius exactly like
## _spawn_town_npc so the planet keeps the authored layout.
func _globe_enemy_surface(center: Vector3, bearing_deg: float, reach: float) -> Vector3:
	var east: Vector3 = Vector3(0, 1, 0).cross(center).normalized()
	var north: Vector3 = center.cross(east).normalized()
	var reach_floor: float = maxf(0.0, 12.0 / maxf(planet_radius, 1.0))
	if planet_radius > 1000.0:
		reach_floor = 0.0
	var eff_reach: float = maxf(reach, reach_floor)
	var rad: float = deg_to_rad(bearing_deg)
	var dir: Vector3 = (center + east * (eff_reach * cos(rad)) \
		+ north * (eff_reach * sin(rad))).normalized()
	var surface: Vector3 = dir * (planet_radius + STREAMER_TILE_LIFT \
		+ float(streamer.walk_surface_h(dir)) + 0.4)
	return surface


## Build one wildlife enemy from its EnemyData template (the same
## configuration spawn_enemy_direct applies, minus the SpawnService
## registration so the scene owns the node + the respawn record).
func _spawn_globe_enemy(template_id: String, surface: Vector3, DS, es, tm, level_override: int = 0):
	var template = DS.get_enemy(template_id) if DS.has_method("get_enemy") else null
	if template == null:
		_log_backend("warn", "GlobeWorld: enemy template '%s' missing; the beat stays empty" % template_id)
		return null
	# Phase 3.2 content-pack gate: a disabled pack's enemy is refused here.
	if not ContentPacks.local_enemy_enabled(template_id):
		_log_backend("info", "GlobeWorld: %s is in a disabled content pack" % template_id)
		return null
	var EnemyScript = load("res://entities/enemy.gd")
	var EnemyAIScript = load("res://core/ai/enemy_ai.gd")
	if EnemyScript == null or EnemyAIScript == null:
		return null
	var enemy = EnemyScript.new()
	enemy.enemy_data = template
	enemy.display_name = template.display_name
	enemy.entity_type = Entity.EntityType.ENEMY
	enemy.relation = Entity.Relation.HOSTILE
	enemy.faction_id = template.faction
	enemy.level = level_override if level_override > 0 else template.level
	# Species modifiers shift stats, so apply before copying them.
	if "species_id" in template and str(template.species_id) != "" and DS.has_method("get_species"):
		var species = DS.get_species(str(template.species_id))
		if species != null:
			enemy.apply_species(species)
	enemy.stats["strength"] = template.strength
	enemy.stats["agility"] = template.agility
	enemy.stats["intelligence"] = template.intelligence
	enemy.stats["vitality"] = template.vitality
	enemy.max_health = template.get_scaled_stat(template.health, enemy.level)
	enemy.current_health = enemy.max_health
	# Pre-applied data: Enemy._ready skips the template reload so the
	# level + scaled stats survive add_child (the direct-spawn law).
	enemy.spawn_data_applied = true
	# Parent under the world root so the enemy rides the floating-origin
	# rebase (world_root.position moves; content under it comes along).
	world_root.add_child(enemy)
	enemy.global_position = world_root.global_position + surface
	# AI configured from the template's ranges; a training dummy keeps its
	# inert stand (attach_ai no-ops on dummies).
	var ai = EnemyAIScript.new()
	ai.aggro_range = template.aggro_range
	ai.chase_range = template.chase_range
	ai.attack_range = template.attack_range
	enemy.attach_ai(ai)
	if es != null and es.has_method("register_entity"):
		var SpawnMetadataScript = load("res://core/events/spawn_metadata.gd")
		var metadata = SpawnMetadataScript.enemy(enemy.display_name, "zone_village_center", \
			enemy.global_position, enemy.level)
		es.register_entity(enemy, metadata)
	if tm != null and tm.has_method("register_targetable"):
		tm.register_targetable(enemy.entity_id, "enemy", enemy, enemy.display_name, \
			enemy.global_position, enemy.entity_type)
	var zm = get_node_or_null("/root/ZoneManager")
	if zm != null and zm.has_method("get_zone") and zm.has_method("entity_enter_zone"):
		var zone = zm.get_zone("zone_village_center")
		if zone:
			zm.entity_enter_zone(enemy, zone)
	return enemy


## A tracked wildlife enemy died: schedule its respawn at the original
## spawn point after EnemyData.respawn_time.
func _on_globe_enemy_died(entity, _killer, _metadata) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var dead_id: String = str(entity.entity_id) if "entity_id" in entity else ""
	for record in _globe_spawns:
		if record.entity_id == dead_id and not record.respawn_pending:
			record.respawn_pending = true
			_respawn_globe_enemy_later(record)
			return


func _respawn_globe_enemy_later(record: GlobeSpawn) -> void:
	var delay: float = maxf(1.0, record.respawn_time)
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func(): _respawn_globe_enemy(record))


## Rebuild one wildlife enemy from its record: fresh node, real data,
## AI brain, fresh registration (the death unregistered the old one).
func _respawn_globe_enemy(record: GlobeSpawn) -> void:
	if not is_inside_tree():
		return
	record.respawn_pending = false
	var DS = get_node_or_null("/root/DataService")
	if DS == null:
		return
	var es = get_node_or_null("/root/EntityService")
	var tm = get_node_or_null("/root/TargetingManager")
	var enemy = _spawn_globe_enemy(record.template_id, record.spawn_position, DS, es, tm)
	if enemy == null:
		return
	# Re-point the record at the new entity so a second kill also respawns.
	record.entity_id = str(enemy.entity_id)
	_log_backend("info", "GlobeWorld: %s respawned at its spawn point" % enemy.display_name)


## Ambience driver (entities/ambience_driver.gd): resolves weather at
## the player every 2s and feeds AudioService.apply_weather. The same
## seam world_playable carries; on the globe the driver reads the
## player's REAL cartesian lat/lon (its own bulb law), so band/season
## weather follows the sphere's cells.
func _setup_ambience() -> void:
	var amb_script: GDScript = load("res://entities/ambience_driver.gd")
	if amb_script == null:
		return
	var amb := Node3D.new()
	amb.name = "AmbienceDriver"
	amb.set_script(amb_script)
	add_child(amb)
	_setup_weather_events()
	var _gl := _glog()
	if _gl:
		_gl.info("GlobeWorld: ambience driver active (the weather sings)")


## WeatherEventService (core/services/weather_event_service.gd): the
## sun-to-sword seam, armed on the globe exactly like world_playable
## arms it. Listens to CosmicService sparks + the weather band and
## stages the world's reaction (stirred packs, aurora mystery
## windows); the ambience driver's band-change push finds this sibling
## by name. Child of the scene so it follows the world's lifecycle.
func _setup_weather_events() -> void:
	var we_script: GDScript = load("res://core/services/weather_event_service.gd")
	if we_script == null:
		return
	var we := Node3D.new()
	we.name = "WeatherEvents"
	we.set_script(we_script)
	add_child(we)


func _build_player() -> void:
	var script: GDScript = load("res://entities/globe_player.gd")
	player = CharacterBody3D.new()
	player.set_script(script)
	player.name = "GlobePlayer"
	# Named bits (round 10): the player rides the entity layer; the mask
	# is world props (solid) + walk surfaces (ground via the pad, solid
	# via PropCollider).
	player.collision_layer = Layers.layer_bit("entity")
	player.collision_mask = Layers.group_mask("entity_solid")

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = PLAYER_SKIN
	col.shape = shape
	player.add_child(col)

	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.6
	mesh.height = 1.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.75, 0.3)
	mesh.material = mat
	mi.mesh = mesh
	mi.position = Vector3(0, 0, 0)
	player.add_child(mi)

	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0, 2.2, 4.5)
	cam.fov = 70.0
	pivot.add_child(cam)
	player.add_child(pivot)

	# Spawn on the equator via the shared spherical convention, on the
	# WALK SURFACE (S8): with streaming the tiles sit TILE_LIFT above
	# the base shell, so spawn height = radius + TILE_LIFT + skin. The
	# same offset feeds the player's snap target and glue check. The
	# player is added to THIS scene (NOT world_root): it is the
	# floating-origin anchor and stays near the world origin.
	# The body's ground_offset is the STATIC tile lift only -- the
	# terrain law arrives through the snap provider (double-counting
	# it here would float the body a terrain-height above the ground).
	# The spawn POSITION does ride the terrain (born on the surface;
	# the frame-1 snap would otherwise teleport it up from inside the
	# hill).
	var static_lift: float = STREAMER_TILE_LIFT
	var spawn_terrain: float = streamer.terrain_h(_spawn_dir()) if streamer else 0.0
	# SEA GUARD (play-test round 6, item 4): the spawn plaza flattens to
	# SPAWN_HEIGHT (9 m) and the sea line tops out at SEA_LEVEL_MIN +
	# SEA_LEVEL_SPAN (7 m), so the boot can never legally land in water.
	# Enforce it here anyway -- a future const drift or seed-rule change
	# must fail LOUD (log + lifted boot) instead of quietly drowning the
	# player ("I spawned on the ocean, green above me").
	var Gen4Spawn = load("res://scenes/worlds/terrain_gen.gd")
	var sea_at_spawn: float = Gen4Spawn.sea_level(streamer.world_seed) if streamer else 0.0
	if spawn_terrain < sea_at_spawn:
		if get_node_or_null("/root/GameLog"):
			get_node_or_null("/root/GameLog").error(
				"GlobeWorld: spawn height %.1f m is BELOW the sea line %.1f m -- lifting the boot onto dry land. Fix the terrain law (SPAWN_HEIGHT vs sea band)." % [spawn_terrain, sea_at_spawn])
		spawn_terrain = sea_at_spawn + 1.0
	# IDENTITY (round 7, item 3): the planar world stamps its player's
	# entity_id before registration; the globe never did, so the body
	# had no id to register a bag under and the starter kit had no
	# owner. Prefer the selected character's id (the account flow's
	# identity), fall back to the planar scene's local id.
	if str(player.entity_id) == "":
		var gm_id = get_node_or_null("/root/GameManager")
		var cd_id = (gm_id.selected_character_data if gm_id != null and "selected_character_data" in gm_id else null)
		if cd_id != null and "character_id" in cd_id and str(cd_id.character_id) != "":
			player.entity_id = str(cd_id.character_id)
		else:
			player.entity_id = "player_1"
	var Sph = load("res://core/frame/math/spherical.gd")
	var spawn: Vector3 = Sph.spherical_to_cartesian(
		SPAWN_LAT_DEG, SPAWN_LON_DEG, PLAYER_SKIN, planet_radius + static_lift + spawn_terrain)
	player.position = spawn
	# Boot truth line (round-6 follow-up): one always-on log so the next
	# play-test report can settle "spawned in the ocean" with the spawn
	# height vs the sea line in black and white. Prototype globes run
	# terrain-off (no water exists there), so say so instead of reading
	# like an underwater boot.
	if get_node_or_null("/root/GameLog"):
		get_node_or_null("/root/GameLog").info(
			"GlobeWorld: boot at lat %.1f lon %.1f, walk surface %.1f m (sea line %.1f m)" % [SPAWN_LAT_DEG, SPAWN_LON_DEG, spawn_terrain, (load("res://scenes/worlds/terrain_gen.gd").sea_level(streamer.world_seed) if streamer else 0.0)])
	player.planet_radius = planet_radius
	player.ground_offset = static_lift
	add_child(player)
	_install_walk_provider()
	# Adopt the sky sun (built before the player existed): the celestial
	# frame is the PLAYER (floating origin -- see _build_sky_sun).
	var sky_sun := get_node_or_null("SkySun")
	if sky_sun != null:
		sky_sun.position = Vector3.ZERO
		sky_sun.get_parent().remove_child(sky_sun)
		player.add_child(sky_sun)
	# Adopt the moon the same way: the pale stone rides the celestial
	# frame next to the sun (the floating-origin law, one frame).
	var sky_moon := get_node_or_null("SkyMoon")
	if sky_moon != null:
		sky_moon.position = Vector3.ZERO
		sky_moon.get_parent().remove_child(sky_moon)
		player.add_child(sky_moon)
	# Adopt the sky signs (the Concord constellation): built before the
	# player existed, so it rides the same celestial frame (Step 1).
	var sky_signs := get_node_or_null("SkySigns")
	if sky_signs != null:
		sky_signs.get_parent().remove_child(sky_signs)
		player.add_child(sky_signs)
	player.begin_loop()
	# WORLD ENTRY (round 7, item 3): world_playable emits
	# player_entered_world so StarterKitService grants the kit; the
	# globe scene never did -- players spawned with an empty bag and
	# the character/eq tabs rendered blank. Same emission, defensively
	# resolved (script-mode probes mount no autoloads).
	_notify_world_entry()


## PLANAR-RETIREMENT STEP 2: register the local globe body with the
## entity + targeting layer, the same wiring world_playable._register_player
## does. Without it EnemyAI's EntityInterest.query_players (which reads
## EntityService.get_entities_in_radius(..., PLAYER)) never sees the body,
## so no enemy can aggro the player and the target frame can't resolve
## them. entity_id is already stamped by _build_player before this runs.
func _register_player() -> void:
	if player == null or not is_instance_valid(player):
		return
	var player_id: String = str(player.entity_id) if "entity_id" in player else ""
	if player_id.is_empty():
		return
	var tm = get_node_or_null("/root/TargetingManager")
	if tm != null:
		if tm.has_method("unregister_targetable"):
			tm.unregister_targetable("")
		if tm.has_method("set_local_player"):
			tm.set_local_player(player_id)
		if tm.has_method("register_targetable"):
			tm.register_targetable(player_id, "player", player, \
				str(player.display_name), player.global_position, player.entity_type)
	var es = get_node_or_null("/root/EntityService")
	if es != null and es.has_method("register_entity"):
		if es.has_method("get_entity_metadata") and es.get_entity_metadata(player_id) == null:
			var SpawnMetadataScript = load("res://core/events/spawn_metadata.gd")
			var metadata = SpawnMetadataScript.new(0, str(player.display_name), \
				"zone_village_center", player.global_position)
			es.register_entity(player, metadata, player_id)
	var zm = get_node_or_null("/root/ZoneManager")
	if zm != null and zm.has_method("get_zone") and zm.has_method("entity_enter_zone"):
		# Direct scene runs skip initialize_world, which is the only boot
		# caller of load_zones -- so the zone table is empty here and the
		# player would boot zone-less (the planar _enter_scene_zone loaded
		# on demand; the globe port dropped that leg). Lazy-load, then enter.
		var zone = zm.get_zone("zone_village_center")
		if zone == null and zm.has_method("load_zones"):
			zm.load_zones()
			zone = zm.get_zone("zone_village_center")
		if zone:
			zm.entity_enter_zone(player, zone)
		else:
			_log_backend("warn", "GlobeWorld: player zone zone_village_center not registered")


## Emit player_entered_world exactly once per boot for the local globe
## player (StarterKitService listens and grants the kit into the bag
## the player just registered -- one frame later, via its own
## _register_bag deferral).
func _notify_world_entry() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm == null or not gm.has_method("notify_player_entered_world"):
		return
	var cd = gm.selected_character_data if "selected_character_data" in gm else null
	var player_id := str(player.entity_id) if player != null and "entity_id" in player else ""
	if player_id.is_empty():
		return
	gm.notify_player_entered_world(player_id, cd)


## Build the on-screen spawn-truth line into the playable HUD (round
## 7, item 4). Terrain globes only: prototype globes run terrain-off
## (no sea exists there), and probes mount no HUD. Silent no-op when
## either is missing.
func _build_spawn_truth() -> void:
	if streamer == null or hud == null:
		return
	var label := Label.new()
	label.name = "SpawnTruthLabel"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.text = ""
	# Top-right, growing leftward: the menu bar owns the top-left and
	# the touch joystick owns the bottom-left.
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	# Round 10: the line grew the mesh-stream tag; widen the box so the
	# extra segment never clips on the right-anchored label.
	label.offset_left = -620.0
	label.offset_right = -12.0
	label.offset_top = 8.0
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(label)
	_truth_label = label
	_update_spawn_truth()


## Refresh the spawn-truth line from the player's live position:
## lat/lon (same convention as the boot log), ground height at the
## player's direction, the sea line, and the MESH STREAM STATE (round
## 10). WET tints the line amber so an ocean report is self-evident
## from a screenshot; mesh:OFF / mesh:fN tell the render half of the
## story -- "dry at 9.0 m" over a rendered ocean is now visible AS a
## render bug on the screenshot itself (the sim-vs-render split).
func _update_spawn_truth() -> void:
	if _truth_label == null or player == null or streamer == null:
		return
	var Sph = load("res://core/frame/math/spherical.gd")
	var dir: Vector3 = (player.global_position - planet_center).normalized()
	var ll: Vector2 = Sph.cartesian_to_spherical(dir * planet_radius, planet_radius)
	var Gen4 = load("res://scenes/worlds/terrain_gen.gd")
	var ground: float = streamer.terrain_h(dir)
	var sea: float = Gen4.sea_level(streamer.world_seed)
	var wet: bool = ground < sea
	var faces: int = streamer.active_faces().size()
	var stream_tag: String = "mesh:OFF"
	if faces > 0:
		stream_tag = "mesh:f%d x%d/%d" % [streamer.current_face, faces, streamer.triangle_count()]
	# ALT: the PLAYER BODY's actual altitude above the base shell. The
	# ground/sea readings are the terrain LAW; ALT is the body. Round-12
	# web question: law said dry but pixels showed ocean -- if ALT ~ 10
	# while the screen is teal, the body never sank and the break is in
	# the draw; if ALT collapsed to ~6 (the sea line), the body sank.
	var alt_m: float = -1.0
	if player != null and is_instance_valid(player):
		alt_m = (player.global_position - planet_center).length() - planet_radius
	var vis: int = streamer.visible_patch_count()
	# Mesh tag FIRST: the right end of this line sits under the minimap
	# on phone/portrait layouts, and the round-10 pack-freshness question
	# ("did the client run the UV-fix pack?") is exactly the tag that got
	# hidden. Leading segment = always on screen.
	# Build stamp (pack-freshness law): CI bakes the packed game content
	# hash into project settings at export time (`git rev-parse --short
	# HEAD` -> config/build/hash); default_project_settings.gsi falls back
	# to "dev" outside CI. A screenshot of this line IS the answer to
	# "is my preview stale?": the PCK content commit reads directly off
	# the running client.
	var content: String = ProjectSettings.get_setting("application/config/build_hash") if ProjectSettings.has_setting("application/config/build_hash") else "dev"
	_truth_label.text = "%s vis%d | ALT %.1f | lat %.2f lon %.2f | ground %.1f m | sea %.1f m | %s | %s" % \
		[stream_tag, vis, alt_m, ll.x, ll.y, ground, sea, "WET" if wet else "dry", content]
	# Feed the full map's player dot (round 13: the map is generated
	# from the terrain law; the gold dot rides the same lat/lon).
	var map := hud.find_child("WorldMap", true, false) if hud != null else null
	if map != null and map.has_method("set_player_lat_lon"):
		map.set_player_lat_lon(ll.x, ll.y)
	_truth_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2, 0.95) if wet else Color(1, 1, 1, 0.85))


## Drive the auto-walk for `seconds` of wall-clock physics, then stop.
func run_walk(seconds: float = WALK_SECONDS) -> void:
	player.auto_walk = true
	player.auto_walk_yaw = 0.0
	var elapsed: float = 0.0
	while elapsed < seconds and is_inside_tree():
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
	player.auto_walk = false


## Distance from the player's body center to the walk surface, above
## planet_radius (probe). Planet-relative: immune to floating-origin
## shifts (the world origin is NOT the planet center after a shift).
func player_surface_error() -> float:
	return player.planet_distance() - (planet_radius + _surface_lift())


## How far the player has walked along the surface (probe).
func player_path_walked() -> float:
	return player.path_walked


## Straight-line displacement since begin_loop (probe).
func player_displacement() -> float:
	return _loop_start_position().distance_to(player.global_position)


## Streamer observability (probe): face ids currently streaming.
func stream_active_faces() -> Array:
	return streamer.active_faces() if streamer else []


## Streamer observability (probe): live triangle count.
func stream_triangle_count() -> int:
	return streamer.triangle_count() if streamer else 0


func _loop_start_position() -> Vector3:
	# begin_loop() recorded it (player script state; dynamic access).
	return player._loop_start
