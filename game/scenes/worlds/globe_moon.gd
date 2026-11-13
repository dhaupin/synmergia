## GlobeMoon -- the S16.6 dev-target moon (labs/prd-multiworld.md
## sec 4, sec 7). CONJURED ON DEMAND: the moon exists because someone
## chose to go -- the Moon Gate conjures this globe as the
## destination root at transit time, and it tears down when the last
## visitor leaves. Nothing runs on the main world for the moon's
## sake; the world stays clean (the owner's flip order: "get all our
## stuff on the moon lol, so the world is clean").
##
## The globe is the sphere pattern at lunar scale (radius 1.2 km from
## world_moon.tres (a small terrain globe; the planar prototype is gone)
## collider IS the physics truth -- no surface pad needed). The
## visitor's body is a globe_player bound to "moon": the 6 m/s^2 law
## adopts from WorldData (S16.4), the wing stays stowed (no
## atmosphere), and ParentSky hangs Earth over the locked meridian.
## A return Moon Gate stands at the landing site.
##
## The registrar marks the group "world_root_moon" (the gate's
## _destination_root resolves it) and remembers its own id so
## ScopeService bookkeeping can find it. Regolith-grey, quiet, and
## honest: terrain is the plain shell -- no content yet, by design
## (the moon is pristine mystery; prd open question 2 stays open).
##
## Tabs, no class_name, ASCII only; autoloads resolved lazily.
extends Node3D

const WORLD_ID: String = "moon"
const PLAYER_SKIN: float = 1.0

const WorldRegistryScript = preload("res://core/frame/srv/world_registry.gd")
const ClipmapScript = preload("res://scenes/worlds/globe_clipmap.gd")
const MoonProviderScript = preload("res://scenes/worlds/moon_provider.gd")
const SurfacePadScript = preload("res://core/world/surface_pad.gd")

## The draw lift (mirrors globe_clipmap.TILE_LIFT): the clipmap sits this
## far above the base radius, so the pad origin rides radius + lift + terrain.
const TILE_LIFT: float = 0.52

var world_root: Node3D
var planet_center: Vector3 = Vector3.ZERO
var planet_radius: float = 1200.0
var player  # globe_player body; untyped (set_script pattern)

var _provider = null            # MoonProvider: the ground law
var _clipmap = null             # GlobeClipmap: the drawn terrain
var _pad = null                 # SurfacePad: the terrain-conforming collider
var _return_gate: Node3D = null
var _parent_sky: Node3D = null
var _visitors: Dictionary = {}


func _ready() -> void:
	# The moon's own declaration is the law; never a hard-coded scale.
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
	_build_regolith()
	_build_terrain()
	_build_crater_pool()
	_build_landing_gate()
	_build_earthrise()
	GameLog.info("GlobeMoon: conjured (dev target; radius %.0f m, the earthrise meridian waits)" % planet_radius)## Bring a visitor across. Called by the Moon Gate AFTER ScopeService
## accepted the swap; adopts the body into lunar physics and places
## it on the surface at the landing site. Idempotent per body.
## Bodies from the planar main world (the player body) get the
## world_id (the gravity/vacuum laws read it) and a radial-landing
## transform; globe bodies additionally get the planet references.
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
	# Land at the site: one radius up from the center, tilted toward
	# the meridian the locked sky promises (home frames the view).
	var dir: Vector3 = _provider.landing_dir() if _provider != null else Vector3(0, 1, 0)
	var land_h: float = float(_provider.walk_height(dir)) if _provider != null else 0.0
	body.global_position = world_root.global_position + dir * (planet_radius + TILE_LIFT + land_h + PLAYER_SKIN + 0.2)
	if "velocity" in body:
		body.set("velocity", Vector3.ZERO)


## The last visitor leaving tears the globe down: the moon exists
## while it is watched (and re-derives identically on the next
## transit -- the seed never forgot).
func release_visitor(body: Node) -> void:
	if body == null:
		return
	var pid: String = str(body.get("entity_id"))
	if pid != "":
		_visitors.erase(pid)
	if _visitors.is_empty():
		GameLog.info("GlobeMoon: last visitor gone -- the pale stone folds back into derivation")
		if _clipmap != null and _clipmap.has_method("async_shutdown"):
			_clipmap.async_shutdown()
		queue_free()


func _track_visitor(body: Node) -> void:
	if not body.has_signal("tree_exiting"):
		return
	if body.is_connected("tree_exiting", _on_visitor_leaving):
		return
	body.tree_exiting.connect(_on_visitor_leaving.bind(body))


func _on_visitor_leaving(body: Node) -> void:
	release_visitor(body)


## The regolith shell: grey, friction-true, collider ON (1.2 km sits
## far below the planar-shell stall threshold).
func _build_regolith() -> void:
	var shell := StaticBody3D.new()
	shell.name = "MoonShell"
	shell.physics_material_override = PhysicsMaterial.new()
	shell.physics_material_override.friction = 1.0
	shell.physics_material_override.bounce = 0.0
	# The drawn terrain is the clipmap now, so the base sphere is a hidden
	# backstop only (the terrain-conforming pad is the physics truth, the
	# globe_world law). The visible shell would read as a second ground.
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = planet_radius
	col.shape = sphere
	col.disabled = true
	shell.add_child(col)
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = planet_radius + 0.5
	mesh.height = (planet_radius + 0.5) * 2.0
	mesh.radial_segments = 96
	mesh.rings = 48
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.62, 0.64)
	mat.roughness = 1.0
	mesh.material = mat
	mi.mesh = mesh
	mi.name = "ShellVisual"
	mi.visible = false
	shell.add_child(mi)
	world_root.add_child(shell)


