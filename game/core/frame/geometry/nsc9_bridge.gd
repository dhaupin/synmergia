## NSC-9 -> SpatialFragmenter -> T3 Integration Bridge
##
## Connects the three frame primitives into a unified pipeline:
##   NSC-9 spatial code (9-AAA-BBB-CCCCCC)
##       -> SpatialFragmenter address (octree, 64-bit)
##          -> T3 content-hash tree (deterministic state storage)
##
## Pure functions: no state, no autoload, no GameManager dependency.
##
## Usage:
##   var bridge := Nsc9Bridge.new()
##   var address := bridge.nsc9_to_address(nsc_code)
##   var hash := bridge.store_nsc9_state(t3, nsc_code, state_dict)
##   var results := bridge.query_nsc9_vertex(t3, nsc_code)
##
## See labs/prd-geometry.md sec. 6K for the wiring pattern spec.
extends RefCounted

const Nsc9Script = preload("res://core/frame/math/nsc9.gd")
const SpatialFragmenterScript = preload("res://core/frame/geometry/spatial_fragmenter.gd")

const MAX_COORD: int = 0xFFFF


## Convert an NSC-9 code into a SpatialFragmenter address.
##
## NSC-9 components map to spatial coords as:
##   facility   -> x coordinate (0-999, fits in 16 bits)
##   axis       -> vertex via SpatialFragmenter.nsc9_code_to_vertex (1-12 -> 0-11)
##   sequence   -> split into y (bits 10-19, 0-1023) and z (bits 0-9, 0-1023)
##   depth      -> subdivision depth (caller-specified, default 0)
##
## Hot path: uses bitwise unpack() instead of string parsing.
## Returns 0 if the code is invalid or axis is not spatial.
## Returns a SpatialFragmenter address on success.
func nsc9_to_address(code: int, depth: int = 0, sf: Variant = null) -> int:
	if code < 0:
		return 0
	if sf == null:
		sf = SpatialFragmenterScript.new()

	var vertex: int = sf.nsc9_code_to_vertex(code)
	if vertex < 0:
		return 0

	var nsc9: Variant = Nsc9Script.new()
	var components: Dictionary = nsc9.unpack(code)
	var facility: int = components.get("facility", 0)
	var sequence: int = components.get("sequence", 0)

	var x: int = facility & MAX_COORD
	var y: int = ((sequence >> 10) & 0x3FF) & MAX_COORD
	var z: int = (sequence & 0x3FF) & MAX_COORD
	depth = clampi(depth, 0, SpatialFragmenterScript.MAX_DEPTH)

	return sf.make_address(x, y, z, depth, vertex)


## Convert a SpatialFragmenter address to a T3 path string.
## Example: "spatial/0001-0002-0003-d0-v4"
func address_to_t3_path(address: int, sf: Variant = null) -> String:
	if sf == null:
		sf = SpatialFragmenterScript.new()
	return sf.path_for_address(address)


## Convert an NSC-9 code directly to a T3 path.
## Example: "spatial/0001-0000-0000-d0-v0"
func nsc9_to_t3_path(code: int, depth: int = 0) -> String:
	var address: int = nsc9_to_address(code, depth)
	if address == 0:
		return ""
	return address_to_t3_path(address)


## Query spatial fragments in an NSC-9-derived region (vertex + depth).
## Returns fragments within the bounding box of the NSC-9 address.
func query_nsc9_region(t3: Variant, nsc9_code: int, depth: int = 0) -> Array[Dictionary]:
	if t3 == null:
		return []
	var address: int = nsc9_to_address(nsc9_code, depth)
	if address == 0:
		return []
	var sf: Variant = SpatialFragmenterScript.new()
	var path: String = sf.path_for_address(address)
	return sf.query_spatial_tree(t3, path)


## Store NSC-9-indexed entity state in the T3 substrate.
## Returns the T3 node hash, or empty PackedByteArray if t3 is null or code is invalid.
func store_nsc9_state(t3: Variant, nsc9_code: int, state: Dictionary, depth: int = 0, metadata: Dictionary = {}) -> PackedByteArray:
	if t3 == null:
		return PackedByteArray()
	var address: int = nsc9_to_address(nsc9_code, depth)
	if address == 0:
		return PackedByteArray()
	var sf: Variant = SpatialFragmenterScript.new()
	var path: String = sf.path_for_address(address)
	return sf.store_fragment_in_t3(t3, path, address, metadata)


