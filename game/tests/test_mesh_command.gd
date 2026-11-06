## test_mesh_command.gd - THE /mesh OPERATOR-SURFACE RECEIPT.
##
## Verifies the read-only mesh status command (labs/prd-shard-mesh.md
## Phase 3):
##  * non-admins are refused,
##  * an admin's report names the role + self id (MeshRole law),
##  * the registry section reflects CoordinatorService's shard board,
##  * the bus section reflects the active transport (get_id/get_display_name),
##  * the report is READ-ONLY (no mesh write follows it).
## Run: cd game && godot --headless --path . --script res://tests/test_mesh_command.gd
extends SceneTree

const MeshRole := preload("res://core/mesh/mesh_role.gd")

var _cs: Node
var _perm: Node
var _ns: Node
var _coord: Node
var _fired: Array = []
var _fails := 0
var _passes := 0

func _initialize() -> void:
        await process_frame
        _cs = root.get_node_or_null("ChatService")
        _perm = root.get_node_or_null("PermissionManager")
        _ns = root.get_node_or_null("NotificationService")
        _coord = root.get_node_or_null("CoordinatorService")
        if _cs == null or _perm == null or _ns == null:
                push_error("FAIL: required autoloads missing")
                quit(1)
                return
        print("--- MESH COMMAND TEST ---")
        _ns.notification_sent.connect(func(_pid, n):
                _fired.append(str(n.get("message", "") if n is Dictionary else n)))
        await _run()
        print("--- RESULT: %d passed, %d failed ---" % [_passes, _fails])
        quit(1 if _fails > 0 else 0)

func _ok(cond: bool, label: String) -> void:
        if cond:
                _passes += 1
                print("PASS: ", label)
        else:
                _fails += 1
                push_error("FAIL: %s" % label)

func _said(needle: String) -> bool:
        for m in _fired:
                if m.find(needle) != -1:
                        return true
        return false

func _last() -> String:
        return str(_fired[-1]) if not _fired.is_empty() else ""

func _run() -> void:
        _perm._validation_cache["mesh_admin"] = {"time": Time.get_ticks_msec(), "level": 100}
        _perm._validation_cache["mesh_player"] = {"time": Time.get_ticks_msec(), "level": 0}

        # --- 1. non-admin refused --------------------------------------------
        _fired.clear()
        _cs._handle_command("mesh_player", 9, "mesh", "")
        _ok(_said("Admin permission required"), "non-admin is refused")

        # --- 2. admin report: role + self id ---------------------------------
        _fired.clear()
        _cs._handle_command("mesh_admin", 9, "mesh", "")
        _ok(_said("[mesh]"), "report header present")
        _ok(_said("role: "), "report names the role")
        _ok(_said("self_id: "), "report names the self id")
        _ok(_said("shard_id: "), "report names the shard id")
        _ok(_said(MeshRole.resolve()), "role matches MeshRole.resolve()")
        _ok(_said(MeshRole.self_id()), "self id matches MeshRole.self_id()")

        # --- 3. registry section reflects the coordinator board --------------
        if _coord != null and _coord.has_method("get_all_shard_ids"):
                var ids: Array = _coord.get_all_shard_ids()
                _ok(_said("registry: %d shard(s)" % ids.size()),
                        "registry section reports the coordinator board size")
        else:
                _ok(_said("registry:"), "registry section present")

        # --- 4. bus section reflects the active transport --------------------
        _ok(_said("bus: "), "bus section present")
        if _coord != null and _coord.has_method("bus"):
                var bus = _coord.bus()
                if bus != null and bus.has_method("get_display_name"):
                        _ok(_said(str(bus.get_display_name())), "bus section names the active transport")

        # --- 5. READ-ONLY: no mesh write follows the report ------------------
        # A read command must not mutate the registry. Snapshot the shard
        # board before/after and assert it is unchanged.
        if _coord != null and _coord.has_method("get_all_shard_ids"):
                var before: Array = _coord.get_all_shard_ids().duplicate()
                _fired.clear()
                _cs._handle_command("mesh_admin", 9, "mesh", "")
                var after: Array = _coord.get_all_shard_ids()
                _ok(before == after, "the report is read-only (registry unchanged)")
