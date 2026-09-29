## Tests for FoldedShell -- the storage mechanism (owner insight,
## 2026-09-29: folding surface area increases store/state; the
## intersection between spaces is a storage rebate).
##
## Covers: the fold law (4x capacity in the same footprint),
## containment (folding never leaves the parent slot), depth limits
## (the shape refuses to overrun), the intersection rebate (shared
## facts stored once, claimed by many), intersection-aware removal
## (a leaving space never erases claimed state), and the bounded hot
## working set (stress is measured, not feared).
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var FS = load("res://core/frame/kv/folded_shell.gd")

	# ---- A. The fold law ---------------------------------------------------
	_check("one fold = 4x capacity (4^depth)", FS.fold_capacity(0) == 1 \
		and FS.fold_capacity(1) == 4 and FS.fold_capacity(4) == 256)
	_check("depth 0 is the unfolded root", FS.cell_depth(0) == 0)
	_check("folding the root yields 4 children", FS.fold_cell(0).size() == 4)
	var kids: Array = FS.fold_cell(0)
	_check("children of the root are exactly {1,2,3,4} (heap law)", \
		kids[0] == 1 and kids[1] == 2 and kids[2] == 3 and kids[3] == 4)
	var kid0_depth: int = FS.cell_depth(kids[0])
	_check("children sit one fold deeper than the parent", kid0_depth == 1)
	_check("folding a child stays inside the parent's ring (containment)", \
		(kids[0] as int) >= 1 and (kids[3] as int) < 1 + 4)
	var grand: Array = FS.fold_cell(kids[0])
	_check("folding compounds (grandchildren exist)", grand.size() == 4 \
		and FS.cell_depth(grand[0]) == 2)

	# ---- B. The shape refuses to overrun ------------------------------------
	var deepest: Array = FS.fold_cell(0)
	for i in range(FS.MAX_FOLD_DEPTH + 2):
		var next: Array = FS.fold_cell(deepest[0])
		if next.is_empty():
			break
		deepest = next
	_check("past MAX_FOLD_DEPTH the fold is refused", FS.fold_cell(deepest[0]).is_empty())

	# ---- C. The intersection rebate ------------------------------------------
	var shell = FS.new(64)
	shell.ensure_space("main")
	shell.ensure_space("moon")
	# Main stores five facts; moon stores three, TWO of which are the
	# same content (the intersection).
	var paid_main := 0
	for i in range(5):
		if shell.put("main", 0, "hash_%d" % i, "fact_%d" % i):
			paid_main += 1
	_check("first insertion pays", paid_main == 5)
	var paid_moon := 0
	paid_moon += 1 if shell.put("moon", 0, "hash_0", "fact_0") else 0
	paid_moon += 1 if shell.put("moon", 0, "hash_1", "fact_1") else 0
	paid_moon += 1 if shell.put("moon", 0, "hash_moon_1", "moon_fact_1") else 0
	_check("the rebate: shared facts are claimed, not paid again", \
		paid_moon == 1 and shell.space_size("moon") == 3)
	_check("two spaces, five distinct facts (one store)", shell.rebate("main", "moon") == 2)
	var inter: Array = shell.intersection("main", "moon")
	_check("intersection reports exactly the shared facts", inter.size() == 2 \
		and inter.has("hash_0") and inter.has("hash_1"))
	_check("the shared fact holds one value across spaces", \
		shell.get_value("hash_0") == "fact_0" and shell.has_fact("hash_1"))
	_check("fact_cells tracks every claiming cell", shell.fact_cells("hash_0").size() == 1)
	_check("intersecting_spaces finds the overlap", \
		shell.intersecting_spaces("main") == ["moon"])

	# ---- D. Removal is intersection-aware ------------------------------------
	_check("releasing moon keeps the shared facts alive", \
		shell.release_space("moon") == 1 \
		and shell.has_fact("hash_0") and shell.has_fact("hash_1") \
		and shell.get_value("hash_0") == "fact_0")
	_check("main is untouched by the release", shell.space_size("main") == 5)
	_check("releasing main orphans exactly its unique facts", \
		shell.release_space("main") == 5 and not shell.has_fact("hash_0"))

	# ---- E. Stress is measured (the bounded working set) ----------------------
	var small = FS.new(2)
	for i in range(6):
		small.put("solo", 0, "k_%d" % i, i)
	_check("hot set bounded at max_size", small.is_hot("k_5") and not small.is_hot("k_0"))
	_check("evictions counted, not feared", small.evictions() == 4)
	_check("cold facts still remembered by the shape", small.get_value("k_0") != null)

	if _fails == 0:
		print("FOLDED SHELL TEST PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("FOLDED SHELL TEST FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
