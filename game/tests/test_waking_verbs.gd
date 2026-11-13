## Smoke test: the waking-verb achievement wiring (prd-quests.md section 4 --
## "extend with wake-counts (Waymaker tiers), Bloom-containment deeds, and
## companion/mount bonds"). Proves the three new event sources actually reach
## AchievementService, and that the anti-farm guards hold:
##   - waypoint_reached  -> "wake"       (once per waypoint per session)
##   - horde bloom win   -> "bloom"      (via HordeEventService._track_horde_achievements)
##   - mount_summoned    -> "mount_bond" (once per DISTINCT mount per session)
## Run: godot --headless --path . --script res://tests/test_waking_verbs.gd
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
        print("--- WAKING VERBS TEST ---")

        var ach = root.get_node_or_null("AchievementService")
        var listeners = root.get_node_or_null("AchievementListeners")
        var waypoint = root.get_node_or_null("WaypointService")
        var horde = root.get_node_or_null("HordeEventService")
        var ride = root.get_node_or_null("RideService")
        _assert("AchievementService present", ach != null)
        _assert("AchievementListeners present", listeners != null)
        _assert("WaypointService present", waypoint != null)
        _assert("HordeEventService present", horde != null)
        _assert("RideService present", ride != null)
        if ach == null or listeners == null or waypoint == null or horde == null or ride == null:
                _finish()
                return

        # --script mode: force the data + wiring the autoload _ready may not have
        # reached yet (same guard test_achievement_flow uses).
        var defs: Array = ach.get_all_achievements()
        if defs.is_empty():
                var ds = root.get_node_or_null("DataService")
                if ds and ds.has_method("load_all_data"):
                        ds.load_all_data()
                if ach.has_method("_load_achievement_definitions"):
                        ach._load_achievement_definitions()
        defs = ach.get_all_achievements()
        _assert("defs loaded (%d)" % defs.size(), defs.size() >= 10)

        _assert("waymaker_1 def present", _find_def(defs, "waymaker_1") != null)
        _assert("waymaker_10 def present", _find_def(defs, "waymaker_10") != null)
        _assert("waymaker_50 def present", _find_def(defs, "waymaker_50") != null)
        _assert("bloom_contained def present", _find_def(defs, "bloom_contained") != null)
        _assert("mount_bonded def present", _find_def(defs, "mount_bonded") != null)

        # Signals are connected by the listener bridge. In --script mode the
        # autoload _ready has run (autoloads attach before _init), but call the
        # connect entry points directly to be order-independent.
        listeners._connect_all()
        listeners._connect_ride_bridge()

        _test_waypoint_wakes(listeners, ach)
        _test_waypoint_antifarm(listeners, ach)
        _test_mount_bond(listeners, ach)
        _test_mount_bond_antifarm(listeners, ach)
        _test_bloom_containment(horde, ach)

        _finish()


## A reached waypoint wakes a road: waymaker_1 unlocks on the first one.
## The reward grant is local-player-only (see _grant_rewards), so the title is
## exercised directly through TitleService with the id the def names.
func _test_waypoint_wakes(listeners, ach) -> void:
        var pid := "wake_player_%d" % Time.get_ticks_msec()
        listeners._on_waypoint_reached(pid, "wp_alpha")
        _assert("waypoint_reached unlocks waymaker_1", ach.has_unlocked(pid, "waymaker_1"))
        var ts = root.get_node_or_null("TitleService")
        _assert("TitleService present", ts != null)
        if ts != null:
                ts.unlock(pid, "waymaker")
                _assert("waymaker title resolves and unlocks",
                        _title_unlocked(pid, "waymaker"))


## Parking on one beacon must not climb the tiers: 12 reaches of the SAME id
## still leave waymaker_10 (target 10) locked.
func _test_waypoint_antifarm(listeners, ach) -> void:
        var pid := "wake_farm_%d" % Time.get_ticks_msec()
        for i in 12:
                listeners._on_waypoint_reached(pid, "wp_same")
        _assert("repeat reaches of one waypoint do not farm waymaker_10",
                not ach.has_unlocked(pid, "waymaker_10"))


## Three DISTINCT mounts bond; the third unlocks mount_bonded.
func _test_mount_bond(listeners, ach) -> void:
        var pid := "mount_player_%d" % Time.get_ticks_msec()
        for m in ["mount_meadow_pacer", "mount_gullwing", "mount_pearl_ray"]:
                listeners._on_mount_summoned(pid, m)
        _assert("three distinct mounts unlock mount_bonded", ach.has_unlocked(pid, "mount_bonded"))


## Summoning the SAME mount repeatedly must not bond.
func _test_mount_bond_antifarm(listeners, ach) -> void:
        var pid := "mount_farm_%d" % Time.get_ticks_msec()
        for i in 6:
                listeners._on_mount_summoned(pid, "mount_gullwing")
        _assert("repeat summons of one mount do not bond",
                not ach.has_unlocked(pid, "mount_bonded"))


## A completed Bloom horde is a containment deed: the real
## HordeEventService._track_horde_achievements path credits "bloom".
func _test_bloom_containment(horde, ach) -> void:
        var pid := "bloom_player_%d" % Time.get_ticks_msec()
        var h := {"participants": {pid: {"damage": 100, "kills": 2}}}
        var rewards := {pid: {"gold": 10}}
        horde._track_horde_achievements("bloom_cull", h, rewards)
        _assert("bloom horde completion unlocks bloom_contained",
                ach.has_unlocked(pid, "bloom_contained"))
        # A non-bloom horde must NOT credit containment.
        var pid2 := "horde_player_%d" % Time.get_ticks_msec()
        var h2 := {"participants": {pid2: {"damage": 100, "kills": 2}}}
        var r2 := {pid2: {"gold": 10}}
        horde._track_horde_achievements("storm_wolves", h2, r2)
        _assert("non-bloom horde does not credit bloom containment",
                not ach.has_unlocked(pid2, "bloom_contained"))


func _title_unlocked(player_id: String, title_id: String) -> bool:
        var ts = root.get_node_or_null("TitleService")
        if ts == null or not ts.has_method("is_unlocked"):
                return false
        return bool(ts.is_unlocked(player_id, title_id))


func _find_def(defs: Array, id: String) -> AchievementData:
        for d in defs:
                if d is AchievementData and d.id == id:
                        return d
        return null


func _assert(name: String, cond: bool) -> void:
        if cond:
                _pass += 1
                print("  PASS: " + name)
        else:
                _fail += 1
                print("  FAIL: " + name)


func _finish() -> void:
        print("--- %d passed, %d failed ---" % [_pass, _fail])
        quit(0 if _fail == 0 else 1)
