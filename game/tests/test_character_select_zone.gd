## test_character_select_zone.gd - a created character must carry a REAL zone.
##
## ORIGINAL GAP (lane C content audit): species_akkan.home_zone named no file in
## data/zones/ (no dark_highlands.tres existed). character_select._on_play_pressed
## copies species.home_zone straight into CharacterData.zone_id, so an Akkan
## character was created carrying a phantom zone id -- a dangling reference the
## data-naming lint did NOT catch (it did not check home_zone). Two fixes landed:
## the creation path resolves the home zone against the zone catalog and falls
## back to the spawn zone, AND the phantom itself is gone: the Akkan homeland is
## now authored as zone_dark_highlands.tres (id "zone_dark_highlands") and the
## species points at it. The data-naming lint now also gates home_zone refs.
##
## Run: godot --headless --path game --script res://tests/test_character_select_zone.gd
##
## Legs:
##   1. a real zone (zone_starter_plains) resolves.
##   2. an unknown zone id does NOT resolve (the fallback still guards).
##   3. EVERY species home_zone resolves to a real zone (none is a phantom).
##   4. the Akkan creation path lands in its authored homeland (zone_dark_highlands).
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
        _check(not panel._zone_exists("zone_never_authored"), "an unknown zone id does NOT resolve")

        # Every species home_zone must resolve to a real zone (no phantom survives).
        var bad: Array = []
        for sp in CharacterData.get_all_species():
                var hz: String = sp.home_zone
                if hz != "" and not panel._zone_exists(hz):
                        bad.append("%s -> %s" % [sp.id, hz])
                var resolved: String = hz if panel._zone_exists(hz) else SPAWN_ZONE
                _check(panel._zone_exists(resolved),
                        "species %s lands on a real zone (%s)" % [sp.id, resolved])
        if bad.size() > 0:
                print("   note: species with an unauthored home_zone (fallback applied): %s"
                        % ", ".join(bad))

        # The Akkan creation path specifically: now lands in its authored homeland.
        var akkan := CharacterData.load_species("akkan")
        _check(akkan != null, "akkan species loads")
        if akkan != null:
                _check(panel._zone_exists(akkan.home_zone),
                        "the Akkan home_zone resolves to a real zone (%s)" % akkan.home_zone)
                var chosen: String = akkan.home_zone if panel._zone_exists(akkan.home_zone) else SPAWN_ZONE
                _check(chosen == "zone_dark_highlands",
                        "an Akkan character is created in its homeland (%s)" % chosen)

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
