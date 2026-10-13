## StarterVillage -- the authored plaza PROTO (the ledger's parked
## "starter-village PROTO build": the strait content's boots-and-stalls
## village law).
##
## THREE authored structures ride laws that already exist -- the village
## needs NO terrain law of its own:
##   - the spawn plaza is flat at exactly SPAWN_HEIGHT out to
##     SPAWN_FLAT_ANG (the streamer's mesh saw it), so every structure
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
## angular reach from the plaza center in radians). All three sit
## inside SPAWN_FLAT_ANG's full-flat ring, bearings spread so the
## structures frame the boot plaza without crowding the spawn point.
const HALL_BEARING_DEG: float = 8.0
const HALL_REACH: float = 0.017
const FORGE_BEARING_DEG: float = 48.0
const FORGE_REACH: float = 0.019
const SIGN_BEARING_DEG: float = -36.0
const SIGN_REACH: float = 0.013


## Build the village under `parent` (globe_world's world_root):
## planet_radius + the streamer's tile lift + the walk law answer the
## lift for each structure's dir; walk provider must be the streamer's
## walk_surface_h Callable (law-consistent ground under every boot).
static func build(parent: Node3D, planet_radius: float, surface_lift: float,
		walk_surface_h: Callable) -> Node3D:
	var village := Node3D.new()
	village.name = "StarterVillage"
	parent.add_child(village)

	var spawn: Vector3 = TerrainGen.SPAWN_CENTER
	var east: Vector3 = Vector3(0, 1, 0).cross(spawn).normalized()
	var north: Vector3 = spawn.cross(east).normalized()

	_structure(village, _dir_for(spawn, east, north, HALL_BEARING_DEG, HALL_REACH),
		planet_radius, surface_lift, walk_surface_h, "VillageHall")
	_structure(village, _dir_for(spawn, east, north, FORGE_BEARING_DEG, FORGE_REACH),
		planet_radius, surface_lift, walk_surface_h, "ForgeStall")
	_structure(village, _dir_for(spawn, east, north, SIGN_BEARING_DEG, SIGN_REACH),
		planet_radius, surface_lift, walk_surface_h, "WaySignpost")
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


static func _make_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m
