## WorldRegistry - the S16.1 multiworld lattice (frame primitive).
##
## ONE universe seed derives every world. Nothing stored that players
## did not choose: a world's seed is SeedChain.derive_seed through its
## nesting path ("world:main", "world:underworld",
## "world:main/subworld:..."). Orbits are CLOSED FORM functions of the
## sky-clock epoch -- where is the moon is a function call, not a
## simulation (prd-multiworld.md sec 2, the "clock you wind once a
## year" thesis).
##
## Frame conventions: no autoload, no class_name, no GameManager
## dependency; co-located test test_world_lattice.gd. The game layer
## (WorldService) consumes this the way it consumes glider_state.
extends RefCounted

const WorldDataScript = preload("res://core/schemas/world_data.gd")
const SeedChain = preload("res://core/frame/kv/seed_chain.gd")

## The one constant of the universe (S16 thesis: wind once). The main
## world's player/shard seeds already run through FrameService's
## runtime seed -- this root anchors the LATTICE DERIVATION so every
## install derives the same worlds from the same source. Content
## generation re-binds per-shard runtime seeds ON TOP of these world
## seeds (world seed = domain, shard seed = variation), which is why
## the constant is safe to commit: knowing it reveals no content.
const UNIVERSE_SEED_HEX: String = "73796e6d6572676961000000000000000000000000000000000000000000000000"

var _worlds: Dictionary = {}   # id -> WorldData
var _seeds: Dictionary = {}    # id -> PackedByteArray (derived, cached)


## Load every data/worlds/*.tres declaration.
func load_worlds() -> void:
	_worlds.clear()
	_seeds.clear()
	var dir := DirAccess.open("res://data/worlds")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var w: Resource = load("res://data/worlds/" + fname)
			if w != null and w is WorldDataScript:
				_worlds[str(w.id)] = w
		fname = dir.get_next()


func get_world(id: String):
	return _worlds.get(id)


func all_worlds() -> Array:
	return _worlds.values()


## The universe seed as bytes (derived from the hex constant once).
func universe_seed() -> PackedByteArray:
	return _hex_to_bytes(UNIVERSE_SEED_HEX)


## A world's derived seed: SeedChain through the universe root and
## the world's nesting path. Deterministic across installs, shards,
## and reboots -- same constant, same bytes, forever.
func world_seed(id: String) -> PackedByteArray:
	if _seeds.has(id):
		return _seeds[id]
	var w = get_world(id)
	if w == null:
		return PackedByteArray()
	# Parent nesting: derive the parent's seed first, then fold the
	# child path through it (subworlds inherit their primary's domain).
	var stack: Array[PackedByteArray] = [universe_seed()]
	if str(w.parent_world) != "" and _worlds.has(str(w.parent_world)):
		stack.append(world_seed(str(w.parent_world)))
	var seed: PackedByteArray = SeedChain.derive_seed(stack, w.seed_path())
	_seeds[id] = seed
	return seed


func world_seed_hex(id: String) -> String:
	return world_seed(id).hex_encode()


## ---- Closed-form orbits (prd-multiworld sec 2.2) --------------------------

## World-local position of an orbiting world at sky-epoch `epoch`
## (SignService.sky_epoch_days() -- the Concord clock in fractional
## days; THE canonical epoch since S16.2). Pure function:
## angle = 2pi * (epoch / period) + phase, rotated into the inclined
## plane. Returns ZERO for non-orbiting worlds.
static func orbit_position(w, epoch: float) -> Vector3:
	if w == null or float(w.orbit_radius_m) <= 0.0 or float(w.orbit_period_days) <= 0.0:
		return Vector3.ZERO
	var angle: float = TAU * (epoch / float(w.orbit_period_days)) + float(w.orbit_phase_rad)
	var flat := Vector3(cos(angle), 0.0, sin(angle)) * float(w.orbit_radius_m)
	# Inclination rotates the orbital plane about the X axis (0 = the
	# ecliptic plane; pi/2 = a polar orbit).
	var inc: float = float(w.orbit_inclination_rad)
	if absf(inc) > 0.0001:
		flat = flat.rotated(Vector3(1, 0, 0), inc)
	return flat


## Transfer-window favorability between two worlds at an epoch.
##
## PHYSICS NOTE (the honest model): a moon on a circular orbit keeps
## CONSTANT distance from its parent, so a moon gate cannot key on
## distance -- it keys on ORBITAL PHASE. Favorability is the phase
## angle's distance from alignment (0.0 = the body sits exactly on
## the gate azimuth -- orbit_phase + the epoch-driven sweep resolving
## to the alignment angle), 1.0 = opposite. Two free-orbiting bodies
## (both with radii) instead measure mutual phase distance. Pure
## function so windows are computable YEARS ahead (the almanac's
## moon page reads this).
static func window_favorability(a, b, epoch: float) -> float:
	# ab = whichever argument is the ORBITING body (the other is the
	# static pivot whose gate azimuth defines alignment).
	var ab = a if a != null and float(a.orbit_radius_m) > 0.0 else b
	var pivot = b if ab == a else a
	if ab == null or pivot == null or ab == pivot:
		return 1.0
	var ra: float = float(ab.orbit_radius_m)
	var rp: float = float(pivot.orbit_radius_m)
	if ra <= 0.0 and rp <= 0.0:
		return 1.0
	# The orbiting body contributes its swept angle; the static pivot
	# contributes 0. Both orbiting: the RELATIVE angle matters.
	var ang_body := _orbit_angle(ab, epoch)
	var ang_pivot := _orbit_angle(pivot, epoch)
	var diff: float = absf(fposmod(ang_body - ang_pivot, TAU))
	if diff > PI:
		diff = TAU - diff
	return clampf(diff / PI, 0.0, 1.0)


## Closed-form orbital angle at an epoch (rad). Static bodies: 0.
static func _orbit_angle(w, epoch: float) -> float:
	if w == null or float(w.orbit_period_days) <= 0.0:
		return 0.0
	return TAU * (epoch / float(w.orbit_period_days)) + float(w.orbit_phase_rad)


## The next epoch (from `from_epoch`, inclusive) where two orbiting
## worlds come within `threshold` favorability. Steps in `step_days`
## increments up to `max_days` ahead; returns -1.0 when no window
## opens inside the horizon. Pure function.
static func next_transfer_window(a, b, from_epoch: float, threshold: float = 0.15, step_days: float = 0.25, max_days: float = 40.0) -> float:
	var epoch := from_epoch
	var horizon: float = from_epoch + max_days
	while epoch <= horizon:
		if window_favorability(a, b, epoch) <= threshold:
			return epoch
		epoch += step_days
	return -1.0


## ---- Bytes helper (hex constant -> PackedByteArray) -----------------------

static func _hex_to_bytes(hex: String) -> PackedByteArray:
	var clean := hex.replace(" ", "")
	var out := PackedByteArray()
	var i := 0
	while i + 1 < clean.length():
		out.append(("0x" + clean.substr(i, 2)).hex_to_int())
		i += 2
	return out
