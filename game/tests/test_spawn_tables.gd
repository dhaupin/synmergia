## test_spawn_tables.gd - the zone spawn rung: SpawnTableData /
## SpawnTableResolver / ZoneSpawner, the DataService catalog, and the
## live globe wiring.
##
## Run headless:
##
##   cd game && godot --headless --path . --script res://tests/test_spawn_tables.gd
##
## Covers:
##   1. SpawnTableResolver: convention path, prefixed variant, unknown.
##   2. DataService.get_spawn_table catalog (bare + prefixed id, unknown
##      null, list non-empty).
##   3. Every authored table's template_ids resolve to real EnemyData.
##   4. ZoneSpawner: activation by proximity, hysteresis (no thrash at the
##      ring), retire past the ring, interest from ANY tracked player.
##   5. Deterministic scatter: body_position is stable for the same key
##      (server + client agree) and distinct per index.
##   6. Live globe: the rung loads tables and materialises bodies near the
##      spawn (boot roster + rung bodies all carry respawn records).
##
## Exit 0 = all pass.
extends SceneTree

const SPAWNER = preload("res://core/world/zone_spawner.gd")
const RESOLVER = preload("res://core/schemas/spawn_table_resolver.gd")
const TERRAIN = preload("res://scenes/worlds/terrain_gen.gd")

var _pass := 0
var _fail := 0


func _ok(label: String, cond: bool, detail: String = "") -> void:
        if cond:
                _pass += 1
                print("  PASS " + label + (" " + detail if detail != "" else ""))
        else:
                _fail += 1
                print("  FAIL " + label + (" " + detail if detail != "" else ""))


func _initialize() -> void:
        call_deferred("_run")


func _run() -> void:
        print("=== SPAWN TABLES RECEIPT ===")
        _test_resolver()
        _test_catalog()
        _test_entries_resolve()
        _test_spawner_logic()
        _test_scatter()
        await _test_live_globe()
        print("=== SPAWN TABLES: %d passed, %d failed ===" % [_pass, _fail])
        quit(1 if _fail > 0 else 0)


func _test_resolver() -> void:
        print("- resolver")
        var t = RESOLVER.load_table("spawn_starter_plains")
        _ok("convention path resolves", t != null and t.id == "spawn_starter_plains")
        var t2 = RESOLVER.load_table("spawn_starter_plains")
        _ok("idempotent load", t2 != null)
        _ok("unknown id is null", RESOLVER.load_table("spawn_does_not_exist") == null)
        _ok("empty id is null", RESOLVER.load_table("") == null)


func _test_catalog() -> void:
        print("- catalog")
        var ds = root.get_node_or_null("DataService")
        _ok("DataService present", ds != null)
        if ds == null:
                return
        var all: Array = ds.get_all_spawn_tables()
        _ok("catalog non-empty", all.size() >= 6, "(%d tables)" % all.size())
        var t = ds.get_spawn_table("spawn_starter_plains")
        _ok("get by file-stem id", t != null)
        var t2 = ds.get_spawn_table("starter_plains")
        _ok("get by bare id (prefix normalized)", t2 != null)
        _ok("unknown id is null", ds.get_spawn_table("nope") == null)


func _test_entries_resolve() -> void:
        print("- entries resolve to real enemies")
        var ds = root.get_node_or_null("DataService")
        if ds == null:
                _ok("DataService present", false)
                return
        var bad: Array = []
        for table in ds.get_all_spawn_tables():
                for tid in table.template_ids():
                        if ds.get_enemy(str(tid)) == null:
                                bad.append("%s -> %s" % [str(table.id), str(tid)])
        _ok("every spawn template resolves to EnemyData", bad.is_empty(), str(bad))


func _test_spawner_logic() -> void:
        print("- spawner proximity + hysteresis")
        var table = RESOLVER.load_table("spawn_forest_meadow")
        _ok("forest table loads", table != null)
        if table == null:
                return
        var spawner = SPAWNER.new()
        spawner.configure(TERRAIN.SPAWN_CENTER, 20000.0)
        spawner.add_table(table)
        _ok("one table registered", spawner.table_count() == 1)

        # Entry 0 lives at bearing 120, reach 0.35 rad (~7000 m out).
        var entry_dir: Vector3 = _entry_dir(TERRAIN.SPAWN_CENTER, 120.0, 0.350)
        var spawn_dir: Vector3 = TERRAIN.SPAWN_CENTER.normalized()

        # At spawn, the forest entry is FAR -> nothing spawns.
        var far_plan: Dictionary = spawner.reconcile([spawn_dir])
        _ok("no spawn while far from the treeline", far_plan["spawn"].is_empty() and far_plan["retire"].is_empty())

        # Move onto the entry -> it activates.
        var near_plan: Dictionary = spawner.reconcile([entry_dir])
        _ok("entry activates on proximity", near_plan["spawn"].size() == 1, "(%d)" % near_plan["spawn"].size())
        _ok("live_count tracks activation", spawner.live_count() == 1)

        # Re-reconcile at the same spot -> no re-spawn (already live).
        var again: Dictionary = spawner.reconcile([entry_dir])
        _ok("no duplicate spawn while live", again["spawn"].is_empty())

        # Step just past the retire ring -> retires, not thrash.
        var past_dir: Vector3 = _dir_at_arc(entry_dir, 1300.0)
        var retire_plan: Dictionary = spawner.reconcile([past_dir])
        _ok("entry retires past the ring", retire_plan["retire"].size() == 1, "(%d)" % retire_plan["retire"].size())
        _ok("live_count clears on retire", spawner.live_count() == 0)

        # Interest from a SECOND player keeps it live (MMO shape).
        var p2_plan: Dictionary = spawner.reconcile([entry_dir])
        _ok("re-activates", p2_plan["spawn"].size() == 1)
        var other: Dictionary = spawner.reconcile([spawn_dir, entry_dir])
        _ok("second player keeps the region live", other["retire"].is_empty())