## THE TERRAIN (labs/prd-clipmap.md 10): the SAME clipmap renderer that
## draws the main world now draws the moon, backed by MoonProvider. Real
## heightfield + props, and a terrain-conforming collider under the body.
func _build_terrain() -> void:
	_provider = MoonProviderScript.new()
	_clipmap = ClipmapScript.new()
	_clipmap.configure(planet_radius, 7.0, world_root, _provider)
	_clipmap.terrain_on = true
	_clipmap.build_all()
	_pad = SurfacePadScript.new()
	_pad.build(world_root, _provider, planet_radius, TILE_LIFT)


## THE BUILDER'S POOL (S16.6): the crater the moon DECLARES
## (data/oceans/ocean_lunar_crater.tres) is now a real dish -- a dark
## water disc at the declared surface height, riding the provider's carved
## bowl. The water physics stay in the ocean volume (floor_is_radial =
## false, a LOCAL pool); this builds the STONE and the visible water.
func _build_crater_pool() -> void:
	if _provider == null:
		return
	var jug := Node3D.new()
	jug.name = "BuilderPool"
	world_root.add_child(jug)
	var dir: Vector3 = _provider.crater_dir()
	var water_y: float = _provider.crater_water_y()
	var rim_r: float = 40.0
	# The water disc: a translucent shell at the declared surface height,
	# seated at the crater's radial position (planet-relative).
	var water := MeshInstance3D.new()
	var wmesh := CylinderMesh.new()
	wmesh.top_radius = rim_r * 0.94
	wmesh.bottom_radius = rim_r * 0.94
	wmesh.height = 0.3
	water.mesh = wmesh
	water.name = "CraterWater"
	water.position = dir * water_y
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wmat := StandardMaterial3D.new()
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.albedo_color = Color(0.35, 0.40, 0.50, 0.72)
	wmat.roughness = 0.2
	wmat.metallic = 0.1
	wmesh.material = wmat
	# Lay the disc flat in the crater plane (its local +Y points up along dir).
	var up: Vector3 = dir
	var hint := Vector3(0, 1, 0)
	if absf(up.dot(hint)) > 0.999:
		hint = Vector3(0, 0, -1)
	var east: Vector3 = (hint - up * hint.dot(up)).normalized()
	var north: Vector3 = east.cross(up)
	water.basis = Basis(east, up, north)
	jug.add_child(water)
	GameLog.info("GlobeMoon: the Builder's Pool is built (%.0f m dish, water at %.1f m)" % [rim_r, water_y])


## The ride home: a return Moon Gate at the landing site naming main.
## It stands UNDER the world root so it frees with the globe.
func _build_landing_gate() -> void:
	var gate_script: GDScript = load("res://entities/moon_gate.gd")
	if gate_script == null:
		return
	_return_gate = gate_script.new()
	_return_gate.name = "ReturnGate"
	_return_gate.set("target_world", "main")
	_return_gate.set("display_name", "Earthward Gate")
	# The ride home obeys the same sky law (a window opens both ways
	# -- phase alignment is symmetric in the relation). The return
	# gate carries the hatch too: the dev crew never gets stranded
	# behind an unfavorable sky on the moon the dev work lives on.
	_return_gate.set("window_law", true)
	_return_gate.set("dev_hatch", true)
	# Stand the gate on the landing flat (the provider's landing site), one
	# radius up so it rests on the drawn surface, not inside the shell.
	var ldir: Vector3 = _provider.landing_dir() if _provider != null else Vector3(0, 1, 0)
	var lh: float = float(_provider.walk_height(ldir)) if _provider != null else 0.0
	_return_gate.position = ldir * (planet_radius + TILE_LIFT + lh + 0.2)
	world_root.add_child(_return_gate)
	# The main world's root is the boot scene itself; register the
	# group the gate's _destination_root looks for so the way home
	# resolves even on the conjured globe.
	var main_marker := Node3D.new()
	main_marker.name = "MainWorldMarker"
	main_marker.add_to_group("world_root_main")
	world_root.add_child(main_marker)


## Earthrise: home hangs over the locked meridian (S16.4 entity).
func _build_earthrise() -> void:
	var sky_script: GDScript = load("res://entities/parent_sky.gd")
	if sky_script == null:
		return
	_parent_sky = sky_script.new()
	_parent_sky.set("world_id", WORLD_ID)
	add_child(_parent_sky)


func _process(_delta: float) -> void:
	# Stream the terrain + keep the pad under the visitor (the clipmap's own
	# tick path -- the same one the main world rides).
	if _visitors.is_empty():
		return
	var body = _visitors.values()[0]
	if body == null or not is_instance_valid(body):
		return
	if _clipmap != null:
		_clipmap.update(body.global_position - world_root.global_position)
	if _pad != null:
		_pad.update(body.global_position, world_root.global_position)


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
