## HordeDataResolver - convention-path loader for HordeData configs.
##
## Mirrors loot_table_resolver.gd: config ids are bare ids ("trollmoot"),
## resolved as
##   1. res://data/hordes/<id>.tres            (the convention)
##   2. res://data/hordes/horde_<id>.tres      (prefixed variant)
##   3. DataService.get_horde(id)              (future service hook)
##
## Frame-primitive rules: pure functions over the filesystem, no
## autoload dependency in the parse-time path (DataService is probed
## defensively so --script test mode stays parseable).
extends RefCounted

const HORDE_DIR := "res://data/hordes"

static func load_config(config_id: String):
	var cid := config_id.strip_edges()
	if cid.is_empty():
		return null
	# 1 + 2: convention paths (direct and prefixed).
	for candidate in [HORDE_DIR + "/" + cid + ".tres", HORDE_DIR + "/horde_" + cid + ".tres"]:
		if ResourceLoader.exists(candidate):
			var res: Resource = load(candidate)
			if res != null and res.get_script() != null and str(res.get_script().get_instance_base_type()) == "Resource":
				# Duck-type on the to_config() surface rather than a
				# class_name check (new schemas miss the global cache
				# until an editor import pass -- the GuardData lesson).
				if res.has_method("to_config"):
					return res
	# 3: DataService hook (when the catalog exists).
	var ml: MainLoop = Engine.get_main_loop()
	if ml != null and ml is SceneTree:
		var ds: Node = (ml as SceneTree).root.get_node_or_null("DataService")
		if ds != null and ds.has_method("get_horde"):
			var served = ds.call("get_horde", cid)
			if served != null and served.has_method("to_config"):
				return served
	return null
