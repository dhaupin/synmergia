## FerryVessel -- the Pans Runner (S14.5's missing boat). The route +
## schedule are live server truth (data/vehicles/veh_pans_ferry.tres
## through FerrySchedule's closed form); the deck motion law is still
## virtual (S14.6 carries riders), but the VESSEL now physically rides
## the lane:
##
##   - build() stands the hull from plain authored primitives (timber
##     hull + deck, hold tent, lateen mast + yard + canvas, stern
##     lantern) -- the engine-ban dialect (no combustion, wind and
##     water only);
##   - place(t) rides the pier<->pans lane: t=0 berthed at the capitol
##     pier's water face, t=1 floating off the pans mooring flank; in
##     between the hull floats ON the sea line (the ocean is the water
##     law's own surface; walk_surface_h at sea dirs returns the
##     seabed, so the sea level clamps it back up) and the vessel's
##     frame points along the travel tangent, bow toward the pans leg.
##
## The pier-end dir mirrors entities/capitol_monolith.gd's pier law
## (the capitol bearing walked seaward around the same south axis) so
## the visible berth IS the pier the route declares. RefCounted
## builder (static build()), no autoload, no class_name.
extends RefCounted

const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
const CapitolMonolith = preload("res://entities/capitol_monolith.gd")
const PropCollider = preload("res://entities/prop_collider.gd")

# The pier walk mirrors CapitolMonolith's pier law (six seaward steps
# land the pier head; the boat berths its water face).
const CAPITOL_PIER_STEPS: int = 6

# The pans-side berthing flank: the PansMonolith's own moor step
# (the same south-axis beat keeps the two laws one dialect).
const PAN_MOOR_STEP: float = 0.004

# The hull draft: the float height ABOVE the water line.
const FLOAT_LIFT: float = 0.45

# The pier berth (the clip tune, v12): the hull's keel bottoms at the
# berth origin MINUS 0.55 (the 1.1 m belly box), and the pier head's
# deck top rides at walk + 1.125 (the head origin lift 0.85 + its
# plate at +0.15 with half-thickness 0.125) -- so the lift must stay
# at or past 1.675 + a walking margin (the old 1.7 left 2.5 cm: the
# berthed hull clipped the boards at every wave of the walk law).
const PIER_BERTH_LIFT: float = 2.0

# The pans moor (the far end's berth, v12): the runner ties off at
# the mooring flank in the shallows -- beached lightly, keel just at
# the bank line.
const PAN_MOOR_LIFT: float = 0.9


## Route dirs (precomputed once): [pier_dir, pans_moor_dir].
static func lane_dirs() -> Array:
	var cap_dir: Vector3 = TerrainGen.capitol_plaza_dir()
	var spawn_dir: Vector3 = TerrainGen.SPAWN_CENTER
	var south_axis: Vector3 = cap_dir.cross(spawn_dir).normalized()
	var pier_dir: Vector3 = cap_dir
	for _s in range(CAPITOL_PIER_STEPS):
		pier_dir = pier_dir.rotated(south_axis, CapitolMonolith.CAPITOL_FLAT_OUT_STEP).normalized()
	var pans_dir: Vector3 = TerrainGen.sun_pans_dir().normalized()
	var pans_south: Vector3 = spawn_dir.cross(pans_dir).normalized()
	var pans_moor: Vector3 = pans_dir.rotated(pans_south, PAN_MOOR_STEP).normalized()
	return [pier_dir.normalized(), pans_moor.normalized()]


