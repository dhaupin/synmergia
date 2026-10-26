## HarborLights - the coast's answer to the ferry lantern (S14.8's
## two-end light law). The v11 stern lantern settled the BOAT's light;
## the beach never gave the sailor one. This builder stands the two
## landings' lights:
##
##   - build_pier_beacon(): a stone column + caged amber lamp beside
##     the capitol pier head (a flank step off the pier dir, the same
##     south-axis dialect the pans moor uses) -- the sailor reads it
##     from the dark sea;
##   - build_moor_guide(): a flat guide stone at the pans moor flank,
##     an amber ember panel carved into its face -- the far country
##     lights its own sand.
##
## THE NIGHT LAW: both lamps ride the CONCORD SKY CLOCK (the same
## epoch the ferry's closed form reads) -- lit from DUSK_H (18.0) to
## DAWN_H (6.0) sky hours, dark to the sun. One derivation, any
## caller: the globe's ferry tick calls place_night() every second
## with the epoch it already holds. RefCounted builder (static
## build_*), no autoload, no class_name.
extends RefCounted

const PropCollider = preload("res://entities/prop_collider.gd")

# The night band on the Concord day (hours 0..24). The lamp wakes at
# the dusk boundary itself and sleeps at the dawn one (>= DUSK_H OR
# < DAWN_H) -- the same boundary-honesty the ferry's boarding window
# rides.
const DUSK_H: float = 18.0
const DAWN_H: float = 6.0

# The flank beat: the lights stand one south-axis step off their
# berth dirs (two laws, one beat -- the pans moor flank's tool).
const BEACON_FLANK_STEP: float = 0.004

# Heights: the beacon column rises so the SUN-lit band is visible
# from a boat (the lamp sits at ~5.2 m); the guide stone stays low
# (the moor bank is the sand's own light, not a mast).
const BEACON_TOTAL_H: float = 6.4
const GUIDE_TOTAL_H: float = 1.8


## Route dirs come from the vessel law's ONE derivation (lane_dirs)
## so the lights, the boat and the arrival pins share their worlds.
static func _flank(dir: Vector3, spawn_dir: Vector3, sign: float) -> Vector3:
	var south_axis: Vector3 = dir.cross(spawn_dir).normalized()
	return dir.rotated(south_axis, BEACON_FLANK_STEP * sign).normalized()


## THE PIER BEACON: a stone column beside the pier head. The lamp
## material is carried on the returned node's meta ("lamp") so
## place_night() needs no re-derivation.
static func build_pier_beacon(parent: Node3D, planet_radius: float, surface_lift: float,
		walk_surface_h: Callable, pier_dir: Vector3, sea_level: float) -> Node3D:
	var spawn_dir: Vector3 = Vector3(0, 1, 0)
	var dir: Vector3 = _flank(pier_dir.normalized(), spawn_dir, 1.0)
	var node := Node3D.new()
	node.name = "PierBeacon"
	parent.add_child(node)
	node.set_meta("walk", walk_surface_h)
	node.set_meta("dir", dir)
	node.set_meta("radius", planet_radius)
	node.set_meta("surface_lift", surface_lift)
	node.set_meta("sea", sea_level)
	var walk: float = float(walk_surface_h.call(dir))
	# THE SEA CLAMP (the vessel law): a light may stand IN the
	# shallows, never UNDER them -- the base reads max(walk, sea).
	var base_r: float = planet_radius + surface_lift + maxf(walk, sea_level)
	node.position = dir * base_r
	_set_tangent_frame(node, dir, spawn_dir)
	# THE COLUMN: stone shaft + door void + the caged lamp head --
	# grey-green stone, a gold finial (the art law: gold = active only,
	# so the metal CAP glows with the lamp band, never the stone).
	_box(node, Vector3(0, 1.2, 0), Vector3(1.7, 2.4, 1.7), _STONE)
	_box(node, Vector3(0, 3.2, 0), Vector3(0.55, 1.6, 0.55), _STONE)
	# THE CAGE: four slim posts + cap plate + the amber lamp under it.
	for corner in [Vector3(1.0, 4.0, 1.0), Vector3(-1.0, 4.0, 1.0), Vector3(1.0, 4.0, -1.0), Vector3(-1.0, 4.0, -1.0)]:
		_box(node, corner + Vector3(0, 0.4, 0), Vector3(0.14, 0.8, 0.14), _STONE)
	_box(node, Vector3(0, 4.85, 0), Vector3(2.3, 0.15, 2.3), _FINIAL)
	var lamp := _lamp(node, Vector3(0, 4.35, 0), 0.34)
	node.set_meta("lamp", lamp.material_override)
	PropCollider.attach(node)
	return node


