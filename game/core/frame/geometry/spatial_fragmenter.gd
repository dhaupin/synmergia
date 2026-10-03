## Spatial Geometry Fragmenter (v1.0)
## Deterministic sub-cell addressing for icosahedral / NSC-9 spatial state.
##
## Design principles (per architecture review):
## - Pure functions: no state, no side-effects
## - Integer/quantized math only: no floating-point seam cracks
## - Fixed-width 64-bit address encoding: no hash collisions
## - MAX_DEPTH guard: prevents fragment explosion (tree depth runaway)
## - Deterministic: same input -> same output, always
##
## Address bit layout (uint64):
##   Bits 0-15:    X offset (16-bit quantized coordinate)
##   Bits 16-31:  Y offset (16-bit quantized coordinate)
##   Bits 32-47:  Z offset (16-bit quantized coordinate)
##   Bits 48-55:  Depth (8-bit subdivision level, 0-15)
##   Bits 56-63:  Vertex/region type (8-bit icosahedral VERTEX, 0-11)
##
## NAMESPACE NOTE (audit round 17): "face" names TWO different things in
## the spatial layer. IcosahedralFaces (math/icosahedral_faces.gd) works
## in 0..19 TRIANGLES -- the terrain faces. This fragmenter's field is the
## 0..11 icosahedral VERTEX (NSC-9 spatial axis 1-12 maps to vertex 0-11
## via nsc9_axis_to_vertex). Mixing them silently addresses the wrong
## cell, so the field, accessors, and key suffix all say "vertex".
##
## Use: SpatialFragmenter.subdivide(cell_addr) -> Array[child_addr]
##      SpatialFragmenter.get_parent(child_addr) -> parent_addr
##      SpatialFragmenter.find_common_ancestor(Array[addr]) -> ancestor_addr
##
## T3 integration bridge (pure function bridge):
## - No persistence, no autoload, no GameManager dependency.
## - These methods simply bridge SpatialFragmenter addresses into the T3
##   content-hash tree substrate.
##
## See labs/prd-spatial-geometry.md for the full spec.
extends RefCounted

class_name SpatialFragmenter

## MAX_DEPTH is bounded by the ADDRESS LAYOUT, not a wish: x/y/z are
## 16-bit fields, so a subdivision path holds 16 x-bits + 16 y-bits +
## 16 z-bits = 48 bits = 16 levels (3 bits per level). A larger depth
## (the old value was 24) shifts coordinates past bit 15, the mask
## silently drops the overflow, and DISTINCT cells at depth >= 17
## collapse onto the same address (audit round 16: two distinct
## depth-16 parents produced fully-overlapping depth-17 child sets).
const MAX_DEPTH: int = 16
const X_MASK: int = 0xFFFF
const Y_MASK: int = 0xFFFF << 16
const Z_MASK: int = 0xFFFF << 32
const DEPTH_MASK: int = 0xFF << 48
const VERTEX_MASK: int = 0xFF << 56

const X_SHIFT: int = 0
const Y_SHIFT: int = 16
const Z_SHIFT: int = 32
const DEPTH_SHIFT: int = 48
const VERTEX_SHIFT: int = 56


func make_address(x: int, y: int, z: int, depth: int, vertex: int = 0) -> int:
	return (x & X_MASK) | ((y & X_MASK) << Y_SHIFT) | ((z & X_MASK) << Z_SHIFT) | ((depth & 0xFF) << DEPTH_SHIFT) | ((vertex & 0xFF) << VERTEX_SHIFT)


func get_x(address: int) -> int:
	return address & X_MASK


func get_y(address: int) -> int:
	return (address >> Y_SHIFT) & X_MASK


func get_z(address: int) -> int:
	return (address >> Z_SHIFT) & X_MASK


func get_depth(address: int) -> int:
	return (address >> DEPTH_SHIFT) & 0xFF


## The 8-bit vertex/region field (bits 56-63). This is the icosahedral
## VERTEX index 0-11, NOT an IcosahedralFaces triangle (0-19).
func get_vertex(address: int) -> int:
	return (address >> VERTEX_SHIFT) & 0xFF


