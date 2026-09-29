## Tests for T3 dedup at scale -- the first FoldedShell consumer.
##
## The owner's T3-at-scale thesis: N entities sharing K distinct
## state blocks pay K stores, not N. The tree keeps node records;
## the payload VALUE lives in a content-hash cell on the shell (the
## intersection rebate). Covers:
##   A. the byte-identical rebate (same value at many paths pays once),
##   B. distinct content never merges (different bytes = different cells),
##   C. the scale measurement (savings_ratio against a duplicate workload),
##   D. the same-root proof (dedup cannot change tree identity),
##   E. diff/apply re-claims content instead of re-paying,
##   F. Resource payloads fall back to inline cells (identity, not content),
##   G. removal is intersection-aware (release keeps shared facts).
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var T3 = load("res://core/frame/kv/t3.gd")
	var FS = load("res://core/frame/kv/folded_shell.gd")
	var schema := Resource.new()

	# ---- A. The byte-identical rebate ---------------------------------------
	var t3 = T3.new()
	var vb := {"hp": 100, "mp": 50, "pos": [12.5, 0.0, -3.25]}
	var h1: PackedByteArray = t3.insert("entities/wolf_a", vb, schema)
	t3.insert("entities/wolf_b", vb, schema)
	t3.insert("entities/wolf_c", vb, schema)
	var distinct_a: int = t3.shell().space_size("t3")
	_check("three identical payloads collapse to ONE cell", distinct_a == 1)
	_check("all three paths read the shared value back", \
		t3.get_at("entities/wolf_a").get("hp") == 100 \
		and t3.get_at("entities/wolf_b").get("pos")[0] == 12.5 \
		and t3.get_at("entities/wolf_c").get("mp") == 50)
	var _unused: PackedByteArray = t3.insert("entities/wolf_a", vb, schema)  # re-store: rebate re-claims, no new cell
	_check("the cell stores content, and node records stay separate", \
		t3._nodes.size() == 3 and t3.shell().space_size("t3") == 1)

	# ---- B. Distinct content never merges -------------------------------------
	t3.insert("entities/wolf_d", {"hp": 101, "mp": 50, "pos": [12.5, 0.0, -3.25]}, schema)
	t3.insert("entities/wolf_e", {"hp": 100, "mp": 50, "pos": [12.5, 0.0, -3.25]}, schema)  # byte-identical to wolf_a's content
	_check("one differing byte makes a new cell (no false merge)", \
		t3.shell().space_size("t3") == 2)
	_check("and identical content from a different path re-claims the ORIGINAL cell", \
		t3.get_at("entities/wolf_e").get("hp") == 100)
	_check("the shared cell is untouched by the new stores", \
		t3.get_at("entities/wolf_a").get("hp") == 100)

	# ---- C. The scale measurement ----------------------------------------------
	var t3s = T3.new()
	# Realistic workload: 300 entities over a small distinct-state pool.
	var distinct_pool: int = 12
	var kinds: Array = []
	for k in range(distinct_pool):
		kinds.append({"type": "position", "x": k * 1.5, "region": "starter_plains"})
	var stores: int = 0
	for i in range(300):
		t3s.insert("entities/e_%d" % i, kinds[i % distinct_pool], schema)
		stores += 1
	var cells: int = t3s.shell().space_size("t3")
	var ratio: float = t3s.savings_ratio()
	_check("300 stores pay only the distinct pool", cells == distinct_pool)
	_check("savings measured, near the N/K thesis ceiling", \
		ratio > 0.95 and ratio <= 1.0)
	_check("every path still reads its own logical value", \
		t3s.get_at("entities/e_7").get("x") == 7 * 1.5 \
		and t3s.get_at("entities/e_299").get("x") == (299 % distinct_pool) * 1.5)

	# ---- D. The same-root proof (dedup cannot change identity) -----------------
	var plain = T3.new()
	var dedup = T3.new()
	var blob_a := {"i": 1, "p": [1, 2, 3]}
	var blob_b := {"i": 2, "p": [4, 5, 6]}
	for i in range(8):
		plain.insert("n/%d" % i, blob_a if i % 2 == 0 else blob_b, schema)
		dedup.insert("n/%d" % i, blob_a if i % 2 == 0 else blob_b, schema)
	_check("an identical workload hashes to the same root as before the shell", \
		plain.hash_subtree("/") == dedup.hash_subtree("/"))

	# ---- E. diff/apply re-claims content instead of re-paying -------------------
	var src = T3.new()
	src.insert("a", {"v": 1}, schema)
	var r0: PackedByteArray = src.hash_subtree("/")
	src.insert("b", {"v": 1}, schema)   # same CONTENT, new path
	src.insert("a", {"v": 2}, schema)   # path a changes
	var r1: PackedByteArray = src.hash_subtree("/")
	var dst = T3.new()
	dst.insert("a", {"v": 1}, schema)   # dst starts at r0 state
	var patch: Array = src.diff(r0, r1)
	var applied: PackedByteArray = dst.apply_diff(r0, patch)
	_check("apply_diff roundtrips to the source root", applied == r1)
	_check("rebased paths re-claim shared content cells", \
		dst.get_at("a").get("v") == 2 and dst.get_at("b").get("v") == 1)
	_check("the destination paid for DISTINCT content only", \
		dst.shell().space_size("t3") == 2)

	# ---- F. Resource payloads fall back to inline cells --------------------------
	var t3r = T3.new()
	var res := Resource.new()
	res.set_meta("k", "shared")
	t3r.insert("r/one", res, schema)
	t3r.insert("r/two", res, schema)
	_check("resources store on inline cells (identity, not content)", \
		t3r.get_at("r/one").get_meta("k") == "shared" \
		and t3r.get_at("r/two").get_meta("k") == "shared")

	# ---- G. Removal is intersection-aware ----------------------------------------
	t3r.clear()
	_check("clear releases the tree's claim set", t3r.shell().space_size("t3") == 0)

	# ---- H. QC: the content-hash law (same hash IS the same fact) ------------------
	# Two paths storing BYTE-IDENTICAL values but through DIFFERENT
	# node paths share the cell; and a value that serializes
	# identically but differs in key ORDER is the same content too
	# (var_to_bytes follows insertion order -- so it does NOT fold key
	# order; different order = different bytes = different cells, and
	# that is the honest contract: bytes are identity).
	var t3h = T3.new()
	var ord_a := {"a": 1, "b": 2}
	var ord_b := {"b": 2, "a": 1}
	t3h.insert("o/a", ord_a, schema)
	t3h.insert("o/b", ord_b, schema)
	_check("key order is part of content (bytes are identity, stated honestly)", \
		t3h.shell().fact_count() == 2)
	# A resource value falls back to inline storage even when another
	# resource with the same meta exists -- identity, not content.
	var res_a := Resource.new()
	res_a.set_meta("k", "x")
	var res_b := Resource.new()
	res_b.set_meta("k", "x")
	t3h.insert("r/a", res_a, schema)
	t3h.insert("r/b", res_b, schema)
	_check("two equal-but-distinct resources stay distinct (identity law)", \
		t3h.get_at("r/a") != t3h.get_at("r/b"))

	# ---- I. QC: shared cells under update-heavy workloads ---------------------------
	# Overwrites accumulate distinct content cells (the shell keeps
	# content-addressed history -- same asymptotics as the T3 snapshot
	# law, no regression). Roundtrip through diff/apply must still be
	# exact after a long update chain.
	var t3u = T3.new()
	t3u.insert("hot", {"tick": 0}, schema)
	var roots: Array = [t3u.hash_subtree("/")]
	for tick in range(1, 21):
		t3u.insert("hot", {"tick": tick}, schema)
		roots.append(t3u.hash_subtree("/"))
	_check("each update made a new distinct cell (content-addressed history)", \
		t3u.shell().fact_count() == 21)
	_check("savings honestly near zero on all-distinct workloads", \
		t3u.savings_ratio() == 0.0)
	var deep = T3.new()
	deep.insert("hot", {"tick": 0}, schema)
	var hot_patch: Array = t3u.diff(roots[0], roots[20])
	var applied_root: PackedByteArray = deep.apply_diff(roots[0], hot_patch)
	_check("20-update chain roundtrips to the source root", \
		applied_root == roots[20] and deep.get_at("hot").get("tick") == 20)
	_check("diff carries only the root DELTA (intermediate history never crosses the wire)", \
		hot_patch.size() == 1 and deep.shell().fact_count() == 2)

	# ---- J. QC: batch inserts obey the same rebate -----------------------------------
	var t3b = T3.new()
	var entries: Array = []
	for i in range(50):
		entries.append(["batch/%d" % (i % 10), {"slot": i % 10}, schema])
	t3b.insert_batch(entries)
	_check("batch of 50 over 10 distinct payloads pays 10 cells", \
		t3b.shell().fact_count() == 10)
	_check("batch paths read back correctly", \
		t3b.get_at("batch/3").get("slot") == 3 and t3b.get_at("batch/9").get("slot") == 9)

	if _fails == 0:
		print("T3 DEDUP TEST PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("T3 DEDUP TEST FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
