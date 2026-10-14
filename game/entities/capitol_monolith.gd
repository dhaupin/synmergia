## CapitolMonolith -- the authored capitol installation (the ledger's
## parked build: "the Capitol city monolith on the coast with the road
## connecting them"). The CONNECTING road already exists in the path
## law -- the cartway walks village harbor -> capitol plaza across the
## homeland, and the auto-walk arrival law reads the capitol anchor
## ring. This builder stands the MONOLITH the ring points at:
##
##   - placement rides `TerrainGen.capitol_plaza_dir()` (the far-coast
##     bearing at the harbor's own range), lifted by the SAME frame
##     every authored install rides (planet_radius + tile lift +
##     walk_surface_h);
##   - the megalith is plain authored boxes/prisms (stone + bronze)
##     with the one-law PropCollider belt (solid + climbable);
##   - the plaza bench ring reads the site's own radial gravity (the
##     up vector points INTO the planet), so benches sit like chairs.
##
## RefCounted builder (static build()), no autoload, no class_name.
extends RefCounted

const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
const PropCollider = preload("res://entities/prop_collider.gd")


static func build(parent: Node3D, planet_radius: float, surface_lift: float,
		walk_surface_h: Callable) -> Node3D:
	var capitol := Node3D.new()
	capitol.name = "CapitolMonolith"
	parent.add_child(capitol)

	var dir: Vector3 = TerrainGen.capitol_plaza_dir()
	var lift: float = surface_lift + float(walk_surface_h.call(dir))
	capitol.position = dir * (planet_radius + lift)
	# The celestial frame: up = radial (into the sky at the capitol);
	# the tangent frame stays north-west styled so the monolith faces
	# the harbor road's approach arc.
	var east: Vector3 = Vector3(0, 1, 0).cross(dir).normalized()
	var up: Vector3 = dir
	var zref: Vector3 = east.cross(up).normalized()
	capitol.basis = Basis(east, up, zref)

	## THE PLINTH: a broad stone step, the plaza's grazing bench.
	_box(capitol, Vector3(0, 0.35, 0), Vector3(7.0, 0.7, 7.0), _STONE)
	## THE SHAFT: the monolith itself -- a tall seamed block rising
	## 14 m off the plaza, its faces reading the carved band rows.
	_box(capitol, Vector3(0, 6.8, 0), Vector3(2.6, 12.6, 2.6), _MONO)
	for row in range(3):
		_box(capitol, Vector3(0, 2.4 + 3.4 * float(row), 0), \
			Vector3(2.7, 0.22, 2.7), _BRONZE)
	## THE CAPSTONE: a low prism crowning the shaft.
	_prism(capitol, Vector3(0, 13.9, 0), Vector3(3.4, 1.5, 3.4), _STONE)
	## THE PENNANT POLES: two flanking masts (the cart approach arcs
	## between them), each a slim pole with a small banner.
	for side in [-1.0, 1.0]:
		_pole(capitol, Vector3(side * 4.6, 2.0, 2.2))
		_box(capitol, Vector3(side * 4.6, 3.2, 2.2), Vector3(0.9, 0.7, 0.05), _BRONZE)
	## THE BENCH RING: four plaza stools facing the monolith (the
	## concord audience) -- small blocks at the plinth's edge.
	for k in range(4):
		var ang: float = TAU * float(k) / 4.0 + PI / 4.0
		_box(capitol, Vector3(cos(ang) * 4.4, 0.6, sin(ang) * 4.4),
			Vector3(0.9, 0.55, 0.9), _STONE)

	PropCollider.attach(capitol)
	return capitol


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


static func _pole(parent: Node3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.07
	mesh.bottom_radius = 0.09
	mesh.height = 4.2
	mi.mesh = mesh
	mi.material_override = _TIMBER
	mi.position = pos
	parent.add_child(mi)


## The capitol palette: deep mountain stone, a dark seam-cut monolith
## face, bronze banding (the Concord's marker metal -- the same tint
## family the signs read). Plain colors; the terrain laws own the
## view budget.
static var _STONE: StandardMaterial3D = _make_mat(Color(0.58, 0.56, 0.52))
static var _MONO: StandardMaterial3D = _make_mat(Color(0.34, 0.35, 0.38))
static var _BRONZE: StandardMaterial3D = _make_mat(Color(0.60, 0.42, 0.22))
static var _TIMBER: StandardMaterial3D = _make_mat(Color(0.40, 0.27, 0.16))


static func _make_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m
