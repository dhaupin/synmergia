extends SceneTree
const RngScript = preload("res://core/frame/srv/cosmic_rng.gd")
const CosmicScript = preload("res://core/frame/srv/cosmic_entropy.gd")

func _init() -> void:
	var table = load("res://data/loot_tables/loot_sky_crate_daily.tres")
	var counts := {}
	for day in range(30):
		var c = CosmicScript.new()
		c.feed_kp(0.33 + 0.1 * (day % 7))
		var r = RngScript.new(true)
		r.stir_from_cosmic(c)
		var roll: Dictionary = table.roll_drop(r.stream_for("loot/sky_crate_daily/%d" % day))
		var key := str(roll["items"]) + str(roll["currency"])
		counts[key] = counts.get(key, 0) + 1
	var distinct := counts.size()
	var mode := 0
	for k in counts:
		mode = maxi(mode, counts[k])
	print("distinct=%d mode=%d/30" % [distinct, mode])
	quit(0)
