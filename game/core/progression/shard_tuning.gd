## ShardTuning - THE PHASE 3.1 SHARD TUNING RESOLVER.
##
## Applies a shard's LOCAL progression overrides (level_cap_override,
## xp_ratio_override) from ShardParameters into LevelCurve. This is a
## LOCAL READ, never a shared write: the mesh's hashed/shared identity
## stays uniform across shards (labs/prd-shard-mesh.md sec.3.1).
##
## Called at boot (after ShardManager has its id and ShardParameters has
## its definitions) and again whenever a tuning parameter is applied, so
## an operator can flip a running shard's numbers. Absent overrides leave
## the curve UNIFORM -- the default case is not negotiable.
##
## The service is passed in (not resolved as a bare autoload) so
## script-mode receipts and tests need no registered autoload.

extends RefCounted
class_name ShardTuning

const LevelCurveScript = preload("res://core/progression/level_curve.gd")

const CAP_PARAM := "level_cap_override"
const XP_RATIO_PARAM := "xp_ratio_override"

## Names of the parameters this resolver reads (for a caller wiring a
## change listener so it only re-applies on a tuning write).
static func tuning_param_names() -> Array:
	return [CAP_PARAM, XP_RATIO_PARAM]

## Resolve and apply a shard's tuning from ShardParameters.
## `sp` is the ShardParameters service; returns true when an override was
## applied, false when the shard runs the uniform curve.
static func apply(shard_id: String, sp: Node) -> bool:
	if sp == null or shard_id == "":
		LevelCurveScript.clear_shard_tuning()
		return false
	var cap: int = 0
	var ratio: float = 0.0
	if sp.has_method("get_param"):
		var cap_v: Variant = sp.get_param(shard_id, CAP_PARAM)
		if cap_v != null:
			cap = int(cap_v)
		var ratio_v: Variant = sp.get_param(shard_id, XP_RATIO_PARAM)
		if ratio_v != null:
			ratio = float(ratio_v)
	if cap >= 2 or ratio > 0.0:
		LevelCurveScript.set_shard_tuning(cap, ratio)
		return true
	LevelCurveScript.clear_shard_tuning()
	return false