## THE MOOR GUIDE: a flat stone at the pans moor flank, the warm ember
## panel carved on the seaward face.
static func build_moor_guide(parent: Node3D, planet_radius: float, surface_lift: float,
		walk_surface_h: Callable, moor_dir: Vector3, sea_level: float) -> Node3D:
	var spawn_dir: Vector3 = Vector3(0, 1, 0)
	var dir: Vector3 = _flank(moor_dir.normalized(), spawn_dir, -1.0)
	var node := Node3D.new()
	node.name = "MoorGuide"
	parent.add_child(node)
	node.set_meta("walk", walk_surface_h)
	node.set_meta("dir", dir)
	node.set_meta("radius", planet_radius)
	node.set_meta("surface_lift", surface_lift)
	node.set_meta("sea", sea_level)
	var walk: float = float(walk_surface_h.call(dir))
	var base_r: float = planet_radius + surface_lift + maxf(walk, sea_level)
	node.position = dir * base_r
	_set_tangent_frame(node, dir, spawn_dir)
	_box(node, Vector3(0, 0.7, 0), Vector3(2.2, 1.4, 0.8), _STONE)
	# THE EMBER PANEL: the amber face plate (a stone inset, not a
	# flame -- the engine-ban dialect keeps wind and water honest).
	var ember := _lamp(node, Vector3(0, 0.7, 0.45), 0.0)
	var ember_mat: Material = ember.material_override
	_box(node, Vector3(0, 0.7, 0.35), Vector3(0.9, 0.8, 0.12), ember_mat)
	_box(node, Vector3(0, 1.55, -0.1), Vector3(1.2, 0.15, 0.9), _FINIAL)
	node.set_meta("lamp", ember_mat)
	PropCollider.attach(node)
	return node


## THE NIGHT LAW: lit from dusk (18.0) through dawn (6.0), dark to
## the sun. Pure -- the caller carries the epoch; the globe's ferry
## tick passes the epoch it already holds, so the lights and the
## berth clock share one sky.
static func place_night(node: Node3D, epoch_days: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not node.has_meta("lamp"):
		return
	var hour: float = fposmod(epoch_days, 1.0) * 24.0
	set_lit(node, hour >= DUSK_H or hour < DAWN_H)


## The lamp flip: emission ON/OFF on the carried material (the truth
## the lamp mesh renders). The door-void stays stone; the metal cap
## is static.
static func set_lit(node: Node3D, lit: bool) -> void:
	var mat = node.get_meta("lamp")
	if mat == null or not is_instance_valid(mat):
		return
	mat.emission_enabled = lit


## The tangent frame: up = radial, forward = the projection of the
## spawn direction onto the tangent plane (any light is symmetric
## about its mast, so ONE honest frame serves both lands) -- the
## vessel law's own shape: Basis(side, up, forward).
static func _set_tangent_frame(node: Node3D, dir: Vector3, spawn_hint: Vector3) -> void:
	var up: Vector3 = dir
	var fwd: Vector3 = (spawn_hint - up * spawn_hint.dot(up))
	if fwd.length_squared() < 0.0001:
		return
	fwd = fwd.normalized()
	var east: Vector3 = up.cross(fwd).normalized()
	node.basis = Basis(east, up, fwd)


static func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	if mat != null:
		mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _lamp(parent: Node3D, pos: Vector3, radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = maxf(radius, 0.2)
	mesh.height = mesh.radius * 2.0
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _LAMP
	parent.add_child(mi)
	return mi


# The painted night: grey-green stone, gold finial caps, and the amber
# lamp law the ferry lantern already set.
static var _STONE: StandardMaterial3D = _make_mat(Color(0.42, 0.48, 0.45), 0.95)
static var _FINIAL: StandardMaterial3D = _make_mat(Color(0.85, 0.70, 0.30), 0.5)
static var _LAMP: StandardMaterial3D = _make_lamp()


static func _make_mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _make_lamp() -> StandardMaterial3D:
	var m := _make_mat(Color(1.0, 0.75, 0.35), 0.4)
	# DARK at build time by law (the dawn build is not a lit lamp --
	# the NIGHT LAW owns the flip, not the builder).
	m.emission_enabled = false
	return m