func subdivide(address: int, depth: int = 1) -> Array[int]:
	if depth <= 0:
		return [address]
	var current_depth: int = get_depth(address)
	if current_depth >= MAX_DEPTH:
		return [address]
	var x: int = get_x(address)
	var y: int = get_y(address)
	var z: int = get_z(address)
	var vertex: int = get_vertex(address)
	var new_depth: int = mini(current_depth + depth, MAX_DEPTH)

	var children: Array[int] = []
	for i in range(8):
		var cx: int = (x << 1) | ((i >> 0) & 1)
		var cy: int = (y << 1) | ((i >> 1) & 1)
		var cz: int = (z << 1) | ((i >> 2) & 1)
		cx &= X_MASK
		cy &= X_MASK
		cz &= X_MASK
		children.append(make_address(cx, cy, cz, new_depth, vertex))
	return children


func get_parent(address: int) -> int:
	var depth: int = get_depth(address)
	if depth <= 0:
		return address
	return make_address(get_x(address) >> 1, get_y(address) >> 1, get_z(address) >> 1, depth - 1, get_vertex(address))


func is_ancestor(ancestor: int, descendant: int) -> bool:
	if ancestor == descendant:
		return true
	if get_vertex(ancestor) != get_vertex(descendant):
		return false
	var anc_depth: int = get_depth(ancestor)
	var desc_depth: int = get_depth(descendant)
	if anc_depth >= desc_depth:
		return false
	var current: int = descendant
	for i in range(desc_depth - anc_depth):
		current = get_parent(current)
		if current == ancestor:
			return true
	return false


func get_bounding_box(address: int) -> Dictionary:
	var x: int = get_x(address)
	var y: int = get_y(address)
	var z: int = get_z(address)
	var depth: int = get_depth(address)
	var vertex: int = get_vertex(address)
	var scale: int = 1 << (MAX_DEPTH - depth) if depth < MAX_DEPTH else 1
	return {
		"min_x": x * scale,
		"min_y": y * scale,
		"min_z": z * scale,
		"max_x": (x + 1) * scale,
		"max_y": (y + 1) * scale,
		"max_z": (z + 1) * scale,
		"depth": depth,
		"vertex": vertex,
	}


func find_common_ancestor(addresses: Array[int]) -> int:
	if addresses.is_empty():
		return 0
	if addresses.size() == 1:
		return addresses[0]

	var vertex: int = get_vertex(addresses[0])
	for addr in addresses:
		if get_vertex(addr) != vertex:
			return 0

	var current: int = addresses[0]
	while current != 0:
		var all_descendants: bool = true
		for addr in addresses:
			if addr != current and not is_ancestor(current, addr):
				all_descendants = false
				break
		if all_descendants:
			return current
		current = get_parent(current)
	return make_address(0, 0, 0, 0, vertex)


func generate_key(address: int) -> String:
	var x: int = get_x(address)
	var y: int = get_y(address)
	var z: int = get_z(address)
	var depth: int = get_depth(address)
	var vertex: int = get_vertex(address)
	return "%04x-%04x-%04x-d%d-v%d" % [x, y, z, depth, vertex]


## T3 integration bridge (pure function bridge):
## - No persistence, no autoload, no GameManager dependency.
## - These methods simply bridge SpatialFragmenter addresses into the T3
##   content-hash tree substrate.


## Stores a spatial fragment in the T3 substrate.
## Returns the T3 node hash, or an empty PackedByteArray if t3 is null.
func store_fragment_in_t3(t3: Variant, path: String, address: int, metadata: Dictionary = {}) -> PackedByteArray:
	if t3 == null:
		return PackedByteArray()

	var x: int = get_x(address)
	var y: int = get_y(address)
	var z: int = get_z(address)
	var depth: int = get_depth(address)
	var vertex: int = get_vertex(address)
	var key: String = generate_key(address)
	var bbox: Dictionary = get_bounding_box(address)

	var value := {
		"address": address,
		"x": x,
		"y": y,
		"z": z,
		"depth": depth,
		"vertex": vertex,
		"key": key,
		"bbox": bbox,
		"metadata": metadata
	}

	return t3.insert(path, value, Resource.new())


