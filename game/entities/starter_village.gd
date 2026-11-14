## StarterVillage -- the authored plaza PROTO (the ledger's parked
## "starter-village PROTO build": the strait content's boots-and-stalls
## village law).
##
## THREE authored structures ride laws that already exist -- the village
## needs NO terrain law of its own:
##   - the spawn plaza is flat at exactly SPAWN_HEIGHT out to
##     SPAWN_FLAT_ANG (the retired retired streamer's mesh saw it), so every structure
##     foot lands on exact flat ground;
##   - the apron keeps the ring dry and owns its ground (the boot
##     apron outranks the cartway), so the road never regrades or
##     paints under the village;
##   - PropCollider.attach carries the one-law collision + climb
##     group, the same belt every other world prop rides.
## Placement is the gateway's own frame: tangent bearings around
## SPAWN_CENTER, each dir lifted to planet_radius + tile lift +
## walk_surface_h (the plaza's exact 9 m).
##
## RefCounted builder (static build()), no autoload, no class_name.
extends RefCounted

const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
const PropCollider = preload("res://entities/prop_collider.gd")


## Authored layout: (bearing degrees about spawn's tangent frame,
## angular reach from the plaza center in radians). Five structures
## frame the boot plaza without crowding the spawn point: the hall,
## the forge, the way-sign, the general store (the merchant include's
## ITS door), and the harbor dock -- the strait's ferry terminal at
## the mainland rim (the road law's start bearing, the cartway
## walks harbor -> capitol). HarborDock rides village_harbor_dir()
## (its own anchor, not a spawn bearing): the REAL co-located seam
## the ferry + road + npc_merchant_general .tres all point at.
const HALL_BEARING_DEG: float = 8.0
const HALL_REACH: float = 0.017
const FORGE_BEARING_DEG: float = 48.0
const FORGE_REACH: float = 0.019
const SIGN_BEARING_DEG: float = -36.0
const SIGN_REACH: float = 0.013
const STORE_BEARING_DEG: float = -8.0
const STORE_REACH: float = 0.020


## Build the village under `parent` (globe_world's world_root):
## planet_radius + the retired retired streamer's tile lift + the walk law answer the
## lift for each structure's dir; walk provider must be the retired retired streamer's
## walk_surface_h Callable (law-consistent ground under every boot).
static func build(parent: Node3D, planet_radius: float, surface_lift: float,
		walk_surface_h: Callable) -> Node3D:
	var village := Node3D.new()
	village.name = "StarterVillage"
	parent.add_child(village)

	var spawn: Vector3 = TerrainGen.SPAWN_CENTER
	var east: Vector3 = Vector3(0, 1, 0).cross(spawn).normalized()
	var north: Vector3 = spawn.cross(east).normalized()

	# THE BOOT-CLEAR REACH (the globe probe's boot normal caught it):
	# the authored reaches are ANGULAR (the planet-scale layout), but
	# the boot BALL is a fixed meter size -- at the prototype bench
	# radius the angular reaches put the village INSIDE the boot's
	# first ticks. The bench scale pads every reach out to 8 m so the
	# clearance is scale-free in METERS, not radians: the planet keeps
	# the authored layout, the bench keeps its boot sane.
	var reach_floor: float = maxf(0.0, 8.0 / maxf(planet_radius, 1.0))
	if planet_radius > 1000.0:
		reach_floor = 0.0  # the authored planet layout owns the reach

	_structure(village, _dir_for(spawn, east, north, HALL_BEARING_DEG, maxf(HALL_REACH, reach_floor)),
		planet_radius, surface_lift, walk_surface_h, "VillageHall")
	_structure(village, _dir_for(spawn, east, north, FORGE_BEARING_DEG, maxf(FORGE_REACH, reach_floor)),
		planet_radius, surface_lift, walk_surface_h, "ForgeStall")
	_structure(village, _dir_for(spawn, east, north, SIGN_BEARING_DEG, maxf(SIGN_REACH, reach_floor)),
		planet_radius, surface_lift, walk_surface_h, "WaySignpost")
	_structure(village, _dir_for(spawn, east, north, STORE_BEARING_DEG, maxf(STORE_REACH, reach_floor)),
		planet_radius, surface_lift, walk_surface_h, "GeneralStore")
	# THE HARBOR DOCK: its own anchor law (village_harbor_dir) -- the
	# ferry terminal toward the strait's mainland rim, where the island
	# bearing points and the cart road starts.
	var harbor_anchor: Vector3 = TerrainGen.village_harbor_dir()
	# THE DOCK APRON LAW: the real harbor rim sits ~32 deg / 11 km out
	# (a full cart journey), but the apron's dry ring ends at
	# SPAWN_APRON_OUTER_ANG (~1800 m). The dock sits ON that dry ring
	# edge, on the REAL harbor's bearing: close enough to walk to from
	# the plaza, honest about which way the coast is.
	var harbor_bearing: float = spawn.signed_angle_to(harbor_anchor, spawn.cross(Vector3(0, 1, 0)).normalized())
	var harbor_dir: Vector3 = _dir_for(spawn, \
		Vector3(0, 1, 0).cross(spawn).normalized(), \
		spawn.cross(Vector3(0, 1, 0)).normalized(), \
		rad_to_deg(harbor_bearing), float(TerrainGen.SPAWN_APRON_OUTER_ANG))
	_structure(village, harbor_dir, planet_radius, surface_lift,
		walk_surface_h, "HarborDock")
	return village


