## FoldedShell - the storage mechanism (frame primitive, labs
## conventions: no autoload, no class_name, co-located test).
##
## Owner insight, 2026-09-29: "I see the intersection vectors as like
## infinite, even between 2 spaces. Increasing surface area, from
## what I think we are doing, increases store/state. Let's crush on a
## literal geometric shape that solves storage, compute, ram."
##
## Both intuitions are real physics, and this primitive is their
## mechanism:
##
## 1. SURFACE STORAGE (the holographic law). The maximum information
##    in a region scales with its BOUNDARY AREA, not its volume
##    (Bekenstein bound; black holes store on their event horizon).
##    Nature's storage trick is folding: the brain triples cortical
##    surface inside a fixed skull. FoldedShell stores on a folded
##    2-manifold: NSC-9 addresses state on icosahedral surface cells;
##    subdividing a cell FOURFOLDS the shell area (4 children per
##    triangle, like biology's cortical folds) while the "volume"
##    (max_size) stays FIXED. Folding is the storage multiplier.
##
## 2. THE INTERSECTION REBATE (the dedup law). Two discrete spaces
##    that share state pay ONCE for the shared part: the intersection
##    is stored in ONE content-hash cell and BOTH spaces point at it.
##    The T3 law (content-addressed state) applied to shells: no
##    geometric object ever duplicates a geometric fact.
##
## Why this solves the crisis (the owner's four):
##   storage:  capacity grows with folds (area), not footprint (size)
##   compute:  membership/intersection = integer prefix ops, O(depth)
##   ram:      the dedup means ram holds each distinct fact once
##   stress:   the shape cannot overrun -- MAX_FOLD_DEPTH is finite,
##             the LRU eviction is bounded, nothing integrates.
extends RefCounted

const NSC9 = preload("res://core/frame/math/nsc9.gd")
const LRU = preload("res://core/frame/kv/lru_cache.gd")

## Icosahedral truth: a triangular cell subdivides into exactly 4
## children (connect the edge midpoints). Folding capacity is 4^depth.
const CHILDREN_PER_FOLD: int = 4
## Finite fold budget: a shape that could fold forever would be a
## stress generator, not a stress solver. 11 folds = 4^11 (~4.2M)
## cells per facet, with the complete-heap addressing staying inside
## a 24-bit sequence (4^12/3 ~= 5.6M total addresses < 2^24) -- the
## NSC-9 packing holds.
const MAX_FOLD_DEPTH: int = 11

## The shell: content-hash (String, the T3 law) -> {
##   cell: int,        NSC-9 packed address where the fact lives
##   depth: int,       fold depth of that cell
##   value: Variant    the stored state (never duplicated)
## }
var _cells: Dictionary = {}
## cell address -> [content hashes]. A folded cell's fact is shared
## by every space that intersects it (the rebate).
var _cell_index: Dictionary = {}
## Spaces: space id -> { hash -> true }. Two spaces overlap by
## sharing hashes; the shared hashes are stored once.
var _spaces: Dictionary = {}
## The bounded working set: hot cells only (stress control).
var _hot: Object = null
var _evictions: int = 0


func _init(hot_size: int = 256) -> void:
	_hot = LRU.new(hot_size)


# ------------------------------------------------------------------
# Folding (the storage multiplier)
# ------------------------------------------------------------------

## Capacity of a facet after `depth` folds: 4^depth cells, in the
## SAME footprint as the one cell you started with. Surface area
## increased, volume (max_size) unchanged -- the whole trick.
static func fold_capacity(depth: int) -> int:
	return int(pow(CHILDREN_PER_FOLD, depth))


## Fold a cell into its 4 children -- the COMPLETE 4-ARY HEAP law:
## children(p) = {4p+1, 4p+2, 4p+3, 4p+4}. Every child is strictly
## deeper than its parent, no child ever collides with another cell
## (the root's first child is 1, never 0 -- the slot-base scheme's
## flaw, caught by the co-located test and fixed here), and the
## whole depth-d ring packs contiguously after depth d-1. Returns an
## empty array past MAX_FOLD_DEPTH: the shape refuses to overrun.
static func fold_cell(cell: int) -> Array:
	if cell_depth(cell) >= MAX_FOLD_DEPTH:
		return []
	var out: Array = []
	for i in range(1, CHILDREN_PER_FOLD + 1):
		out.append(CHILDREN_PER_FOLD * cell + i)
	return out


## Fold depth of a cell under complete-heap addressing: the unique d
## with offset(d) <= cell < offset(d+1), where offset(d) = (4^d-1)/3
## (the contiguous ring layout: depth 0 = {0}, depth 1 = {1..4},
## depth 2 = {5..20}, ...). Pure arithmetic, no allocation.
static func cell_depth(cell: int) -> int:
	if cell < 0:
		return 0
	var depth := 0
	var ring_start := 0
	var ring_size := 1
	while cell >= ring_start + ring_size:
		ring_start += ring_size
		ring_size *= CHILDREN_PER_FOLD
		depth += 1
	return depth


