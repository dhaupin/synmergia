## SkyMoon -- the moon in Synmergia's sky (the one-way ownership
## closed: the moon globe already hangs Earth via parent_sky.gd; the
## main world now sees the pale stone back).
##
## NOT a simulation: the disc's direction is the closed-form orbit
## geometry read from the PARENT side (WorldRegistry.orbit angle at
## the sky epoch -- the same math the moon gate and the transfer
## windows evaluate). The disc rides that direction at fixed distance
## from the anchor (the player -- the ParentSky lesson: floating
## origin means a world-fixed disc swings with every step). Where the
## geometry says the moon is, the moon is -- admin time travel moves
## it with the calendar.
##
## PHASE SHADING: the lit fraction is the synodic angle between the
## sun's arc direction and the moon's direction at the same epoch --
## new moon as the moon nears the sun, full moon opposite. The
## fraction drives the disc's emission AND a DirectionalLight that
## rides the moon direction with night-scaled energy: night gets
## brighter when the moon is up, and at dusk the moon's fading-light
## competes with the sun's -- moon-shadows against sun-shadows as the
## two lights cross.
##
## Sky law (the one clock): position, phase, and light are PURE
## FUNCTIONS of SignService.sky_epoch_days(). No per-frame
## accumulation; the same epoch the moon orbits, the sun arcs, and
## the weather bands read.
##
## Autoloads resolve lazily (script-mode safe). Tabs, no class_name.
extends Node3D

const MOON_DISTANCE: float = 260.0
## The moon at 90 km subtends asin(1200/90000) ~ 0.76 deg from
## Synmergia -- small and honest against the 26-degree Earth the
## mooners see. Scaled 4x for readability at render distance (a
## sky-light, not a collider; the angular RATE stays exact).
const MOON_RADIUS: float = 3.6   # 260 m * tan(4 * 0.76 deg) ~ 3.6 m
## Moonlight ceiling: a full overhead moon pushes 0.35 -- bright
## night, real shadows, but never sun-strength (day owns 1.15).
const MOON_LIGHT_MAX: float = 0.35

var _disc: MeshInstance3D = null
var _terminator_mat: ShaderMaterial = null
var _light: DirectionalLight3D = null
var _moon_dir: Vector3 = Vector3.ZERO
var _phase_frac: float = 0.0
var _waxing: bool = true
var _logged: bool = false


func _ready() -> void:
	_build_disc()
	_build_light()


func _process(_delta: float) -> void:
	var epoch := _epoch_days()
	var moon = _moon_data()
	if moon == null or float(moon.orbit_radius_m) <= 0.0 or float(moon.orbit_period_days) <= 0.0:
		_disc.visible = false
		_set_light(0.0)
		return
	_moon_dir = _direction(moon, epoch)
	_phase_frac = _lit_fraction(moon, epoch)
	_disc.visible = _moon_dir.length() > 0.01
	_disc.position = _moon_dir * MOON_DISTANCE
	_disc.look_at_from_position(_disc.position, Vector3.ZERO, Vector3.UP)
	_update_terminator(epoch)
	_apply_phase_shading()
	if not _logged:
		_logged = true
		GameLog.info("SkyMoon: the pale stone rides the Concord clock (period %.1f d, phase %.2f rad)" % [
			float(moon.orbit_period_days), float(moon.orbit_phase_rad)])


## The moon's direction in the sky (unit vector). The orbital angle
## (the same _orbit_angle the gate math uses) sweeps the plane;
## inclination tips it about X; a slight Y squash keeps the disc in
## a readable sky band against the sun's arc. Parent-side read: the
## moon crosses Synmergia's sky on its own 8-day period, independent
## of the day-wheel the sun rides.
func _direction(moon, epoch: float) -> Vector3:
	var angle: float = TAU * (epoch / float(moon.orbit_period_days)) + float(moon.orbit_phase_rad)
	var flat := Vector3(cos(angle), 0.0, sin(angle))
	var inc: float = float(moon.orbit_inclination_rad)
	if absf(inc) > 0.0001:
		flat = flat.rotated(Vector3(1, 0, 0), inc)
	return (flat * Vector3(1.0, 0.35, 1.0)).normalized()


## LIT FRACTION (synodic phase): the angular distance between the
## moon's direction and the SUN's has-to-have relation: fraction 0 =
## moon near the sun (new, unlit face toward us), 1 = opposite (full).
## Waxing before full, waning after -- the fraction plus the waxing
## flag is everything a phase-shaded disc needs.
func _lit_fraction(moon, epoch: float) -> float:
	var moon_angle: float = TAU * (epoch / float(moon.orbit_period_days)) + float(moon.orbit_phase_rad)
	# The sun's arc re-reads its own convention: dawn east at day
	# phase 0.0, west at 0.5 -- sun_angle = TAU * day fraction.
	var sun_angle: float = TAU * fposmod(epoch, 1.0)
	var rel: float = fposmod(moon_angle - sun_angle, TAU)
	_waxing = rel <= PI
	var diff: float = rel if rel <= PI else TAU - rel
	return clampf(diff / PI, 0.0, 1.0)


