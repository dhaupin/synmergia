## SeaBar - the sea-state chip (S14.7.3, the swim book's HUD leg).
##
## Sits under HudLayer (name: SeaBar) next to HordeBar/StormBar: while
## the local body is WET (globe_player's _sea_wet book) it tells the
## truth about the water that body is obeying -- the band (SURFACE
## SWIM / SUBMERGED / SQUEEZE / CRUSH), the BREATH bar (seconds left of
## the capacity the breather declares), the deposit pool (the depth
## tax the sea is accruing), and a DROWNING flash when the breath hits
## zero. Dry bodies never see it (the bar hides itself).
##
## Wire-only: polls the local body's swim book every 0.15 s (a
## published-numbers read, the same posture the HUD keeps for the
## wallet), so tests can drive it bare with update_from_body().
## ASCII copy only; the DAMAGE is the body's own law -- this only
## tells the truth about it.
extends Control

const POLL_S: float = 0.15

var _title_label: Label
var _band_label: Label
var _breath_bar: ProgressBar
var _breath_label: Label
var _pressure_label: Label

var _poll_t: float = 0.0
var _drown_flash: bool = false

func _ready() -> void:
	_setup_ui()
	visible = false

## ---------------------------------------------------------------------------
## Driving
## ---------------------------------------------------------------------------

## The local body's own numbers (globe_player's swim book); slot in a
## bare body variant for tests/helpers. body null == dry.
## THE DUCK READ: Object.get() is one-arg, so the two-arg dictionary
## form is out for body properties -- this helper answers "is it in
## the book, and what", once, for every read below.
func _v_s(body: Node, prop: String, default_v: Variant = null) -> Variant:
	if prop in body:
		return body.get(prop)
	return default_v


func update_from_body(body: Node) -> void:
	if _title_label == null:
		return
	if body == null or not is_instance_valid(body) or not bool(_v_s(body, "_sea_wet", false)):
		visible = false
		return
	var band: int = int(_v_s(body, "_sea_band", 0))
	var names: Array = ["DRY", "WADING", "SUBMERGED", "SQUEEZE", "CRUSH"]
	var band_name: String = str(names[mini(band, names.size() - 1)])
	if band == 2 and float(_v_s(body, "_sea_depth", 99.0)) <= 2.2:
		band_name = "SURFACE SWIM"  # the top-meter breath law (the hand at the surface)
	_title_label.text = "THE SEA HOLDS YOU"
	_band_label.text = band_name
	_band_label.modulate = Color(0.55, 0.83, 0.9)
	var bmax: float = maxf(float(_v_s(body, "_sea_breath_max", 45.0)), 1.0)
	var breath_s: float = maxf(float(_v_s(body, "_sea_breath_s", 0.0)), 0.0)
	var br: float = clampf(breath_s / bmax, 0.0, 1.0)
	_breath_bar.max_value = 1.0
	_breath_bar.value = br
	_breath_label.text = "Breath %d:%02d" % [int(breath_s) / 60, int(breath_s) % 60]
	_drown_flash = float(_v_s(body, "_sea_drowning_s", 0.0)) > 0.0
	if _drown_flash:
		_breath_label.text = "DROWNING - surface now"
		_breath_label.modulate = Color(1.0, 0.35, 0.3)
	else:
		_breath_label.modulate = Color(0.85, 0.9, 0.85)
	var pres: float = float(_v_s(body, "_sea_pressure", 0.0))
	if pres > 0.05:
		_pressure_label.text = "Pressure %.1f" % pres
		_pressure_label.modulate = Color(1.0, 0.72, 0.5)
	else:
		_pressure_label.text = ""
	visible = true

## -------------------------------------------------------------
## Poll heartbeat: read the local body's book on the timer.
## -------------------------------------------------------------

func _process(delta: float) -> void:
	_poll_t -= delta
	if _poll_t > 0.0:
		return
	_poll_t = POLL_S
	var pm = Engine.get_main_loop().root.get_node_or_null(NodePath("PlayerManager")) \
		if Engine.get_main_loop() is SceneTree else null
	if pm == null:
		visible = false
		return
	var body = pm.get("local_player")
	update_from_body(body if body != null and is_instance_valid(body) else null)

## ---------------------------------------------------------------------------
## UI (the StormBar dialect: PanelContainer core + labels + bar)
## ---------------------------------------------------------------------------

func _setup_ui() -> void:
	# THE SEAM: right of the horde bar's slot (top-center), under the
	# storm chip -- a swimmer looks at their breath, not the weather.
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	custom_minimum_size = Vector2(300, 88)
	position = Vector2(-150, 192)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_title_label)

	_band_label = Label.new()
	_band_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_band_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_band_label)

	_breath_bar = ProgressBar.new()
	_breath_bar.min_value = 0.0
	_breath_bar.max_value = 1.0
	_breath_bar.show_percentage = false
	vbox.add_child(_breath_bar)

	_breath_label = Label.new()
	_breath_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_breath_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_breath_label)

	_pressure_label = Label.new()
	_pressure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pressure_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_pressure_label)
