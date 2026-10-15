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

	## THE CITY QUARTERS (turn 15, the placeholder-builds law): six
	## authored buildings ringing the plaza (the capitol reads as a
	## town; the monolith still crowns it). Each rides its own dir
	## (small tangent beats around the strand anchor) lifted by the
	## SAME walk-law frame.
	var cap_dir: Vector3 = TerrainGen.capitol_plaza_dir()
	var spawn_dir: Vector3 = TerrainGen.SPAWN_CENTER
	var north_axis: Vector3 = spawn_dir.cross(cap_dir).normalized()
	var south_axis: Vector3 = cap_dir.cross(spawn_dir).normalized()
	var beats: Array = [
		["ConcordHall", north_axis, 0.010],
		["WestHouse", north_axis.rotated(cap_dir, 0.5), 0.011],
		["EastHouse", north_axis.rotated(cap_dir, -0.5), 0.011],
		["SouthHouse", south_axis, 0.010],
	]
	for beat in beats:
		var bdir: Vector3 = cap_dir.rotated(beat[1], beat[2]).normalized()
		var blift: float = surface_lift + float(walk_surface_h.call(bdir))
		_quarter(capitol, bdir * (planet_radius + blift), bdir, str(beat[0]),
			planet_radius)
	## THE CAPITOL PIER (the ferry system's city end): a timber pier
	## extending from the city's seaward rim over the cove water --
	## the dock where the urban ferry calls. Rotating cap_dir around
	## the south axis by +steps lands the planks OUT toward the bay
	## (away from spawn); each plank rides its own dir's walk lift +
	## a deck raise, so the boards run level over the water band.
	var sea_axis_k: Vector3 = south_axis
	var pier_tip: Vector3 = cap_dir
	for step in range(6):
		var step_ang: float = CAPITOL_FLAT_OUT_STEP * float(step + 1)
		var pdir: Vector3 = cap_dir.rotated(sea_axis_k, step_ang).normalized()
		pier_tip = pdir
		var plift: float = surface_lift + float(walk_surface_h.call(pdir))
		_pier_plank(capitol, pdir * (planet_radius + plift), pdir)
	_pier_head(capitol, pier_tip, planet_radius + surface_lift \
		+ float(walk_surface_h.call(pier_tip)) + 0.85)

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


## Deferred in-tree attach: PropCollider only reads transforms
## inside the tree, so the city quarters carry their body the frame
## after the deferred add lands (the same warning the probe caught).
static func _attach_collider(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	PropCollider.attach(node)


## One capitol quarter: a plain authored building at a world-space
## anchor (already computed by the caller from its own dir + walk
## lift). Stone walls, timber roof, a door -- same placeholder
## dialect the starter village carries.
static func _quarter(capitol: Node3D, anchor: Vector3, dir: Vector3,
		qname: String, _planet_radius: float) -> void:
	var b := Node3D.new()
	b.name = qname
	b.position = anchor
	# Radial frame: up = the dir, tangent stays the authored axes.
	var east: Vector3 = Vector3(0, 1, 0).cross(dir).normalized()
	var up: Vector3 = dir
	var z_axis: Vector3 = east.cross(up).normalized()
	b.basis = Basis(east, up, z_axis)
	_box(b, Vector3(0, 1.7, 0), Vector3(5.2, 3.4, 4.6), _STONE)
	_prism(b, Vector3(0, 4.3, 0), Vector3(6.2, 2.0, 5.6), _BRONZE)
	_box(b, Vector3(0, 1.1, 2.4), Vector3(1.3, 2.2, 0.3), _TIMBER)
	# THE IN-TREE COLLIDER LAW: PropCollider.attach reads
	# get_global_transform (an in-tree read); attach the body AFTER
	# the whole structure is inside the tree (deferred aliases into
	# the boot frame), not while the capitol root is still detached --
	# the out-of-tree read spams the engine warning every boot.
	capitol.add_child.call_deferred(b)
	_attach_collider.call_deferred(b)


## One pier plank: a timber board over the bay at its own dir (world
## anchor precomputed by the caller), aligned radial-up.
static func _pier_plank(capitol: Node3D, anchor: Vector3, dir: Vector3) -> void:
	var plank := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.2, 0.18, 3.6)
	plank.mesh = mesh
	plank.material_override = _TIMBER
	plank.position = anchor + dir * 0.95
	# Radial-up frame so the board lies flat on the bay.
	var east: Vector3 = Vector3(0, 1, 0).cross(dir).normalized()
	var up: Vector3 = dir
	var z_axis: Vector3 = east.cross(up).normalized()
	plank.basis = Basis(east, up, z_axis)
	capitol.add_child(plank)
	# Bracing: two legs tick down into the water band.
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.18, 2.4, 0.18)
		leg.mesh = leg_mesh
		leg.material_override = _TIMBER
		# Legs hang DOWN-radial from the deck.
		leg.position = plank.position + east * side - up * 1.45
		leg.basis = Basis(east, up, z_axis)
		capitol.add_child(leg)


## The pier head: the dock's landing pad (the ferry berth).
static func _pier_head(capitol: Node3D, dir: Vector3, _lift: float) -> void:
	var pad: Vector3 = dir * _lift
	var head := Node3D.new()
	head.name = "CapitolPierHead"
	head.position = pad
	var east: Vector3 = Vector3(0, 1, 0).cross(dir).normalized()
	var up: Vector3 = dir
	var z_axis: Vector3 = east.cross(up).normalized()
	head.basis = Basis(east, up, z_axis)
	_box(head, Vector3(0, 0.15, 0), Vector3(3.4, 0.25, 4.2), _TIMBER)
	# Mooring posts.
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var post_mesh := CylinderMesh.new()
		post_mesh.top_radius = 0.08
		post_mesh.bottom_radius = 0.10
		post_mesh.height = 1.6
		post.mesh = post_mesh
		post.material_override = _TIMBER
		post.position = Vector3(side * 1.4, 1.05, 1.6)
		head.add_child(post)
	# THE IN-TREE COLLIDER LAW (the quarters' same law): attach after
	# the deferred add lands, never while the capitol root is detached.
	capitol.add_child.call_deferred(head)
	_attach_collider.call_deferred(head)


## The capitol palette: deep mountain stone, a dark seam-cut monolith
## face, bronze banding (the Concord's marker metal -- the same tint
## family the signs read). Plain colors; the terrain laws own the
## view budget.
## The city beat constants: the pier steps ~120 m each seaward.
const CAPITOL_FLAT_OUT_STEP: float = 0.006
static var _STONE: StandardMaterial3D = _make_mat(Color(0.58, 0.56, 0.52))
static var _MONO: StandardMaterial3D = _make_mat(Color(0.34, 0.35, 0.38))
static var _BRONZE: StandardMaterial3D = _make_mat(Color(0.60, 0.42, 0.22))
static var _TIMBER: StandardMaterial3D = _make_mat(Color(0.40, 0.27, 0.16))


static func _make_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m