## Phase shading + moonlight. Emission and light energy follow the
## lit fraction; light energy folds in a night factor (sky_sun's day
## curve, reversed) so moonlight yields at noon instead of fighting
## the sun over the shadows.
func _apply_phase_shading() -> void:
	_set_light(MOON_LIGHT_MAX * _phase_frac * _night_factor())
	# The TERMINATOR SHADER owns the disc's lit fraction (real world-
	# normal x sun-dir geometry, not a mirrored emission knob). The
	# waning/waxing mirror law also retired with it: shading lives in
	# the sphere's own normals now. Light energy still rides the law.
	var mat: ShaderMaterial = _disc_mesh_material()
	if mat != null:
		mat.set_shader_parameter("lit_gain", 1.75)
		# Earthshine law: the dark side keeps a floor that scales with
		# the phase (a quarter moon's shadowed sliver reads slightly
		# brighter than a new moon's, the way scattered light works).
		mat.set_shader_parameter("night_floor", clampf(0.10 + 0.06 * _phase_frac, 0.10, 0.16))


## The disc's ShaderMaterial (resolved through the mesh; the disc is
## built once and the material lives on the mesh resource).
func _disc_mesh_material() -> ShaderMaterial:
	if _terminator_mat == null and _disc != null and _disc.mesh != null:
		_terminator_mat = _disc.mesh.material as ShaderMaterial
	return _terminator_mat


## Mirror of sky_sun's day curve: 1.0 through the night half, fading
## through dawn/dusk to a near-zero noon floor. Same epoch read.
func _night_factor() -> float:
	var phase := fposmod(_epoch_days(), 1.0)
	var day := clampf(sin(phase * TAU) * 1.6 + 0.08, 0.0, 1.0)
	return clampf(1.0 - day * 1.15, 0.0, 1.0)


func _set_light(energy: float) -> void:
	if _light != null:
		_light.light_energy = energy


func _epoch_days() -> float:
	var svc = get_node_or_null("/root/SignService")
	if svc != null and svc.has_method("sky_epoch_days"):
		return svc.sky_epoch_days()
	return float(Time.get_unix_time_from_system()) / 86400.0


func _moon_data():
	var scope = get_node_or_null("/root/ScopeService")
	if scope != null and scope.has_method("world_data"):
		return scope.world_data("moon")
	var reg_script := load("res://core/frame/srv/world_registry.gd")
	if reg_script == null:
		return null
	var reg = reg_script.new()
	reg.load_worlds()
	return reg.get_world("moon")


## The disc: a pale sphere rendered by the TERMINATOR SHADER -- the
## lit fraction is the sphere's own world normals dotted against the
## sun's direction at the epoch, so New casts a dark face, Full casts
## a full round, and the crescent/gibbous line moves across the disc
## the way it moves across the real moon. The `_phase_frac` law still
## owns the moonLIGHT energy (the fraction is the same arithmetic, read
## from the geometry side of the same epoch).
func _build_disc() -> void:
	if get_node_or_null("MoonDisc") != null:
		_disc = get_node_or_null("MoonDisc") as MeshInstance3D
		return
	var mesh := SphereMesh.new()
	mesh.radius = MOON_RADIUS
	mesh.height = MOON_RADIUS * 2.0
	mesh.radial_segments = 32
	mesh.rings = 16
	var shader := Shader.new()
	shader.code = _TERMINATOR_GLSL
	_terminator_mat = ShaderMaterial.new()
	_terminator_mat.shader = shader
	_terminator_mat.set_shader_parameter("moon_albedo", Color(0.62, 0.66, 0.74, 1.0))
	_terminator_mat.set_shader_parameter("sun_dir", Vector3(1, 0, 0))
	_terminator_mat.set_shader_parameter("night_floor", 0.12)
	_terminator_mat.set_shader_parameter("lit_gain", 1.75)
	mesh.material = _terminator_mat
	_disc = MeshInstance3D.new()
	_disc.name = "MoonDisc"
	_disc.mesh = mesh
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)


## The terminator GLSL: unshaded (scene light never touches the disc
## -- the SUN directions the shader), cull disabled (the disc faces
## inward at the anchor; both arcs render). The WORLD normal is taken
## in the vertex shader (MODEL_MATRIX transform) and soft-terminated
## in fragment: smoothstep over a small band so the line reads as the
## regolith dusk, not an aliasing knife-edge. Emission = albedo x
## (floor + gain x lit): the dark side keeps a hair of earthshine.
const _TERMINATOR_GLSL: String = "
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform vec4 moon_albedo : source_color = vec4(0.62, 0.66, 0.74, 1.0);
uniform float night_floor = 0.12;
uniform float lit_gain = 1.75;
varying vec3 world_normal;
void vertex() {
\tworld_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
\tfloat d = dot(normalize(world_normal), normalize(sun_dir));
\tfloat lit = smoothstep(-0.10, 0.18, d);
\tfloat glow = night_floor + lit_gain * pow(lit, 1.2);
\tALBEDO = moon_albedo.rgb;
\tEMISSION = moon_albedo.rgb * glow;
}\n"

## Feed the shader the sun's CURRENT arc direction (sky_sun.gd's own
## convention: dawn east at day phase 0, tilted 28 deg south).
func _update_terminator(epoch: float) -> void:
	if _terminator_mat == null:
		return
	var sun_angle: float = TAU * fposmod(epoch, 1.0)
	var dir := Vector3(cos(sun_angle), sin(sun_angle), 0.0)
	var tilt := Basis(Vector3(0, 0, 1), deg_to_rad(-28.0))
	_terminator_mat.set_shader_parameter("sun_dir", (tilt * dir).normalized())


## The moonlight: a dim, cool DirectionalLight that rides the moon's
## direction and casts REAL shadows at night (the dusk law: moon-
## shadows against the sun's as the two lights cross).
func _build_light() -> void:
	_light = DirectionalLight3D.new()
	_light.name = "MoonLight"
	_light.light_color = Color(0.72, 0.78, 0.92)
	_light.light_energy = 0.0
	_light.shadow_enabled = true
	add_child(_light)
