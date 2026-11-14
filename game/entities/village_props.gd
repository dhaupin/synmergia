## VillageProps -- the authored GAME-FUNCTION props (the owner's
## turn-15 law: "starter village has all the NPCs, an ankh, a moon
## gate, and a duel/elim/tdm/royale gate; the capitol gets them too").
##
## The three instant kinds, all riding the SAME frame every authored
## install rides (dir -> planet_radius + tile lift + walk_surface_h),
## all parented under the globe's StarterVillage / CapitolCity prop
## roots:
##
##   - THE ANKH (a core/schemas/ankh.gd class_name node): the shared
##     respawn shrine. The bind law is Ankh's own (walk up, E --
##     the player body's _activate_nearby_ankh resolves the "ankhs"
##     group); the prop only SETS its identity + position.
##   - THE MOON GATE (entities/moon_gate.gd): the sealed way between
##     worlds. Its mystery-state visuals are the entity's own; the
##     prop stands it on the plaza edge, village and capitol alike.
##   - THE BOUT GATE STONES: three authored stone arches (Coliseum
##     for duel/elimination, Sandpit for TDM, Valley for royale),
##     each an Area3D loaded from scenes/worlds/arena_gateway.gd
##     carrying its zone id --
##     the S11 law: stones in towns are the lobby's doors; the queue
##     teleports in at assembly and every ending returns here.
##
## RefCounted builder (static build_village / build_capitol), no
## autoload, no class_name.
extends RefCounted

const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
const PropCollider = preload("res://entities/prop_collider.gd")

## The bout stone roster: (name, zone id, tint). zone ids are the
## data/zones .tres ids (the gateway law's target_lookup path).
## The mode door cluster the owner asked for ("duel/elim/tdm/Royale
## gate thing"): the coliseum stone fronts the duel/elimiation
## bouts, the sandpit stone the team-deathmatch bouts, and the
## valley stone the 30-fighter royale.
const BOUT_STONES: Array = [
	["BoutStoneDuel", "zone_arena_coliseum", Color(0.85, 0.68, 0.25)],
	["BoutStoneTDM", "zone_arena_sandpit", Color(0.30, 0.60, 0.45)],
	["BoutStoneRoyale", "zone_royale_valley", Color(0.55, 0.30, 0.70)],
]

## Village layout: authored bearings (spawn tangent frame) + reaches.
const VILLAGE_BATCH: Array = [
	# kind, name, bearing_deg, reach_rad
	["ankh", "VillageAnkh", -150.0, 0.012],
	["moongate", "VillageMoonGate", -110.0, 0.016],
	["boutstones", "VillageBoutStones", 120.0, 0.014],
]

## Capitol layout: the same prop family, spread around the capitol
## plaza anchor (the cove strand) in PLAZA-frame beats.
const CAPITOL_BATCH: Array = [
	# kind, name, bearing_deg, reach_rad
	["ankh", "CapitolAnkh", 20.0, 0.004],
	["moongate", "CapitolMoonGate", -35.0, 0.006],
	["boutstones", "CapitolBoutStones", 155.0, 0.005],
	# The Concord sink shrine: the physical home of the Sigil Vault
	# (the herald NPC stands plaza-side of it -- see globe_world's
	# CAPITOL_NPC_BATCH, same bearing, one step in).
	["concord_shrine", "ConcordSinkShrine", -95.0, 0.007],
]

## THE CONCORD LOOP BELT (planar-retirement Step 1): the Ancient Door
## and the Concord Stone. These are INTERACT props, so their reach is
## in METERS from the spawn plaza -- the radian reach the village belt
## uses spreads props 240+ m out, which is fine for scenery but puts an
## E-to-use prop far outside the 4 m interact range. Meter reach keeps
## them a short walk from spawn at every planet scale.
const CONCORD_BATCH: Array = [
	# kind, name, bearing_deg, reach_m
	["ancientdoor", "AncientDoor", -40.0, 7.0],
	["concordstone", "ConcordStone", 40.0, 7.0],
]


## Build the village prop belt under `village_root` (globe world's
## StarterVillage node). The plaza frame is the spawn plaza's own:
## SPAWN_CENTER tangent bearings, each dir lifted by the walk law.
static func build_village(village_root: Node3D, planet_radius: float,
		surface_lift: float, walk_surface_h: Callable) -> void:
	var spawn: Vector3 = TerrainGen.SPAWN_CENTER
	_build_batch(village_root, spawn, VILLAGE_BATCH, planet_radius,
		surface_lift, walk_surface_h)


