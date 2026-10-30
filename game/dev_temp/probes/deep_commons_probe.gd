## deep_commons_probe - S15.7 the underworld's world-commons receipt:
##   1) LAVA AS WATER-FRAME DATA: lava_underglow_lake loads off the
##      ocean service with the LAVA liquid body + the bite (8 dps),
##      and the same claim law that reads the cistern reads the lake;
##   2) THE BURN LAW (live): a body left in the lake accrues damage in
##      whole digits through the underworld's own _process tick;
##   3) THE AIRFLOW LAW: standing vents carry a body upward through
##      the underworld tick, the Ascent thrower sleeps until the
##      ritual wakes it, and a woken thrower HURLS (launch ticket
##      rides the same sample);
##   4) THE WEATHER LAW: weather_mist is a pure closed form of the
##      tide (thin at the crest, thick at the low tide) and the live
##      environment receives it;
##   5) THE TRAIL + THE BANDS: two trail legs of plates, and the five
##      biome bands ride their declarations (counts match the data).
## Run headless: godot --headless --path . --script res://dev_temp/probes/deep_commons_probe.gd
extends SceneTree

const UNDER_SCENE := "res://scenes/worlds/globe_underworld.tscn"

# SCRIPT-MODE LAW: no const preloads of game scripts (autoload
# identifiers register after parse; load at RUNTIME, _run only).

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("COMMONS-PASS %s %s" % [label, detail])
	else:
		_fails += 1
		print("COMMONS-MISS %s %s" % [label, detail])


