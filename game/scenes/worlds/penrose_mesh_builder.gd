## PenroseMeshBuilder — the game-side renderer feed (the caller's move
## the frame primitive deliberately leaves open).
##
## pentagrid.gd is pure data (no Node, no scene tree). This is the
## game-side adapter that takes its triangle_soup / soup_to_mesh_arrays
## output and produces REAL ArrayMeshes ready for a MeshInstance3D:
##   * two fat/thin surfaces (colorable per rhombus kind),
##   * optional gnomonic projection onto the planet sphere,
##   * one call to get a scene-ready mesh; the caller adds the node.
##
## Tests: game/tests/probe_penrose_mesh.gd. Docs: labs/
## world-building-research.md sec 1.9 (raster seam row).
extends RefCounted
class_name PenroseMeshBuilder

const PentagridScript = preload("res://core/frame/math/pentagrid.gd")

## Color budget: fat/thin base colors (renderer may override via
## material); delivered as vertex COLOR data so a plain spatial
## material with vertex-color-use renders immediately.
const FAT_COLOR := Color(0.72, 0.56, 0.24)   # brass-sun
const THIN_COLOR := Color(0.36, 0.44, 0.62)  # slate-moon


## Build a scene-ready ArrayMesh from a pentagrid patch: two surfaces
## (fat, then thin) each as a full ARRAY_MAX dict with positions +
## per-vertex colors + normals (flat +Z / sphere normal when
## projected). Returns the ArrayMesh itself — the CALLER wraps it in
## a MeshInstance3D wherever it wants.
##
## planar=true: tiles in tiling coordinates (z = height), flat shading.
## planar=false: tiles projected to the planet sphere through the
## tangent plane at (center_lat, center_lon) — per-patch gnomonic, use
## only within the chart cap (pentagrid.patch_cap_deg).
static func build_mesh(patch: Array, planar: bool = true, scale: float = 1.0,
		center_lat: float = 0.0, center_lon: float = 0.0,
		radius: float = 20000.0) -> ArrayMesh:
	var fat := _surface_arrays(patch, PentagridScript.TileKind.FAT, planar, scale, center_lat, center_lon, radius)
	var thin := _surface_arrays(patch, PentagridScript.TileKind.THIN, planar, scale, center_lat, center_lon, radius)
	var mesh := ArrayMesh.new()
	if not (fat[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fat)
	if not (thin[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, thin)
	return mesh


## One kind-filtered surface: positions, colors, normals; full
## ARRAY_MAX shape for add_surface_from_arrays.
static func _surface_arrays(patch: Array, kind: int, planar: bool, scale: float,
		center_lat: float, center_lon: float, radius: float) -> Array:
	var positions := PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var normals := PackedVector3Array()
	var base: Color = FAT_COLOR if kind == PentagridScript.TileKind.FAT else THIN_COLOR
	for t in patch:
		if t.kind != kind:
			continue
		if planar:
			var v: Array[Vector2] = t.verts
			for idx in [0, 1, 2]:
				positions.append(Vector3(v[idx].x * scale, v[idx].y * scale, 0.0))
			for idx in [0, 2, 3]:
				positions.append(Vector3(v[idx].x * scale, v[idx].y * scale, 0.0))
			for _i in range(6):
				colors.append(base)
				normals.append(Vector3(0, 0, 1))
		else:
			# Sphere projection: split the projected quad along the
			# same diagonal triangle_soup uses (0-1-2, 0-2-3); the
			# per-vertex normal is the normalized sphere point (the
			# gnomonic map is conformal at the tangent point).
			var pts := PackedVector3Array()
			for v2 in t.verts:
				pts.append(PentagridScript.gnomonic_project(v2, center_lat, center_lon, radius))
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for idx in tri:
					positions.append(pts[idx])
					normals.append(pts[idx].normalized())
					colors.append(base)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	return arrays


## Convenience: a MeshInstance3D on the built mesh (name-tagged); the
## caller chooses the parent. Material optional — the mesh carries
## vertex colors, a material with vertex_color_use=true shows them.
static func build_instance(patch: Array, mesh_name: String = "penrose_patch",
		planar: bool = true, scale: float = 1.0,
		center_lat: float = 0.0, center_lon: float = 0.0,
		radius: float = 20000.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = build_mesh(patch, planar, scale, center_lat, center_lon, radius)
	return mi
