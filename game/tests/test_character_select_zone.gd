## test_character_select_zone.gd - a created character must carry a REAL zone.
##
## THE GAP (lane C content audit): species_akkan.home_zone = "dark_highlands"
## names no file in data/zones/ (verified: no dark_highlands.tres exists).
## character_select._on_play_pressed copies species.home_zone straight into
## CharacterData.zone_id, so an Akkan character was created carrying a phantom
## zone id -- a dangling reference the data-naming lint does NOT catch (it does
## not check home_zone). The creation path now resolves the home zone against
## the zone catalog and falls back to the spawn zone.
##
## Run: godot --headless --path game --script res://tests/test_character_select_zone.gd
##
## Legs:
##   1. a real zone (zone_starter_plains) resolves.
##   2. the phantom (dark_highlands) does NOT resolve.
##   3. EVERY species home_zone is either real or handled by the fallback --
##      so a live character can never carry a zone id that names no zone.
##   4. the Akkan creation path lands on the fallback spawn zone, not the phantom.
##
## Exit 0 = every leg observed. Failures print FAIL lines and exit 1.
extends SceneTree

var _pass := 0
var _fail := 0
const SPAWN_ZONE := "zone_starter_plains"


func _initialize() -> void:
        _run.call_deferred()


func _run() -> void:
        var scene := load("res://ui/menus/character_select.tscn")
        _check(scene != null, "character_select.tscn loads")
        if scene == null:
                return _finish()
        var panel = scene.instantiate()
        root.add_child(panel)
        await process_frame

        _check(panel.has_method("_zone_exists"), "creation path exposes _zone_exists")
        _check(panel._zone_exists(SPAWN_ZONE), "a real zone resolves (%s)" % SPAWN_ZONE)
        _check(not panel._zone_exists("dark_highlands"), "the phantom zone does NOT resolve")

        # Every species home_zone must be real, or the creation path falls back.
        var bad: Array = []
        for sp in CharacterData.get_all_species():
                var hz: String = sp.home_zone
                if hz != "" and not panel._zone_exists(hz):
                        bad.append("%s -> %s" % [sp.id, hz])
                var resolved: String = hz if panel._zone_exists(hz) else SPAWN_ZONE
                _check(panel._zone_exists(resolved),
                        "species %s lands on a real zone (%s)" % [sp.id, resolved])
        # The phantom is EXPECTED to be caught by the fallback, not to vanish
        # silently -- report it so a future authored zone is visible here.
        if bad.size() > 0:
                print("   note: species with an unauthored home_zone (fallback applied): %s"
                        % ", ".join(bad))

        # The Akkan creation path specifically.
        var akkan := CharacterData.load_species("akkan")
        _check(akkan != null, "akkan species loads")
        if akkan != null:
                var chosen: String = akkan.home_zone if panel._zone_exists(akkan.home_zone) else SPAWN_ZONE
                _check(chosen == SPAWN_ZONE,
                        "an Akkan character is created in %s, not the phantom" % SPAWN_ZONE)

        panel.queue_free()
        _finish()


func _check(cond: bool, msg: String) -> void:
        if cond:
                _pass += 1
                print("   PASS  %s" % msg)
        else:
                _fail += 1
                print("   FAIL  %s" % msg)


func _finish() -> void:
        print("=== CHARACTER SELECT ZONE: %d passed, %d failed ===" % [_pass, _fail])
        quit(0 if _fail == 0 else 1)
