## Probe: the daily sky crate end-to-end. Load the loot table, roll it
## through a CosmicRng stream stirred by real Kp readings, verify the
## quest reward parses with the crate item, and confirm determinism.
extends SceneTree

const RngScript = preload("res://core/frame/srv/cosmic_rng.gd")
const CosmicScript = preload("res://core/frame/srv/cosmic_entropy.gd")

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# 1. Loot table loads and rolls.
	var table = load("res://data/loot_tables/loot_sky_crate_daily.tres")
	_check("loot table loads", table != null and table.has_method("roll_drop"))

	# 2. Roll through a cosmic-stirred master RNG stream (the wiring
	#    the loot resolver contract expects: an injected RNG).
	var cosmic = CosmicScript.new()
	cosmic.feed_kp(5.67)  # the Oct 4 storm
	var rng = RngScript.new(true)
	rng.stir_from_cosmic(cosmic)
	var stream = rng.stream_for("loot/sky_crate_daily")
	var result: Dictionary = table.roll_drop(stream)
	_check("roll_drop returns items+currency", result.has("items") and result.has("currency"))
	_check("guaranteed gold dropped", result["got_any"])

	# 3. Determinism: same cosmic history + scope replays identically.
	var cosmic2 = CosmicScript.new()
	cosmic2.feed_kp(5.67)
	var rng2 = RngScript.new(true)
	rng2.stir_from_cosmic(cosmic2)
	var stream2 = rng2.stream_for("loot/sky_crate_daily")
	var result2: Dictionary = table.roll_drop(stream2)
	_check("storm-day crate roll is replayable",
		str(result["items"]) == str(result2["items"]) and str(result["currency"]) == str(result2["currency"]))

	# 4. A calm sky gives a different crate than a storm.
	var calm = CosmicScript.new()
	calm.feed_kp(0.33)
	var rng_calm = RngScript.new(true)
	rng_calm.stir_from_cosmic(calm)
	var result_calm: Dictionary = table.roll_drop(rng_calm.stream_for("loot/sky_crate_daily"))
	_check("calm-day crate differs from storm-day",
		str(result_calm["items"]) != str(result["items"]) or str(result_calm["currency"]) != str(result["currency"]))

	# 5. Crate item + quest reward parse.
	var item = load("res://data/consumables/item_sky_crate_daily.tres")
	_check("crate item loads", item != null and item.id == "item_sky_crate_daily")
	var quest = load("res://data/quests/quest_watch_the_sky.tres")
	_check("quest loads", quest != null)
	var crate_rewards := []
	for r in quest.rewards:
		if r.get("type", "") == "item":
			crate_rewards.append(r)
	_check("quest rewards include the crate", crate_rewards.size() == 1
		and crate_rewards[0]["id"] == "item_sky_crate_daily")

	# 6. 30 days of quiet skies: crate contents vary day to day.
	var seen: Array[String] = []
	for day in range(30):
		var c = CosmicScript.new()
		c.feed_kp(0.33 + 0.1 * (day % 7))
		var r = RngScript.new(true)
		r.stir_from_cosmic(c)
		var roll: Dictionary = table.roll_drop(r.stream_for("loot/sky_crate_daily/%d" % day))
		seen.append(str(roll["items"]) + str(roll["currency"]))
	var uniq := {}
	for s in seen:
		uniq[s] = true
	_check("30 days yield varied crates (%d distinct)" % uniq.size(), uniq.size() > 10)

	print("SkyCrate probe: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _check(label: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("  PASS %s" % label)
	else:
		_failed += 1
		print("  FAIL %s" % label)
