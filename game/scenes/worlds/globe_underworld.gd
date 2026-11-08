## GlobeUnderworld -- the S15 planet-in-planet (labs/prd-underworld.md).
## A second, smaller globe (radius from world_underworld.tres, 2 km)
## whose SKY is the inner wall of Synmergia: strata glow, root veins,
## the deep dark (entities/interior_sky.gdshader). CONJURED like the
## moon (MoonGate destination at transit), and DEV_ONLY reachable --
## offline stays true for players (the door the underworld does not
## have is the whole mystery).
##
## Differences from the moon globe: has_atmosphere = true (the wing
## works down here -- WorldData law), the sky is the INTERIOR dome
## (the underworld proved the interior-sky trick; prd-multiworld sec
## 3), the glow tides ride the Concord epoch (one clock law -- the
## same SignService day index the ferry schedule and the windows
## read), and the Deep Root lives: a surface camp (S15.3) with a
## zone, an NPC, and a quest through the SAME data pipelines the
## surface uses (DataService, QuestService bridges, naming lint).
##
## The return shaft: a sealed Ascent Gate (S15.4) stands at camp --
## the future player door to Synmergia. Sealed for everyone today
## (no door on the underside either -- The Ascent names the mystery),
## hatched only for dev round-trips.
##
## Tabs, no class_name, ASCII only; autoloads resolved lazily
## (the globe_moon pattern -- this file is its sibling).
extends Node3D

const WORLD_ID: String = "underworld"
const PLAYER_SKIN: float = 1.0
## Glow tide: one cycle per Synmergia day (the surface's dawn is the
## Deep Root's high glow -- a tide, not a second clock).
const GLOW_TIDE_PERIOD_DAYS: float = 1.0

const WorldRegistryScript = preload("res://core/frame/srv/world_registry.gd")
const ResourceScan = preload("res://core/frame/srv/resource_scan.gd")

var world_root: Node3D
var planet_center: Vector3 = Vector3.ZERO
var planet_radius: float = 2000.0
var player  # globe_player body; untyped (set_script pattern)

var _return_gate: Node3D = null
var _ascent_gate: Node3D = null
var _sky_mesh: MeshInstance3D = null
var _sky_mat: ShaderMaterial = null
var _strata_light: DirectionalLight3D = null
var _npc_spawns: Array = []
var _visitors: Dictionary = {}


func _ready() -> void:
	# The underworld's own declaration is the law; never a hard-coded
	# scale (the globe_moon lesson).
	var reg = WorldRegistryScript.new()
	reg.load_worlds()
	var w = reg.get_world(WORLD_ID)
	if w != null:
		planet_radius = float(w.radius_m)
	world_root = Node3D.new()
	world_root.name = "WorldRoot"
	world_root.add_to_group("world_root_" + WORLD_ID)
	add_child(world_root)
	add_to_group("globe_moons")
	planet_center = world_root.position
	_build_shell()
	_build_interior_sky()
	_build_deep_light()
	_build_camp()
	_build_cistern()
	_build_lava_lake()
	_build_trail()
	_build_wilds()
	_build_ascent_gate()
	_build_return_gate()
	GameLog.info("GlobeUnderworld: conjured (the Deep Root; radius %.0f m, the strata remember the sun)" % planet_radius)


## Bring a visitor across (MoonGate -> receive_visitor, the moon
## pattern). Adopts the body into underworld physics and places it at
## camp. Idempotent per body.
func receive_visitor(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	var pid: String = str(body.get("entity_id"))
	if pid != "" and not _visitors.has(pid):
		_visitors[pid] = body
		_track_visitor(body)
	if body.has_method("bind_to_world"):
		body.bind_to_world(WORLD_ID)
	if "world_id" in body:
		body.set("world_id", WORLD_ID)
	if "planet_center" in body:
		body.set("planet_center", planet_center)
	if "planet_radius" in body:
		body.set("planet_radius", planet_radius)
	# Land at the camp head (world_root local coords; the camp is the
	# arrival hall of the Deep Root).
	body.global_position = world_root.global_position + CAMP_HEAD_POS + Vector3(0, PLAYER_SKIN + 0.4, 0)
	if "velocity" in body:
		body.set("velocity", Vector3.ZERO)
	_credit_arrival(body)


## The last visitor leaving tears the globe down: the Deep Root also
## exists while it is watched (same derivation law as the moon).
func release_visitor(body: Node) -> void:
	if body == null:
		return
	var pid: String = str(body.get("entity_id"))
	if pid != "":
		_visitors.erase(pid)
		var ocean = get_node_or_null("/root/OceanService")
		if ocean != null:
			ocean.forget_swimmer(pid)
	if _visitors.is_empty():
		GameLog.info("GlobeUnderworld: last visitor gone -- the Deep Root folds back into derivation")
		queue_free()


func _track_visitor(body: Node) -> void:
	if not body.has_signal("tree_exiting"):
		return
	if body.is_connected("tree_exiting", _on_visitor_leaving):
		return
	body.tree_exiting.connect(_on_visitor_leaving.bind(body))


func _on_visitor_leaving(body: Node) -> void:
	release_visitor(body)


## The stone shell: dark basalt, friction-true, collider ON (2 km is
## far below the planar-shell stall threshold -- the sphere collider
## IS the physics truth, the moon pattern).
func _build_shell() -> void:
	var shell := StaticBody3D.new()
	shell.name = "DeepShell"
	shell.physics_material_override = PhysicsMaterial.new()
	shell.physics_material_override.friction = 1.0
	shell.physics_material_override.bounce = 0.0
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = planet_radius
	col.shape = sphere
	shell.add_child(col)
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = planet_radius + 0.5
	mesh.height = (planet_radius + 0.5) * 2.0
	mesh.radial_segments = 96
	mesh.rings = 48
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.08, 0.1)
	mat.roughness = 1.0
	mesh.material = mat
	mi.mesh = mesh
	shell.add_child(mi)
	world_root.add_child(shell)


