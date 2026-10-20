## PansMonolith -- the Sun Pans waypoint's own installation (the flats'
## answer to the Capitol monolith: the far country's marker). The
## gateway pin (data/gateways/waypoint_sun_pans.tres) registers the
## walk-up law; this builder stands the ART the pin points at:
##
##   - placement rides `TerrainGen.sun_pans_dir()` (the atoll's own
##     bearing on its outer bank), lifted by the SAME frame every
##     authored install rides (planet_radius + tile lift +
##     walk_surface_h);
##   - the obelisk is plain authored boxes/prisms in a SUNBAKED
##     palette (pale sandstone + scorched bronze), the desert's
##     honest dialect;
##   - two mooring posts on the seaward flank mark the berth the
##     Pans Runner ties off at;
##   - the whole structure carries the one-law collider belt.
##
## RefCounted builder (static build()), no autoload, no class_name --
## the capitol build dialect (entities/capitol_monolith.gd).
extends RefCounted

const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
const PropCollider = preload("res://entities/prop_collider.gd")

# The moor beat: the berthing flank sits a step seaward of the
# obelisk's bank (small rotations around the south axis read the
# same tangent dialect the capitol pier steps use).
const PAN_MOOR_STEP: float = 0.004


static func build(parent: Node3D, planet_radius: float, surface_lift: float,
		walk_surface_h: Callable) -> Node3D:
	var pans := Node3D.new()
	pans.name = "PansMonolith"
	parent.add_child(pans)

	# THE OUTER BANK: the atoll's bearing itself (the beach ring band).
	var dir: Vector3 = TerrainGen.sun_pans_dir().normalized()
	var lift: float = surface_lift + float(walk_surface_h.call(dir))
	pans.position = dir * (planet_radius + lift)
	# The celestial frame: up = radial; the tangent frame is styled
	# north-west so the obelisk faces the approach sea (the bearing a
	# run from the capitol pier arrives on).
	var east: Vector3 = Vector3(0, 1, 0).cross(dir).normalized()
	var up: Vector3 = dir
	var zref: Vector3 = east.cross(up).normalized()
	pans.basis = Basis(east, up, zref)

	## THE PLINTH: a broad sun-baked step, half-sunk in the pan (the
	## climbing bank's first hold).
	_box(pans, Vector3(0, 0.5, 0), Vector3(6.4, 1.0, 6.4), _SAND)
	## THE OBELISK: the desert's own marker -- a tall tapered shaft,
	## 15 m, its band rows carved with the salt-wind cuts.
	_box(pans, Vector3(0, 8.2, 0), Vector3(2.2, 13.4, 2.2), _SANDCUT)
	for row in range(4):
		_box(pans, Vector3(0, 2.6 + 3.1 * float(row), 0), \
			Vector3(2.3, 0.20, 2.3), _SCORCH)
	## THE CAPSTONE: a low prism crowning the shaft (Concord capsule).
	_prism(pans, Vector3(0, 15.2, 0), Vector3(3.0, 1.3, 3.0), _BRONZE)
	## THE GUIDESTONES: two squat cairns flanking the approach arc
	## (the cartway's dyslexic cousins -- the pans is far country).
	for side in [-1.0, 1.0]:
		_box(pans, Vector3(side * 4.2, 0.75, 3.0), Vector3(1.1, 1.5, 1.1), _SAND)
		_pole(pans, Vector3(side * 4.2, 2.2, 3.0), 2.4)
		_box(pans, Vector3(side * 4.2, 2.9, 3.0), Vector3(0.7, 0.5, 0.05), _SCORCH)
	## THE MOORING FLANK: two heavy posts + a stone bitt on the
	## seaward side -- the Pans Runner's lines. The berthing dir is
	## the obelisk's bearing rotated a step seaward (PAN_MOOR_STEP)
	## around the same south axis the capitol pier walks.
	var south_axis: Vector3 = TerrainGen.SPAWN_CENTER.cross(dir).normalized()
	var moor_dir: Vector3 = dir.rotated(south_axis, PAN_MOOR_STEP).normalized()
	var moor_lift: float = surface_lift + float(walk_surface_h.call(moor_dir))
	var moor := Node3D.new()
	moor.name = "PansMoor"
	moor.position = moor_dir * (planet_radius + moor_lift)
	var med: Vector3 = Vector3(0, 1, 0).cross(moor_dir).normalized()
	moor.basis = Basis(med, moor_dir, med.cross(moor_dir).normalized())
	pans.add_child(moor)
	for side in [-1.0, 1.0]:
		_pole(moor, Vector3(side * 1.3, 1.0, 0), 2.6)
	_box(moor, Vector3(0, 0.4, 0), Vector3(2.0, 0.5, 2.0), _SAND)

	PropCollider.attach(pans)
	return pans


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


static func _pole(parent: Node3D, pos: Vector3, height: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.08
	mesh.bottom_radius = 0.10
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = _TIMBER
	mi.position = pos
	parent.add_child(mi)


## The sunbaked palette: pale bank sand, a wind-cut obelisk face,
## scorched banding, dry timber, and flake bronze (the Concord's
## marker metal -- the same tint family the capitol bands read).
static var _SAND: StandardMaterial3D = _make_mat(Color(0.78, 0.70, 0.52))
static var _SANDCUT: StandardMaterial3D = _make_mat(Color(0.72, 0.62, 0.44))
static var _SCORCH: StandardMaterial3D = _make_mat(Color(0.42, 0.34, 0.30))
static var _BRONZE: StandardMaterial3D = _make_mat(Color(0.60, 0.42, 0.22))
static var _TIMBER: StandardMaterial3D = _make_mat(Color(0.40, 0.27, 0.16))


static func _make_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m
