## SpawnTableResolver - convention-path loader for SpawnTableData.
##
## Mirrors loot_table_resolver.gd / horde_data_resolver.gd: config ids
## are bare ids ("spawn_forest_meadow"), resolved as
##   1. res://data/spawn_tables/<id>.tres        (the convention)
##   2. res://data/spawn_tables/spawn_<id>.tres  (prefixed variant)
##   3. DataService.get_spawn_table(id)          (runtime-registered)
##
## Frame-primitive rules: pure functions over the filesystem, no autoload
## dependency in the parse-time path (DataService is probed defensively
## so --script test mode stays parseable).
extends RefCounted

const SPAWN_DIR := "res://data/spawn_tables"

static func load_table(table_id: String):
        var tid := table_id.strip_edges()
        if tid.is_empty():
                return null
        for candidate in [SPAWN_DIR + "/" + tid + ".tres", SPAWN_DIR + "/spawn_" + tid + ".tres"]:
                if ResourceLoader.exists(candidate):
                        var res: Resource = load(candidate)
                        if res != null and res.has_method("clean_entries"):
                                return res
        var ml: MainLoop = Engine.get_main_loop()
        if ml != null and ml is SceneTree:
                var ds: Node = (ml as SceneTree).root.get_node_or_null("DataService")
                if ds != null and ds.has_method("get_spawn_table"):
                        var served = ds.call("get_spawn_table", tid)
                        if served != null and served.has_method("clean_entries"):
                                return served
        return null