func _test_scatter() -> void:
        print("- deterministic scatter")
        var spawner = SPAWNER.new()
        spawner.configure(TERRAIN.SPAWN_CENTER, 20000.0)
        var point: Vector3 = TERRAIN.SPAWN_CENTER.normalized() * 20000.0
        var a: Vector3 = spawner.body_position(point, "spawn_x:0", 0, 3, 8.0)
        var b: Vector3 = spawner.body_position(point, "spawn_x:0", 0, 3, 8.0)
        _ok("same key+index -> identical position (peer agreement)", a.is_equal_approx(b))
        var c: Vector3 = spawner.body_position(point, "spawn_x:0", 1, 3, 8.0)
        _ok("distinct index -> distinct position", not a.is_equal_approx(c))
        var single: Vector3 = spawner.body_position(point, "spawn_x:0", 0, 1, 8.0)
        _ok("single body sits on the point", single.is_equal_approx(point))


func _test_live_globe() -> void:
        print("- live globe wiring")
        var boot = load("res://tests/support/globe_boot.gd")
        # Full planet scale so the rung's metres-arc rings behave as in prod.
        var globe = await boot.boot(self, 20000.0)
        if globe == null:
                _ok("globe boots", false)
                return
        _ok("globe boots", true)
        var spawner = globe.get("_zone_spawner")
        _ok("zone spawn rung loaded", spawner != null)
        if spawner != null:
                _ok("rung registered every authored table", spawner.table_count() >= 6,
                        "(%d)" % spawner.table_count())
        # The near-village boot roster still placed (the plaza is never empty).
        var spawns: Array = globe.get("_globe_spawns")
        _ok("boot roster placed with respawn records", spawns != null and spawns.size() >= 4,
                "(%d records)" % (spawns.size() if spawns != null else -1))

        # Drive a real materialisation: reconcile onto a far table's entry,
        # then let the scene build the bodies (the live integration proof).
        if spawner != null:
                var before: int = spawns.size()
                var entry_dir: Vector3 = _entry_dir(TERRAIN.SPAWN_CENTER, 120.0, 0.350)
                var plan: Dictionary = spawner.reconcile([entry_dir])
                _ok("live reconcile activates a far table", plan["spawn"].size() >= 1,
                        "(%d)" % plan["spawn"].size())
                var ds = root.get_node_or_null("DataService")
                var es = root.get_node_or_null("EntityService")
                var tm = root.get_node_or_null("TargetingManager")
                for rec in plan["spawn"]:
                        globe.call("_materialize_zone_entry", rec, ds, es, tm)
                var after: int = globe.get("_globe_spawns").size()
                _ok("bodies materialised in-world", after > before, "(%d -> %d)" % [before, after])
                var live_bodies: Dictionary = globe.get("_zone_bodies")
                var live_keys: int = live_bodies.size()
                _ok("live body bookkeeping tracks the entry", live_keys >= 1,
                        "(%d keys)" % live_keys)
                # Retire the same entry -> bodies freed, records dropped.
                globe.call("_retire_zone_bodies", str(plan["spawn"][0]["key"]))
                _ok("retire frees the entry's bodies", globe.get("_zone_bodies").size() < live_keys)

        await boot.teardown(globe, self)


## The direction of a bearing/reach on the spawn tangent frame (mirrors
## the spawner's own math, so the test is independent of it).
func _entry_dir(center: Vector3, bearing_deg: float, reach: float) -> Vector3:
        var east: Vector3 = Vector3(0, 1, 0).cross(center).normalized()
        var north: Vector3 = center.cross(east).normalized()
        var rad: float = deg_to_rad(bearing_deg)
        return (center + east * (reach * cos(rad)) + north * (reach * sin(rad))).normalized()


## A direction `arc_m` metres of ground away from `dir` along a tangent.
func _dir_at_arc(dir: Vector3, arc_m: float) -> Vector3:
        var up: Vector3 = dir.normalized()
        var east: Vector3 = Vector3(0, 1, 0).cross(up).normalized()
        var ang: float = arc_m / 20000.0
        return (up * cos(ang) + east * sin(ang)).normalized()