## The Concord loop (Ancient Door + Concord Stone) under `root`, placed
## in METER reach from the spawn plaza (see CONCORD_BATCH). The globe
## world's live Concord loop lives here.
static func build_concord(root: Node3D, planet_radius: float,
		surface_lift: float, walk_surface_h: Callable) -> void:
	var spawn: Vector3 = TerrainGen.SPAWN_CENTER
	_build_batch_meters(root, spawn, CONCORD_BATCH, planet_radius,
		surface_lift, walk_surface_h)


## Build the capitol prop belt under `capitol_root` (the CapitolCity
## node). The plaza frame is the capitol anchor's own tangent frame
## (the strand law); beats ride the capitol plaza's flat.
static func build_capitol(capitol_root: Node3D, planet_radius: float,
		surface_lift: float, walk_surface_h: Callable) -> void:
	var cap: Vector3 = TerrainGen.capitol_plaza_dir()
	_build_batch(capitol_root, cap, CAPITOL_BATCH, planet_radius,
		surface_lift, walk_surface_h)


static func _build_batch(root: Node3D, center: Vector3, batch: Array,
		planet_radius: float, surface_lift: float, walk_surface_h: Callable) -> void:
	var east: Vector3 = Vector3(0, 1, 0).cross(center).normalized()
	var north: Vector3 = center.cross(east).normalized()
	# THE BOOT-CLEAR REACH (mirrors starter_village.build): the authored
	# reaches are ANGULAR (the planet-scale layout), but the prototype
	# bench radius shrinks them to ~1 m, dropping the ankh / moon gate /
	# bout stones ON the spawn and wedging the player inside their
	# colliders. Pad every reach out to 8 m at bench scale so clearance
	# is scale-free in METERS; the planet keeps the authored layout.
	var reach_floor: float = maxf(0.0, 8.0 / maxf(planet_radius, 1.0))
	if planet_radius > 1000.0:
		reach_floor = 0.0  # the authored planet layout owns the reach
	for entry in batch:
		var kind: String = entry[0]
		var pname: String = entry[1]
		var bearing: float = deg_to_rad(float(entry[2]))
		var reach: float = maxf(float(entry[3]), reach_floor)
		var dir: Vector3 = (center + east * (reach * cos(bearing)) \
			+ north * (reach * sin(bearing))).normalized()
		var pos: Vector3 = dir * (planet_radius + surface_lift \
			+ float(walk_surface_h.call(dir)))
		var node: Node3D = _instantiate(kind, pname, pos, dir)
		if node != null:
			root.add_child(node)


## Same batch law as `_build_batch`, but `reach` is METERS of arc along
## the surface (angular offset = reach / planet_radius). Interact props
## need a fixed short walk from spawn at every scale, which a radian
## reach cannot give (0.014 rad is 280 m on the 20 km planet).
static func _build_batch_meters(root: Node3D, center: Vector3, batch: Array,
		planet_radius: float, surface_lift: float, walk_surface_h: Callable) -> void:
	var east: Vector3 = Vector3(0, 1, 0).cross(center).normalized()
	var north: Vector3 = center.cross(east).normalized()
	for entry in batch:
		var kind: String = entry[0]
		var pname: String = entry[1]
		var bearing: float = deg_to_rad(float(entry[2]))
		var reach_rad: float = float(entry[3]) / maxf(planet_radius, 1.0)
		var dir: Vector3 = (center + east * (reach_rad * cos(bearing)) \
				+ north * (reach_rad * sin(bearing))).normalized()
		var pos: Vector3 = dir * (planet_radius + surface_lift \
				+ float(walk_surface_h.call(dir)))
		var node: Node3D = _instantiate(kind, pname, pos, dir)
		if node != null:
			root.add_child(node)


## One kind factory. Returns a configured Node3D (already positioned
## in world space) or null when the script is unavailable.
static func _instantiate(kind: String, pname: String, pos: Vector3,
		dir: Vector3) -> Node3D:
	match kind:
		"ankh":
			return _ankh(pname, pos, dir)
		"moongate":
			return _moongate(pname, pos, dir)
		"boutstones":
			return _bout_stones(pname, pos, dir)
		"concord_shrine":
			return _concord_shrine(pname, pos, dir)
		"ancientdoor":
			return _ancient_door(pname, pos, dir)
		"concordstone":
			return _concord_stone(pname, pos, dir)
	return null


# ---- THE ANCIENT DOOR (entities/ancient_door.gd) -----------------------

## The Concord Chronicle's door: the slab the tribe's watching opens at
## dawn. The entity owns its own state machine (adds itself to
## "ancient_doors", emits door_opened); the prop only SETS identity +
## position, exactly like the ankh and moon gate above.
static func _ancient_door(pname: String, pos: Vector3, dir: Vector3) -> Node3D:
	var script: GDScript = load("res://entities/ancient_door.gd")
	if script == null:
		return null
	var door: Node3D = script.new()
	door.name = pname
	door.set("display_name", "The First Ancient")
	door.position = pos
	_align_radial(door, dir)
	return door