## THE INTERIOR SKY (S15.1, the underworld's one new primitive): an
## inverted dome hung INSIDE the shell, its material the inner wall
## of Synmergia. Glow tides ride the Concord epoch -- one clock.
func _build_interior_sky() -> void:
	var dome := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	# The dome hangs above the walk surface (radius + shell skin +
	# headroom) and renders its INSIDE (cull_front in the shader).
	mesh.radius = planet_radius + 12.0
	mesh.height = (planet_radius + 12.0) * 2.0
	mesh.radial_segments = 64
	mesh.rings = 32
	dome.mesh = mesh
	var shader: Shader = load("res://entities/interior_sky.gdshader")
	if shader != null:
		_sky_mat = ShaderMaterial.new()
		_sky_mat.shader = shader
		dome.material_override = _sky_mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(dome)
	_sky_mesh = dome


func _process(_delta: float) -> void:
	# The glow tide: one closed-form evaluation per frame off the
	# Concord epoch (the almanac / Moon Gate clock). Pure function of
	# (epoch) -- no accumulation, no drift, no second clock.
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("tide_phase", _glow_tide_phase())
	## The strata light breathes with the same tide (the only sun the
	## Deep Root has ever had is the glow of the world around it).
	if _strata_light != null:
		var e := 0.35 + 0.25 * _glow_tide_phase()
		_strata_light.light_energy = e
	## The cistern rides the same tide: the pool drinks at dawn, and the
	## stone's glow veins brighten with it (the dusk-read law: in a
	## world whose noon is a dark shelf, the shape must carry its own
	## light or it disappears at the low part of the tide).
	if _cistern_water_mat != null:
		var tide := cistern_glow(_glow_tide_phase())
		_cistern_water_mat.emission_energy_multiplier = tide
	if _cistern_stone_mat != null:
		_cistern_stone_mat.emission_energy_multiplier = 0.18 * cistern_glow(_glow_tide_phase())
	## The lava lake burns with its own steady pulse riding the same
	## tide (the underworld's one clock, honest: the melt licks
	## brightest at the crest, surliest at the low tide).
	if _lava_mat != null:
		_lava_mat.emission_energy_multiplier = 1.1 + 0.4 * cistern_glow(_glow_tide_phase())
	## THE WEATHER LAW: the strata mist density is the same closed
	## form, read per frame (no accumulation, no drift).
	if _world_env != null:
		_world_env.fog_density = weather_mist(_glow_tide_phase())
	## THE SWIM DELIVERY (the cistern's law, live): bodies the underworld
	## hosts tick through OceanService so the pool's water is REAL -- the
	## breath clock, the bands, and the water_entered credit signal
	## (QuestService's swim bridge reads it for the Warden's quest).
	## Positions are world_root-local (the volume data's planet truth).
	if not _visitors.is_empty():
		var ocean = get_node_or_null("/root/OceanService")
		var thermo = get_node_or_null("/root/ThermalService")
		if ocean != null:
			for pid in _visitors:
				var body = _visitors[pid]
				if body == null or not is_instance_valid(body):
					continue
				var local: Vector3 = body.global_position - world_root.global_position
				var r: Dictionary = ocean.tick_swimmer(str(pid), local, _delta)
				# THE BURN LAW: a lava volume bites in WHOLE digits. The
				# accrual pool rounds the dirty float flow so a body dips
				# for damage honestly and leaves for free.
				var burn: float = float(r.get("burn_dps", 0.0))
				if burn > 0.0 and int(r.get("band", 0)) != 0:  # band 0 = DRY
					var owe: float = float(_burn_pool.get(pid, 0.0)) + burn * _delta
					if owe >= 1.0:
						var hit := int(floorf(owe))
						if body.has_method("take_damage"):
							body.take_damage(hit, null, "burn")
						owe -= float(hit)
					# The debt BOOKS every frame (a fractional owe must
					# survive across frames or the melt never draws its
					# blood -- the one-frame reset bug the probe caught).
					_burn_pool[pid] = owe
				# THE CURRENT DRIFT: declared lava currents push the body
				# a gentle half-strength while it stands IN the liquid
				# (the ford pull law, water-frame flavor).
				var drift: Vector3 = r.get("current", Vector3.ZERO)
				if drift.length_squared() > 0.00001 and "velocity" in body:
					body.velocity += drift * _delta * 0.5
				# THE AIRFLOW LAW: the underworld answers the updraft books
				# -- vents carry; the Ascent thrower HURLS (the launch
				# ticket rides the same sample so a throw is never a hack).
				if thermo != null:
					var lift: float = float(thermo.sample(local, str(pid)))
					if lift > 0.0 and "velocity" in body:
						body.velocity.y += lift * _delta
						thermo.record_glide_tick(str(pid), 0.0, \
							local.y - _wilds_surface())


## THE STRATA MIST (the underworld's weather law): warm fog density
## as a pure closed form of the tide -- thick as the wall rests,
## a whisper when the glow crest floods in. static so probes read the
## band without booting the globe.
static func weather_mist(phase: float) -> float:
	var tide_norm: float = (cistern_glow(phase) - cistern_glow(0.5)) \
		/ (cistern_glow(0.0) - cistern_glow(0.5))
	return clampf(0.055 - 0.035 * tide_norm, 0.02, 0.055)


## Glow tide phase in [0, 1): one cycle per Synmergia day, phase 0 at
## the surface dawn (the sky code the Ancient Door reads is the same
## number the strata glow follows -- the Concord keeps one truth).
func _glow_tide_phase() -> float:
	return fposmod(_epoch_days() / GLOW_TIDE_PERIOD_DAYS, 1.0)


## Dim warm key light so the camp reads without depending on shader
## emission alone (web safety: forward_plus emission is cheap, but a
## light is the honest floor on any renderer).
func _build_deep_light() -> void:
	_strata_light = DirectionalLight3D.new()
	_strata_light.rotation_degrees = Vector3(-35.0, 20.0, 0.0)
	_strata_light.light_color = Color(1.0, 0.72, 0.45)
	_strata_light.light_energy = 0.5
	_strata_light.shadow_enabled = false
	add_child(_strata_light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.012, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.2, 0.16)
	e.ambient_light_energy = 0.5
	# THE STRATA MIST (the underworld's weather): warm fog that rides
	# the glow tide -- the wall rests, the mist thickens (the law in
	# _weather_mist). One clock, no second timer.
	e.fog_enabled = true
	e.fog_light_color = Color(0.35, 0.2, 0.14)
	e.fog_density = weather_mist(0.0)
	e.fog_sky_affect = 0.0
	add_child(env)
	env.environment = e
	_world_env = e


