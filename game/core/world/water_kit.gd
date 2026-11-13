## WaterKit -- the ONE localized-water builder (labs/prd-clipmap.md 11a:
## "props everywhere"; the render twin of OceanService).
##
## The swim PHYSICS is already one shared call: declare an `OceanVolume`
## (data/oceans/*.tres) and a body ticks through `OceanService.tick_swimmer`
## -- state, depth, band, current, breath, pressure, drowning, burn -- on any
## globe, in any instance. The RENDER was the part rebuilt by hand at every
## site: the underworld cistern disc, the lava lake melt, the moon crater
## shell. This kit is the render twin: given an `OceanVolume` and a seat, it
## builds the visible water body (a translucent / emissive disc at the
## declared surface) so a new pool, lake, or dish is a declaration + ONE call,
## never a bespoke mesh.
##
## Geometry class: RADIAL water (the moon crater's ocean cap, the main-world
## rivers) is the clipmap's own standing-water sheet -- a sphere-fitting surface
## clipped at the shore. This kit is for LOCALIZED discs: a dish of water at a
## point (the OceanVolume `floor_is_radial = false` local-pool model), where
## the clipmap's per-direction table cannot represent the body.
##
## Fairness law (mirrors InstancePropKit): the kit draws PAINT only -- never a
## collider. The swim law reads the OceanVolume; a second collision truth here
## would be a second law (the cistern/lake law: "no collider on the water").
##
## Tabs, no class_name (instantiated by path, the InstancePropKit pattern).
extends RefCounted

## Build one localized water disc from a volume declaration. `water_center` is
## the disc's world-space center (the caller projects the declared
## `surface_height` into its own frame); `up` is the dish normal; `radius` the
## disc reach. `style` carries the look (see DEFAULT look keys). Returns the
## MeshInstance3D (its material cached for a caller's per-frame emission rider),
## or null when a radius/center is unusable.
##
## style keys (all optional):
##   name            String    node name (default "WaterDisc")
##   radius          float     top/bottom radius (default: given radius)
##   height          float     disc thickness (default 0.3)
##   y_offset        float     sink along `up` from water_center (default 0)
##   albedo          Color     base colour (default a cool sea blue)
##   roughness       float     (default 0.15)
##   metallic        float     (default 0.0)
##   alpha           float     < 1.0 turns on alpha transparency (default 1.0)
##   emission        Color     emission colour (default: none)
##   emission_energy float     emission multiplier (default 1.0)
##   cast_shadow     bool      (default false -- water casts no shadow here)
func build_pool(parent: Node3D, water_center: Vector3, up: Vector3,
		radius: float, style: Dictionary = {}) -> MeshInstance3D:
	if parent == null or radius <= 0.0:
		return null
	var u: Vector3 = up.normalized() if up.length_squared() > 0.000001 else Vector3.UP
	var r: float = float(style.get("radius", radius))
	var h: float = float(style.get("height", 0.3))
	var mi := MeshInstance3D.new()
	mi.name = str(style.get("name", "WaterDisc"))
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = h
	mi.mesh = cyl
	mi.position = water_center + u * float(style.get("y_offset", 0.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(style.get("cast_shadow", false)) \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	var alpha: float = float(style.get("alpha", 1.0))
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(style.get("albedo", Color(0.35, 0.40, 0.50)), alpha)
	else:
		mat.albedo_color = style.get("albedo", Color(0.35, 0.40, 0.50))
	mat.roughness = float(style.get("roughness", 0.15))
	mat.metallic = float(style.get("metallic", 0.0))
	if style.has("emission"):
		mat.emission_enabled = true
		mat.emission = style.get("emission")
		mat.emission_energy_multiplier = float(style.get("emission_energy", 1.0))
	cyl.material = mat
	# Lay the disc flat in the dish plane (its local +Y points along `up`).
	var hint := Vector3(0, 1, 0)
	if absf(u.dot(hint)) > 0.999:
		hint = Vector3(0, 0, -1)
	var east: Vector3 = (hint - u * hint.dot(u)).normalized()
	var north: Vector3 = east.cross(u)
	mi.basis = Basis(east, u, north)
	parent.add_child(mi)
	return mi


## Convenience: build the disc for an `OceanVolume` declaration, reading its
## reach (`floor_radius`) and surface. `center_xz` is the dish's horizontal
## seat; the water plane sits at the volume's declared `surface_height` (the
## local-pool model). `style` overrides the look (the kit defaults fill the
## rest). This is the "declare a volume -> one call" seam.
func build_from_volume(parent: Node3D, volume, center_xz: Vector3,
		style: Dictionary = {}) -> MeshInstance3D:
	if volume == null or not ("floor_radius" in volume):
		return null
	var radius: float = float(volume.floor_radius)
	var water_center := Vector3(center_xz.x, float(volume.surface_height), center_xz.z)
	return build_pool(parent, water_center, Vector3.UP, radius, style)