# ---- THE CONCORD STONE (entities/concord_stone.gd) ---------------------

## The player's window-insight trigger: press E to record a sky gaze
## (the stone adds itself to "concord_stones"; SignService owns the
## state). Same prop-only contract as the door.
static func _concord_stone(pname: String, pos: Vector3, dir: Vector3) -> Node3D:
	var script: GDScript = load("res://entities/concord_stone.gd")
	if script == null:
		return null
	var stone: Node3D = script.new()
	stone.name = pname
	stone.set("display_name", "The Haven Stone")
	stone.position = pos
	_align_radial(stone, dir)
	return stone


# ---- THE ANKH (core/schemas/ankh.gd, class_name Ankh) ------------------

static func _ankh(pname: String, pos: Vector3, dir: Vector3) -> Node3D:
	var script: GDScript = load("res://core/schemas/ankh.gd")
	if script == null:
		return null
	var ankh: Node3D = script.new()
	ankh.name = pname
	ankh.set("ankh_id", pname.to_snake_case() + "_" + pname)
	ankh.set("display_name", pname.replace("Village", "Village ") \
		.replace("Capitol", "Capitol "))
	ankh.set("ankh_type", 0)  # Ankh.AnkhType.SHARED: anyone binds
	ankh.position = pos
	# Radial frame: up = radial, so the shrine stands on the ground.
	_align_radial(ankh, dir)
	_glow_column(ankh, Color(0.95, 0.82, 0.30))  # the gold ankh light
	return ankh


# ---- THE MOON GATE (entities/moon_gate.gd) -----------------------------

static func _moongate(pname: String, pos: Vector3, dir: Vector3) -> Node3D:
	var script: GDScript = load("res://entities/moon_gate.gd")
	if script == null:
		return null
	var gate := Node3D.new()
	gate.name = pname
	gate.set_script(script)
	gate.set("display_name", "Moon Gate")
	gate.set("target_world", "moon")
	gate.position = pos
	_align_radial(gate, dir)
	return gate


# ---- THE BOUT GATE STONES (scenes/worlds/arena_gateway.gd) -------------

## Two stone arches: the queue stones the S11 law describes. Each is
## an Area3D carrying one zone id; collision rides the gateway's own
## shape/body config (the class is an Area3D itself).
static func _bout_stones(pname: String, pos: Vector3, dir: Vector3) -> Node3D:
	var script: GDScript = load("res://scenes/worlds/arena_gateway.gd")
	if script == null:
		return null
	var cluster: Node3D = Node3D.new()
	cluster.name = pname
	cluster.position = pos
	_align_radial(cluster, dir)
	var k: int = 0
	for stone in BOUT_STONES:
		var gateway: Area3D = script.new()
		gateway.name = str(stone[0])
		gateway.set("zone_id", str(stone[1]))
		gateway.set("queue_mode", true)  # S11: stones are queue doors
		# Arch local frame: 2.6 m apart along the local east axis.
		gateway.position = Vector3(float(k) * 2.6, 0.0, 0.0)
		_stone_arch(gateway, Color(stone[2]))
		cluster.add_child(gateway)
		k += 1
	return cluster


## The authored stone arch (plain geometry; the gateway's Area3D
## handles the trigger -- the stone is the DOOR, not a collider).
static func _stone_arch(gateway: Node3D, tint: Color) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = tint.lerp(Color(0.52, 0.50, 0.47), 0.55)
	mat.roughness = 0.85
	for side in [-1.0, 1.0]:
		var leg: MeshInstance3D = MeshInstance3D.new()
		var leg_mesh: BoxMesh = BoxMesh.new()
		leg_mesh.size = Vector3(0.45, 3.2, 0.45)
		leg.mesh = leg_mesh
		leg.material_override = mat
		leg.position = Vector3(side * 1.05, 1.6, 0.0)
		gateway.add_child(leg)
	var lintel: MeshInstance3D = MeshInstance3D.new()
	var lintel_mesh: BoxMesh = BoxMesh.new()
	lintel_mesh.size = Vector3(2.55, 0.5, 0.55)
	lintel.mesh = lintel_mesh
	lintel.material_override = mat
	lintel.position = Vector3(0.0, 3.35, 0.0)
	gateway.add_child(lintel)


# ---- THE CONCORD SINK SHRINE (the Sigil Vault's home) ------------------