## The Deep Root camp (S15.3): a strata-lit shelf with a hearth, the
## keeper, and the shaft-head. Coordinates are world_root-local (the
## globe is conjured at origin, so local == planet-relative).

const CAMP_HEAD_POS: Vector3 = Vector3(0, 2000.0, 0)
const GLOW_SHARD_COUNT: int = 14

var _cistern_water_mat: StandardMaterial3D = null
var _cistern_stone_mat: StandardMaterial3D = null
var _lava_mat: StandardMaterial3D = null
var _world_env: Environment = null
## Books for the underworld's live chemistry: burn pools (body -> the
## floating accrual a lava dip pays out in whole damage ticks) and
## the loaded biome-band declarations (resource id -> BiomeBand).
var _burn_pool: Dictionary = {}
var _bands: Dictionary = {}

# THE DUSK-READ PALETTE (the cistern stone law): one shared vein-lit
# wall material builds the whole ring (the glow law rides it per
# frame), the slab is the darker basin rock, and the BENCH is the
# one brightest stone -- the exit reads as an exit, not as another
# block in the dark.
const STONE_WALL_ALBEDO: Color = Color(0.17, 0.15, 0.19)
const STONE_WALL_VEINS: Color = Color(0.35, 0.8, 0.55)
const STONE_SLAB_ALBEDO: Color = Color(0.12, 0.11, 0.14)
const STONE_BENCH_ALBEDO: Color = Color(0.3, 0.27, 0.33)


## THE GLOW CISTERN (S15.5): the catch-dish at the camp shelf -- the
## "pool gets the glow" beat. Water is DATA (the ocean_ id law): the
## physics body lives in data/oceans/ocean_deep_root_pool.tres (a
## LOCAL pool declaration; a dished pool near a globe's surface is
## not radial-from-planet-center truth), and this function only builds
## the STONE the dish holds:
##
##   slab  -- the basin bottom ON the walk line (the dish's rock)
##   ring  -- 7 tall wall arcs (top 3.2 m up, no fence-hop out)
##   bench -- the sheave bench on the rim's low side, topping 0.3 m
##            over the water: the one honest way out (a hop from the
##            pool clears it; no climb mesh, no glitch exit).