## A stand-in body: just enough shape for the underworld's live
## chemistry (position, id, health, velocity, burn through
## take_damage). Nothing else -- no physics world, no inventory.
class ProbeBody extends Node3D:
	var entity_id: String = "commons_probe_body"
	var hit_points: int = 100
	var velocity: Vector3 = Vector3.ZERO
	func take_damage(amount: int, _source = null, _dtype: String = "physical") -> int:
		hit_points -= amount
		return amount


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var OceanServiceScript = load("res://core/services/ocean_service.gd")
	var VolumeScript = load("res://core/schemas/ocean_volume.gd")
	# 1) LAVA IS WATER-FRAME DATA
	var svc = OceanServiceScript.new()
	root.add_child(svc)
	for _i in range(2):
		await root.get_tree().process_frame
	var lake = svc.get_volume("lava_underglow_lake")
	if lake == null:
		print("COMMONS-MISS lava_underglow_lake did not load")
		quit(1)
		return
	_check("lake_data", str(lake.id) == "lava_underglow_lake" and int(lake.liquid) == int(VolumeScript.Liquid.LAVA) \
		and float(lake.burn_dps) > 0.0, "burn=%.1f" % float(lake.burn_dps))
	_check("lake_gentle_pressure", float(lake.pressure_per_meter) == 0.0)
	var in_lake := Vector3(-26, 2001.0, 20)
	var depth: float = svc.sample_depth(in_lake)
	_check("lake_claim", depth > 0.0 and absf(depth - 0.2) < 0.15, "depth=%.2f" % depth)
	_check("lake_wading", svc.band_at(in_lake) != VolumeScript.DepthBand.DRY)
	# The cistern stays WATER (the lava bite is the lake's alone).
	var pool = svc.get_volume("ocean_deep_root_pool")
	if pool != null:
		_check("cistern_stays_water", int(pool.liquid) == int(VolumeScript.Liquid.WATER) and float(pool.burn_dps) == 0.0)
	var r: Dictionary = svc.tick_swimmer("statics_lava", in_lake, 1.0 / 60.0)
	_check("tick_returns_liquid", r.has("liquid") and int(r["liquid"]) == int(VolumeScript.Liquid.LAVA) \
		and float(r.get("burn_dps", 0.0)) > 0.0 and r.has("current"))
	svc.forget_swimmer("statics_lava")

	# Boot the globe for the live laws (the cistern probe pattern).
	var packed: PackedScene = load(UNDER_SCENE)
	if packed == null:
		print("COMMONS-MISS globe_underworld.tscn missing")
		quit(1)
		return
	var under: Node = packed.instantiate()
	root.add_child(under)
	for _i in range(10):
		await root.get_tree().process_frame
	var wr: Node = under.get("world_root")
	var body := ProbeBody.new()
	root.add_child(body)

	# 2) THE BURN LAW (live): park IN the lake, run frames, watch the
	#    accrual pay out in whole digits.
	(under.get("_visitors") as Dictionary)["commons_probe_body"] = body
	body.global_position = wr.global_position + Vector3(-26, 2001.0, 20)
	var before: int = body.hit_points
	for _i in range(60):
		under._process(1.0 / 60.0)
	var dipped: int = before - body.hit_points
	_check("lava_burns", dipped >= 5 and dipped <= 10, "dps~8 over 1 s, took %d" % dipped)
	# Parked at camp afterwards: the burn stops (leave for free).
	body.global_position = wr.global_position + under.get("CAMP_HEAD_POS")
	var mid: int = body.hit_points
	for _i in range(30):
		under._process(1.0 / 60.0)
	_check("dry_is_free", body.hit_points == mid)

	# 3) THE AIRFLOW LAW
	var thermo = root.get_node_or_null("ThermalService")
	if thermo == null:
		print("COMMONS-MISS ThermalService missing")
		_fails += 1
	else:
		# A standing vent carries.
		body.global_position = wr.global_position + Vector3(24, 2000.6, -14)
		body.velocity = Vector3.ZERO
		under._process(1.0 / 60.0)
		_check("vent_carries", body.velocity.y > 0.0 and str(thermo.updraft_at(body.global_position - wr.global_position)) == "thermal_underworld_vent_east")
		# A hold still samples when the underworld is not ticking... the
		# law is the column: direct sample truth.
		_check("vent_column", float(thermo.sample(body.global_position - wr.global_position)) > 0.0)
		# THE THROWER: RITUAL -- asleep means nothing answers.
		var sleep_pos := Vector3(4.0, 2000.6, 4.0)
		body.global_position = wr.global_position + sleep_pos
		body.velocity = Vector3.ZERO
		under._process(1.0 / 60.0)
		_check("thrower_sleeps", body.velocity.y <= 0.0 and not thermo.is_awake("thermal_ascent_thrower"))
		# The rite: the shard wakes it; NOW the column hurls.
		thermo.awaken_launcher("thermal_ascent_thrower")
		body.velocity = Vector3.ZERO
		under._process(1.0 / 60.0)
		var hurled: bool = body.velocity.y > 0.0 and float(thermo.sample_launch(body.global_position - wr.global_position)) > 0.0
		_check("thrower_hurls", hurled)
		# Clean the rite book so the probe is idempotent across boots.
		thermo._awake.erase("thermal_ascent_thrower")
		for u in thermo.get_updrafts():
			if str(u.id) == "thermal_ascent_thrower":
				u.awakened = false
		var DictStoreScript = load("res://adapters/persistence/dict_store.gd")
		var store: Object = DictStoreScript.new()
		store.set_kv("thermals:awake", [])

	# 4) THE WEATHER LAW (the underworld relates its own mist).
	var Under = load("res://scenes/worlds/globe_underworld.gd")
	var thick_at_low: float = Under.weather_mist(0.5)
	var thin_at_high: float = Under.weather_mist(0.0)
	_check("mist_band", thick_at_low > thin_at_high and thick_at_low <= 0.055 and thin_at_high >= 0.02, \
		"phase 0=%.3f phase 0.5=%.3f" % [thin_at_high, thick_at_low])
	var env = under.get("_world_env")
	if env != null:
		var phase: float = under._glow_tide_phase()
		under._process(0.0)
		var fed: float = float(env.fog_density)
		_check("mist_fed", absf(fed - Under.weather_mist(phase)) < 0.02)

	# 5) THE TRAIL + THE BANDS (declarations own the wilds).
	var trail: Node = wr.get_node_or_null("DeepTrail")
	if trail == null:
		_check("trail_root", false)
	else:
		var plates := 0
		var legs := {}
		var camp_head: Vector3 = under.get("CAMP_HEAD_POS")
		var nearest: float = 9999.0
		for c in trail.get_children():
			plates += 1
			var tag := str(c.name).split("_")[1]
			legs[tag] = true
			var d: Vector3 = (c.position as Vector3) - camp_head + Vector3(0, 0, 0)
			nearest = minf(nearest, Vector3(d.x, 0.0, d.z).length())
		_check("trail_plates", plates == 32 and legs.size() == 2, "plates=%d legs=%d" % [plates, legs.size()])
		_check("trail_starts_camp", nearest < 2.0, "nearest=%.2f" % nearest)
	var bands: Dictionary = under._wire_bands()
	_check("five_bands", bands.size() == 5, "bands=%d" % bands.size())
	var want := {"biome_underworld_crag_ring": 12, "biome_underworld_dead_grove": 7, \
		"biome_underworld_mycelium_field": 9, "biome_underworld_stalagmite_runs": 14, \
		"biome_underworld_odd_grasses": 36}
	var band_ok := true
	for id_v in want:
		var b = bands.get(id_v)
		if b == null or int(b.count) != int(want[id_v]):
			band_ok = false
			break
	_check("band_counts_match_data", band_ok)

	if _fails > 0:
		print("COMMONS-FAIL %d" % _fails)
		quit(1)
		return
	print("COMMONS-OK")
	quit(0)
