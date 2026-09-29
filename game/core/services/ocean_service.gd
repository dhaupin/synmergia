## OceanService - the water layer's one sampler (S14.1,
## labs/prd-ocean-depths.md sec 2: "one sampler, three readers").
##
## SCENE-SPACE HONESTY (learned by probe): both current scenes put
## the water's surface at a world-Y plane near the action (main
## world y=0, crater y=-6) and the rock a plane below it. The RADIAL
## world-shell model stays in the schema (the day a scene wraps a
## true globe sphere, the shelf flips floor_is_radial=true and the
## math is ready) but both shipped volumes use the LOCAL plane
## model -- the honest geometry for a playable dish or shelf.
##
## Loads data/oceans/*.tres into a book and answers the ONE question
## every water reader has: how deep is this body, in THIS volume?
## The sign discipline mirrors ThermalService.sample:
##
##   depth < 0  -- above the waterline (DRY)
##   depth >= 0 -- meters below the waterline
##
## Readers: physics (band -> movement class + buoyancy), renderer
## (fog + surface plane), anticheat (aquatic limits + the current
## drift exemption -- currents move bodies passively, so the
## validator ignores current-only displacement via the volume's
## declared current vector, server-side truth).
##
## Terrain respect (prd sec 2): sample_depth clamps to the volume's
## radial floor -- you can never swim through rock. The floor is
## read from the same distance-to-center geometry the globe walk
## uses; no second collision world.
##
## Autoload: NO class_name (AGENTS rule).
extends Node

const OceanVolumeScript = preload("res://core/schemas/ocean_volume.gd")
const SwimStateScript = preload("res://core/frame/srv/swim_state.gd")

## The grace band before pressure ramps (prd sec 4), which breathers
## extend (S14.4). Lives here so schema and probes read one number.
const PRESSURE_GRACE_M: float = 10.0
## The default floor radius when a volume declares none (the main
## planet's surface scale).
const DEFAULT_FLOOR_RADIUS: float = 20000.0

var _volumes: Dictionary = {}
var _loaded: bool = false


func _ready() -> void:
	ensure_loaded()


## Load every data/oceans/*.tres. Idempotent (re-load refreshes).
func ensure_loaded() -> void:
	if _loaded:
		return
	_volumes.clear()
	var dir := DirAccess.open("res://data/oceans")
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.ends_with(".tres"):
				var v: Resource = load("res://data/oceans/" + fname)
				if v != null and v is OceanVolumeScript:
					_volumes[str(v.id)] = v
			fname = dir.get_next()
	_loaded = true


func get_volume(id: String):
	return _volumes.get(id)


func all_volumes() -> Array:
	return _volumes.values()


## The volume containing a position, or null. A volume claims the
## space between its radial floor and a surface plane near it (plus
## wading slack): the claim test is the RADIAL COLUMN, not a shell
## band -- a crater floor at 1194 and a planet floor at 20000 can
## share a center without one swallowing the other, because each
## claims from its own rock UP to the near side of its waterline.
##
## Concretely, a volume owns `pos` when:
##   floor_dist <= |pos - center| <= floor_dist + max_depth + slack
## (the body is above the rock and inside the water column the
## volume can honestly hold). For the plane waterline the column
## height is implied by the surface_height declaration; the +50 m
## slack covers the air just above the surface (wading entries).
func volume_at(pos: Vector3):
	ensure_loaded()
	var best = null
	var best_dist: float = -1.0
	for v in _volumes.values():
		if bool(v.floor_is_radial):
			# WORLD-SHELL ocean: claims the radial band above its rock.
			var center: Vector3 = v.floor_center if v.floor_center != Vector3.ZERO else _default_center()
			var floor_r: float = float(v.floor_radius) if float(v.floor_radius) > 0.0 else DEFAULT_FLOOR_RADIUS
			var d: float = pos.distance_to(center)
			if d < floor_r:
				continue  # inside the rock: no volume owns the stone
			if d > floor_r + float(v.max_depth) + 50.0:
				continue  # above the water column's reach
			if best == null or d < best_dist:
				best = v
				best_dist = d
		else:
			# LOCAL pool: claims the box from its rock plane up past
			# its surface (a pool is small; a planar claim is honest).
			var surface_y: float = float(v.surface_height)
			if pos.y > surface_y + 2.0:
				continue  # above the water's wading reach
			if pos.y < float(v.floor_y):
				continue  # inside the rock
			# Horizontal reach: the dish's own radius. floor_center is
			# the surface center; the dish reaches floor_radius (its
			# carved width) horizontally -- a SMALL dish beats a WIDE
			# one when both could claim a body (specificity wins).
			var horiz: float = Vector2(pos.x - v.floor_center.x, pos.z - v.floor_center.z).length()
			var reach: float = float(v.floor_radius) if float(v.floor_radius) > 0.0 else float(v.max_depth) * 2.0 + 20.0
			if horiz > reach:
				continue
			if best == null or reach < best_dist:
				best = v
				best_dist = reach
	return best


