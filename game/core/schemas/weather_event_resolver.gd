## WeatherEventResolver - convention-path loader for WeatherEventData.
##
## Mirrors HordeDataResolver/loot_table_resolver: config ids are bare
## ids ("storm_pack"), resolved as
##   1. res://data/weather_events/weather_<id>.tres  (the convention)
##   2. res://data/weather_events/<id>.tres          (unprefixed variant)
##   3. DataService.get_weather_event(id)            (service hook)
## Duck-types on the to_config() surface (the GuardData lesson): new
## schemas miss the global class_name cache until an editor import pass.
extends RefCounted

const WEATHER_DIR := "res://data/weather_events"

static func load_config(config_id: String):
	var cid := config_id.strip_edges()
	if cid.is_empty():
		return null
	for candidate in [WEATHER_DIR + "/weather_" + cid + ".tres", WEATHER_DIR + "/" + cid + ".tres"]:
		if ResourceLoader.exists(candidate):
			var res: Resource = load(candidate)
			if res != null and res.has_method("to_config"):
				return res
	var ml: MainLoop = Engine.get_main_loop()
	if ml != null and ml is SceneTree:
		var ds: Node = (ml as SceneTree).root.get_node_or_null("DataService")
		if ds != null and ds.has_method("get_weather_event"):
			var served = ds.call("get_weather_event", cid)
			if served != null and served.has_method("to_config"):
				return served
	return null
