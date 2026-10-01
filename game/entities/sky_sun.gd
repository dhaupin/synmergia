## SkySun -- the playable world's sun (play-day feedback #8).
## PLACEHOLDER GEOMETRY, HONEST CLOCK: the disc hangs where the sky
## clock says the sun is, so direction sense works today and the
## end-game sun replaces the disc without changing the math.
##
## Sky principles this hooks into (the one-clock law):
##   - Position is a PURE FUNCTION of SignService.sky_epoch_days()
##     (the same epoch the moon orbits, the windows open on, and the
##     Deep Root's glow tides read). No per-frame accumulation, no
##     drift, admin time-travel moves the sun.
##   - One arc per day: phase 0.0 = dawn (east horizon), 0.25 = noon
##     (overhead), 0.5 = dusk (west horizon), night below. The arc
##     plane is tilted so the noon sun sits south of overhead -- a
##     shadow-bearing direction, like every compass world expects.
##   - The DirectionalLight tracks the disc and dims to moonless-night
##     floor at night; the disc's emission fades with it.
##
## The disc is a small sphere at fixed distance on the current
## direction (never a skybox: it must parallax like a real body --
## the same reason the moon's earthrise is a ParentSky disc).
##
## Autoloads resolve lazily (script-mode safe). Tabs, no class_name.
extends Node3D

const SUN_DISTANCE: float = 260.0
const SUN_RADIUS: float = 9.0
## Arc tilt: degrees the sun's daily plane tips south of zenith.
const ARC_TILT_DEG: float = 28.0
## Ambient floor at deep night (never pure black; the Concord sky
## glows faintly -- prd-psy: the sky is machinery, not void).
const NIGHT_LIGHT_ENERGY: float = 0.18
const DAY_LIGHT_ENERGY: float = 1.15

var _disc: MeshInstance3D = null
var _disc_mat: StandardMaterial3D = null
var _light: DirectionalLight3D = null
var _sun_dir: Vector3 = Vector3(0, 1, 0)


func _ready() -> void:
	_build_disc()
	_build_light()


func _process(_delta: float) -> void:
	var phase := _day_phase()
	_sun_dir = _direction_for_phase(phase)
	# CELESTIAL FRAME: the disc is "infinitely far" -- at planet scale
	# (floating origin) the world slides under the player, and a disc
	# fixed to the world origin swung across the sky with every step
	# (round-5: "the sun is tracking across the sky like the planet is
	# still 100"). The parent scene re-anchors this node under the
	# PLAYER (it re-parents/re-positions at build time); the disc rides
	# the direction at fixed distance from the PLAYER, so the sun is
	# stable the way a real star is.
	position = _sun_dir * SUN_DISTANCE
	if _disc_mat != null:
		# Day factor: smooth dawn/dusk ramp (phase distance from the
		# horizon). 1.0 at high day, 0.0 through the night half.
		var day := clampf(sin(phase * TAU) * 1.6 + 0.08, 0.0, 1.0)
		_disc_mat.emission_energy_multiplier = 0.4 + 3.2 * day
	if _light != null:
		_light.position = global_position + _sun_dir * SUN_DISTANCE
		_light.look_at_from_position(_light.position, global_position, Vector3.UP)
		var day := clampf(sin(phase * TAU) * 1.6 + 0.08, 0.0, 1.0)
		_light.light_energy = NIGHT_LIGHT_ENERGY + (DAY_LIGHT_ENERGY - NIGHT_LIGHT_ENERGY) * day


## The sun's current direction (unit vector). Exposed for the minimap
## compass and any future shadow-caster alignment.
func sun_direction() -> Vector3:
	return _sun_dir


## Day phase in [0, 1): 0 = dawn, 0.25 = noon, 0.5 = dusk. The Concord
## epoch's fractional part IS the phase (one sky day = one rotation);
## admin time travel and test clocks move the sun with the calendar.
func _day_phase() -> float:
	return fposmod(_epoch_days(), 1.0)


## Direction on the daily arc: east-west sweep around the world's Y,
## tilted by ARC_TILT_DEG so noon sits south of overhead.
func _direction_for_phase(phase: float) -> Vector3:
	var angle: float = phase * TAU
	var dir := Vector3(cos(angle), sin(angle), 0.0)
	var tilt := Basis(Vector3(0, 0, 1), deg_to_rad(-ARC_TILT_DEG))
	return (tilt * dir).normalized()


func _epoch_days() -> float:
	var svc = get_node_or_null("/root/SignService")
	if svc != null and svc.has_method("sky_epoch_days"):
		return svc.sky_epoch_days()
	return float(Time.get_unix_time_from_system()) / 86400.0


func _build_disc() -> void:
	_disc = MeshInstance3D.new()
	_disc.name = "SunDisc"
	var mesh := SphereMesh.new()
	mesh.radius = SUN_RADIUS
	mesh.height = SUN_RADIUS * 2.0
	_disc_mat = StandardMaterial3D.new()
	_disc_mat.albedo_color = Color(1.0, 0.92, 0.7)
	_disc_mat.emission_enabled = true
	_disc_mat.emission = Color(1.0, 0.88, 0.55)
	_disc_mat.emission_energy_multiplier = 3.0
	_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = _disc_mat
	_disc.mesh = mesh
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)


func _build_light() -> void:
	_light = DirectionalLight3D.new()
	_light.name = "SunLight"
	_light.light_color = Color(1.0, 0.94, 0.82)
	_light.light_energy = DAY_LIGHT_ENERGY
	_light.shadow_enabled = true
	add_child(_light)