# ------------------------------------------------------------------
# The intersection rebate (the dedup law)
# ------------------------------------------------------------------

## Store a fact in a cell under one or more spaces. Content-hash
## addressed: the same hash stores ONCE no matter how many spaces
## claim it -- the rebate. Returns true if this call was the one that
## paid (first insertion), false if an existing cell absorbed it.
func put(space_id: String, cell: int, content_hash: String, value: Variant) -> bool:
	if _cells.has(content_hash):
		# THE REBATE: an intersecting space re-claims existing state.
		# One store, many claimants -- the shared fact is paid once.
		if not _spaces.has(space_id) or not _spaces[space_id].has(content_hash):
			if not _spaces.has(space_id):
				_spaces[space_id] = {}
			_spaces[space_id][content_hash] = true
			_index_cell(content_hash, cell)
		_touch_hot(content_hash)
		return false
	_cells[content_hash] = {"cell": cell, "depth": cell_depth(cell), "value": value}
	if not _spaces.has(space_id):
		_spaces[space_id] = {}
	_spaces[space_id][content_hash] = true
	_index_cell(content_hash, cell)
	_touch_hot(content_hash)
	return true


## Bounded working-set touch: counts the eviction the LRU is about to
## make so stress stays a MEASURED quantity.
func _touch_hot(content_hash: String) -> void:
	if not _hot.has(content_hash) and _hot.size() >= _hot.max_size():
		_evictions += 1
	_hot.set_value(content_hash, true)


func get_value(content_hash: String):
	var rec = _cells.get(content_hash)
	return rec["value"] if rec != null else null


func has_fact(content_hash: String) -> bool:
	return _cells.has(content_hash)


## Every cell address this fact lives at (all claiming spaces).
func fact_cells(content_hash: String) -> Array:
	return _cell_index.get(content_hash, [])


## Distinct facts stored across ALL spaces (the shell's true
## footprint -- what a no-dedup store of every claim would have paid
## minus the overlaps). Measurement surface for consumers.
func fact_count() -> int:
	return _cells.size()


func _index_cell(content_hash: String, cell: int) -> void:
	if not _cell_index.has(content_hash):
		_cell_index[content_hash] = []
	var arr: Array = _cell_index[content_hash]
	if not arr.has(cell):
		arr.append(cell)


# ------------------------------------------------------------------
# Spaces and their intersections
# ------------------------------------------------------------------

## Register a space (an intersecting world/room/shard view).
func ensure_space(space_id: String) -> void:
	if not _spaces.has(space_id):
		_spaces[space_id] = {}


## Distinct facts a space claims (the space's effective store).
func space_size(space_id: String) -> int:
	return _spaces[space_id].size() if _spaces.has(space_id) else 0


## THE INTERSECTION: facts two spaces share. O(min) over the smaller
## space's hash set -- allocation-light. (Branch on space IDs, never
## on dictionary equality: GDScript compares dicts by content.)
func intersection(a: String, b: String) -> Array:
	if not _spaces.has(a) or not _spaces.has(b):
		return []
	var small_id: String = a if _spaces[a].size() <= _spaces[b].size() else b
	var large_id: String = b if small_id == a else a
	var small: Dictionary = _spaces[small_id]
	var large: Dictionary = _spaces[large_id]
	var out: Array = []
	for h in small.keys():
		if large.has(h):
			out.append(h)
	return out


## The rebate, measured: total distinct facts minus what one space
## would have stored alone, summed over the intersection. What the
## geometry SAVED by folding two spaces together.
func rebate(a: String, b: String) -> int:
	return intersection(a, b).size()


## All spaces that intersect `space_id` (share at least one fact).
func intersecting_spaces(space_id: String) -> Array:
	if not _spaces.has(space_id):
		return []
	var out: Array = []
	for other in _spaces.keys():
		if other != space_id and not intersection(space_id, other).is_empty():
			out.append(other)
	return out


# ------------------------------------------------------------------
# Stress control (the bounded working set)
# ------------------------------------------------------------------

## Is this fact's cell hot? Cold facts stay in _cells (the shape
## remembers); only the working-set claim is bounded.
func is_hot(content_hash: String) -> bool:
	return _hot.has(content_hash)


func evictions() -> int:
	return _evictions


## Drop a space's CLAIMS, not the shared facts: an intersecting space
## leaving must never erase state another space still claims (the
## rebate cuts both ways -- removal is also intersection-aware).
func release_space(space_id: String) -> int:
	if not _spaces.has(space_id):
		return 0
	var orphans: Array = []
	for h in _spaces[space_id].keys():
		var still_claimed := false
		for other in _spaces.keys():
			if other != space_id and _spaces[other].has(h):
				still_claimed = true
				break
		if not still_claimed:
			orphans.append(h)
	var count: int = orphans.size()
	# Each orphan hash is dropped once (audit round 17: the old loop
	# iterated fact_cells(h) but deleted h per cell, leaking the hot
	# entry when a fact had zero indexed cells).
	for h in orphans:
		_hot.delete(h)
		_cells.erase(h)
		_cell_index.erase(h)
	_spaces.erase(space_id)
	return count
