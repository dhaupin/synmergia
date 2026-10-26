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
		_visitors[pid] = true
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
	## The cistern rides the same tide: the pool drinks at dawn.
	if _cistern_water_mat != null:
		_cistern_water_mat.emission_energy_multiplier = cistern_glow(_glow_tide_phase())


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
	add_child(env)
	env.environment = e


## The Deep Root camp (S15.3): a strata-lit shelf with a hearth, the
## keeper, and the shaft-head. Coordinates are world_root-local (the
## globe is conjured at origin, so local == planet-relative).

const CAMP_HEAD_POS: Vector3 = Vector3(0, 2000.0, 0)
const GLOW_SHARD_COUNT: int = 14

var _cistern_water_mat: StandardMaterial3D = null


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
	# --- the basin slab (the dish's bottom: standable stone) ---
	var slab := MeshInstance3D.new()
	var slab_mesh := CylinderMesh.new()
	slab_mesh.top_radius = inner_r
	slab_mesh.bottom_radius = inner_r + 0.4
	slab_mesh.height = 0.4
	slab.mesh = slab_mesh
	slab.name = "CisternSlab"
	slab.position = seat_xz + Vector3(0, floor_top - 0.2, 0)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.11, 0.1, 0.12)
	stone.roughness = 1.0
	slab_mesh.material = stone
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
			var wall_mat := StandardMaterial3D.new()
			wall_mat.albedo_color = Color(0.12, 0.11, 0.13)
			wall_mat.roughness = 1.0
			mesh.material = wall_mat
		else:
			mesh.size = Vector3(0.8, ledge_h, wall_len)
			piece.position = seat_xz + Vector3(cos(a) * ring_r, floor_top + ledge_h / 2.0 - 0.2, sin(a) * ring_r)
			piece.name = "CisternBench"
			var bench_mat := StandardMaterial3D.new()
			bench_mat.albedo_color = Color(0.14, 0.13, 0.15)
			bench_mat.roughness = 1.0
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
	# Playable-surface body (PlayerController): the full standard path
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