### One vein-lit stone material (the dusk-read pass): dark basalt whose
## glow veins ride the tide. The bench keeps its own brighter albedo
## (the exit reads as an exit) -- the wall/ring material is created by
## _build_cistern and stored on _cistern_stone_mat.
## Build all the cistern stone. Piece seats are planet-relative X/Z
## (12 m from the camp head) with ABSOLUTE local Y (world_root local
## == planet coords for a globe conjured at origin), so data law
## (surface 2002.4 / floor 2000.0) and stone land on the same numbers.
func _build_cistern() -> void:
	var jug := Node3D.new()
	jug.name = "GlowCistern"
	world_root.add_child(jug)
	var seat_xz: Vector3 = Vector3(12.0, 0.0, 0.0)
	var floor_top: float = planet_radius		# slab top == the walk line
	var water_y: float = floor_top + 2.4		# the cistern's 2.4 m jug (the data law)
	var rim_top: float = floor_top + 3.2			# walls tower 3.2 m: no fence-hop out
	var ledge_top: float = water_y + 0.3			# the sheave bench tops 0.3 over the water
	var inner_r: float = 3.4						# the dish's interior radius
	var ring_r: float = inner_r + 0.4				# wall mid-radius (0.8 band)
	# THE SHARED VEIN WALL: one vein-lit material for the whole ring --
	# the glow law feeds it per frame. Local var so the global mat var
	# is only assigned once and freed with the globe.
	var wall_mat := _cistern_wall_material()
	_cistern_stone_mat = wall_mat		# the _process glow rider reads it
	# --- the basin slab (the dish's bottom: standable stone) ---
	var slab := MeshInstance3D.new()
	var slab_mesh := CylinderMesh.new()
	slab_mesh.top_radius = inner_r
	slab_mesh.bottom_radius = inner_r + 0.4
	slab_mesh.height = 0.4
	slab.mesh = slab_mesh
	slab.name = "CisternSlab"
	slab.position = seat_xz + Vector3(0, floor_top - 0.2, 0)
	slab_mesh.material = _cistern_slab_material()
	_cistern_piece(jug, slab)
	# --- the ring: 8 seats, 7 tall walls + 1 low sheave bench ---
	var wall_len: float = TAU * ring_r / 8.0 + 0.12
	var wall_h: float = rim_top - floor_top + 0.4
	var ledge_h: float = ledge_top - floor_top + 0.2
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var piece := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		# X is the radial band (0.8 wide: faces at 3.4/4.2); Z the
		# tangent seat; rotation -a turns each seat to its arc.
		if i != 0:
			mesh.size = Vector3(0.8, wall_h, wall_len)
			piece.position = seat_xz + Vector3(cos(a) * ring_r, floor_top + wall_h / 2.0 - 0.2, sin(a) * ring_r)
			piece.name = "CisternWall_%d" % i
			mesh.material = wall_mat
		else:
			mesh.size = Vector3(0.8, ledge_h, wall_len)
			piece.position = seat_xz + Vector3(cos(a) * ring_r, floor_top + ledge_h / 2.0 - 0.2, sin(a) * ring_r)
			piece.name = "CisternBench"
			# THE BENCH: the one bright stone (the exit reads as an
			# exit -- a still-dark bench hides in the glow's cast).
			var bench_mat := _cistern_bench_material()
			mesh.material = bench_mat
		piece.mesh = mesh
		piece.rotation.y = -a
		_cistern_piece(jug, piece)
	# --- the glow-water disc: one translucent shell, physics in DATA ---
	var water := MeshInstance3D.new()
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = inner_r
	water_mesh.bottom_radius = inner_r
	water_mesh.height = 0.3
	water.mesh = water_mesh
	water.name = "CisternWater"
	water.position = seat_xz + Vector3(0, water_y, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wmat := StandardMaterial3D.new()
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.albedo_color = Color(0.16, 0.42, 0.44, 0.66)
	wmat.roughness = 0.15
	wmat.emission_enabled = true
	wmat.emission = Color(0.3, 0.85, 0.6)
	wmat.emission_energy_multiplier = cistern_glow(_glow_tide_phase())
	water_mesh.material = wmat
	_cistern_water_mat = wmat
	# NO collider on the water: the swim law reads the OceanVolume, the
	# disc is only the renderer's paint (one ground truth law).
	jug.add_child(water)
	GameLog.info("GlobeUnderworld: the Glow Cistern caught tide at %.1f m (the pool gets the glow)" % water_y)


## Piece-collider wrapper: every cistern stone joints the attach law.
func _cistern_piece(jug: Node3D, stone: MeshInstance3D) -> void:
	jug.add_child(stone)
	PropCollider.attach(stone)


# ---- THE DEEP WILDS (S15.6, the underworld's first biome law) -------
# Five bands walk outward from the camp shelf, each its own scatter
# family: crags (the ring ridge), dead trees (the grove), mycelium
# (the glow field), stalagmites (the spike runs), odd grasses (the
# dark meadow). Every position is a PURE function of its index (a
# golden-ratio spindle, the same discipline the camp shards use):
# no seed, no RNG, so the Deep Root re-derives byte-identical.
#
# THE BAND LAW (biome data): the five bands are DECLARATIONS in
# data/biomes/ (BiomeBand schema, world_id underworld) -- the
# builders read count/radii/palette/colliders from the data and only
# fall back to these literals when a declaration is missing. Changes
# to the wilds are data edits, never code edits.
#
# Collider law: stones stand (PropCollider), grass and mycelium do
# not (the walk-over law) -- a ballroom of colliders in the dark is
# how you lose a player.
const WILDS_INNER_M: float = 16.0
const WILDS_OUTER_M: float = 70.0
const STONE_VEINS: Color = Color(0.35, 0.8, 0.55)

## THE LAKE SEAT: the Underglow Lake sits southeast of the cistern.
const LAVA_LAKE_SEAT: Vector3 = Vector3(-26, 0, 20)

## The wilds seat in world_root-local planet coords: the walk line.
func _wilds_surface() -> float:
	return planet_radius


## Deterministic scramble in [0, 1): pure arithmetic on the index
## (the spindle discipline: same input, same drift, every boot).
static func _wilds_drift(i: int, salt: float) -> float:
	return fposmod(sin(float(i) * 12.9898 + salt * 78.233) * 43758.5453, 1.0)


func _build_wilds() -> void:
	var wilds := Node3D.new()
	wilds.name = "DeepWilds"
	world_root.add_child(wilds)
	var ground: float = _wilds_surface()
	_build_crag_ring(wilds, ground)
	_build_dead_grove(wilds, ground)
	_build_mycelium_field(wilds, ground)
	_build_stalagmite_runs(wilds, ground)
	_build_odd_grasses(wilds, ground)
	GameLog.info("GlobeUnderworld: the Deep Wilds dress the shelf (%d bands, deterministic)" % _wire_bands().size())


## THE BAND BOOK (data law, the biome_band schema): loads
## data/biomes/*.tres and keeps only this world's declarations.
## Idempotent; the family builders read count/radii/palette from it
## and fall back to literals when a declaration is missing.
func _wire_bands() -> Dictionary:
	if not _bands.is_empty():
		return _bands
	# Property-contract check rather than an `is BandScript` type test:
	# a runtime-loaded schema variable cannot serve as a type (the
	# script-mode lesson), and the declaration's own fields are the
	# contract the builders already depend on.
	for p in ResourceScan.list_resources("res://data/biomes"):
		var b: Resource = load(p)
		if b == null or not ("world_id" in b) or not ("family" in b):
			continue
		if str(b.world_id) != WORLD_ID:
			continue
		_bands[str(b.id)] = b
	return _bands


## The band the family builder reads (null-safe; a missing .tres
## falls back to the builder's literals -- no silent degenerate).
func _band(id: String):
	return _wire_bands().get(id)


## Band palette resolves: null band (missing declaration) keeps the
## literal the builder names.
func _band_dark(band, fallback: Color) -> Color:
	return band.palette_dark if band != null else fallback


func _band_accent(band, fallback: Color) -> Color:
	return band.palette_accent if band != null else fallback


func _band_emission(band, fallback: Color) -> Color:
	return band.palette_emission if band != null else fallback


func _band_energy(band, fallback: float) -> float:
	return float(band.emission_energy) if band != null else fallback


## The band's seat radius: a pure spindle drift lerped across the
## declaration's span (one input, one truth, re-derived identical).
static func _band_span(drift: float, inner: float, outer: float) -> float:
	return inner + (outer - inner) * drift


## THE CRAG RING: big dark rock prisms leaning against the glow. The
## band declaration (biome_underworld_crag_ring) owns the count,
## span, palette, and keeps-clear; the apron law says a crag never
## walls the arrival in.
func _build_crag_ring(wilds: Node3D, ground: float) -> void:
	var band = _band("biome_underworld_crag_ring")
	var crag_mat := StandardMaterial3D.new()
	crag_mat.albedo_color = _band_dark(band, Color(0.14, 0.12, 0.16))
	crag_mat.roughness = 1.0
	var vein_mat := StandardMaterial3D.new()
	vein_mat.albedo_color = _band_accent(band, Color(0.2, 0.18, 0.23))
	vein_mat.emission_enabled = true
	vein_mat.emission = _band_emission(band, STONE_VEINS)
	vein_mat.emission_energy_multiplier = _band_energy(band, 0.5)
	var total: int = 12 if band == null else band.seat_count()
	var inner: float = 22.0 if band == null else band.radius_inner_m
	var outer: float = 34.0 if band == null else band.radius_outer_m
	var phase: float = 0.27 if band == null else band.angular_offset
	var apron: float = 6.0 if band == null else maxf(band.clearance_m, 0.01)
	for i in range(total):
		var a: float = TAU * float(i) / float(total) + phase
		var rad: float = _band_span(_wilds_drift(i, 1.0), inner, outer)
		var seat := CAMP_HEAD_POS + Vector3(cos(a) * rad, 0.0, sin(a) * rad)
		# The two gates and the cistern keep their aprons clear.
		if seat.distance_to(CAMP_HEAD_POS + Vector3(4.0, 0.0, 4.0)) < apron \
				or seat.distance_to(CAMP_HEAD_POS + Vector3(-4.0, 0.0, 4.0)) < apron \
				or (Vector3(seat.x, 0.0, seat.z) - Vector3(12.0, 0.0, 0.0)).length() < 8.0:
			continue
		var crag := MeshInstance3D.new()
		var prism := PrismMesh.new()
		var h: float = 3.0 + 4.0 * _wilds_drift(i, 2.0)
		prism.size = Vector3(2.0 + 2.0 * _wilds_drift(i, 3.0), h, 2.0 + 2.0 * _wilds_drift(i, 4.0))
		prism.material = vein_mat if i % 3 == 0 else crag_mat
		crag.mesh = prism
		crag.name = "DeepCrag_%d" % i
		crag.position = seat + Vector3(0, ground - 0.4 + h * 0.35, 0)
		crag.rotation = Vector3(0.08 * _wilds_drift(i, 5.0) - 0.04, a, 0.06 * _wilds_drift(i, 6.0) - 0.03)
		wilds.add_child(crag)
		PropCollider.attach(crag)


## THE DEAD GROVE: charcoal trunks and bare branch forks -- the band
## declaration owns the count, span, palette, and the fork count.
func _build_dead_grove(wilds: Node3D, ground: float) -> void:
	var band = _band("biome_underworld_dead_grove")
	var bark_mat := StandardMaterial3D.new()
	bark_mat.albedo_color = _band_dark(band, Color(0.16, 0.13, 0.11))
	bark_mat.roughness = 1.0
	var total: int = 7 if band == null else band.seat_count()
	var forks: int = 2 if band == null else maxi(band.sub_count, 0)
	var inner: float = 34.0 if band == null else band.radius_inner_m
	var outer: float = 48.0 if band == null else band.radius_outer_m
	var phase: float = 2.1 if band == null else band.angular_offset
	for i in range(total):
		var a: float = TAU * float(i) / float(total) + phase
		var rad: float = _band_span(_wilds_drift(i, 11.0), inner, outer)
		var seat := CAMP_HEAD_POS + Vector3(cos(a) * rad, 0.0, sin(a) * rad)
		var h: float = 5.0 + 3.0 * _wilds_drift(i, 12.0)
		var trunk := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.18
		cyl.bottom_radius = 0.42
		cyl.height = h
		cyl.material = bark_mat
		trunk.mesh = cyl
		trunk.name = "DeadTrunk_%d" % i
		trunk.position = seat + Vector3(0, ground + h * 0.5, 0)
		trunk.rotation = Vector3(0.05 * _wilds_drift(i, 13.0) - 0.025, a, 0.09 * _wilds_drift(i, 14.0) - 0.045)
		wilds.add_child(trunk)
		PropCollider.attach(trunk)
		#a bare fork per sub_count: thin boxes splintering off the crown.
		for f in range(forks):
			var fork := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.12, 1.6 + 0.8 * _wilds_drift(i, 15.0 + float(f)), 0.12)
			bm.material = bark_mat
			fork.mesh = bm
			fork.position = trunk.position + Vector3(0.3 * (f + 1), h * 0.42, 0.25 * (f + 1))
			fork.rotation = Vector3(0.5 - 0.25 * f, a + 0.7 * f, -0.4 + 0.3 * f)
			wilds.add_child(fork)


