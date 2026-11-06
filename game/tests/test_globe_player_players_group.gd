## test_globe_player_players_group - THE LOCAL BODY JOINS "players".
##
## The planar controller (player_controller.gd) joins the "players" group
## in _ready; the globe body (the world the player actually plays, since
## globe_world is the spherical default) never did. Every
## get_first_node_in_group("players") lookup therefore missed the local
## body in globe mode -- ActionBar resolves its ability caster that way,
## and PlayerProgress falls back to it.
##
## This receipt builds a REAL globe body through the real script and
## asserts the group membership the consumers rely on, plus that the
## planar controller keeps the same contract (so a future refactor cannot
## silently drop one side).
##
## Run: godot --headless --path game --script res://tests/test_globe_player_players_group.gd
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
        print("=== GLOBE PLAYER 'players' GROUP RECEIPT: %d checks, %d failed ===" % [_passed, _failed])
        if _failed == 0:
                print("GLOBE PLAYER 'players' GROUP RECEIPT PASSED")
                quit(0)
        else:
                print("GLOBE PLAYER 'players' GROUP RECEIPT FAILED")
                quit(1)


func _initialize() -> void:
        call_deferred("_run")


func _run() -> void:
        print("--- GLOBE PLAYER 'players' GROUP RECEIPT ---")
        await process_frame

        # 1. The globe body script loads.
        var GP: GDScript = load("res://entities/globe_player.gd")
        _check(GP != null, "globe_player.gd loads")
        if GP == null:
                _finish()
                return

        # 2. A real body joins the group on _ready.
        var body = GP.new()
        body.entity_id = "group_receipt_pilot"
        root.add_child(body)
        # _ready (and the group join) runs during add_child; stop the physics
        # tick so a bare body with no planet center does not spam the
        # up_direction guard in headless mode.
        body.set_physics_process(false)
        await process_frame
        _check(body.is_in_group("players"), "globe body is in the 'players' group after _ready")

        # 3. The consumer's exact lookup finds it.
        var found = get_first_node_in_group("players")
        _check(found != null and found == body,
                "get_first_node_in_group('players') resolves the globe body")

        # 4. Leaving the tree drops membership (no ghost in the group).
        body.queue_free()
        await process_frame
        await process_frame
        _check(get_first_node_in_group("players") == null or
                        not get_first_node_in_group("players").is_queued_for_deletion(),
                "a freed body leaves no live 'players' entry")

        # 5. The planar controller keeps the SAME contract (parity guard).
        var PC: GDScript = load("res://entities/player/player_controller.gd")
        if PC != null:
                var src: String = PC.source_code
                _check(src.find('add_to_group("players")') != -1,
                        "planar player_controller.gd still joins 'players' (parity)")
        else:
                _fail("player_controller.gd did not load (parity check skipped)")

        _finish()
