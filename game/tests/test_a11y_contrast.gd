## WCAG contrast audit of the UIStyles palettes (PRD round 4).
## Verifies the text pairs the UI actually renders on its panels:
## 4.5:1 for normal text (WCAG 2.x AA 1.4.3) and 3.0:1 for the status
## indicators treated as graphical objects (1.4.11 non-text contrast).
## The HIGH_CONTRAST palette's "WCAG 4.5:1 compliant" comment is a
## CLAIM here -- the test computes the ratios, it does not trust them.
## Run: godot --headless --path game --script res://tests/test_a11y_contrast.gd
extends SceneTree

const UIStylesScript = preload("res://ui/components/ui_styles.gd")

func _init() -> void:
	var ok := true
	print("=== WCAG contrast audit: UIStyles palettes ===")
	ok = _audit_default() and ok
	ok = _audit_high_contrast() and ok
	print("A11yContrast: passed" if ok else "A11yContrast: FAILED")
	quit(0 if ok else 1)

## WCAG 2.x relative luminance (sRGB channel -> linear).
func _linear(c: float) -> float:
	if c <= 0.04045:
		return c / 12.92
	return pow((c + 0.055) / 1.055, 2.4)

func _luminance(col: Color) -> float:
	return 0.2126 * _linear(col.r) + 0.7152 * _linear(col.g) + 0.0722 * _linear(col.b)

func _ratio(fg: Color, bg: Color) -> float:
	var lf := _luminance(fg)
	var lb := _luminance(bg)
	var hi: float = max(lf, lb)
	var lo: float = min(lf, lb)
	return (hi + 0.05) / (lo + 0.05)

## pairs: [[fg, bg, label], ...]. Prints every ratio so the audit is a record.
func _check(pairs: Array, threshold: float, tag: String) -> bool:
	var ok := true
	for p in pairs:
		var fg: Color = p[0]
		var bg: Color = p[1]
		var label: String = p[2]
		var r := _ratio(fg, bg)
		var meets := r >= threshold
		if not meets:
			ok = false
		print("%s %-36s %.2f:1 %s (need %.1f)" % [tag, label, r, "PASS" if meets else "FAIL", threshold])
	return ok

func _audit_default() -> bool:
	var c: Dictionary = UIStylesScript.COLORS
	var bg: Color = c.background
	var bgd: Color = c.background_dark
	var fbg: Color = c.focus_bg
	var pairs := [
		[c.text_primary, bg, "text_primary on background"],
		[c.text_primary, bgd, "text_primary on background_dark"],
		[c.text_primary, fbg, "text_primary on focus_bg"],
		[c.text_secondary, bg, "text_secondary on background"],
		[c.text_secondary, bgd, "text_secondary on background_dark"],
		[c.text_secondary, fbg, "text_secondary on focus_bg"],
		[c.accent_gold, bg, "accent_gold on background"],
		[c.success, bg, "success on background"],
		[c.error, bg, "error on background"],
		[c.info, bg, "info on background"],
		[c.warning, bg, "warning on background"],
		[c.text_disabled, bg, "text_disabled on background"],
		# The CTA pair as rendered by apply_cta_button: near-black text
		# on the mint fill (ui_styles.gd font_color override).
		[Color(0.05, 0.12, 0.09), c.accent_green, "cta_text on accent_green"],
	]
	var ok := _check(pairs, 4.5, "default")
	# Status indicators/dots are graphical objects: WCAG 1.4.11 wants 3.0.
	var indicators := [
		[c.online, bg, "online on background"],
		[c.offline, bg, "offline on background"],
		[c.border, bg, "border on background"],
	]
	ok = _check(indicators, 3.0, "graph") and ok
	return ok

func _audit_high_contrast() -> bool:
	var c: Dictionary = UIStylesScript.HIGH_CONTRAST_COLORS
	var pairs := [
		[c.text_primary, c.background, "text_primary on background"],
		[c.text_secondary, c.background, "text_secondary on background"],
		[c.text_disabled, c.background, "text_disabled on background"],
		[c.text_secondary, c.focus_bg, "text_secondary on focus_bg"],
	]
	return _check(pairs, 4.5, "highcon")
