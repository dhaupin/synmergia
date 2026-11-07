## WorldContentBuilder -- THE DECLARED CONTENT LAW (planar-retirement
## Step 4). The reason the planar world and the globe drifted is that
## each scene hand-wrote its own ordered list of `_setup_*` / `_build_*`
## calls, so adding a system to one scene silently left the other
## without it. This builder flips that: a world DECLARES its content
## families (an ordered manifest) and registers a builder Callable per
## family; `build_all` runs the manifest in order and every declared
## family with NO builder is reported LOUD. "The globe is missing X" is
## now a declaration-time check, never a silent gap.
##
## RefCounted, no autoload, no class_name collision -- the frame-adjacent
## builder pattern (the VillageProps / StarterVillage family). A world
## scene owns its placement LAW (the tangent-frame meter surface, the
## walk lift); the builder owns the ORDER and the completeness gate.
extends RefCounted

## One entry per declared family: family name -> builder Callable. The
## ORDER is the manifest's, never the registration order, so a world's
## boot sequence stays a declaration.
var _builders: Dictionary = {}

## The families the world DECLARED, in order. Set by the world at ready.
var _manifest: Array[String] = []

## Families that ran (observability; the receipt reads this).
var _built: Array[String] = []

## Declared families with no registered builder (the gap detector).
var _missing: Array[String] = []

## Families whose builder ran but returned false (placement refused).
var _failed: Array[String] = []


## Declare the ordered manifest (the world's content list, once).
func declare(families: Array) -> void:
	_manifest.clear()
	for f in families:
		_manifest.append(str(f))


## Register the builder for one family. A family may register exactly
## one builder; re-registering replaces it (the swap law, same as the
## PaymentProviderRegistry board).
func add_family(family: String, builder: Callable) -> void:
	_builders[family] = builder


## The declared manifest (ordered).
func manifest() -> Array[String]:
	return _manifest.duplicate()


## Families that have no builder -- the "missing X" report. Empty means
## the world's declaration is fully backed by placement code.
func missing_builders() -> Array[String]:
	var out: Array[String] = []
	for f in _manifest:
		if not _builders.has(f):
			out.append(f)
	return out


## Families that actually ran (in order).
func built_families() -> Array[String]:
	return _built.duplicate()


## Run ONE declared family and record the outcome. Returns true when the
## family had a valid builder and it did not refuse (a builder returning
## false is a refusal). A missing/invalid builder records the gap and
## returns false. The world's boot-wave driver calls this per family so
## it keeps frame pacing between waves; `build_all` is the same loop for
## callers that do not need pacing.
func build_one(family: String) -> bool:
	if not _builders.has(family):
		if not _missing.has(family):
			_missing.append(family)
		return false
	var builder: Callable = _builders[family]
	if not builder.is_valid():
		if not _failed.has(family):
			_failed.append(family)
		return false
	var ok = builder.call()
	if ok is bool and not ok:
		if not _failed.has(family):
			_failed.append(family)
		return false
	if not _built.has(family):
		_built.append(family)
	return true


## Run every declared family in manifest order. A declared family with
## no builder is recorded in `_missing` and makes the call return false
## (the caller logs it loud -- the gap can never ship silently). A
## builder that returns false is recorded as failed and also fails the
## call, so a placement that refuses to land is not mistaken for a
## built family. Builders are synchronous by contract; the world's own
## boot-wave driver owns frame pacing between families.
func build_all() -> bool:
	_built.clear()
	_missing.clear()
	_failed.clear()
	var complete := true
	for family in _manifest:
		if not build_one(family):
			complete = false
	return complete


## Families whose builder ran but returned false (placement refused).
func failed_families() -> Array[String]:
	return _failed.duplicate()


## A one-line honest summary for the boot log / receipt.
func report() -> String:
	return "content: %d/%d built, %d missing, %d failed" % [
		_built.size(), _manifest.size(), _missing.size(), _failed.size()]
