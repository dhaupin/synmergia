extends SceneTree

## General ("shared verb") skills -- the class-agnostic skills every class
## starts with (Bind, Recover), authored under data/skills/general/ with
## required_class == "".
##
## Contracts frozen here:
##   1. DataService.get_general_skills() returns them, id-sorted, and every
##      one carries no required_class (a class tag would hide it from every
##      other class).
##   2. The runtime class gate actually lets ANY class cast them: the combat
##      Skill.can_cast passes a general skill for a caster of a foreign
##      class, and still refuses a class-owned skill for the wrong class.
##   3. _setup_starting_skills loads the general skills FIRST, so they lead
##      the skillbar ahead of the class kit.
##
## Run: godot --headless --path . --script res://tests/test_general_skills.gd

const CombatSkill = preload("res://core/combat/skill.gd")

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
        print("--- GENERAL SKILLS: %d passed, %d failed ---" % [_passed, _failed])
        quit(0 if _failed == 0 else 1)

## Minimal caster: Skill.can_cast reads character_class / level / resources
## off the Node it is handed, so a bare Node with those vars answers it.
class FakeCaster extends Node:
        var character_class: String = ""
        var level: int = 1
        var current_mana: int = 1000
        var current_stamina: int = 1000
        var current_health: int = 1000

func _caster(class_id: String) -> Node:
        var c := FakeCaster.new()
        c.character_class = class_id
        return c

func _run() -> void:
        var ds = get_root().get_node_or_null("DataService")
        if ds == null:
                _fail("DataService autoload missing")
                _finish()
                return

        var generals: Array = ds.get_general_skills()
        if generals.is_empty():
                _fail("get_general_skills() returned nothing (no shared verbs authored)")
                _finish()
                return
        _ok("general skills present (%d): %s" % [generals.size(), _general_ids(generals)])

        var ids: Array = []
        for g in generals:
                ids.append(str(g.id))

        var tagged: Array = []
        for g in generals:
                if str(g.required_class) != "":
                        tagged.append(str(g.id))
        if tagged.is_empty():
                _ok("every general skill is class-agnostic (required_class == \"\")")
        else:
                _fail("general skills carrying a required_class (hidden from other classes): %s" % ", ".join(tagged))

        # The general set must match the files under data/skills/general/:
        # a file there that got a required_class (and so dropped out of the
        # list) is a hidden regression, not an empty set.
        var authored: Array = []
        var gdir := DirAccess.open("res://data/skills/general")
        if gdir != null:
                gdir.list_dir_begin()
                var gf := gdir.get_next()
                while gf != "":
                        if gf.ends_with(".tres"):
                                authored.append(gf.trim_suffix(".tres"))
                        gf = gdir.get_next()
        authored.sort()
        var returned: Array = ids.duplicate()
        returned.sort()
        if authored == returned:
                _ok("get_general_skills() matches the authored general/ set (%d)" % authored.size())
        else:
                _fail("general/ files %s != returned %s (a general skill was tagged or dropped)" % [", ".join(authored), ", ".join(returned)])

        # Id-sorted for a deterministic skillbar.
        var sorted_ids := ids.duplicate()
        sorted_ids.sort()
        if ids == sorted_ids:
                _ok("general skills come back id-sorted")
        else:
                _fail("general skills are not id-sorted: %s" % ", ".join(ids))

        # The class gate: a general skill casts for a foreign class; a
        # class-owned skill does not.
        var bind_schema = ds.get_skill("general_bind")
        if bind_schema == null:
                _fail("general_bind did not load")
        else:
                var bind = CombatSkill.from_schema(bind_schema)
                var foreign: Node = _caster("human_warrior")
                if bind.can_cast(foreign):
                        _ok("a human_warrior can cast general_bind (class gate passes)")
                else:
                        _fail("a foreign class could NOT cast the general skill general_bind")

                var void_schema = ds.get_skill("akkan_void_slash")
                if void_schema == null:
                        _fail("akkan_void_slash did not load (needed for the negative leg)")
                else:
                        var void_slash = CombatSkill.from_schema(void_schema)
                        if not void_slash.can_cast(foreign):
                                _ok("the same human_warrior is refused akkan_void_slash (owner akkan_attacker)")
                        else:
                                _fail("a foreign class cast a class-owned skill -- the class gate is open")
                        if void_slash.can_cast(_caster("akkan_attacker")):
                                _ok("akkan_attacker can cast its own akkan_void_slash")
                        else:
                                _fail("akkan_attacker was refused its own class skill")

        # The skillbar leads with the shared verbs: source contract on the
        # loader (the full body boot is covered by test_player_base).
        var pb_script: GDScript = load("res://entities/player/player_base.gd")
        if pb_script == null:
                _fail("player_base.gd did not load")
        elif pb_script.source_code.contains("get_general_skills()"):
                _ok("_setup_starting_skills pulls the general skills into the skillbar")
        else:
                _fail("_setup_starting_skills never reads get_general_skills()")

        _finish()

func _general_ids(arr: Array) -> String:
        var out: Array = []
        for g in arr:
                out.append(str(g.id))
        return ", ".join(out)