## Store NSC-9 spatial state AND fragment it with the data Fragmenter for
## distributed storage. Each fragment is stored under a sub-path.
## Returns the root fragment hash, or empty if t3/fragmenter is null.
func store_nsc9_fragmented(t3: Variant, nsc9_code: int, state: Dictionary, fragmenter: Variant, depth: int = 0) -> PackedByteArray:
	if t3 == null or fragmenter == null:
		return PackedByteArray()
	var address: int = nsc9_to_address(nsc9_code, depth)
	if address == 0:
		return PackedByteArray()
	var sf: Variant = SpatialFragmenterScript.new()
	var path: String = sf.path_for_address(address)

	var fragments: Array = fragmenter.fragment(state, 5)
	if fragments.is_empty():
		return PackedByteArray()

	var root_hash: PackedByteArray = PackedByteArray()
	for i in range(fragments.size()):
		var frag_path: String = "%s/frag_%d" % [path, i]
		var frag: Dictionary = fragments[i]
		var frag_metadata: Dictionary = {
			"fragment_index": i,
			"total_fragments": fragments.size(),
			"checksum": frag.get("checksum", 0),
			"size": frag.get("size", 0),
			"data": frag.get("data", ""),
			"nsc9_code": nsc9_code,
			"address": address
		}
		var frag_hash: PackedByteArray = sf.store_fragment_in_t3(t3, frag_path, address, frag_metadata)
		if frag_hash.size() > 0:
			root_hash = frag_hash
	return root_hash


## Restore fragmented NSC-9 state from T3.
## Returns the reconstructed state dictionary, or empty Dictionary if not found.
func restore_nsc9_fragmented(t3: Variant, nsc9_code: int, fragmenter: Variant, depth: int = 0) -> Dictionary:
	if t3 == null or fragmenter == null:
		return {}
	var address: int = nsc9_to_address(nsc9_code, depth)
	if address == 0:
		return {}
	var sf: Variant = SpatialFragmenterScript.new()
	var path: String = sf.path_for_address(address)
	var results: Array[Dictionary] = sf.query_spatial_tree(t3, path)
	if results.is_empty():
		return {}

	# Rebuild the fragment dictionaries the Fragmenter.weld() contract expects:
	# each entry needs shard index, data (PackedByteArray), and checksum. The
	# store path persists whole metadata dicts, so recover the original fragment
	# fields from them instead of passing raw data blobs.
	var fragment_data: Array = []
	for result in results:
		var metadata: Dictionary = result.get("metadata", {})
		if metadata.is_empty() or not metadata.has("data"):
			continue
		fragment_data.append({
			shard = metadata.get("fragment_index", fragment_data.size()),
			data = metadata.get("data"),
			checksum = metadata.get("checksum", 0)
		})
	if fragment_data.is_empty():
		return {}
	var welded: String = fragmenter.weld(fragment_data)
	if welded == "":
		return {}
	var parsed: Variant = JSON.parse_string(welded)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


## Query all spatial fragments stored under a given NSC-9 vertex code.
## Returns Array[Dictionary] with path, hash, address, metadata for each fragment.
func query_nsc9_vertex(t3: Variant, nsc9_code: int) -> Array[Dictionary]:
	if t3 == null:
		return []
	var sf: Variant = SpatialFragmenterScript.new()
	var vertex: int = sf.nsc9_code_to_vertex(nsc9_code)
	if vertex < 0:
		return []
	var results: Array[Dictionary] = sf.query_spatial_tree(t3, "/")
	var filtered: Array[Dictionary] = []
	for result in results:
		if result.get("vertex") == vertex:
			filtered.append(result)
	return filtered


## Check if an NSC-9 code has a valid spatial axis mapping (axis 1-12).
func is_spatial_nsc9(code: int) -> bool:
	var sf: Variant = SpatialFragmenterScript.new()
	return sf.nsc9_code_to_vertex(code) >= 0


## Derive an NSC-9 vertex from an NSC-9 entity-spatial encoding.
## Wraps Nsc9.pack_entity_spatial() -> SpatialFragmenter vertex.
## Hot path: uses bitwise pack() instead of decimal format.
func entity_spatial_to_vertex(facility: int, vertex: int) -> int:
	var nsc9: Variant = Nsc9Script.new()
	var code: int = nsc9.pack_entity_spatial(facility, vertex)
	var sf: Variant = SpatialFragmenterScript.new()
	return sf.nsc9_code_to_vertex(code)
