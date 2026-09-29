## StarCells - the X2 address-space galaxy (frame primitive).
##
## Owner thesis (prd-industry-labs X2): "stars exist because their
## NSC-9 address says so -- derive_seed 'star:<addr>'". A star is not
## a spawned entity; it is a DERIVED PROPERTY of an address. The
## galaxy tier (calibration_galaxy.tres: EVALUATE, hourly, anchored
## "nsc9:0", derives_state) evaluates addresses, it does not tick
## them. H0 is already declared on the universe tier for the day the
## lattice stretches.
##
## Mechanics, all closed form:
##   - A facility/axis pair names a 2-manifold of candidate cells
##     (sequence 0..999999, the NSC-9 24-bit sequence space).
##   - star_seed(universe_seed, address) hashes "star:<nsc9 addr>" to
##     32 deterministic bytes; the TOP byte's high bit decides
##     existence -- the address IS the star's identity, the seed IS
##     the verdict.
##   - Spectral class comes from the same bytes (a map of the second
##     byte into the historical O B A F G K M ladder), luminosity and
##     radius from the third. Nothing stored that players did not
##     choose: an address unobserved costs nothing.
##   - Storage goes through the FoldedShell: the sky is stored ONCE
##     as content-hash cells and every observing space (a shard, a
##     player's far-gaze, an almanac page) RE-CLAIMS the intersection
##     instead of re-paying. One universe, one sky, many claimants.
##
## Frame conventions: no autoload, no class_name, co-located test.
extends RefCounted

const NSC9 = preload("res://core/frame/math/nsc9.gd")
const SeedChain = preload("res://core/frame/kv/seed_chain.gd")
const FoldedShell = preload("res://core/frame/kv/folded_shell.gd")

## The spectral ladder (historical O B A F G K M) with simple
## illustrative luminosity/temperature ratios. Classes are DERIVED
## from star bytes, never stored.
const SPECTRAL_CLASSES: Array = ["O", "B", "A", "F", "G", "K", "M"]
## Illustrative surface temperature (K) per class index.
const CLASS_TEMPERATURE_K: Array = [30000.0, 10000.0, 7500.0, 6000.0, 5500.0, 4000.0, 3000.0]

## The NSC-9 address domain (decimal format): facility and axis are
## 0..999 (three digits each), sequence 0..999999 (six digits).
## encode_int is INJECTIVE within this domain (999*1e6 + 999999 <
## 1e9), which is what makes one address name exactly one star.
## Coordinates outside the domain are refused: a star at an address
## no decoder can reach would be a phantom -- derived, stored, and
## unreachable by any telescope.
const MIN_FACILITY: int = 0
const MAX_FACILITY: int = 999
const MIN_AXIS: int = 0
const MAX_AXIS: int = 999
const MAX_SEQUENCE: int = 999999

## Storage: content-hash cells on the shell; every observer space
## (a shard, a far-gaze, an almanac page) re-claims the shared sky
## and the rebate is measured between them.
var _shell: FoldedShell = null

## Evaluated-address counts (measurement surface for the probe).
var _evaluated: int = 0
var _found: int = 0


func _init(hot_size: int = 256) -> void:
	_shell = FoldedShell.new(hot_size)


## The shared shell (measurement + cross-space rebate access).
func shell() -> FoldedShell:
	return _shell


## Evaluated / found counters (stress measured, not feared).
func evaluated() -> int:
	return _evaluated


func found() -> int:
	return _found


## The star verdict for one address: derive 32 bytes from
## (universe_seed, "star:<addr>"), top byte's high bit decides.
## Pure function of the seed and the address -- the galaxy tier may
## re-derive hourly; the verdict never drifts.
static func star_seed(universe_seed: PackedByteArray, address: int) -> PackedByteArray:
	var stack: Array[PackedByteArray] = [universe_seed]
	return SeedChain.derive_seed(stack, "star:%d" % address)


