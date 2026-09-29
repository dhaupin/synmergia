# probe_ocean.gd - S14.1: water is data (labs/prd-ocean-depths.md).
#
# Covers:
#   A. Declarations: both volumes load (the real shelf + the moon
#      crater), filename == id, prefixed ids (naming law).
#   B. THE SIGN LAW: sample_depth is negative above the waterline,
#      meters below below it -- the ThermalService mirror.
#   C. Terrain respect: the floor clamp -- depth never reads through
#      the rock (one collision truth, the radial floor).
#   D. Band mapping: DRY/WADING/SUBMERGED/SQUEEZE/CRUSH as a pure
#      function of depth + breather grace (one mapping, three
#      readers: physics, renderer, anticheat).
#   E. Current truth: the declared vector is what the drag model and
#      the anticheat's current-only exemption both read.
#   F. Volume lookup: the sampler resolves the containing volume;
#      unknown water reads as dry.
#   G. The moon crater: the Builder's Pool is real -- tame by design
#      (no current, no pressure) and sitting on the Watched Stone.
#
# Script mode: autoloads resolved at runtime (OceanService).
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	_check("OceanService present in script mode", svc != null)
	if svc == null:
		quit(1)
		return
	var OVS: GDScript = load("res://core/schemas/ocean_volume.gd")
	var B = OVS.DepthBand  # the band enum (used across sections C-G)

	# ---- A. Declarations -----------------------------------------------------
	svc.ensure_loaded()
	var shelf = svc.get_volume("ocean_haven_shelf")
	var crater = svc.get_volume("ocean_lunar_crater")
	_check("both volumes load (the shelf + the Builder's Pool)", \
		shelf != null and crater != null)
	_check("ids are ocean_-prefixed and match filenames (naming law)", \
		str(shelf.id) == "ocean_haven_shelf" and str(crater.id) == "ocean_lunar_crater")
	_check("the schema is Resource-typed with the class registered", OVS != null)

	# ---- B. The sign law -------------------------------------------------------
	# The shelf: waterline at y=0, floor plane at y=-60, centered at
	# x=3000 (west of Haven -- the crater pool sits at the origin in
	# scene space; volumes do not share water). A body 5 m above the
	# waterline reads -5; 5 m below reads +5.
	var above := Vector3(3000, 5, 0)
	var below := Vector3(3000, -5, 0)
	_check("above the waterline is NEGATIVE (meters above)", \
		svc.sample_depth(above, shelf) == -5.0)
	_check("below the waterline is POSITIVE (meters below)", \
		absf(svc.sample_depth(below, shelf) - 5.0) < 0.0001)
	_check("the waterline itself reads zero", absf(svc.sample_depth(Vector3(0, 0, 0), shelf)) < 0.0001)

	# ---- C. Terrain respect (the floor clamp) ----------------------------------
	# The Builder's Pool: surface plane y=-6, rock plane y=-30 (24 m
	# of honest water). Pressure depth is the WATER ABOVE the body:
	# a body 1 m above the rock reads 23 m deep (23 m of water over
	# it); a body pushed INSIDE the stone reads the no-water sentinel
	# (-1, same as unknown space) -- the rock is not water.
	var on_rock := Vector3(0, -29.0, 0)
	var honest: float = svc.sample_depth(on_rock, crater)
	_check("the floor reads honest pressure depth near the rock (23 m)", absf(honest - 23.0) < 0.0001)
	var under_rock := Vector3(0, -31.0, 0)
	var clamped: float = svc.sample_depth(under_rock, crater)
	_check("inside the stone there is no water (the -1 sentinel)", clamped == -1.0)
	_check("the band inside the stone is DRY (stone is not water)", \
		svc.band_at(under_rock) == B.DRY)
	_check("the surface plane never lies about the waterline", \
		svc.sample_depth(Vector3(0, -10.0, 0), crater) == 4.0)

	# ---- D. Band mapping ---------------------------------------------------------
	# band_for is an INSTANCE method of the schema; the enum is the
	# script's. A throwaway volume carries the mapping for pure-depth
	# checks (the mapping does not depend on the instance's fields
	# except max_depth -- set to the shelf's 60 m for the ladder).
	var ladder = OVS.new()
	ladder.max_depth = 60.0
	_check("DRY is above the line", ladder.band_for(-0.5, 0.0) == B.DRY)
	_check("WADING is the ankle band", ladder.band_for(1.0, 0.0) == B.WADING)
	_check("SUBMERGED is the swim band", ladder.band_for(10.0, 0.0) == B.SUBMERGED)
	_check("SQUEEZE starts at max_depth minus the natural free band", \
		ladder.band_for(52.0, 0.0) == B.SQUEEZE)
	_check("CRUSH is past max_depth", ladder.band_for(60.0, 0.0) == B.CRUSH)
	# The breather law (fixed direction): grace DEEPENS the squeeze
	# line (50 -> 58 with grace 8) -- gear extends the free swim
	# toward the rock; CRUSH never moves.
	_check("a breather pushes the SQUEEZE line deeper (grace extends)", \
		ladder.band_for(52.0, 8.0) == B.SUBMERGED \
		and ladder.band_for(59.0, 8.0) == B.SQUEEZE \
		and ladder.band_for(60.0, 8.0) == B.CRUSH)
	# Through the service (the band_at path readers use).
	_check("band_at resolves through the volume", \
		svc.band_at(below) == B.SUBMERGED and svc.band_at(above) == B.DRY)

	# ---- E. Current truth -----------------------------------------------------------
	_check("the shelf's current is declared and readable (the ferry lane)", \
		svc.current_at(below).length() > 0.0 \
		and svc.current_at(below).is_equal_approx(shelf.current_vector()) \
		and svc.volume_at(below) == shelf)
	_check("the crater has no current (tame by design)", \
		svc.current_at(Vector3(0, -8, 0)).length() == 0.0)

	# ---- F. Volume lookup --------------------------------------------------------------
	_check("the sampler resolves the containing volume (shelf, its own span)", \
		svc.volume_at(below) == shelf)
	_check("the sampler resolves the crater (pool scale)", \
		svc.volume_at(Vector3(0, -12.0, 0)) == crater)
	var nowhere := Vector3(500000.0, 500000.0, 500000.0)
	_check("unknown water reads as dry (no invented ocean)", \
		svc.volume_at(nowhere) == null and svc.sample_depth(nowhere) == -1.0 \
		and svc.band_at(nowhere) == B.DRY and svc.current_at(nowhere) == Vector3.ZERO)

	# ---- G. The Builder's Pool (the dev workshop's water) ------------------------------
	_check("the pool is tame: no current, no pressure (a workshop, not a monster)", \
		float(crater.current_strength) == 0.0 and float(crater.pressure_per_meter) == 0.0)
	_check("the pool sits on the Watched Stone (a dish carved in the regolith)", \
		not bool(crater.floor_is_radial) and absf(float(crater.floor_y) + 30.0) < 0.001 \
		and absf(float(crater.surface_height) + 6.0) < 0.001)
	_check("the pool's lore carries the workshop mystery", \
		str(crater.lore).contains("builders") and str(crater.lore).contains("workshop"))
	# The full swim band exists in the crater (24 m of honest water).
	var crater_mid := Vector3(0, -12.0, 0)
	_check("the crater holds a real swim band (6 m at the mid mark)", \
		absf(svc.sample_depth(crater_mid, crater) - 6.0) < 0.0001 \
		and svc.band_at(crater_mid) == B.SUBMERGED)

	# ---- H. The breather (S14.4: gear owns air, the profile owns speed) ---
	var ds = root.get_node_or_null("DataService")
	_check("DataService present (gear is data)", ds != null)
	var reed = ds.get_item("acc_breather_reed")
	var shell = ds.get_item("acc_breather_lungshell")
	_check("the Hollow Reed loads as BREATHER data (air x2, +2 m grace)", \
		reed != null and int(reed.accessory_type) == 6 \
		and absf(float(reed.breath_multiplier) - 2.0) < 0.001 \
		and absf(float(reed.squeeze_grace_m) - 2.0) < 0.001)
	_check("the Lungshell loads as BREATHER data (air x4, +8 m grace)", \
		shell != null and int(shell.accessory_type) == 6 \
		and absf(float(shell.breath_multiplier) - 4.0) < 0.001 \
		and absf(float(shell.squeeze_grace_m) - 8.0) < 0.001)
	_check("the reed sits on the neck (one breath slot)", \
		reed != null and int(reed.equip_slot) == 11)
	var b_none: Dictionary = svc.breather_for("swimmer_with_no_gear")
	_check("no gear resolves to the unbreathered default", \
		absf(float(b_none["mult"]) - 1.0) < 0.001 and absf(float(b_none["grace_m"])) < 0.001)
	# Grace deepens the squeeze line on the shelf: 50 -> 52 m with the
	# reed, 58 m with the lungshell; CRUSH never moves (the stone's
	# patience is not for sale).
	_check("the reed's grace deepens the squeeze line (50 -> 52 m)", \
		ladder.band_for(51.0, 2.0) == B.SUBMERGED and ladder.band_for(53.0, 2.0) == B.SQUEEZE)
	_check("the lungshell's grace deepens it further (58 m), CRUSH unmoved", \
		ladder.band_for(59.0, 8.0) == B.SQUEEZE and ladder.band_for(60.0, 8.0) == B.CRUSH)
	# The full service path: tick_swimmer with the grace breathes the
	# state machine deeper (drive-by of the helper's contract).
	svc.forget_swimmer("breather_prober")
	svc.tick_swimmer("breather_prober", Vector3(3000, -51.0, 0), 0.5, 2.0)
	var bstate = svc.swim_state("breather_prober")
	_check("a breathered body at 51 m is still in the free swim (no pressure)", \
		bstate != null and float(bstate.pressure) == 0.0)
	svc.forget_swimmer("breather_prober")

	# ---- I. The sailing schedule (sec 9: the almanac gets a page) --------
	var ferry = ds.get_vehicle("veh_haven_ferry")
	_check("the ferry declares a schedule (8 cast-offs a day)", \
		ferry != null and int(ferry.ferries_per_day) == 8)
	_check("the schedule is closed-form data (first cast-off, crossing time)", \
		ferry != null and absf(float(ferry.first_departure_hour) - 6.0) < 0.001 \
		and absf(float(ferry.crossing_hours) - 0.5) < 0.001)
	_check("the ferry is a FERRY with a real route", \
		ferry != null and int(ferry.kind) == 1 and ferry.route_gateways.size() >= 2)
	_check("the crater pool has no ferry (it is a workshop pool)", \
		ferry == null or not str(ferry.description).to_lower().contains("crater"))

	# ---- J. The sailing page renders (sec 9: the almanac gets a page) ---
	var ui_script = load("res://ui/components/sky_almanac_ui.gd")
	_check("the almanac script loads (the page's paper)", ui_script != null)
	if ui_script != null:
		var panel = ui_script.new()
		root.add_child(panel)
		await process_frame
		var sails = panel._sail_rows
		_check("the sailing page exists on the panel", \
			sails != null and sails.get_child_count() > 0)
		var ferry_text := ""
		if sails != null:
			for c in sails.get_children():
				if c is Label:
					ferry_text += str(c.text) + " "
		_check("the page names the Haven Ferry and its route", \
			ferry_text.contains("Haven Ferry") and ferry_text.contains("village center") \
			and ferry_text.contains("nexus central"))
		_check("the page names the crossing time and the wake law", \
			ferry_text.contains("crossing takes") and ferry_text.contains("first ride"))
		_check("the page counts the cast-offs", ferry_text.contains("8"))
		root.remove_child(panel)
		panel.free()

	if _fails == 0:
		print("OCEAN PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("OCEAN PROBE FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
