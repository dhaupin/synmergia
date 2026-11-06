## test_shard_tuning_admin.gd - THE PHASE 3.1 OPERATOR-SURFACE RECEIPT.
##
## The tuning lever (labs/prd-shard-mesh.md sec.3.1) shipped with a data
## path but no operator handle. This receipt covers the /shardparam admin
## command that closes it:
##  * non-admins are refused,
##  * an admin sets a shard's cap and the LOCAL curve re-reads it live,
##  * a second shard stays uniform (the lever is local),
##  * an absurd cap is refused with the cap unchanged,
##  * the read view + the state board report the numbers,
##  * reset restores the uniform curve,
##  * a ratio override compounds the post-band cost.
## Run: cd game && godot --headless --path . --script res://tests/test_shard_tuning_admin.gd
extends SceneTree

const CurveScript := preload("res://core/progression/level_curve.gd")
const ShardTuning := preload("res://core/progression/shard_tuning.gd")

var _sp: Node
var _sm: Node
var _cs: Node
var _perm: Node
var _ns: Node
var _fired: Array = []
var _fails := 0
var _passes := 0

func _initialize() -> void:
	await process_frame
	_sp = root.get_node_or_null("ShardParameters")
	_sm = root.get_node_or_null("ShardManager")
	_cs = root.get_node_or_null("ChatService")
	_perm = root.get_node_or_null("PermissionManager")
	_ns = root.get_node_or_null("NotificationService")
	if _sp == null or _sm == null or _cs == null or _perm == null or _ns == null:
		push_error("FAIL: required autoloads missing")
		quit(1)
		return
	_sp.load_definitions()
	OS.set_environment("LEVEL_CAP", "")
	print("--- SHARD TUNING ADMIN (PHASE 3.1) TEST ---")
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
	CurveScript.clear_shard_tuning()

	# Admin + non-admin seams (the PermissionManager validation cache).
	_perm._validation_cache["op_admin"] = {"time": Time.get_ticks_msec(), "level": 100}
	_perm._validation_cache["op_player"] = {"time": Time.get_ticks_msec(), "level": 0}

	# --- 1. non-admin refused ---------------------------------------------
	_fired.clear()
	_cs._handle_command("op_player", 9, "shardparam %s 30" % local, "")
	_ok(_said("Admin permission required"), "non-admin is refused")
	_ok(int(_sp.get_param(local, "level_cap_override")) == 0, "non-admin write did not land")

	# --- 2. admin sets the local cap -> the curve re-reads it live --------
	# The live re-read rides ShardManager's param_applied listener, so pin
	# that signal path here (it is what makes the lever effective).
	var applied_rows: Array = []
	_sp.param_applied.connect(func(sid, pname, value, _actor):
		applied_rows.append([sid, pname, value]))
	_fired.clear()
	_cs._handle_command("op_admin", 9, "shardparam %s 30" % local, "")
	await process_frame
	_ok(_said("[shardparam]"), "admin set acknowledged")
	_ok(int(_sp.get_param(local, "level_cap_override")) == 30, "cap override landed (30)")
	_ok(CurveScript.max_level() == 30, "local curve re-reads the cap (30) live")
	_ok(CurveScript.has_shard_tuning(), "has_shard_tuning() true after set")
	var saw_cap := false
	for row in applied_rows:
		if str(row[0]) == local and str(row[1]) == "level_cap_override" and int(row[2]) == 30:
			saw_cap = true
	_ok(saw_cap, "param_applied fired for the cap write (the live-re-apply driver)")

	# --- 3. the read view reports the numbers -----------------------------
	_fired.clear()
	_cs._handle_command("op_admin", 9, "shardparam %s" % local, "")
	_ok(_said("cap=30"), "read view reports cap=30")

	# --- 4. the state board lists the shards ------------------------------
	_fired.clear()
	_cs._handle_command("op_admin", 9, "shardparam", "")
	_ok(_said("shard tuning"), "board header present")
	_ok(_said(local), "board lists the local shard")

	# --- 5. the lever is LOCAL: a second shard stays uniform --------------
	_ok(int(_sp.get_param("shard_2", "level_cap_override")) == 0, "shard_2 has no override")
	var applied: bool = ShardTuning.apply("shard_2", _sp)
	_ok(not applied and CurveScript.max_level() == CurveScript.DEFAULT_CAP,
		"shard_2 resolves uniform -- the lever is local")

	# --- 6. an absurd cap is refused, cap unchanged -----------------------
	_fired.clear()
	_cs._handle_command("op_admin", 9, "shardparam %s 1" % local, "")
	_ok(_said(">= 2"), "absurd cap refused by name")
	_ok(int(_sp.get_param(local, "level_cap_override")) == 30, "refused write left the cap at 30")
	# Re-apply the local shard's real override after the shard_2 probe.
	ShardTuning.apply(local, _sp)
	_ok(CurveScript.max_level() == 30, "local curve restored to 30 after probe")

	# --- 7. reset restores the uniform curve ------------------------------
	_fired.clear()
	_cs._handle_command("op_admin", 9, "shardparam %s reset" % local, "")
	_ok(_said("reset"), "reset acknowledged")
	_ok(int(_sp.get_param(local, "level_cap_override")) == 0, "reset cleared the cap")
	_ok(CurveScript.max_level() == CurveScript.DEFAULT_CAP, "reset restored DEFAULT_CAP")
	_ok(not CurveScript.has_shard_tuning(), "reset -> has_shard_tuning() false")

	# --- 8. a ratio override compounds the post-band cost -----------------
	_fired.clear()
	_cs._handle_command("op_admin", 9, "shardparam %s 60 1.10" % local, "")
	_ok(int(_sp.get_param(local, "level_cap_override")) == 60, "ratio set also set the cap (60)")
	_ok(abs(CurveScript.effective_band_step() - 1.10) < 0.0001, "ratio override -> effective ratio 1.10")
	var band_top := float(1000) * pow(1.5, 9)
	_ok(CurveScript.level_cost(11) == int(band_top * 1.10), "post-band cost compounds the override ratio")

func _cleanup() -> void:
	var local: String = str(_sm.shard_id)
	_sp.set_param(local, ShardTuning.CAP_PARAM, 0, "test")
	_sp.set_param(local, ShardTuning.XP_RATIO_PARAM, 0.0, "test")
	CurveScript.clear_shard_tuning()
	OS.set_environment("LEVEL_CAP", "")
