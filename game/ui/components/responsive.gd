## Responsive - viewport-class helpers for the UI frame (play-test round 9)
##
## One law for every device class (portrait phone, wide-screen phone,
## square tablet, laptop, desktop, high-res): screens ask THIS layer
## for sizes instead of hardcoding pixels. The canvas_items stretch
## maps the design resolution onto the device; these helpers adapt
## CONTENT SIZES to the logical viewport so nothing bleeds or clips.
##
## Godot-native building blocks this complements (the answer to "what
## can we leverage in Godot"):
##   - HFlowContainer / VBoxContainer: children wrap and reflow like
##     flex -- card strips stop bleeding off narrow screens.
##   - CenterContainer + anchors presets: centering without frozen
##     offset math.
##   - root.content_scale_factor: the one true UI-zoom lever (canvas_items
##     stretch) -- settings -> UI Scale.
##   - Theme + theme_type_variation: one place for widget looks.
##   - Control.get_viewport_rect(): the logical viewport these helpers read.
##
## No UTF-8, tabs only. (No class_name: it is consumed via preload
## consts, and an unused global registration is exactly the kind of
## shadow risk AGENTS.md warns about.)
extends RefCounted

## Breakpoints in LOGICAL design pixels (the canvas is 1280x720 base
## and letterboxes; a portrait phone shows ~720 wide of logical space).
const NARROW_X: float = 820.0
const COMPACT_X: float = 1100.0


static func viewport() -> Vector2:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return Vector2(1280, 720)
	var tree := ml as SceneTree
	if tree.root == null:
		return Vector2(1280, 720)
	return tree.root.get_visible_rect().size


static func is_narrow() -> bool:
	return viewport().x < NARROW_X


static func is_compact() -> bool:
	return viewport().x < COMPACT_X


## Card minimum width that adapts to the viewport class: full base on
## wide screens, ~half the viewport (two-up) on narrow ones, capped so
## a single card never exceeds the base width. `base_size` is the
## design-time minimum.
static func card_size(base_size: Vector2, two_up_target: float = 2.0) -> Vector2:
	var vp := viewport()
	var w := base_size.x
	if vp.x < NARROW_X:
		w = minf(base_size.x, (vp.x - 48.0) / two_up_target)
	return Vector2(maxf(w, 150.0), base_size.y)


## Panel minimum size clamped to a fraction of the viewport (the
## UIPanel clamp does this at runtime; flow screens can pre-shape with
## this so their first layout is already sane on phones).
static func panel_size(base_size: Vector2, max_frac: float = 0.92) -> Vector2:
	var vp := viewport()
	return Vector2(
		minf(base_size.x, vp.x * max_frac),
		minf(base_size.y, vp.y * max_frac)
	)