## THE MYCELIUM FIELD: low glow caps pooled between the crags -- the
## band declaration owns count, span, palette, and the cap count per
## seat. Walk-over paint: the caps never block a boot.
func _build_mycelium_field(wilds: Node3D, ground: float) -> void:
	var band = _band("biome_underworld_mycelium_field")
	var base: Color = _band_dark(band, Color(0.45, 0.6, 0.5))
	base.a = 0.85
	var cap_mat := StandardMaterial3D.new()
	cap_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cap_mat.albedo_color = base
	cap_mat.emission_enabled = true
	cap_mat.emission = _band_emission(band, Color(0.25, 0.75, 0.65))
	cap_mat.emission_energy_multiplier = _band_energy(band, 0.8)
	var total: int = 9 if band == null else band.seat_count()
	var caps: int = 3 if band == null else maxi(band.sub_count, 1)
	var inner: float = 22.0 if band == null else band.radius_inner_m
	var outer: float = 62.0 if band == null else band.radius_outer_m
	var phase: float = 0.9 if band == null else band.angular_offset
	for i in range(total):
		var a: float = TAU * float(i) / float(total) + phase
		var rad: float = _band_span(_wilds_drift(i, 21.0), inner, outer)
		var seat := CAMP_HEAD_POS + Vector3(cos(a) * rad, 0.0, sin(a) * rad)
		var host := Node3D.new()
		host.name = "MyceliumClump_%d" % i
		host.position = seat
		wilds.add_child(host)
		for c in range(caps):
			var cap := MeshInstance3D.new()
			var dome := SphereMesh.new()
			dome.radius = 0.35 + 0.3 * _wilds_drift(i * 4 + c, 22.0)
			dome.height = dome.radius * 0.7
			dome.material = cap_mat
			cap.mesh = dome
			var offset := Vector3(1.6 * _wilds_drift(i * 7 + c, 23.0) - 0.8, 0.0, 1.6 * _wilds_drift(i * 9 + c, 24.0) - 0.8)
			cap.position = offset + Vector3(0, ground + dome.height * 0.35, 0)
			cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			host.add_child(cap)


## THE STALAGMITE RUNS: pale stone spikes growing where the shell
## sweats -- the band declaration owns count, span, palette; each
## spike is a wall you climb (PropCollider), never a shrub you push.
func _build_stalagmite_runs(wilds: Node3D, ground: float) -> void:
	var band = _band("biome_underworld_stalagmite_runs")
	var spike_mat := StandardMaterial3D.new()
	spike_mat.albedo_color = _band_dark(band, Color(0.5, 0.48, 0.45))
	spike_mat.roughness = 0.8
	var total: int = 14 if band == null else band.seat_count()
	var inner: float = 18.0 if band == null else band.radius_inner_m
	var outer: float = 64.0 if band == null else band.radius_outer_m
	var phase: float = 1.57 if band == null else band.angular_offset
	for i in range(total):
		var a: float = TAU * float(i) / float(total) + phase
		var rad: float = _band_span(_wilds_drift(i, 31.0), inner, outer)
		var seat := CAMP_HEAD_POS + Vector3(cos(a) * rad, 0.0, sin(a) * rad)
		var h: float = 0.9 + 2.2 * _wilds_drift(i, 32.0)
		var spike := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.7 + 0.3 * _wilds_drift(i, 33.0), h, 0.7 + 0.3 * _wilds_drift(i, 34.0))
		prism.material = spike_mat
		spike.mesh = prism
		spike.name = "Stalagmite_%d" % i
		# A stalagmite grows UP: the prism's point is down, so the
		# spike body rides pi on X (the point becomes the base).
		spike.position = seat + Vector3(0, ground + h * 0.5 - h * 0.33, 0)
		spike.rotation = Vector3(PI, 0.0, 0.0)
		wilds.add_child(spike)
		PropCollider.attach(spike)


