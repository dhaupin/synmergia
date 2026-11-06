## test_shard_tuning.gd - THE PHASE 3.1 SHARD TUNING RECEIPT.
##
## Verifies the shard-local progression lever (labs/prd-shard-mesh.md
## sec.3.1) end to end:
##  * ShardParameters.get_param() reads the effective value (applied
##    state-tree value -> definition default -> null).
##  * ShardTuning.apply() folds level_cap_override / xp_ratio_override
##    into LevelCurve as a LOCAL read.
##  * The curve stays UNIFORM absent an override (the default case).
##  * An override is LOCAL: it never leaks to another shard.
##  * The edge proxy is wired (entrypoint `edge` mode + mesh compose).
## Run: cd game && godot --headless --path . --script res://tests/test_shard_tuning.gd
extends SceneTree

const CurveScript := preload("res://core/progression/level_curve.gd")
const ShardTuning := preload("res://core/progression/shard_tuning.gd")

var _sp: Node
var _fails := 0
var _passes := 0

func _initialize() -> void:
	_sp = root.get_node_or_null("ShardParameters")
	if _sp == null:
		push_error("FAIL: ShardParameters autoload missing")
		quit(1)
		return
	_sp.load_definitions()
	print("--- SHARD TUNING (PHASE 3.1) TEST ---")
	_test_definitions()
	_test_read_accessor_default()
	_test_read_accessor_sees_applied()
	_test_uniform_by_default()
	_test_cap_override_applies()
	_test_ratio_override_applies()
	_test_override_wins_over_env()
	_test_override_is_local()
	_test_invalid_override_is_uniform()
	_test_clear_restores_uniform()
	_test_edge_wiring()
	_finish()

func _finish() -> void:
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

## Reset both tuning params for a shard to 0 and clear the curve statics.
func _reset(shard_id: String) -> void:
	_sp.set_param(shard_id, "level_cap_override", 0, "test")
	_sp.set_param(shard_id, "xp_ratio_override", 0.0, "test")
	CurveScript.clear_shard_tuning()

## ---- the .tres definitions ship with the right contract ---------------
func _test_definitions() -> void:
	var cap = load("res://data/roots/world/parameters/level_cap_override.tres")
	var ratio = load("res://data/roots/world/parameters/xp_ratio_override.tres")
	_ok(cap != null and cap.name == "level_cap_override", "level_cap_override.tres loads (name matches)")
	_ok(cap != null and cap.type == "int", "level_cap_override is int-typed")
	_ok(cap != null and cap.critical, "level_cap_override is critical (immediately readable)")
	_ok(ratio != null and ratio.name == "xp_ratio_override", "xp_ratio_override.tres loads (name matches)")
	_ok(ratio != null and ratio.type == "float", "xp_ratio_override is float-typed")
	_ok(ratio != null and ratio.critical, "xp_ratio_override is critical (immediately readable)")
	_ok(ShardTuning.tuning_param_names().has("level_cap_override")
		and ShardTuning.tuning_param_names().has("xp_ratio_override"),
		"resolver names both tuning params")

## ---- the read accessor falls back to the definition default -----------
func _test_read_accessor_default() -> void:
	_sp.set_state_tree("shard_r", _new_tree())
	_ok(_sp.get_param("shard_r", "level_cap_override") == 0, "unwritten cap reads definition default 0")
	_ok(float(_sp.get_param("shard_r", "xp_ratio_override")) == 0.0, "unwritten ratio reads default 0.0")
	_ok(_sp.get_param("shard_r", "no_such_param") == null, "unknown param reads null")

## ---- the read accessor sees an applied (critical) write ---------------
func _test_read_accessor_sees_applied() -> void:
	_sp.set_state_tree("shard_a", _new_tree())
	_reset("shard_a")
	_sp.set_param("shard_a", "level_cap_override", 30, "test")
	_ok(int(_sp.get_param("shard_a", "level_cap_override")) == 30, "applied cap reads back 30")

## ---- UNIFORM BY DEFAULT (the non-negotiable case) ---------------------
func _test_uniform_by_default() -> void:
	OS.set_environment("LEVEL_CAP", "")
	_sp.set_state_tree("shard_u", _new_tree())
	_reset("shard_u")
	var applied: bool = ShardTuning.apply("shard_u", _sp)
	_ok(not applied, "no override -> apply() reports uniform")
	_ok(not CurveScript.has_shard_tuning(), "no override -> has_shard_tuning() false")
	_ok(CurveScript.max_level() == CurveScript.DEFAULT_CAP, "no override -> DEFAULT_CAP")
	_ok(CurveScript.effective_band_step() == CurveScript.BAND_STEP, "no override -> BAND_STEP ratio")

## ---- a cap override applies, and the curve reads it -------------------
func _test_cap_override_applies() -> void:
	OS.set_environment("LEVEL_CAP", "")
	_sp.set_state_tree("shard_c", _new_tree())
	_reset("shard_c")
	_sp.set_param("shard_c", "level_cap_override", 30, "test")
	var applied: bool = ShardTuning.apply("shard_c", _sp)
	_ok(applied, "cap override -> apply() reports applied")
	_ok(CurveScript.max_level() == 30, "cap override -> max_level() is 30")
	# The in-band law is untouched by a cap-only override.
	_ok(CurveScript.level_cost(10) == int(float(1000) * pow(1.5, 9)),
		"cap override leaves the shipped in-band law untouched")
	_ok(CurveScript.effective_band_step() == CurveScript.BAND_STEP,
		"cap-only override leaves the post-band ratio at BAND_STEP")

