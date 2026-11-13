## Regression test: class focal stats actually load (and thus actually buff).
##
## CharacterClass.focal_stat_1 / focal_stat_2 feed calculate_stat, which grants
## each focal stat +1 growth per level (a focal stat grows at base+1, not +1).
## Eighteen of the twenty-one class .tres files authored these as dict-pair
## lines -- `"focal_stat_1": "strength",` -- some as stray top-level lines,
## some stuffed INSIDE the stat_growth dict. Godot does not read a dict-pair as
## a property assignment: it silently drops the line, the resource still loads,
## and focal_stat_1/2 stayed "". Every class silently lost its focal bonus.
##
## The data lint now gates the stray-pair shape (a depth-0 `"key":` line); this
## receipt proves the LOADED VALUES are real and that the gameplay effect
## (calculate_stat's focal +1) rides them, so the bug cannot come back as a
## silent no-op that still passes a text-only check.
##
## Run: godot --headless --path . --script res://tests/test_class_focal_stats.gd

extends SceneTree

var _passed: int = 0
var _failed: int = 0

const CLASS_DIR := "res://data/classes"
const STATS := ["strength", "agility", "intelligence", "vitality", "endurance", "wisdom"]

## GM classes are exempt (they carry no focal stats by design).
func _initialize() -> void:
        _run.call_deferred()

func _run() -> void:
        _test_every_class_loads_focals()
        _test_focal_bonus_applies()
        _finish()

## --- Leg 1: every non-GM class declares two real, distinct focal stats ---
func _test_every_class_loads_focals() -> void:
        var files := _class_files()
        if files.is_empty():
                _fail("no class .tres found under %s" % CLASS_DIR)
                return
        var bad: Array = []
        var checked: int = 0
        for fn in files:
                var res = load(CLASS_DIR + "/" + fn)
                if res == null:
                        bad.append("%s (load failed)" % fn)
                        continue
                var cid: String = str(res.id)
                if cid.begins_with("gm_"):
                        continue
                checked += 1
                var f1: String = str(res.focal_stat_1)
                var f2: String = str(res.focal_stat_2)
                if f1 == "" or f2 == "":
                        bad.append("%s focal='%s','%s'" % [cid, f1, f2])
                elif not STATS.has(f1) or not STATS.has(f2):
                        bad.append("%s focal names unknown stat: '%s','%s'" % [cid, f1, f2])
                elif f1 == f2:
                        bad.append("%s focal stats identical: '%s'" % [cid, f1])
        if bad.is_empty():
                _ok("all %d non-GM classes declare two real, distinct focal stats" % checked)
        else:
                _fail("classes with missing/bad focal stats: %s" % ", ".join(bad))

## --- Leg 2: the focal bonus is real -- calculate_stat pays +1/level for them ---
func _test_focal_bonus_applies() -> void:
        var res = load(CLASS_DIR + "/class_human_guardian.tres")
        if res == null:
                _fail("class_human_guardian failed to load")
                return
        # human_guardian: base vitality 14 / growth 3, base strength 10 / growth 2,
        # base agility 5 / growth 1; focal_stat_1 = "vitality", focal_stat_2 =
        # "strength". Both focal stats grow +1/level (vitality +4, strength +3);
        # agility is non-focal (+1).
        var vit_l1: int = int(res.calculate_stat("vitality", 1))
        var vit_l2: int = int(res.calculate_stat("vitality", 2))
        var str_l1: int = int(res.calculate_stat("strength", 1))
        var str_l2: int = int(res.calculate_stat("strength", 2))
        var agi_l2: int = int(res.calculate_stat("agility", 2))
        if vit_l1 == 14 and str_l1 == 10:
                _ok("level-1 stats read base values (vitality 14, strength 10)")
        else:
                _fail("level-1 stats wrong: vitality %d, strength %d" % [vit_l1, str_l1])
        if vit_l2 == 18:
                _ok("focal vitality grows at +4/level (14 -> 18 at level 2)")
        else:
                _fail("focal vitality did not apply: level 2 = %d (want 18)" % vit_l2)
        if str_l2 == 13:
                _ok("focal strength grows at +3/level (10 -> 13 at level 2)")
        else:
                _fail("focal strength did not apply: level 2 = %d (want 13)" % str_l2)
        if agi_l2 == 6:
                _ok("non-focal agility grows at +1/level (5 -> 6 at level 2)")
        else:
                _fail("non-focal agility wrong: level 2 = %d (want 6)" % agi_l2)

func _class_files() -> Array:
        var out: Array = []
        var d := DirAccess.open(CLASS_DIR)
        if d == null:
                return out
        d.list_dir_begin()
        var f := d.get_next()
        while f != "":
                if f.ends_with(".tres"):
                        out.append(f)
                f = d.get_next()
        out.sort()
        return out

func _ok(msg: String) -> void:
        _passed += 1
        print("  [OK] ", msg)

func _fail(msg: String) -> void:
        _failed += 1
        print("  [FAIL] ", msg)

func _finish() -> void:
        print("--- CLASS FOCAL STATS: %d passed, %d failed ---" % [_passed, _failed])
        quit(0 if _failed == 0 else 1)
