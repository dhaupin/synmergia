## Regression test: dialogue_ended must carry the LIVE npc_id.
##
## Bug: DialogService.start_dialogue(npc_id, dialogue_id) received the id of
## the NPC the player was standing in front of, then threw it away --
## end_dialogue emitted the TREE's own `npc_id` field instead. When two NPCs
## shared one tree (the capital instances reused the village trees:
## npc_elder_capital -> village_elder_greeting, whose npc_id is
## npc_village_elder) TALK quest credit keyed on the wrong NPC. The
## blacksmith's "Meet the People" quest could be ticked by talking to the
## WRONG NPC, and a quest targeting the capital instance could never tick.
##
## The data side is now distinct trees per NPC (see test_data_naming_lint's
## dialogue include parity gate), but the service contract still must hold:
## the emitted id is the one the caller passed, not the tree's authoring id.
##
## Run: godot --headless --path . --script res://tests/test_dialogue_npc_attribution.gd

extends SceneTree

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
        call_deferred("_run")

func _ok(msg: String) -> void:
        _passed += 1
        print("  [OK] ", msg)

func _fail(msg: String) -> void:
        _failed += 1
        print("  [FAIL] ", msg)

func _finish() -> void:
        print("--- DIALOGUE NPC ATTRIBUTION: %d passed, %d failed ---" % [_passed, _failed])
        quit(0 if _failed == 0 else 1)

func _run() -> void:
        var root_node := get_root()
        var ds = root_node.get_node_or_null("DialogService")
        if ds == null:
                _fail("DialogService autoload missing")
                _finish()
                return
        _ok("DialogService present")

        # village_elder_greeting's tree npc_id is npc_village_elder; open it
        # as though the CAPITAL instance (a different NPCData id) were talking.
        var seen := {"npc": "", "dialogue": ""}
        var handler := func(npc_id: String, dialogue_id: String) -> void:
                seen["npc"] = npc_id
                seen["dialogue"] = dialogue_id
        ds.dialogue_ended.connect(handler)

        if not ds.start_dialogue("npc_elder_capital", "village_elder_greeting"):
                _fail("start_dialogue failed for village_elder_greeting")
                _finish()
                return
        ds.end_dialogue()
        if str(seen["npc"]) == "npc_elder_capital":
                _ok("dialogue_ended carries the live npc_id (not the tree's)")
        else:
                _fail("dialogue_ended carried '%s' (want npc_elder_capital)" % str(seen["npc"]))
        if str(seen["dialogue"]) == "village_elder_greeting":
                _ok("dialogue_ended still carries the dialogue id")
        else:
                _fail("dialogue_ended dialogue id wrong: %s" % str(seen["dialogue"]))

        # A fresh start with a matching id must also report that id.
        if ds.start_dialogue("npc_village_elder", "village_elder_greeting"):
                ds.end_dialogue()
                if str(seen["npc"]) == "npc_village_elder":
                        _ok("second start reports its own live id")
                else:
                        _fail("second start leaked a stale id: %s" % str(seen["npc"]))
        else:
                _fail("second start_dialogue failed")

        ds.dialogue_ended.disconnect(handler)
        _finish()