## Does a star exist at this address? The address IS the identity;
## the derived bytes ARE the verdict.
static func star_exists(universe_seed: PackedByteArray, address: int) -> bool:
	var seed_bytes := star_seed(universe_seed, address)
	return seed_bytes[0] & 0x80 != 0


## A star record derived from its address bytes: spectral class,
## temperature, luminosity (relative to Sol = 1.0), radius (solar
## radii). Returns {} for an empty address -- the map from bytes to
## star is total on the ladder.
static func star_record(universe_seed: PackedByteArray, address: int) -> Dictionary:
	var seed_bytes := star_seed(universe_seed, address)
	if seed_bytes[0] & 0x80 == 0:
		return {}
	var class_idx: int = seed_bytes[1] % SPECTRAL_CLASSES.size()
	var luminosity: float = 1.0 + float(seed_bytes[2]) / 255.0 * 99.0
	var radius: float = 0.3 + float(seed_bytes[3]) / 255.0 * 2.7
	return {
		"address": address,
		"seed_hex": seed_bytes.hex_encode(),
		"spectral_class": SPECTRAL_CLASSES[class_idx],
		"temperature_k": CLASS_TEMPERATURE_K[class_idx],
		"luminosity": luminosity,
		"radius_solar": radius,
	}


## ---- The sky as folded storage ---------------------------------------------

## Observe the sky over one facility/axis facet: walk the sequence
## space, store every found star as a content-hash cell under
## `observer_id` (the shell re-claims already-stored stars for free).
## Returns the count of stars VISIBLE to this observer (claims).
## The galaxy tier's hourly EVALUATE is exactly this walk.
## Coordinates outside the NSC-9 domain are refused (phantom-star
## law); sequence_limit is clamped to the sequence space -- a facet
## walk never exceeds the domain that addresses can encode.
func observe_facet(universe_seed: PackedByteArray, facility: int, axis: int, observer_id: String, sequence_limit: int = 4096) -> int:
	if facility < MIN_FACILITY or facility > MAX_FACILITY or axis < MIN_AXIS or axis > MAX_AXIS:
		push_error("StarCells.observe_facet: facility/axis outside NSC-9 domain (%d/%d) -- refused" % [facility, axis])
		return 0
	var limit: int = clampi(sequence_limit, 0, MAX_SEQUENCE + 1)
	var nsc9 := NSC9.new()
	var visible: int = 0
	var seq := 0
	while seq < limit:
		var address: int = nsc9.encode_int(facility, axis, seq)
		_evaluated += 1
		if star_exists(universe_seed, address):
			_found += 1
			visible += 1
			var rec := star_record(universe_seed, address)
			# The payload stored IS the star (content = its seed bytes
			# + derived class); identical stars re-claim, never re-pay.
			var content_hash: String = rec["seed_hex"]
			_shell.put(observer_id, address, content_hash, rec)
		seq += 1
	return visible


## How many stars this observer currently claims.
func visible_count(observer_id: String) -> int:
	return _shell.space_size(observer_id)


## The rebate between two observers: shared stars stored ONCE.
func shared_sky(a: String, b: String) -> int:
	return _shell.rebate(a, b)


## Look one star up by address (a telescope is a LOOKUP, not a
## raycast: address in, verdict out). Re-derives; never misses a star
## the seed says is there. Out-of-domain coordinates point at no
## address any decoder can reach: {} -- the same answer as an empty
## coordinate, never a phantom star.
static func telescope_lookup(universe_seed: PackedByteArray, facility: int, axis: int, sequence: int) -> Dictionary:
	if facility < MIN_FACILITY or facility > MAX_FACILITY \
			or axis < MIN_AXIS or axis > MAX_AXIS \
			or sequence < 0 or sequence > MAX_SEQUENCE:
		return {}
	var address: int = NSC9.new().encode_int(facility, axis, sequence)
	return star_record(universe_seed, address)
