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
##   Bits 48-55:  Depth (8-bit subdivision level, 0-255)
##   Bits 56-63:  Face/region type (8-bit, e.g., NSC-9 prefix or icosahedron face)
##
## Use: SpatialFragmenter.subdivide(cell_addr) -> Array[child_addr]
##      SpatialFragmenter.get_parent(child_addr) -> parent_addr
##      SpatialFragmenter.find_common_ancestor(Array[addr]) -> ancestor_addr
##
## See labs/prd-spatial-geometry.md for the full spec.
extends RefCounted

class_name SpatialFragmenter

const MAX_DEPTH: int = 24
const X_MASK: int = 0xFFFF
const Y_MASK: int = 0xFFFF << 16
const Z_MASK: int = 0xFFFF << 32
const DEPTH_MASK: int = 0xFF << 48
const FACE_MASK: int = 0xFF << 56

const X_SHIFT: int = 0
const Y_SHIFT: int = 16
const Z_SHIFT: int = 32
const DEPTH_SHIFT: int = 48
const FACE_SHIFT: int = 56


func make_address(x: int, y: int, z: int, depth: int, face: int = 0) -> int:
	return (x & X_MASK) | ((y & X_MASK) << Y_SHIFT) | ((z & X_MASK) << Z_SHIFT) | ((depth & 0xFF) << DEPTH_SHIFT) | ((face & 0xFF) << FACE_SHIFT)


func get_x(address: int) -> int:
	return address & X_MASK


func get_y(address: int) -> int:
	return (address >> Y_SHIFT) & X_MASK


func get_z(address: int) -> int:
	return (address >> Z_SHIFT) & X_MASK


func get_depth(address: int) -> int:
	return (address >> DEPTH_SHIFT) & 0xFF


func get_face(address: int) -> int:
	return (address >> FACE_SHIFT) & 0xFF


func subdivide(address: int, depth: int = 1) -> Array[int]:
	if depth <= 0:
		return [address]
	var current_depth: int = get_depth(address)
	if current_depth >= MAX_DEPTH:
		return [address]
	var x: int = get_x(address)
	var y: int = get_y(address)
	var z: int = get_z(address)
	var face: int = get_face(address)
	var new_depth: int = mini(current_depth + depth, MAX_DEPTH)

	var children: Array[int] = []
	for i in range(8):
		var cx: int = (x << 1) | ((i >> 0) & 1)
		var cy: int = (y << 1) | ((i >> 1) & 1)
		var cz: int = (z << 1) | ((i >> 2) & 1)
		cx &= X_MASK
		cy &= X_MASK
		cz &= X_MASK
		children.append(make_address(cx, cy, cz, new_depth, face))
	return children


func get_parent(address: int) -> int:
	var depth: int = get_depth(address)
	if depth <= 0:
		return address
	return make_address(get_x(address) >> 1, get_y(address) >> 1, get_z(address) >> 1, depth - 1, get_face(address))


func is_ancestor(ancestor: int, descendant: int) -> bool:
	if ancestor == descendant:
		return true
	if get_face(ancestor) != get_face(descendant):
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
	var face: int = get_face(address)
	var scale: int = 1 << (MAX_DEPTH - depth) if depth < MAX_DEPTH else 1
	return {
		"min_x": x * scale,
		"min_y": y * scale,
		"min_z": z * scale,
		"max_x": (x + 1) * scale,
		"max_y": (y + 1) * scale,
		"max_z": (z + 1) * scale,
		"depth": depth,
		"face": face,
	}


func find_common_ancestor(addresses: Array[int]) -> int:
	if addresses.is_empty():
		return 0
	if addresses.size() == 1:
		return addresses[0]

	var face: int = get_face(addresses[0])
	for addr in addresses:
		if get_face(addr) != face:
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
	return make_address(0, 0, 0, 0, face)


func generate_key(address: int) -> String:
	var x: int = get_x(address)
	var y: int = get_y(address)
	var z: int = get_z(address)
	var depth: int = get_depth(address)
	var face: int = get_face(address)
	return "%04x-%04x-%04x-d%d-f%d" % [x, y, z, depth, face]
