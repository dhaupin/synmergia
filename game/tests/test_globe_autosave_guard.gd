## test_globe_autosave_guard - THE GROUP JOIN MUST NOT CLOBBER SAVES.
##
## The globe body joins "players" (for ActionBar's caster lookup). But
## PlayerProgress._find_tracked_player falls back to that same group for
## its autosave tick, and the globe body carries no experience/gold/level
## -- save_player would fabricate a 0/0/1 snapshot over the character's
## real one. The guard rejects any "players" node without the progression
## surface, while still returning a real progress-bearing body.
##
## Run: godot --headless --path game --script res://tests/test_globe_autosave_guard.gd
extends SceneTree

var _passed := 0
var _failed := 0


func _ok(msg: String) -> void:
        _passed += 1
        print("   PASS  %s" % msg)


func _fail(msg: String) -> void:
        _failed += 1
        print("   FAIL  %s" % msg)


func _check(cond: bool, msg: String) -> void:
        if cond:
                _ok(msg)
        else:
                _fail(msg)


func _finish() -> void:
        print("=== GLOBE AUTOSAVE GUARD RECEIPT: %d checks, %d failed ===" % [_passed, _failed])
        if _failed == 0:
                print("GLOBE AUTOSAVE GUARD RECEIPT PASSED")
                quit(0)
        else:
                print("GLOBE AUTOSAVE GUARD RECEIPT FAILED")
                quit(1)


func _initialize() -> void:
        call_deferred("_run")


func _run() -> void:
        print("--- GLOBE AUTOSAVE GUARD RECEIPT ---")
        await process_frame

        var progress = root.get_node_or_null("PlayerProgress")
        _check(progress != null, "PlayerProgress autoload is present")
        if progress == null:
                _finish()
                return

        # 1. A globe body in "players" must be REJECTED (no clobber).
        var GP: GDScript = load("res://entities/globe_player.gd")
        var globe = GP.new()
        globe.entity_id = "guard_globe"
        root.add_child(globe)
        globe.set_physics_process(false)
        await process_frame
        _check(globe.is_in_group("players"), "globe body is in 'players'")
        var resolved = progress._find_tracked_player("guard_globe")
        _check(resolved == null,
                "_find_tracked_player rejects the progress-less globe body")

        # 2. A progress-bearing body in "players" is still returned.
        var stub = Node.new()
        stub.name = "ProgressStub"
        stub.set_script(_make_stub_script())
        stub.set("experience", 500)
        stub.set("gold", 250)
        stub.set("level", 4)
        stub.entity_id = "guard_stub"
        globe.queue_free()
        await process_frame
        root.add_child(stub)
        stub.add_to_group("players")
        await process_frame
        var resolved2 = progress._find_tracked_player("guard_stub")
        _check(resolved2 == stub,
                "_find_tracked_player still returns a progress-bearing body")

        # 3. save_player on the globe body must be refused by the guard path:
        #    with no EntityService match and the guard rejecting the group
        #    fallback, the autosave tick finds nothing to write.
        stub.queue_free()
        await process_frame
        var g2 = GP.new()
        g2.entity_id = "guard_globe2"
        root.add_child(g2)
        g2.set_physics_process(false)
        await process_frame
        var none = progress._find_tracked_player("guard_globe2")
        _check(none == null, "a lone globe body yields no tracked player to autosave")

        g2.queue_free()
        await process_frame
        _finish()


func _make_stub_script() -> GDScript:
        var s := GDScript.new()
        s.source_code = "extends Node\nvar entity_id: String = \"\"\nvar experience: int = 0\nvar gold: int = 0\nvar level: int = 1\n"
        s.reload()
        return s