## THE ODD GRASSES: thin luminous blades across every band (the dark
## meadow, the band declaration owns count, span, palette, and blade
## count per tuft). Paint only: grass never blocks a foot.
func _build_odd_grasses(wilds: Node3D, ground: float) -> void:
	var band = _band("biome_underworld_odd_grasses")
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = _band_dark(band, Color(0.4, 0.62, 0.42))
	blade_mat.emission_enabled = true
	blade_mat.emission = _band_emission(band, Color(0.35, 0.8, 0.55))
	blade_mat.emission_energy_multiplier = _band_energy(band, 0.7)
	var total: int = 36 if band == null else band.seat_count()
	var blades: int = 3 if band == null else maxi(band.sub_count, 1)
	var inner: float = WILDS_INNER_M if band == null else band.radius_inner_m
	var outer: float = WILDS_OUTER_M if band == null else band.radius_outer_m
	var phase: float = 0.13 if band == null else band.angular_offset
	for i in range(total):
		var a: float = TAU * float(i) / float(total) + phase
		var rad: float = _band_span(_wilds_drift(i, 41.0), inner, outer)
		var seat := CAMP_HEAD_POS + Vector3(cos(a) * rad, 0.0, sin(a) * rad)
		var tuft := Node3D.new()
		tuft.name = "WildGrass_%d" % i
		tuft.position = seat
		wilds.add_child(tuft)
		for b in range(blades):
			var blade := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.05, 0.4 + 0.5 * _wilds_drift(i * 3 + b, 42.0), 0.05)
			bm.material = blade_mat
			blade.mesh = bm
			blade.position = Vector3(0.22 * _wilds_drift(i * 5 + b, 43.0) - 0.11, ground + bm.size.y * 0.5, 0.22 * _wilds_drift(i * 11 + b, 44.0) - 0.11)
			blade.rotation = Vector3(0.6 * _wilds_drift(i * 13 + b, 45.0) - 0.3, 2.0, 0.6 * _wilds_drift(i * 17 + b, 46.0) - 0.3)
			blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tuft.add_child(blade)


## THE VEIN WALL material (the dusk-read pass): dark basalt carrying
## faint glow veins whose energy rides the tide per frame (see
## _process). One shared instance: the ring looks like ONE built wall,
## and the rider touches one material.
func _cistern_wall_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = STONE_WALL_ALBEDO
	m.roughness = 0.95
	m.emission_enabled = true
	m.emission = STONE_WALL_VEINS
	m.emission_energy_multiplier = 0.18 * cistern_glow(_glow_tide_phase())
	return m


## The basin slab: darker rock (the dish reads as carved-in, the pool
## seen THROUGH its rim), a whisper of the veins so it never goes
## flat black at the low tide.
func _cistern_slab_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = STONE_SLAB_ALBEDO
	m.roughness = 1.0
	m.emission_enabled = true
	m.emission = STONE_WALL_VEINS
	m.emission_energy_multiplier = 0.05
	return m


## The sheave bench: the brightest stone, with a faint warm ember
## light (WAYFINDING law: the one honest exit says so aloud -- the
## cistern has no other opening worth a jump). Way out bench emission
## is static: it is a place, not a clock.
func _cistern_bench_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = STONE_BENCH_ALBEDO
	m.roughness = 0.85
	m.emission_enabled = true
	m.emission = Color(0.9, 0.7, 0.4)
	m.emission_energy_multiplier = 0.25
	return m


## THE GLOW LAW (one number, one truth): the water's emission energy
## is a pure function of the tide phase -- high at the surface dawn
## (phase 0), dimmest a half-day later (phase 0.5). Static so
## probes read the law without booting the globe.
static func cistern_glow(phase: float) -> float:
	return 0.45 + 0.55 * (0.5 + 0.5 * cos(TAU * phase))



func _build_camp() -> void:
	# The camp shelf: a small glowing basalt platform at the arrival
	# head (local y = planet_radius -- ON the walk surface).
	var pad := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 7.0
	cyl.bottom_radius = 8.0
	cyl.height = 1.2
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.12, 0.1, 0.12)
	pad_mat.emission_enabled = true
	pad_mat.emission = Color(0.5, 0.3, 0.15)
	pad_mat.emission_energy_multiplier = 0.25
	cyl.material = pad_mat
	pad.mesh = cyl
	pad.position = CAMP_HEAD_POS + Vector3(0, -0.4, 0)
	world_root.add_child(pad)

	# Glow shards: the Deep Root's flora -- strata-fed crystal spires
	# that lean toward the tide. Deterministic scatter (no seed drift:
	# the camp re-derives identically).
	for i in range(GLOW_SHARD_COUNT):
		var a := TAU * float(i) / float(GLOW_SHARD_COUNT) + 0.31
		var rad := 9.0 + 7.0 * float(i % 3)
		var shard := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.5, 1.4 + 0.9 * float(i % 4), 0.5)
		var shard_mat := StandardMaterial3D.new()
		shard_mat.albedo_color = Color(0.55, 0.7, 0.6)
		shard_mat.emission_enabled = true
		shard_mat.emission = Color(0.35, 0.8, 0.55)
		shard_mat.emission_energy_multiplier = 0.9
		prism.material = shard_mat
		shard.mesh = prism
		shard.position = CAMP_HEAD_POS + Vector3(cos(a) * rad, 0.2, sin(a) * rad)
		shard.rotation = Vector3(0.12 * float(i % 3), a, -0.1 * float(i % 2))
		world_root.add_child(shard)

	# Zone BEFORE the keeper: the spawn path enters the NPC into the
	# zone (rosters), so the declaration must exist first.
	_build_camp_zone()
	_build_camp_keeper()


