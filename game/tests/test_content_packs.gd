## test_content_packs.gd - THE PHASE 3.2 PER-SHARD CONTENT-PACK RECEIPT.
##
## Verifies the content-pack lever (labs/prd-shard-mesh.md sec.3.2):
##  * the pack data loads and every owned id resolves against DataService
##    truth (no phantom SKUs),
##  * the gate is UNIFORM BY DEFAULT (no disable -> every pack enabled),
##  * a disabled pack hides its quests from the roster AND the accept gate
##    (QuestService), and its enemies from every spawn route (SpawnService),
##  * the gate is LOCAL: a second shard stays uniform,
##  * the /contentpack operator surface (board / read / enable / disable),
##  * the write rides the ShardParameters lever (critical -> readable now).
## Run: cd game && godot --headless --path . --script res://tests/test_content_packs.gd
extends SceneTree

const ContentPacks := preload("res://core/mesh/content_packs.gd")
const PackScript := preload("res://core/schemas/content_pack_data.gd")

var _sp: Node
var _sm: Node
var _qs: Node
var _ss: Node
var _ds: Node
var _cs: Node
var _perm: Node
var _ns: Node
var _fired: Array = []
var _fails := 0
var _passes := 0

const PACK := "pack_tide_season"

func _initialize() -> void:
        await process_frame
        _sp = root.get_node_or_null("ShardParameters")
        _sm = root.get_node_or_null("ShardManager")
        _qs = root.get_node_or_null("QuestService")
        _ss = root.get_node_or_null("SpawnService")
        _ds = root.get_node_or_null("DataService")
        _cs = root.get_node_or_null("ChatService")
        _perm = root.get_node_or_null("PermissionManager")
        _ns = root.get_node_or_null("NotificationService")
        if _sp == null or _sm == null or _qs == null or _ss == null or _ds == null \
                        or _cs == null or _perm == null or _ns == null:
                push_error("FAIL: required autoloads missing")
                quit(1)
                return
        _sp.load_definitions()
        ContentPacks.reload()
        print("--- CONTENT PACKS (PHASE 3.2) TEST ---")
        _ns.notification_sent.connect(func(_pid, n):
                _fired.append(str(n.get("message", "") if n is Dictionary else n)))
        await _run()
        _cleanup()
        print("--- RESULT: %d passed, %d failed ---" % [_passes, _fails])
        quit(1 if _fails > 0 else 0)

func _ok(cond: bool, label: String) -> void:
        if cond:
                _passes += 1
                print("PASS: ", label)
        else:
                _fails += 1
                push_error("FAIL: %s" % label)

func _new_tree():
        var T3Script = load("res://core/frame/kv/t3.gd")
        var StateTreeScript = load("res://core/frame/kv/state_tree.gd")
        return StateTreeScript.new(T3Script.new())

func _said(needle: String) -> bool:
        for m in _fired:
                if m.find(needle) != -1:
                        return true
        return false

func _run() -> void:
        var local: String = str(_sm.shard_id)
        _sp.set_state_tree(local, _new_tree())
        _sp.set_state_tree("shard_2", _new_tree())

        _test_data_integrity()
        _test_uniform_by_default(local)
        _test_quest_gate(local)
        _test_enemy_gate(local)
        _test_gate_is_local(local)
        await _test_operator_surface(local)
        _test_added_assertions(local)

## ---- the pack data resolves against DataService truth ------------------
func _test_data_integrity() -> void:
        var ids: Array = ContentPacks.pack_ids()
        _ok(ids.has(PACK), "pack_tide_season is on the board")
        var pack: Resource = ContentPacks.get_pack(PACK)
        _ok(pack != null and pack is PackScript, "the pack loads as ContentPackData")
        _ok(pack != null and pack.enemy_ids.size() == 3, "pack owns 3 enemies")
        _ok(pack != null and pack.quest_ids.size() == 4, "pack owns 4 quests")
        # No phantom SKUs: every owned id resolves service truth.
        var missing: Array = pack.missing_refs(_ds)
        _ok(missing.is_empty(), "every owned id resolves DataService truth (missing=%s)" % str(missing))
        _ok(ContentPacks.pack_owning_enemy("tidecursed_diver") == PACK, "diver maps to the pack")
        _ok(ContentPacks.pack_owning_quest("quest_tide_salvage") == PACK, "tide_salvage maps to the pack")
        _ok(ContentPacks.pack_owning_enemy("wolf") == "", "an unowned enemy maps to no pack")

