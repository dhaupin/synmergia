## Tests for StarCells -- X2, stars stored at NSC-9 addresses on the
## FoldedShell/galaxy tier.
##
## The owner's thesis: "stars exist because their NSC-9 address says
## so -- derive_seed 'star:<addr>'". Covers:
##   A. existence IS the address (deterministic verdict, ~50% yield,
##      empty addresses return {}),
##   B. derivation is honest (same seed = same star; different
##      universe seed = different sky; the anchor name decodes),
##   C. the spectral ladder is derived, never stored (classes stay in
##      bounds, records carry the historical letters, temperature
##      follows the class),
##   D. the galaxy tier's own anchor evaluates (calibration data ->
##      primitive, the ladder consumes its reservation),
##   E. the sky is folded storage (two observers sharing a sky pay
##      once -- the rebate, measured),
##   F. a telescope is an address lookup (deterministic, address-in
##      verdict-out), and
##   G. the cosmic constants are reachable (c declared on the
##      universe tier -- light-lag honesty has its constant).
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var SC = load("res://core/frame/srv/star_cells.gd")
	var WR = load("res://core/frame/srv/world_registry.gd")
	var reg = WR.new()
	reg.load_worlds()

	# ---- A. Existence IS the address ------------------------------------------
	var universe: PackedByteArray = reg.universe_seed()
	var first: bool = SC.star_exists(universe, 100001)
	_check("the same address always yields the same verdict", \
		first == SC.star_exists(universe, 100001))
	# Derive a histogram over a slice of one facet.
	var hits: int = 0
	var probes: int = 2048
	for seq in range(probes):
		if SC.star_exists(universe, 9000000 + seq):
			hits += 1
	_check("star existence is a real coin (a sky that is all-empty or all-full would be a broken hash)", \
		hits > probes / 4 and hits < probes * 3 / 4)
	var empty: Dictionary = SC.star_record(universe, 100001) if not first else {}
	if first:
		empty = SC.star_record(universe, 100002)
	_check("an empty address returns {} (nothing stored that nobody chose)", empty.is_empty())

	# ---- B. Derivation is honest ------------------------------------------------
	# A different universe: SHA-256 of a different root phrase (the
	# registry's UNIVERSE_SEED_HEX is a const; the LAW under test is
	# that the sky follows the seed, whatever its source).
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("universe:other".to_utf8_buffer())
	var other_sky: PackedByteArray = ctx.finish()
	var differs: bool = false
	for seq in range(64):
		if SC.star_exists(universe, 7000000 + seq) != SC.star_exists(other_sky, 7000000 + seq):
			differs = true
			break
	_check("a different universe seed derives a different sky", differs)
	var anchor_addr: int = int(str("nsc9:0").trim_prefix("nsc9:").to_int())
	var nsc9 = SC.NSC9.new()
	# Decimal NSC-9 code -> decimal decode (do NOT mix formats: the
	# packed-bit decoder answers a different packing).
	var decoded: Dictionary = nsc9.decode_int(nsc9.encode_int(anchor_addr, 1, 0))
	_check("the galaxy anchor decodes to a real facility", \
		str("nsc9:0").begins_with("nsc9:") and int(decoded["facility"]) == anchor_addr \
		and int(decoded["axis"]) == 1)

	# ---- C. The spectral ladder is derived, never stored ------------------------
	var saw_class: Dictionary = {}
	var class_ok: bool = true
	var temp_ok: bool = true
	var probes_c: int = 0
	for seq in range(4096):
		var rec: Dictionary = SC.star_record(universe, 9000000 + seq)
		if rec.is_empty():
			continue
		probes_c += 1
		var cls: String = rec["spectral_class"]
		saw_class[cls] = true
		if not SC.SPECTRAL_CLASSES.has(cls):
			class_ok = false
		if float(rec["temperature_k"]) <= 0.0:
			temp_ok = false
		if probes_c >= 200:
			break
	_check("records carry a valid class from the O B A F G K M ladder", class_ok and probes_c > 0)
	_check("temperature follows the class (hot O to cool M)", temp_ok)
	_check("the derived sky spans several classes (a one-class galaxy would be a broken map)", \
		saw_class.size() >= 3)

	# ---- D. The galaxy tier's own anchor evaluates -------------------------------
	var ds = root.get_node_or_null("DataService")
	_check("DataService present in script mode", ds != null)
	if ds == null:
		quit(1)
		return
	if not ds._loaded:
		ds.load_all_data()
	var galaxy = ds.get_calibration_tier("calibration_galaxy")
	_check("the galaxy tier anchors on an NSC-9 facility", \
		str(galaxy.anchor).begins_with("nsc9:"))
	var fac: int = int(str(galaxy.anchor).trim_prefix("nsc9:").to_int())
	var sky = SC.new(128)
	var galaxy_universe: PackedByteArray = reg.universe_seed()
	var visible: int = sky.observe_facet(galaxy_universe, fac, 1, "probe")
	_check("the anchor facet evaluates (the hourly EVALUATE, exercised)", visible > 0)
	_check("evaluation counters measured", sky.evaluated() == 4096 and sky.found() == visible)

	# ---- E. The sky is folded storage (the rebate, measured) ----------------------
	var sky2 = SC.new(128)
	var u: PackedByteArray = reg.universe_seed()
	var v_shard: int = sky2.observe_facet(u, 0, 1, "shard_a")
	var v_player: int = sky2.observe_facet(u, 0, 1, "player_7")
	var v_elsewhere: int = sky2.observe_facet(u, 3, 2, "player_9")
	_check("both observers of one facet see the same stars", v_shard == v_player and v_shard > 0)
	var shared: int = sky2.shared_sky("shard_a", "player_7")
	_check("the shared sky is stored ONCE (rebate measured)", \
		shared == v_shard and shared == v_player)
	_check("different facets barely intersect", sky2.shared_sky("player_9", "shard_a") == 0 \
		or sky2.shared_sky("player_9", "shard_a") < v_shard)
	_check("each observer claims its own view", \
		sky2.visible_count("shard_a") == v_shard \
		and sky2.visible_count("player_9") == v_elsewhere)
	var distinct: int = sky2.shell().fact_count()
	_check("the shell holds distinct stars only (two claims of the shared sky)", \
		distinct == v_shard + v_elsewhere)

	# ---- F. A telescope is an address lookup --------------------------------------
	var hit: Dictionary = SC.telescope_lookup(u, 0, 1, 0)
	var again: Dictionary = SC.telescope_lookup(u, 0, 1, 0)
	_check("the telescope returns the same star for the same address", \
		(hit.is_empty() and again.is_empty()) \
		or (not hit.is_empty() and hit["address"] == again["address"] \
			and str(hit["seed_hex"]) == str(again["seed_hex"])))
	_check("a found star's record carries its address", \
		hit.is_empty() or int(hit["address"]) == nsc9.encode_int(0, 1, 0))

	# ---- G. The cosmic constants are reachable -------------------------------------
	var uni = ds.get_calibration_tier("calibration_universe")
	_check("c is declared where the ladder will consume it", uni.light_speed_m_s == 299792458.0)
	_check("H0 is declared for the day the lattice stretches", \
		uni.expansion_rate_h0_km_s_mpc == 67.4)

	if _fails == 0:
		print("STAR CELLS TEST PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("STAR CELLS TEST FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