## The camp keeper (S15.3): spawned DIRECTLY on the globe surface
## (the underworld has no planar bind point -- spawn_all_offering
## _npcs is a planar-coordinate path and must not guess here). Same
## SpawnService.configure path as every other NPC: one pipeline, two
## coordinate frames.
func _build_camp_keeper() -> void:
	var npc_data: NPCData = DataService.get_npc("npc_deep_warden") if DataService else null
	if npc_data == null:
		GameLog.warn("GlobeUnderworld: npc_deep_warden missing; the camp stays empty")
		return
	if SpawnService == null or not SpawnService.has_method("spawn_npc_entity"):
		GameLog.warn("GlobeUnderworld: SpawnService absent; the camp stays empty")
		return
	var surface := CAMP_HEAD_POS + Vector3(0, PLAYER_SKIN + 0.4, 0)
	var entity = SpawnService.spawn_npc_entity(WORLD_ID, surface, npc_data)
	if entity == null:
		return
	# Reparent under the world root so the NPC folds away with the
	# globe (the camp is conjured content, not persistent world state).
	if entity.get_parent() != world_root:
		entity.get_parent().remove_child(entity)
		world_root.add_child(entity)
	entity.global_position = world_root.global_position + surface
	# Zone bookkeeping WITHOUT the planar ZoneManager position path:
	# the zone exists for quest/EXPLORE credit and rosters; the globe
	# IS the place, the planar distance check is meaningless here.
	if ZoneManager and ZoneManager.has_method("get_zone"):
		var zone = ZoneManager.get_zone(ZONE_ID)
		if zone != null and ZoneManager.has_method("entity_enter_zone"):
			ZoneManager.entity_enter_zone(entity, zone)
	_npc_spawns.append(entity)
	GameLog.info("GlobeUnderworld: the Deep Warden keeps the camp (%s)" % npc_data.id)


## S15.3 zone: data-declared (zone_deep_root_camp.tres), loaded into
## ZoneManager at conjure time so EXPLORE credit, rosters, and
## respawn law all read the SAME pipeline as the surface zones. The
## zone_center is world_root-local truth, not planar world coords.
func _build_camp_zone() -> void:
	if ZoneManager == null or not ZoneManager.has_method("load_zones"):
		return
	if ZoneManager._zones.is_empty():
		ZoneManager.load_zones()
	if ZoneManager.get_zone(ZONE_ID) == null:
		var packed: ZoneData = load("res://data/zones/zone_deep_root_camp.tres")
		if packed != null and ZoneManager.has_method("register_zone"):
			ZoneManager.register_zone(packed)
			GameLog.info("GlobeUnderworld: zone %s declared live" % ZONE_ID)


const ZONE_ID: String = "zone_deep_root_camp"


## S15.3 quest credit: walking into the Deep Root IS the EXPLORE
## objective's world event. ZoneManager's planar distance loop never
## sees a conjured globe, so the globe declares arrival itself --
## through the SAME signal the surface path emits (QuestService's
## EXPLORE bridge reads player_entered_zone; the pipeline is one).
func _credit_arrival(body: Node) -> void:
	if ZoneManager == null or not ZoneManager.has_method("get_zone"):
		return
	var zone = ZoneManager.get_zone(ZONE_ID)
	if zone == null or not body.has_method("get"):
		return
	var etype = body.get("entity_type")
	if etype == null:
		# Globe bodies (GlobeWorldPlayer) carry no entity_type -- they
		# ARE the player (the only body a conjured globe binds). Fire
		# the ONE signal the QuestService EXPLORE bridge reads, without
		# the planar roster math (entity_enter_zone would dereference
		# entity_type and crash on these bodies).
		if str(body.get("entity_id")) != "" and ZoneManager.has_signal("player_entered_zone"):
			ZoneManager.player_entered_zone.emit(body, zone)
		return
	if int(etype) != 1:  # Entity.EntityType.PLAYER
		return
	# Playable-surface body (the player body): the full standard path
	# -- rosters, population signals, then the EXPLORE event.
	if ZoneManager.has_method("entity_enter_zone"):
		ZoneManager.entity_enter_zone(body, zone)


## S15.4 THE ASCENT: the sealed passage up. Same monolith law as the
## Moon Gate (no door while the mystery is shut), but the target is
## the world you are standing INSIDE. Stands at the camp head.
func _build_ascent_gate() -> void:
	var gate_script: GDScript = load("res://entities/moon_gate.gd")
	if gate_script == null:
		return
	_ascent_gate = gate_script.new()
	_ascent_gate.name = "AscentGate"
	_ascent_gate.set("target_world", "main")
	_ascent_gate.set("display_name", "The Ascent")
	# The ascent is the future PLAYER door out of the Deep Root. The
	# return is main (ONLINE, no hatch needed); window_law is OFF --
	# the underworld does not orbit, and the sky between a world and
	# its own interior has no phase to read (moon_gate returns
	# "open" only for orbit pairs; a static pair would refuse).
	_ascent_gate.set("window_law", false)
	_ascent_gate.set("dev_hatch", true)
	_ascent_gate.position = CAMP_HEAD_POS + Vector3(4.0, 0.0, 4.0)
	world_root.add_child(_ascent_gate)


## The ride home: the MoonGate return-gate pattern (the ascent gate
## IS the ride home; this is the dev-hatch fallback naming main so
## the dev crew is never stranded in the dark).
func _build_return_gate() -> void:
	var gate_script: GDScript = load("res://entities/moon_gate.gd")
	if gate_script == null:
		return
	_return_gate = gate_script.new()
	_return_gate.name = "ReturnGate"
	_return_gate.set("target_world", "main")
	_return_gate.set("display_name", "Sunward Gate")
	_return_gate.set("window_law", false)
	_return_gate.set("dev_hatch", true)
	_return_gate.position = CAMP_HEAD_POS + Vector3(-4.0, 0.0, 4.0)
	world_root.add_child(_return_gate)