## ---- UNIFORM BY DEFAULT (the non-negotiable case) ---------------------
func _test_uniform_by_default(local: String) -> void:
        _sp.set_param(local, ContentPacks.DISABLED_PARAM, "", "test")
        _ok(ContentPacks.disabled_set(local, _sp).is_empty(), "no disable -> empty disabled set")
        _ok(not ContentPacks.is_pack_disabled(PACK, local, _sp), "no disable -> pack enabled")
        _ok(ContentPacks.enemy_enabled("tidecursed_diver", local, _sp), "no disable -> enemy allowed")
        _ok(ContentPacks.quest_enabled("quest_tide_salvage", local, _sp), "no disable -> quest allowed")

## ---- a disabled pack hides its quests (roster + accept gate) ----------
func _test_quest_gate(local: String) -> void:
        ContentPacks.write_disabled(local, [PACK], _sp, "test")
        _ok(ContentPacks.is_pack_disabled(PACK, local, _sp), "disable lands on the local shard")
        _ok(not ContentPacks.quest_enabled("quest_tide_salvage", local, _sp),
                "disabled pack -> quest not enabled")
        # The roster (QuestService.get_available_quests) drops the pack's quests.
        var pid := "pack_quest_tester"
        _qs._player_quests[pid] = {}
        var roster: Array = _qs.get_available_quests(pid)
        var found := false
        for row in roster:
                if str(row.get("id", "")) == "quest_tide_salvage":
                        found = true
        _ok(not found, "disabled pack's quest is absent from the roster")
        # The accept gate refuses by name.
        var avail: Dictionary = _qs.check_quest_availability(pid, "quest_tide_salvage")
        _ok(not bool(avail.get("available", true)), "disabled pack's quest is refused at the gate")
        _ok(str(avail.get("reason", "")).find("Content pack") != -1,
                "refusal names the content pack")
        # A quest owned by NO pack is unaffected.
        _ok(ContentPacks.quest_enabled("quest_wolves_hunt", local, _sp),
                "an unowned quest stays enabled")

## ---- a disabled pack hides its enemies (every spawn route) ------------
func _test_enemy_gate(local: String) -> void:
        ContentPacks.write_disabled(local, [PACK], _sp, "test")
        _ok(not ContentPacks.enemy_enabled("tidecursed_diver", local, _sp),
                "disabled pack -> enemy not enabled")
        # The direct spawn route refuses (returns null).
        var spawned = _ss.spawn_enemy_direct("tidecursed_diver", Vector3.ZERO, "zone_test", 0)
        _ok(spawned == null, "disabled pack -> spawn_enemy_direct refuses")
        # The boss route refuses (the Trench Sentinel is in the pack).
        var boss = _ss.spawn_boss("trench_sentinel", Vector3.ZERO, "zone_test", "", [], -1, -1)
        _ok(boss == null, "disabled pack -> spawn_boss refuses")
        # An enemy owned by NO pack still spawns.
        var wolf = _ss.spawn_enemy_direct("wolf", Vector3.ZERO, "zone_test", 0)
        _ok(wolf != null, "an unowned enemy still spawns")
        if wolf != null and is_instance_valid(wolf):
                wolf.queue_free()

## ---- the gate is LOCAL: a second shard stays uniform ------------------
func _test_gate_is_local(local: String) -> void:
        _ok(ContentPacks.disabled_set("shard_2", _sp).is_empty(), "shard_2 has no disable")
        _ok(ContentPacks.enemy_enabled("tidecursed_diver", "shard_2", _sp),
                "shard_2 resolves the pack enabled -- the gate is local")
        _ok(ContentPacks.quest_enabled("quest_tide_salvage", "shard_2", _sp),
                "shard_2 resolves the quest enabled -- the gate is local")

