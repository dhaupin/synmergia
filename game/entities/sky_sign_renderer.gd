## SkySignRenderer -- client-side Skyward Concord visuals
## (labs/prd-psy.md section 7). Draws the CURRENT window's Sign in the
## sky as a tinted constellation: a ring of emissive quads arranged in
## a per-sign pattern, hanging high above the shard. Everyone sees the
## same sky (the pick is deterministic server+client). Sealed windows
## render DIM and PATTERNLESS -- the sky withholds what the tribe has
## not yet shared; revealed windows render bright in the Sign's tint.
##
## Placement: instanced by world_playable as a child node. Purely
## visual -- zero gameplay authority lives here.
extends Node3D

const SignProfileScript = preload("res://core/schemas/sign_profile.gd")

const SKY_HEIGHT: float = 46.0
const PATTERN_RADIUS: float = 7.0
## Star scale grows once the community reveals the glyph.
const STAR_SCALE_SEALED: float = 0.35
const STAR_SCALE_REVEALED: float = 0.8

var _stars: Array[MeshInstance3D] = []
var _current_sign_id: String = ""
var _pulse: float = 0.0


func _ready() -> void:
	_build_star_pool()


func _process(delta: float) -> void:
	_pulse += delta
	if SignService == null:
		return
	var w: Dictionary = SignService.get_current_window()
	var sign_id := str(w.get("sign_id", ""))
	var revealed: bool = bool(w.get("revealed", false))
	if sign_id != _current_sign_id:
		_current_sign_id = sign_id
		_arrange(sign_id, revealed)
	# Slow breathing pulse; brighter when revealed.
	var brightness := 1.6 if revealed else 0.45
	for s in _stars:
		var mat := s.get_surface_override_material(0) as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = brightness * (0.85 + 0.15 * sin(_pulse * 1.4 + float(s.get_instance_id() % 7)))


## Rebuild the constellation for a sign id. Sealed windows show the
## star COUNT but scatter them in a boring uniform ring -- no pattern
## to read until the reveal.
func _arrange(sign_id: String, revealed: bool) -> void:
	var sign = null
	if SignService != null:
		sign = SignService._signs.get(sign_id)
	var count: int = 7
	var tint: Color = Color(0.7, 0.8, 1.0)
	var seed_hash: int = 0
	if sign != null:
		count = 7 + (absi(hash(str(sign.id))) % 4)
		tint = sign.sky_tint
		seed_hash = hash(str(sign.id) + "arrange")
	var n := _stars.size()
	for i in n:
		var star := _stars[i]
		if i < count:
			star.visible = true
			star.position = _star_position(i, count, seed_hash, revealed)
			var mat := star.get_surface_override_material(0) as StandardMaterial3D
			if mat != null:
				mat.albedo_color = tint
				mat.emission = tint
				var sc := STAR_SCALE_REVEALED if revealed else STAR_SCALE_SEALED
				star.scale = Vector3(sc, sc, sc)
		else:
			star.visible = false


func _star_position(i: int, count: int, seed_hash: int, revealed: bool) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_hash + i
	if revealed:
		# Revealed: deterministic per-sign scatter across two rings --
		# reads as a deliberate figure (each sign gets its own shape).
		var ring := PATTERN_RADIUS * (1.0 if i % 2 == 0 else 0.55)
		var ang := TAU * float(i) / float(count) + rng.randf_range(-0.25, 0.25)
		return Vector3(cos(ang) * ring, rng.randf_range(-1.2, 1.2), sin(ang) * ring)
	# Sealed: flat uniform ring, no figure.
	var ang2 := TAU * float(i) / float(count)
	return Vector3(cos(ang2) * PATTERN_RADIUS, 0.0, sin(ang2) * PATTERN_RADIUS)


## Pool of emissive quads, big enough for the largest constellation.
func _build_star_pool() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	for i in 12:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.7, 0.8, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.7, 0.8, 1.0)
		mat.emission_energy_multiplier = 0.5
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		var star := MeshInstance3D.new()
		star.name = "Star%d" % i
		star.mesh = quad
		star.set_surface_override_material(0, mat)
		star.visible = false
		add_child(star)
		_stars.append(star)
	# The whole constellation rides high on the +Y, tilted toward town.
	position = Vector3(0, SKY_HEIGHT, -30)