## THE UNDERGLOW LAKE (S15.7, lava's turn in the water frame): where
## the shell sweats magma. Water is DATA (data/oceans/
## lava_underglow_lake.tres: LOCAL pool, surface 1999.6, floor
## 1997.8, current drift east, LAVA 8 dps); this builder places the
## STONE (a low curb ring -- step-over-able, honest) and the MOLTEN
## disc (paint; physics stays in the volume).
func _build_lava_lake() -> void:
	var cald := Node3D.new()
	cald.name = "UnderglowLake"
	world_root.add_child(cald)
	var ground: float = _wilds_surface()
	var seat: Vector3 = CAMP_HEAD_POS + LAVA_LAKE_SEAT
	# THE BASEMENT SLAB: the dish's rock ON the walk line (the same
	# dialect the cistern uses -- a real body STANDS here, never
	# inside the shell). The melt rides 1.2 m above it (the data law).
	var floor_top: float = ground							# slab top == the walk line
	var surface_y: float = ground + 1.2					# the melt line (data law)
	var rim_top: float = surface_y + 0.55				# a curb you step over, never climb
	var inner_r: float = 9.0									# the lake's reach (the data law)
	var ring_r: float = inner_r + 0.5
	# THE BASIN: a standable stone floor under the melt (piece law).
	var basin := MeshInstance3D.new()
	var basin_mesh := CylinderMesh.new()
	basin_mesh.top_radius = inner_r
	basin_mesh.bottom_radius = inner_r + 0.6
	basin_mesh.height = 0.4
	basin.mesh = basin_mesh
	basin.name = "LakeBasin"
	basin.position = seat + Vector3(0, floor_top - 0.2, 0)
	basin_mesh.material = _cistern_slab_material()
	cald.add_child(basin)
	PropCollider.attach(basin)
	# THE CURB: 8 low arcs; stepping over the rim is a step, not a
	# climb (the lava bite is choice-shaped, not gate-shaped).
	var curb_len: float = TAU * ring_r / 8.0 + 0.2
	var curb_h: float = rim_top - floor_top + 0.2
	for i in range(8):
		var a: float = TAU * float(i) / 8.0 + 0.35
		var curb := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.9, curb_h, curb_len)
		# THE SHARED VEIN WALL carries the curb too (one stone law).
		mesh.material = _cistern_wall_material()
		curb.mesh = mesh
		curb.name = "LakeCurb_%d" % i
		curb.position = seat + Vector3(cos(a) * ring_r, floor_top - 0.2 + curb_h * 0.5, sin(a) * ring_r)
		curb.rotation.y = -a
		cald.add_child(curb)
		PropCollider.attach(curb)
	# THE MELT: one self-lit disc, emission riding the tide per frame
	# (see _process's lava rider). NO collider on the liquid: the swim
	# law reads the OceanVolume; the disc is only paint.
	var melt := MeshInstance3D.new()
	var melt_mesh := CylinderMesh.new()
	melt_mesh.top_radius = inner_r
	melt_mesh.bottom_radius = inner_r
	melt_mesh.height = 0.5
	melt.mesh = melt_mesh
	melt.name = "LakeMelt"
	melt.position = seat + Vector3(0, surface_y - 0.25, 0)
	melt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.55, 0.12, 0.02)
	lmat.roughness = 0.35
	lmat.emission_enabled = true
	lmat.emission = Color(1.0, 0.35, 0.03)
	lmat.emission_energy_multiplier = 1.1 + 0.4 * cistern_glow(_glow_tide_phase())
	melt_mesh.material = lmat
	_lava_mat = lmat
	cald.add_child(melt)
	GameLog.info("GlobeUnderworld: the Underglow Lake pools at (%.0f, %.0f), melt %.1f -- the melt licks east" % [seat.x, seat.z, surface_y])


## THE DEEP TRAIL (the underworld's roads): flat stone plates the
## walk line -- one leg camp -> cistern, one leg cistern -> the
## lake overlook (which stops four meters short of the curb: nobody
## stumbles into the melt by accident). Plates are walk-over paint
## (flat stone, no colliders), pure index math, byte-stable.
func _build_trail() -> void:
	var path := Node3D.new()
	path.name = "DeepTrail"
	world_root.add_child(path)
	var ground: float = _wilds_surface()
	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.2, 0.18, 0.21)
	plate_mat.roughness = 0.9
	plate_mat.emission_enabled = true
	plate_mat.emission = STONE_VEINS
	plate_mat.emission_energy_multiplier = 0.08
	var cistern_seat: Vector3 = CAMP_HEAD_POS + Vector3(12.0, 0.0, 0.0)
	var lake_overlook: Vector3 = CAMP_HEAD_POS + LAVA_LAKE_SEAT \
		+ (Vector3(26.0, 0.0, -20.0).normalized() * 13.0)
	var legs := [cistern_seat + Vector3(2.4, 0.0, 1.2), lake_overlook]
	var leg_t := 0
	for leg in legs:
		leg_t += 1
		var steps: int = 16
		for i in range(steps):
			var t: float = float(i) / float(steps)
			var stop: Vector3 = (leg as Vector3) + Vector3(0, 0, 0)
			var start: Vector3 = CAMP_HEAD_POS if leg_t == 1 \
				else (legs[0] as Vector3)
			var seat: Vector3 = start.lerp(stop, t)
			var plate := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.9 + 0.18 * _wilds_drift(i * 3 + leg_t, 51.0)
			mesh.bottom_radius = mesh.top_radius + 0.2
			mesh.height = 0.14
			mesh.material = plate_mat
			plate.mesh = mesh
			plate.name = "TrailPlate_%d_%d" % [leg_t, i]
			plate.position = seat + Vector3(0, ground + 0.07, 0)
			plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			path.add_child(plate)
	GameLog.info("GlobeUnderworld: the Deep Trail lays its two legs (camp to cistern to the lake overlook)")


func _moon_data():
	var scope = get_node_or_null("/root/ScopeService")
	if scope != null and scope.has_method("world_data"):
		return scope.world_data(WORLD_ID)
	var reg = WorldRegistryScript.new()
	reg.load_worlds()
	return reg.get_world(WORLD_ID)


func _epoch_days() -> float:
	var svc = get_node_or_null("/root/SignService")
	if svc != null and svc.has_method("sky_epoch_days"):
		return svc.sky_epoch_days()
	return float(Time.get_unix_time_from_system()) / 86400.0


## The camp head: where the visitor lands, the keeper keeps, and the
## Ascent waits. Kept as the one placement authority (world_root
## local); everything above reads it.