## ---- the /contentpack operator surface --------------------------------
func _test_operator_surface(local: String) -> void:
        _perm._validation_cache["pack_admin"] = {"time": Time.get_ticks_msec(), "level": 100}
        _perm._validation_cache["pack_player"] = {"time": Time.get_ticks_msec(), "level": 0}

        # Re-enable first so the board starts uniform.
        ContentPacks.write_disabled(local, [], _sp, "test")

        # non-admin refused
        _fired.clear()
        _cs._handle_command("pack_player", 9, "contentpack %s disable" % PACK, "")
        _ok(_said("Admin permission required"), "non-admin is refused")
        _ok(not ContentPacks.is_pack_disabled(PACK, local, _sp), "non-admin write did not land")

        # board lists the pack
        _fired.clear()
        _cs._handle_command("pack_admin", 9, "contentpack", "")
        _ok(_said("packs (shard"), "board header present")
        _ok(_said(PACK), "board lists the pack")

        # read view reports enabled
        _fired.clear()
        _cs._handle_command("pack_admin", 9, "contentpack %s" % PACK, "")
        _ok(_said("enabled"), "read view reports enabled")

        # admin disables -> lands + readable immediately (critical param)
        _fired.clear()
        _cs._handle_command("pack_admin", 9, "contentpack %s disable" % PACK, "")
        await process_frame
        _ok(_said("disabled on"), "disable acknowledged")
        _ok(ContentPacks.is_pack_disabled(PACK, local, _sp), "disable landed on the local shard")

        # admin re-enables
        _fired.clear()
        _cs._handle_command("pack_admin", 9, "contentpack %s enable" % PACK, "")
        await process_frame
        _ok(_said("enabled on"), "enable acknowledged")
        _ok(not ContentPacks.is_pack_disabled(PACK, local, _sp), "enable cleared the disable")

        # unknown pack refused by name
        _fired.clear()
        _cs._handle_command("pack_admin", 9, "contentpack no_such_pack disable", "")
        _ok(_said("Unknown pack"), "unknown pack refused by name")

## ---- ADDED ASSERTIONS (exercise real code paths) ----------------------
## Three new checks added on top of the receipt; existing assertions are
## untouched. Each drives a production entry point rather than a mock.
func _test_added_assertions(local: String) -> void:
        # (1) local_enemy_enabled -- the REAL gate SpawnService (x3) and
        # HordeEventService call. It resolves shard_id + ShardParameters
        # from the running tree itself, so a disable on the LOCAL shard
        # must flip it false, and clearing the disable must flip it back.
        ContentPacks.write_disabled(local, [PACK], _sp, "test")
        var local_blocked: bool = ContentPacks.local_enemy_enabled("tidecursed_diver")
        ContentPacks.write_disabled(local, [], _sp, "test")
        var local_allowed: bool = ContentPacks.local_enemy_enabled("tidecursed_diver")
        _ok(not local_blocked and local_allowed,
                "local_enemy_enabled follows the local shard's disable (real spawn gate)")

        # (2) board() -- the operator board the /contentpack command renders.
        # With the pack disabled the row must carry the true owned counts
        # (3 enemies / 4 quests) AND a disabled=true flag; after re-enabling
        # the same row must report disabled=false. Both read live data.
        ContentPacks.write_disabled(local, [PACK], _sp, "test")
        var off_row: Dictionary = _board_row(ContentPacks.board(local, _sp), PACK)
        ContentPacks.write_disabled(local, [], _sp, "test")
        var on_row: Dictionary = _board_row(ContentPacks.board(local, _sp), PACK)
        _ok(off_row.get("disabled", false) == true and on_row.get("disabled", true) == false
                        and int(off_row.get("enemy_count", -1)) == 3
                        and int(off_row.get("quest_count", -1)) == 4,
                "board row tracks the local disable and reports the real owned counts")

        # (3) write_disabled round-trip -- the lever write is readable back
        # through disabled_set as a deduped, sorted set, and a second id
        # joins it. This is the exact path an operator /contentpack write
        # takes into ShardParameters.
        ContentPacks.write_disabled(local, [PACK, PACK, "  "], _sp, "test")
        var single: Dictionary = ContentPacks.disabled_set(local, _sp)
        ContentPacks.write_disabled(local, [PACK, "pack_zzz_probe"], _sp, "test")
        var pair: Dictionary = ContentPacks.disabled_set(local, _sp)
        _ok(single.size() == 1 and single.has(PACK) and pair.size() == 2 and pair.has("pack_zzz_probe"),
                "write_disabled round-trips a deduped set through ShardParameters")
        ContentPacks.write_disabled(local, [], _sp, "test")

## The board row with this id, or {} when absent.
func _board_row(rows: Array, pack_id: String) -> Dictionary:
        for row in rows:
                if str(row.get("id", "")) == pack_id:
                        return row
        return {}

func _cleanup() -> void:
        var local: String = str(_sm.shard_id)
        _sp.set_param(local, ContentPacks.DISABLED_PARAM, "", "test")
