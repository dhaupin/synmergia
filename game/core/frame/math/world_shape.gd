## World shape parameter (world-building.md sec 1.6: "map shape is a
## parameter, not a hardcoded choice"). Reads the project setting
## synmergia/world/shape ("planar" | "spherical"); defaults PLANAR.
## Frame primitive: no autoload, no GameManager dependency.
extends RefCounted

class_name WorldShape

enum Shape {
	PLANAR,
	SPHERICAL,
}

const SETTINGS_KEY: String = "synmergia/world/shape"


## Resolve the configured world shape. Unknown values fall back to
## PLANAR (the pre-spherical behavior); never throws.
static func resolve() -> int:
	var raw: String = str(ProjectSettings.get_setting(SETTINGS_KEY, "planar")).to_lower()
	if raw == "spherical":
		return Shape.SPHERICAL
	return Shape.PLANAR


static func is_spherical() -> bool:
	return resolve() == Shape.SPHERICAL