static func _dir_for(spawn: Vector3, east: Vector3, north: Vector3,
		bearing_deg: float, reach: float) -> Vector3:
	var rad := deg_to_rad(bearing_deg)
	var dir: Vector3 = (spawn + east * (reach * cos(rad)) \
		+ north * (reach * sin(rad))).normalized()
	return dir


static func _structure(village: Node3D, dir: Vector3, planet_radius: float,
		surface_lift: float, walk_surface_h: Callable, prop_name: String) -> void:
	var lift: float = surface_lift + float(walk_surface_h.call(dir))
	var root := Node3D.new()
	root.name = prop_name
	root.position = dir * (planet_radius + lift)
	# Align the structure's up with the ground normal (radial); the
	# tangent stays east-aligned so authored shapes read the same
	# at any planet scale.
	var east: Vector3 = Vector3(0, 1, 0).cross(dir).normalized()
	var up: Vector3 = dir
	var z_axis: Vector3 = east.cross(up).normalized()
	root.basis = Basis(east, up, z_axis)
	village.add_child(root)
	_build_parts(root, prop_name)
	PropCollider.attach(root)


static func _build_parts(root: Node3D, prop_name: String) -> void:
	match prop_name:
		"VillageHall":
			_box(root, Vector3(0, 1.6, 0), Vector3(6.0, 3.2, 5.0), _STUCCO)
			_prism(root, Vector3(0, 4.0, 0), Vector3(7.0, 2.4, 6.0), _TIMBER)
			_box(root, Vector3(0, 1.0, 2.55), Vector3(1.2, 2.0, 0.3), _TIMBER)
		"ForgeStall":
			_box(root, Vector3(0, 1.2, 0), Vector3(3.5, 2.4, 3.0), _STONE)
			_prism(root, Vector3(0, 3.0, 0), Vector3(4.2, 1.6, 3.6), _TIMBER)
			_anvil(root)
		"WaySignpost":
			_pole(root)
			_box(root, Vector3(0.25, 1.9, 0), Vector3(0.9, 0.22, 0.06), _TIMBER)
			_box(root, Vector3(-0.2, 1.5, 0), Vector3(0.9, 0.22, 0.06), _TIMBER)
		"GeneralStore":
			# The merchant's shop: a broad-boarded store with a
			# striped awning over the counter and a crate stack.
			_box(root, Vector3(0, 1.7, 0), Vector3(5.6, 3.4, 4.4), _STUCCO)
			_prism(root, Vector3(0, 4.2, 0), Vector3(6.6, 2.2, 5.4), _TERRA)
			_box(root, Vector3(0, 1.1, 2.3), Vector3(3.6, 2.2, 0.5), _TIMBER)  # counter
			_awning(root)
			_crate(root, Vector3(2.1, 0.4, 1.7))
			_crate(root, Vector3(2.1, 1.1, 1.5))
		"HarborDock":
			# The ferry terminal: a timber pier walking into the water
		# band (foot on dry land, deck reaching past the sea line), a
		# mooring post pair, and a low goods shed. The pier is a
		# slope-safe read of the authored strait; the moat law does
		# not touch this ring.
			_pier(root)
			_box(root, Vector3(0, 1.5, -1.6), Vector3(3.2, 3.0, 2.6), _TIMBER)  # shed
			_prism(root, Vector3(0, 3.4, -1.6), Vector3(3.8, 1.6, 3.0), _TERRA)  # shed roof
			_pole_at(root, Vector3(-1.4, 0.9, 1.8))
			_pole_at(root, Vector3(0.6, 0.9, 2.4))
		_:
			pass