## ---- a ratio override applies, and the post-band cost reads it --------
func _test_ratio_override_applies() -> void:
	OS.set_environment("LEVEL_CAP", "")
	_sp.set_state_tree("shard_x", _new_tree())
	_reset("shard_x")
	_sp.set_param("shard_x", "xp_ratio_override", 1.10, "test")
	var applied: bool = ShardTuning.apply("shard_x", _sp)
	_ok(applied, "ratio override -> apply() reports applied")
	_ok(abs(CurveScript.effective_band_step() - 1.10) < 0.0001, "ratio override -> effective ratio 1.10")
	var band_top := float(1000) * pow(1.5, 9)
	_ok(CurveScript.level_cost(11) == int(band_top * 1.10), "post-band cost compounds the override ratio")
	_ok(CurveScript.max_level() == CurveScript.DEFAULT_CAP, "ratio-only override leaves the cap at DEFAULT_CAP")

## ---- the shard override WINS over the deployment env ------------------
func _test_override_wins_over_env() -> void:
	OS.set_environment("LEVEL_CAP", "90")
	_sp.set_state_tree("shard_p", _new_tree())
	_reset("shard_p")
	_sp.set_param("shard_p", "level_cap_override", 30, "test")
	ShardTuning.apply("shard_p", _sp)
	_ok(CurveScript.max_level() == 30, "shard cap override outranks LEVEL_CAP env (30, not 90)")
	OS.set_environment("LEVEL_CAP", "")

## ---- the override is LOCAL: it never leaks to another shard -----------
func _test_override_is_local() -> void:
	OS.set_environment("LEVEL_CAP", "")
	_sp.set_state_tree("shard_l1", _new_tree())
	_sp.set_state_tree("shard_l2", _new_tree())
	_reset("shard_l1")
	_reset("shard_l2")
	_sp.set_param("shard_l1", "level_cap_override", 25, "test")
	ShardTuning.apply("shard_l1", _sp)
	_ok(CurveScript.max_level() == 25, "shard_l1 sees its own cap 25")
	# Another shard has no override -> resolving IT returns the uniform curve.
	ShardTuning.apply("shard_l2", _sp)
	_ok(CurveScript.max_level() == CurveScript.DEFAULT_CAP, "shard_l2 (no override) stays uniform -- the lever is local")

## ---- an invalid override is ignored (uniform) -------------------------
func _test_invalid_override_is_uniform() -> void:
	OS.set_environment("LEVEL_CAP", "")
	_sp.set_state_tree("shard_bad", _new_tree())
	_reset("shard_bad")
	_sp.set_param("shard_bad", "level_cap_override", 1, "test")   # absurd (< 2)
	_sp.set_param("shard_bad", "xp_ratio_override", -0.5, "test") # negative
	var applied: bool = ShardTuning.apply("shard_bad", _sp)
	_ok(not applied, "absurd cap / negative ratio -> apply() reports uniform")
	_ok(CurveScript.max_level() == CurveScript.DEFAULT_CAP, "absurd override falls back to DEFAULT_CAP")

## ---- clearing restores the uniform curve ------------------------------
func _test_clear_restores_uniform() -> void:
	OS.set_environment("LEVEL_CAP", "")
	_sp.set_state_tree("shard_clr", _new_tree())
	_sp.set_param("shard_clr", "level_cap_override", 40, "test")
	ShardTuning.apply("shard_clr", _sp)
	_ok(CurveScript.max_level() == 40, "override in force before clear")
	_sp.set_param("shard_clr", "level_cap_override", 0, "test")
	ShardTuning.apply("shard_clr", _sp)
	_ok(CurveScript.max_level() == CurveScript.DEFAULT_CAP, "clearing the override restores DEFAULT_CAP")
	_ok(not CurveScript.has_shard_tuning(), "cleared -> has_shard_tuning() false")

## ---- the edge proxy is wired (source receipts) ------------------------
func _test_edge_wiring() -> void:
	var repo_root: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var ep := FileAccess.open(repo_root + "/srv/docker/entrypoint.sh", FileAccess.READ)
	_ok(ep != null, "entrypoint.sh is readable")
	if ep != null:
		var src := ep.get_as_text()
		_ok(src.contains('== "edge"'), "entrypoint has an `edge` START_MODE branch")
		_ok(src.contains("_setup_nginx"), "the edge branch drives nginx")
		_ok(src.contains("nginx -g 'daemon off;'"), "the edge branch runs nginx (no Godot)")
	var comp := FileAccess.open(repo_root + "/docker-compose.yml", FileAccess.READ)
	_ok(comp != null, "docker-compose.yml is readable")
	if comp != null:
		var yml := comp.get_as_text()
		_ok(yml.contains("START_MODE=edge"), "mesh compose defines an edge service (START_MODE=edge)")
		_ok(yml.contains("GODOT_UPSTREAM"), "edge service passes the shard upstream list")