## THE sampler (the sign discipline):
##   return < 0: the body is ABOVE the waterline (meters above)
##   return >= 0: the body is this many meters below the surface
## Clamped to the radial floor: a body pressed against the rock
## reads its true depth, never through it (terrain respect).
##
## The radial clamp, both hemispheres: depth is measured DOWN from
## the surface plane toward the floor center, so the honest column
## is (floor_distance - body_distance) -- how much water lies
## between the body and the rock along the radial. This works on
## BOTH sides of a small globe:
##   main world: floor_y = +20000, surface at 0, body at -5 m
##     -> column = 20000 - 19995 = 5 m of water above the rock. Correct.
##   moon crater: floor_r = 1194 near the top of the sphere, surface
##     plane at -6, body below it -> column = distance to the rock.
## The plane waterline decides DRY vs wet; the radial decides how
## much water the body is honestly in.
func sample_depth(pos: Vector3, vol = null) -> float:
	ensure_loaded()
	var v = vol if vol != null else volume_at(pos)
	if v == null:
		return -1.0
	# Plane waterline (the surface is a plane in the current scenes).
	var depth: float = float(v.surface_height) - pos.y
	if depth < 0.0:
		return depth  # above water: meters above the line (negative)
	# The floor clamp, two honest models (see OceanVolume floor docs).
	# Pressure depth is the WATER ABOVE the body (the column between
	# the surface and the body) -- the rock below does not reduce it
	# (23 m of water over a body 1 m above the floor is 23 m of
	# pressure depth). The rock's job: refuse to report water for a
	# body pushed INSIDE the stone (the -1 sentinel -- the rock is
	# not water).
	if bool(v.floor_is_radial):
		var center: Vector3 = v.floor_center if v.floor_center != Vector3.ZERO else _default_center()
		var floor_r: float = float(v.floor_radius) if float(v.floor_radius) > 0.0 else DEFAULT_FLOOR_RADIUS
		if pos.distance_to(center) < floor_r:
			return -1.0  # inside the rock: stone, not water
		return depth
	var floor_line: float = float(v.floor_y)
	if pos.y < floor_line:
		return -1.0  # inside the rock: stone, not water
	return depth


## The band at a position (the mapping every reader shares).
func band_at(pos: Vector3, breather_grace_m: float = 0.0) -> int:
	var v = volume_at(pos)
	if v == null:
		return OceanVolumeScript.DepthBand.DRY
	return v.band_for(sample_depth(pos, v), breather_grace_m)


## The current push a body feels here (the drag model's target
## velocity; the anticheat's current-only exemption reads the same
## vector -- server-side truth, prd sec 6).
func current_at(pos: Vector3) -> Vector3:
	var v = volume_at(pos)
	if v == null:
		return Vector3.ZERO
	return v.current_vector()


## ---- S14.2: the swim driver -------------------------------------------------

## Per-body swim state (the below-the-waterline twin of the glider
## book). Bodies without a book never tick water physics.
var _swimmers: Dictionary = {}   # body_id -> SwimState


## Tick one body's water truth: reads the sampler and the volume's
## declared bands, drives the body's SwimState (breath, pressure,
## drowning), and returns {state, depth, band, current, breath,
## pressure, drowning_s} -- everything the body's physics, the HUD,
## and the anticheat need, from ONE call. A body in no volume reads
## DRY with no clocks.
func tick_swimmer(body_id: String, pos: Vector3, delta: float, breather_grace_m: float = 0.0) -> Dictionary:
	ensure_loaded()
	var v = volume_at(pos)
	var depth: float = sample_depth(pos, v)
	var s = _swimmers.get(body_id)
	if s == null:
		s = SwimStateScript.new()
		_swimmers[body_id] = s
	if v == null:
		s.tick(delta, depth if depth < 0.0 else -1.0, 1.0, 1.0, 0.0, breather_grace_m)
		return {"state": s.state, "depth": depth, "band": OceanVolumeScript.DepthBand.DRY, \
			"current": Vector3.ZERO, "breath": s.breath, "pressure": s.pressure, "drowning_s": s.drowning_s}
	var squeeze_line: float = float(v.max_depth) - OceanVolumeScript.NATURAL_PRESSURE_FREE_M
	if squeeze_line < 0.0:
		squeeze_line = float(v.max_depth)
	var state: int = s.tick(delta, depth, squeeze_line, float(v.max_depth), \
		float(v.pressure_per_meter), breather_grace_m)
	return {"state": state, "depth": depth, "band": v.band_for(depth, breather_grace_m), \
		"current": v.current_vector(), "breath": s.breath, "pressure": s.pressure, \
		"drowning_s": s.drowning_s}


## A body's swim state (null when it never swam).
func swim_state(body_id: String):
	return _swimmers.get(body_id)


## Forget a body (logout, death -- the book never holds the dead).
func forget_swimmer(body_id: String) -> void:
	_swimmers.erase(body_id)


func _default_center() -> Vector3:
	return Vector3.ZERO