static func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _prism(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _anvil(parent: Node3D) -> void:
	_box(parent, Vector3(-0.6, 0.55, 1.0), Vector3(0.5, 0.3, 0.9), _IRON)


static func _awning(parent: Node3D) -> void:
	_box(parent, Vector3(0, 2.8, 2.6), Vector3(4.6, 0.16, 1.4), _CANVAS)


static func _crate(parent: Node3D, pos: Vector3) -> void:
	_box(parent, pos, Vector3(0.7, 0.7, 0.7), _CRATE)


static func _pier(parent: Node3D) -> void:
	# The pier reads along the local tangent (z = seaward here: the
	# shed sits UP-shore behind the foot). Planks: five boards.
	var z: int = 2
	while z <= 10:
		_box(parent, Vector3(0, 0.85, float(z) * 0.55), Vector3(1.7, 0.16, 0.42), _TIMBER)
		z += 1
	# The pier's two bracing posts underwater-tick every second plank.
	z = 3
	while z <= 9:
		_box(parent, Vector3(-0.7, 0.35, float(z) * 0.55), Vector3(0.16, 1.2, 0.16), _TIMBER)
		_box(parent, Vector3(0.7, 0.35, float(z) * 0.55), Vector3(0.16, 1.2, 0.16), _TIMBER)
		z += 2


static func _pole_at(parent: Node3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.07
	mesh.bottom_radius = 0.09
	mesh.height = 1.9
	mi.mesh = mesh
	mi.material_override = _TIMBER
	mi.position = pos
	parent.add_child(mi)


static func _pole(parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.08
	mesh.bottom_radius = 0.10
	mesh.height = 2.4
	mi.mesh = mesh
	mi.material_override = _TIMBER
	mi.position = Vector3(0, 1.2, 0)
	parent.add_child(mi)


## The authored palette (village style slice 0): lime stucco walls,
## dark timber framing, terracotta roofs, stone forge, iron wares.
## Plain colors, no textures -- the vertex-color terrain already owns
## the budget; the village stays cheap and readable.
static var _STUCCO: StandardMaterial3D = _make_mat(Color(0.78, 0.73, 0.62))
static var _TIMBER: StandardMaterial3D = _make_mat(Color(0.40, 0.27, 0.16))
static var _STONE: StandardMaterial3D = _make_mat(Color(0.52, 0.50, 0.47))
static var _IRON: StandardMaterial3D = _make_mat(Color(0.30, 0.31, 0.34))
static var _TERRA: StandardMaterial3D = _make_mat(Color(0.66, 0.36, 0.24))
static var _CANVAS: StandardMaterial3D = _make_mat(Color(0.82, 0.80, 0.74))
static var _CRATE: StandardMaterial3D = _make_mat(Color(0.55, 0.38, 0.22))


static func _make_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m
