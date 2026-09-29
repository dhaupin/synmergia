## ParentSky -- the home world hanging in an orbiting child's sky
## (S16.4, labs/prd-multiworld.md sec 4 "the destination planet IS the
## sky you approach", sec 2 "the moon as a clock you can read").
##
## NOT a skybox, NOT a simulation: the disc's direction is
## WorldRegistry.parent_sky_direction -- the closed-form synodic
## angle evaluated on the Concord epoch every frame. On a tidally
## locked child (spin_period_days <= 0, the moon's condition) the
## vector is CONSTANT: home hangs over one meridian forever, and
## where your base lands decides whether Earth ever rises. The disc
## keeps ONE size and brightness always -- a circular orbit keeps
## constant distance, so the sky keeps its promise.
##
## Angular size is exact: the disc radius is
##   sky_distance * tan(asin(parent_radius / orbit_radius))
## (our lattice: a 20 km Earth seen from a 90 km moon spans ~26
## degrees of sky -- real Luna's Earth gets 2; our universe is
## bigger-hearted).
##
## Consumed by the moon globe when it boots (S16.6 dev target);
## probes drive it directly. Tabs, no class_name, ASCII only.
extends Node3D

const WorldRegistry = preload("res://core/frame/srv/world_registry.gd")

## Which orbiting world's sky this is (the child; its parent renders).
@export var world_id: String = "moon"
## Render distance of the sky disc (meters). Far enough to sit behind
## every terrain LOD; the radius compensates exactly.
@export var sky_distance: float = 8000.0

var _disc: MeshInstance3D = null
var _logged: bool = false


func _ready() -> void:
	_build_disc()


func _process(_delta: float) -> void:
	var epoch: float = _epoch_days()
	var child = _child_data()
	if child == null:
		_disc.visible = false
		return
	var dir := WorldRegistry.parent_sky_direction(child, epoch)
	if dir == Vector3.ZERO:
		# Not an orbiting body: no parent in the sky at all.
		_disc.visible = false
		return
	_disc.visible = true
	_disc.position = dir * sky_distance
	_disc.look_at_from_position(_disc.position, Vector3.ZERO, Vector3.UP)
	if not _logged:
		_logged = true
		var beat: float = WorldRegistry.parent_beat_period_days(child)
		if beat < 0.0:
			GameLog.info("ParentSky: %s is tidally locked -- home hangs over one meridian" % world_id)
		else:
			GameLog.info("ParentSky: %s sees home rise every %.2f sky days" % [world_id, beat])


## The Concord epoch (override-aware). Falls back to the same
## definition when SignService is absent (deep script mode).
func _epoch_days() -> float:
	var svc = get_node_or_null("/root/SignService")
	if svc != null and svc.has_method("sky_epoch_days"):
		return svc.sky_epoch_days()
	return float(Time.get_unix_time_from_system()) / 86400.0


func _child_data():
	var scope = get_node_or_null("/root/ScopeService")
	if scope != null and scope.has_method("world_data"):
		return scope.world_data(world_id)
	# Deep script mode: read the lattice directly.
	var reg = WorldRegistry.new()
	reg.load_worlds()
	return reg.get_world(world_id)


## The disc: the parent's silhouette at exact angular size.
func _build_disc() -> void:
	if get_node_or_null("ParentDisc") != null:
		_disc = get_node_or_null("ParentDisc") as MeshInstance3D
		return
	var child = _child_data()
	var parent = null
	if child != null:
		var scope = get_node_or_null("/root/ScopeService")
		var pid: String = str(child.parent_world)
		if scope != null and scope.has_method("world_data"):
			parent = scope.world_data(pid)
	var r_child: float = float(child.radius_m) if child != null else 1200.0
	var r_orbit: float = float(child.orbit_radius_m) if child != null else 90000.0
	var r_parent: float = float(parent.radius_m) if parent != null else 20000.0
	# Exact angular radius of the parent from the child's surface,
	# projected to the render distance.
	var ang: float = asin(clampf(r_parent / maxf(r_orbit, 0.001), 0.0, 0.9999))
	var disc_r: float = sky_distance * tan(ang)
	var mesh := SphereMesh.new()
	mesh.radius = disc_r
	mesh.height = disc_r * 2.0
	mesh.radial_segments = 48
	mesh.rings = 24
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.52, 0.78, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.22, 0.34, 0.55, 1.0)
	mat.emission_energy_multiplier = 1.1
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	mesh.material = mat
	_disc = MeshInstance3D.new()
	_disc.name = "ParentDisc"
	_disc.mesh = mesh
	# Rendered as sky: no shadows, no collision.
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)
	_disc.visible = false
