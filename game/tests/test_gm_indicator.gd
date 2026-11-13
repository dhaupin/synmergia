## test_gm_indicator - the GM star is wired into the player body.
##
## The GMIndicator feature (a floating gold star above GM bodies, the 3D
## twin of the "[GM]" chat tag / gold nameplate) existed but had zero
## callers since birth. It is now attached by PlayerBase._setup_gm_indicator
## on _ready, ONLY when the body's class is a GM class (role 0). This
## receipt proves the gate: a GM-class body gets the star (with its Star +
## Glow sprites), an ordinary body does not, the attach is idempotent, and a
## bare PlayerBase never crashes when the class schema / DataService is
## absent.
##
## Run: godot --headless --path game --script res://tests/test_gm_indicator.gd
extends SceneTree

var _passed := 0
var _failed := 0


func _check(cond: bool, msg: String) -> void:
        if cond:
                _passed += 1
                print("   PASS  %s" % msg)
        else:
                _failed += 1
                print("   FAIL  %s" % msg)


func _finish() -> void:
        print("=== GM INDICATOR RECEIPT: %d passed, %d failed ===" % [_passed, _failed])
        quit(0 if _failed == 0 else 1)


func _initialize() -> void:
        call_deferred("_run")


func _run() -> void:
        var ds = root.get_node_or_null("DataService")
        if ds != null and not ds._loaded and ds.has_method("load_all_data"):
                ds.load_all_data()
        await process_frame

        var PB: GDScript = load("res://entities/player/player_base.gd")
        _check(PB != null, "player_base.gd loads")
        if PB == null:
                _finish()
                return

        # Drive the REAL _ready path: PlayerBase._setup_starting_skills reads
        # GameManager.selected_character_data (the login contract) and sets
        # character_class from its class_id; _setup_gm_indicator then reads
        # that resolved class. Without a login the default class is used.
        var gm_mgr = root.get_node_or_null("GameManager")
        var CD: GDScript = load("res://core/schemas/character_data.gd")
        var prev_sel = gm_mgr.selected_character_data if gm_mgr != null else null
        if gm_mgr != null:
                var cd = CD.new()
                cd.class_id = "gm_akkan"
                gm_mgr.selected_character_data = cd

        # 1. A GM-class body wears the star after _ready.
        var gm = PB.new()
        root.add_child(gm)
        await process_frame
        _check(gm.character_class == "gm_akkan",
                "the GM class resolved from the login contract (character_class=gm_akkan)")
        var ind = gm.get_node_or_null("GMIndicator")
        _check(ind != null, "a GM-class body carries a GMIndicator child")
        if ind != null:
                _check(String(ind.get_script().resource_path).ends_with("gm_indicator.gd"),
                        "the child runs gm_indicator.gd")
                _check(ind.get_node_or_null("Star") != null, "the star sprite exists")
                _check(ind.get_node_or_null("Glow") != null, "the glow sprite exists")

        # 2. Idempotent: re-running the setup does not double-attach.
        if gm.has_method("_setup_gm_indicator"):
                gm._setup_gm_indicator()
                var count := 0
                for c in gm.get_children():
                        if c.name == "GMIndicator":
                                count += 1
                _check(count == 1, "re-running the setup keeps exactly one GMIndicator")

        # 3. An ordinary body gets NO star. Point the login contract at a
        #    non-GM class first, else the plain body would resolve to GM too.
        if gm_mgr != null:
                var cd_plain = CD.new()
                cd_plain.class_id = "human_warrior"
                gm_mgr.selected_character_data = cd_plain
        var plain = PB.new()
        plain.character_class = "human_warrior"
        root.add_child(plain)
        await process_frame
        _check(plain.get_node_or_null("GMIndicator") == null,
                "an ordinary-class body carries no GMIndicator")

        # 4. The gate is CharacterData.is_gm_class (the one authority).
        _check(CD.is_gm_class("gm_akkan"), "is_gm_class(gm_akkan) is true")
        _check(CD.is_gm_class("gm_human"), "is_gm_class(gm_human) is true")
        _check(not CD.is_gm_class("human_warrior"), "is_gm_class(human_warrior) is false")
        _check(not CD.is_gm_class(""), "is_gm_class(empty) is false (no crash)")

        gm.queue_free()
        plain.queue_free()
        if gm_mgr != null:
                gm_mgr.selected_character_data = prev_sel
        _finish()
