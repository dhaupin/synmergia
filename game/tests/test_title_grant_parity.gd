## Regression test: title grant parity.
##
## A title that declares `unlock_method = 0` (ACHIEVEMENT) and names an
## achievement in `unlock_source` is granted ONLY when that achievement
## carries a matching `title_reward` -- `unlock_source` is documentation,
## TitleService never reads it, and AchievementService._grant_rewards is
## the single generic grant path. Five titles shipped with the method and
## source but no wiring on the achievement side, so the source achievement
## unlocked and the title never did: collector, explorer, slayer,
## social_butterfly, trader. Same silent-null class as an achievement
## naming a title that does not exist (the mirror of the check already in
## test_data_naming_lint.gd).
##
## Leg 1 (data): every ACHIEVEMENT-method title with a resolvable
##   achievement source is actually granted by that achievement.
## Leg 2 (live): the real AchievementService -> TitleService path lands a
##   title in the register for one of the fixed ids (trader), proving the
##   wiring rides the production reward door, not just the .tres text.
##
## Run: godot --headless --path . --script res://tests/test_title_grant_parity.gd

extends SceneTree

var _passed: int = 0
var _failed: int = 0

const ACH_DIR := "res://data/achievements"
const TITLE_DIR := "res://data/titles"

## The five titles this round repaired; every one must stay wired.
const REPAIRED := {
        "collector": "collector_50",
        "explorer": "explorer",
        "slayer": "slayer_100",
        "social_butterfly": "social_butterfly",
        "trader": "trader",
}

func _initialize() -> void:
        _run.call_deferred()

func _run() -> void:
        _test_data_parity()
        _test_live_grant()
        _finish()

## --- Leg 1: data cross-check -------------------------------------------
func _test_data_parity() -> void:
        var ach_reward := _title_reward_by_achievement()
        if ach_reward.is_empty():
                _fail("no achievement defs found under %s" % ACH_DIR)
                return
        _ok("achievement catalog read (%d defs)" % ach_reward.size())

        var bad: Array = []
        var checked: int = 0
        for base in _tres_bases(TITLE_DIR):
                var txt := _read(TITLE_DIR + "/" + base + ".tres")
                var tid := _field(txt, "id")
                if _int_field(txt, "unlock_method") != 0:
                        continue
                var source := _field(txt, "unlock_source")
                if source == "" or not ach_reward.has(source):
                        continue
                checked += 1
                if str(ach_reward.get(source, "")) != tid:
                        bad.append("%s source %s grants '%s'" % [tid, source, str(ach_reward.get(source, ""))])
        if bad.is_empty():
                _ok("every ACHIEVEMENT-method title is granted by its source (%d checked)" % checked)
        else:
                _fail("titles never granted by their source: %s" % ", ".join(bad))

        # The five repaired titles are pinned by name so a later edit that
        # drops one re-opens this failure loudly rather than silently.
        var unwired: Array = []
        for tid2 in REPAIRED:
                var src: String = str(REPAIRED[tid2])
                if str(ach_reward.get(src, "")) != tid2:
                        unwired.append("%s <- %s" % [tid2, src])
        if unwired.is_empty():
                _ok("the five repaired titles stay wired (%d)" % REPAIRED.size())
        else:
                _fail("repaired titles unwired again: %s" % ", ".join(unwired))

## --- Leg 2: live grant through the real reward door ---------------------
func _test_live_grant() -> void:
        var ach = root.get_node_or_null("AchievementService")
        if ach == null:
                _fail("AchievementService autoload missing")
                return
        var ts = root.get_node_or_null("TitleService")
        if ts == null:
                _fail("TitleService autoload missing")
                return
        _ok("AchievementService + TitleService present")

        # --script mode: force the def load if autoload _ready has not run.
        if ach.get_all_achievements().is_empty():
                var ds = root.get_node_or_null("DataService")
                if ds != null and ds.has_method("load_all_data"):
                        ds.load_all_data()
                if ach.has_method("_load_achievement_definitions"):
                        ach._load_achievement_definitions()
        if ach.get_all_achievements().is_empty():
                _fail("achievement defs did not load")
                return

        var pid := "title_parity_probe_%d" % Time.get_ticks_msec()
        if bool(ts.call("_has_title", pid, "trader")):
                _fail("probe player already held the trader title")
                return

        # _grant_rewards only pays the LOCAL player (the authoritative server
        # applies a non-local earner's rewards), so seat the probe as local
        # before driving the unlock -- exactly the live path.
        var pm = root.get_node_or_null("PlayerManager")
        if pm == null or not pm.has_method("set_local_player"):
                _fail("PlayerManager.set_local_player missing")
                return
        var pscript = load("res://entities/player/player_base.gd")
        if pscript == null:
                _fail("player_base.gd failed to load")
                return
        var pnode = pscript.new()
        pnode.entity_id = pid
        pm.set_local_player(pnode)

        # Drive the real unlock: AchievementService.unlock -> _do_unlock ->
        # _grant_rewards -> TitleService.unlock.
        ach.unlock(pid, "trader")
        if not ach.has_unlocked(pid, "trader"):
                _fail("trader achievement did not unlock")
                return
        _ok("trader achievement unlocked via the real service")

        if bool(ts.call("_has_title", pid, "trader")):
                _ok("trader TITLE landed in the register via the reward door")
        else:
                _fail("trader title not granted -- title_reward unwired")

        # Guard the negative: an achievement with no title_reward grants none.
        ach.unlock(pid, "ob_first_skill")
        if bool(ts.call("_has_title", pid, "first_blood")):
                _fail("an untitled achievement granted an unrelated title")
        else:
                _ok("an achievement without title_reward grants no title")

func _title_reward_by_achievement() -> Dictionary:
        var out: Dictionary = {}
        for base in _tres_bases(ACH_DIR):
                var txt := _read(ACH_DIR + "/" + base + ".tres")
                var aid := _field(txt, "id")
                if aid == "":
                        continue
                out[aid] = _field(txt, "title_reward")
        return out

func _tres_bases(dir_path: String) -> Array:
        var out: Array = []
        var d := DirAccess.open(dir_path)
        if d == null:
                return out
        d.list_dir_begin()
        var f := d.get_next()
        while f != "":
                if f.ends_with(".tres"):
                        out.append(f.trim_suffix(".tres"))
                f = d.get_next()
        return out

func _read(path: String) -> String:
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
                return ""
        var t := f.get_as_text()
        f.close()
        return t

func _field(txt: String, key: String) -> String:
        for line in txt.split("\n"):
                var t := line.strip_edges()
                if t.begins_with(key + " = \""):
                        return t.trim_prefix(key + " = \"").trim_suffix("\"")
        return ""

func _int_field(txt: String, key: String) -> int:
        for line in txt.split("\n"):
                var t := line.strip_edges()
                if t.begins_with(key + " = "):
                        return int(t.trim_prefix(key + " = "))
        return -1

func _ok(msg: String) -> void:
        _passed += 1
        print("  [OK] ", msg)

func _fail(msg: String) -> void:
        _failed += 1
        print("  [FAIL] ", msg)

func _finish() -> void:
        print("--- TITLE GRANT PARITY: %d passed, %d failed ---" % [_passed, _failed])
        quit(0 if _failed == 0 else 1)