## The pillared stand where Concord Sigils find their honest out: the
## money-hub world-building for the sink catalog (steed deeds, degree
## stakes, and the vault's own ledger all resolve through the herald
## standing beside it). Authored stone riding the Plaza frame's laws
## like the bout stones, with the sky-cyan sigil band the Concord's
## mark carries -- and a PropCollider body so the pillar stays solid.
static func _concord_shrine(pname: String, pos: Vector3, dir: Vector3) -> Node3D:
	var shrine := Node3D.new()
	shrine.name = pname
	shrine.position = pos
	_align_radial(shrine, dir)
	var stone: StandardMaterial3D = StandardMaterial3D.new()
	stone.albedo_color = Color(0.55, 0.58, 0.60)
	stone.roughness = 0.85
	# The dais: a squat seat-ring the herald's clients can gather on.
	var dais: MeshInstance3D = MeshInstance3D.new()
	var dais_mesh: CylinderMesh = CylinderMesh.new()
	dais_mesh.top_radius = 2.4
	dais_mesh.bottom_radius = 3.0
	dais_mesh.height = 0.4
	dais.mesh = dais_mesh
	dais.material_override = stone
	dais.position = Vector3(0, 0.2, 0)
	shrine.add_child(dais)
	var pillar: MeshInstance3D = MeshInstance3D.new()
	var pillar_mesh: CylinderMesh = CylinderMesh.new()
	pillar_mesh.top_radius = 0.42
	pillar_mesh.bottom_radius = 0.62
	pillar_mesh.height = 5.0
	pillar.mesh = pillar_mesh
	pillar.material_override = stone
	pillar.position = Vector3(0, 2.7, 0)
	shrine.add_child(pillar)
	# THE SIGIL BAND (the Concord's sky-cyan mark): an emissive ring
	# crowning the pillar -- static authored light, no fake pulse.
	var band: MeshInstance3D = MeshInstance3D.new()
	var band_mesh: TorusMesh = TorusMesh.new()
	band_mesh.inner_radius = 0.52
	band_mesh.outer_radius = 0.78
	var band_mat: StandardMaterial3D = StandardMaterial3D.new()
	band_mat.albedo_color = Color(0.55, 0.85, 0.9)
	band_mat.emission_enabled = true
	band_mat.emission = Color(0.55, 0.85, 0.9)
	band_mat.emission_energy_multiplier = 1.2
	band.mesh = band_mesh
	band.material_override = band_mat
	band.position = Vector3(0, 4.9, 0)
	shrine.add_child(band)
	# The capstone: a low bronze lid over the band's base ring.
	var cap: MeshInstance3D = MeshInstance3D.new()
	var cap_mesh: CylinderMesh = CylinderMesh.new()
	cap_mesh.top_radius = 0.55
	cap_mesh.bottom_radius = 0.7
	cap_mesh.height = 0.5
	cap.mesh = cap_mesh
	cap.material_override = stone
	cap.position = Vector3(0, 5.35, 0)
	shrine.add_child(cap)
	# A soft warm halo at the pillar's crown so the shrine reads as a
	# lit place at dusk (the harbor-light school: light marks the
	# landmark, never a beacon you fast-travel to).
	var halo: OmniLight3D = OmniLight3D.new()
	halo.light_color = Color(0.62, 0.88, 0.95)
	halo.light_energy = 1.4
	halo.omni_range = 9.0
	halo.position = Vector3(0, 4.6, 0)
	shrine.add_child(halo)
	# THE IN-TREE COLLIDER LAW (the capitol quarters' law): attach the
	# solid body one frame later, when the prop belt is inside the
	# tree and PropCollider's AABB read can resolve transforms. The
	# deferred lambda keeps the static call off the parse-time path.
	var attach_body := func() -> void:
		PropCollider.attach(shrine)
	attach_body.call_deferred()
	return shrine


# ---- SHARED HELPERS -----------------------------------------------------

## Lay the node's basis radial-up at `dir`: up = the radial (the same
## tangent frame every authored install rides, matching
## starter_village._structure's basis law).
static func _align_radial(node: Node3D, dir: Vector3) -> void:
	var east: Vector3 = Vector3(0, 1, 0).cross(dir).normalized()
	var up: Vector3 = dir
	var z_axis: Vector3 = east.cross(up).normalized()
	node.basis = Basis(east, up, z_axis)


## A slim glowing pillar (the ankh's light mark; the shrine's model
## stays the entity's own -- this is the authored stand it sits on).
static func _glow_column(parent: Node3D, tint: Color) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.80, 0.72, 0.50)
	mat.roughness = 0.8
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 0.5
	var ped: MeshInstance3D = MeshInstance3D.new()
	var ped_mesh: CylinderMesh = CylinderMesh.new()
	ped_mesh.top_radius = 0.45
	ped_mesh.bottom_radius = 0.65
	ped_mesh.height = 0.5
	ped.mesh = ped_mesh
	ped.material_override = mat
	ped.position = Vector3(0, 0.25, 0)
	parent.add_child(ped)