static func build(parent: Node3D, planet_radius: float, surface_lift: float,
		walk_surface_h: Callable, sea_level: float) -> Node3D:
	var lane: Array = lane_dirs()
	var vessel := Node3D.new()
	vessel.name = "PansRunner"
	parent.add_child(vessel)
	# The lane lives on the vessel so place() needs no recompute
	# (importantly: the walk callable is stored too -- the tick law
	# calls place with no extra plumbing).
	vessel.set_meta("lane_a", lane[0])
	vessel.set_meta("lane_b", lane[1])
	vessel.set_meta("radius", planet_radius)
	vessel.set_meta("surface_lift", surface_lift)
	vessel.set_meta("sea", sea_level)
	vessel.set_meta("walk", walk_surface_h)

	# THE HULL: a lean lateen runner in the box dialect -- flat
	# belly + rising bow/stern prisms + deck panels + hold tent.
	_box(vessel, Vector3(0, 0.0, 0), Vector3(3.2, 1.1, 9.0), _HULL)
	_prism(vessel, Vector3(0, 0.55, 5.1), Vector3(3.0, 1.4, 2.2), _HULL)  # the bow
	_prism(vessel, Vector3(0, 0.55, -5.1), Vector3(3.0, 1.4, 2.0), _HULL)  # the stern
	_box(vessel, Vector3(0, 0.85, 0), Vector3(3.0, 0.18, 9.6), _DECK)
	_box(vessel, Vector3(0, 1.8, -1.6), Vector3(2.6, 1.5, 3.4), _CANVAS)  # the hold tent
	_box(vessel, Vector3(0, 3.8, 0.4), Vector3(0.16, 6.4, 0.16), _MAST)  # the mast
	# THE LATEEN RIG: the long spar canted off vertical; the canvas a
	# slim panel flying under the spar.
	var yard := Node3D.new()
	yard.name = "LateenYard"
	yard.position = Vector3(0, 5.6, 0.4)
	yard.rotation_degrees = Vector3(0.0, 0.0, 35.0)
	vessel.add_child(yard)
	_box(yard, Vector3(0, -1.6, 0.0), Vector3(0.12, 7.2, 0.12), _MAST)
	_box(yard, Vector3(0, -3.2, 0.0), Vector3(0.06, 3.2, 6.4), _CANVAS)
	# THE STERN LANTERN: the Concord marker light (the crossing is
	# honest water time; the light is what the beach watches for).
	var lamp := MeshInstance3D.new()
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.16
	lamp_mesh.height = 0.32
	lamp.mesh = lamp_mesh
	lamp.material_override = _LANTERN
	lamp.position = Vector3(0, 1.7, -5.4)
	vessel.add_child(lamp)

	# THE BERTH COLLIDER: the moored boat is a dock face walk-up
	# (board the pier head onto the deck); the whole vessel carries
	# one belt (the walk/climb law attaches at boot, in-tree).
	PropCollider.attach(vessel)

	place(vessel, 0.0)
	return vessel


## RIDE LAW: t in [0, 1] walks the lane pier -> pans. At sea the hull
## floats on the sea line; at the pier end it rides the berth lift.
static func place(vessel: Node3D, t: float) -> void:
	var walk_surface_h: Callable = vessel.get_meta("walk")
	var lane_a: Vector3 = vessel.get_meta("lane_a")
	var lane_b: Vector3 = vessel.get_meta("lane_b")
	var radius: float = float(vessel.get_meta("radius"))
	var surface_lift: float = float(vessel.get_meta("surface_lift"))
	var sea: float = float(vessel.get_meta("sea"))
	# THE LANE: spherical slerp pier -> pans (the arc the ferry runs).
	var dir: Vector3 = lane_a.slerp(lane_b, clampf(t, 0.0, 1.0)).normalized()
	# THE LIFT LAW: the hull floats at the SEA line (never the seabed);
	# at the pier start the berth rides the pier berth lift.
	var walk: float = float(walk_surface_h.call(dir))
	var lift_extra: float = FLOAT_LIFT
	if t <= 0.02:
		lift_extra = PIER_BERTH_LIFT
	elif t >= 0.98:
		lift_extra = PAN_MOOR_LIFT
	var r: float = radius + surface_lift + maxf(walk, sea) + lift_extra
	vessel.position = dir * r
	# THE FRAME: up = radial; the bay model's forward (+Z, where the
	# bow prism sits) points along the travel tangent -- the projection
	# of the pans leg onto the plane orthogonal to up (the slerp's own
	# tangent at this point).
	var up: Vector3 = dir
	var tangent: Vector3 = (lane_b - up * lane_b.dot(up))
	if tangent.length() < 0.001:
		return
	tangent = tangent.normalized()
	var side: Vector3 = up.cross(tangent).normalized()
	vessel.basis = Basis(side, up, tangent)


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


# The painted runner: dark tar hull, pale deck, weathered canvas,
# tall timber spars, and the Concord lantern light (emissive).
static var _HULL: StandardMaterial3D = _make_mat(Color(0.30, 0.20, 0.14), 0.9)
static var _DECK: StandardMaterial3D = _make_mat(Color(0.55, 0.42, 0.28), 0.85)
static var _CANVAS: StandardMaterial3D = _make_mat(Color(0.84, 0.80, 0.68), 0.95)
static var _MAST: StandardMaterial3D = _make_mat(Color(0.42, 0.30, 0.18), 0.85)
static var _LANTERN: StandardMaterial3D = _make_lantern()


static func _make_mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _make_lantern() -> StandardMaterial3D:
	var m := _make_mat(Color(1.0, 0.75, 0.35), 0.4)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.62, 0.20)
	m.emission_energy_multiplier = 1.6
	return m