## Queries the T3 substrate for spatial fragment nodes under scope_path.
## Returns an Array[Dictionary] with path, hash, address, x, y, z, depth,
## vertex, key, bbox, and metadata for each node.
func query_spatial_tree(t3: Variant, scope_path: String = "/") -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if t3 == null:
		return results

	t3.walk(scope_path, func(node_path: String, node_hash: PackedByteArray, value: Variant) -> void:
		if value is Dictionary:
			results.append({
				"path": node_path,
				"hash": node_hash,
				"address": value.get("address"),
				"x": value.get("x"),
				"y": value.get("y"),
				"z": value.get("z"),
				"depth": value.get("depth"),
				"vertex": value.get("vertex"),
				"key": value.get("key"),
				"bbox": value.get("bbox"),
				"metadata": value.get("metadata")
			})
	)
	return results


## Generates a deterministic T3 path for a spatial fragment address.
## Example: "spatial/0001-0002-0003-d0-v4"
func path_for_address(address: int) -> String:
	var x: int = get_x(address)
	var y: int = get_y(address)
	var z: int = get_z(address)
	var depth: int = get_depth(address)
	var vertex: int = get_vertex(address)
	return "spatial/%04x-%04x-%04x-d%d-v%d" % [x, y, z, depth, vertex]


func nsc9_axis_to_vertex(axis: int) -> int:
	"""
	Map NSC-9 spatial axis to SpatialFragmenter vertex code.

	NSC-9 spatial axis range: 1-12 (from nsc9.gd AXIS_SPATIAL_BASE = 1).
	SpatialFragmenter vertex range: 0-11 (icosahedral vertices).

	:arg axis: NSC-9 spatial axis code (1-12)
	:return: SpatialFragmenter vertex code (0-11), or -1 if out of range
	"""
	if axis < 1 or axis > 12:
		return -1
	return axis - 1


func nsc9_code_to_vertex(code: int) -> int:
	"""
	Map a full NSC-9 code to a SpatialFragmenter vertex code.

	Supports both formats:
	- Decimal (legacy): 9_000_000_000_000 + facility * 1_000_000_000 + axis * 1_000_000 + sequence
	- Packed (hot path): prefix(4) | facility(10) | axis(10) | sequence(24)

	The spatial axis is the BBB/axis component (1-12).
	Only spatial axes 1-12 map to icosahedral vertices 0-11.

	:arg code: Full NSC-9 code integer (decimal or packed)
	:return: SpatialFragmenter vertex code (0-11), or -1 if invalid
	"""
	if code < 0:
		return -1

	var axis: int
	# Format discrimination by bit layout, not magnitude: packed codes carry a
	# 4-bit prefix (value 9) at bits 44-47, so they are always >= 9 << 44.
	# Decimal codes max at ~9.99e12, which is below 1 << 44, so the ranges
	# cannot overlap. The old magnitude heuristic (>= 9e12 => decimal) matched
	# every packed code and extracted garbage axes.
	if code & (0xF << 44):
		# Packed format: axis at bits 24-33 (10 bits)
		axis = (code >> 24) & 0x3FF
	else:
		# Decimal (legacy) format: axis at 1000000 position
		axis = int(code / 1000000) % 1000

	return nsc9_axis_to_vertex(axis)


func to_spatial_address(nsc9_code: int, track: int, date: int, race_number: int, vertex: int = -1) -> int:
	"""
	Build a SpatialFragmenter address from an NSC-9 code and track context.

	NSC-9 code provides the vertex (via axis mapping).
	track/date/race_number provide the x/y/z coordinate context.

	:arg nsc9_code: Full NSC-9 code
	:arg track: Track coordinate (x)
	:arg date: Date coordinate (y)
	:arg race_number: Race number coordinate (z)
	:arg vertex: Override vertex code (default -1 to derive from NSC-9)
	:return: SpatialFragmenter address
	"""
	if vertex < 0:
		vertex = nsc9_code_to_vertex(nsc9_code)
	if vertex < 0:
		return -1

	return make_address(track, date, race_number, 0, vertex)
