## LootDropVisual - floating 3D marker over a ground loot drop.
##
## A small rotating coin mesh plus a billboard label listing the items
## colored by rarity, so drops read at a glance in the world:
##   Sword of Truth x1
##   Health Potion x3
extends Node3D

const ITEM = preload("res://core/schemas/item.gd")

## Rarity -> label color (matches the game's rarity palette).
const RARITY_COLORS: Array = [
	Color(0.8, 0.8, 0.8),   # COMMON    gray
	Color(0.4, 1.0, 0.4),   # UNCOMMON  green
	Color(0.35, 0.6, 1.0),  # RARE      blue
	Color(0.7, 0.4, 1.0),   # EPIC      purple
	Color(1.0, 0.65, 0.2),  # LEGENDARY orange
	Color(1.0, 0.3, 0.35),  # MYTHIC    red
]

const ROTATE_SPEED: float = 1.6          # radians/sec spin
const BOB_AMPLITUDE: float = 0.12        # meters of vertical bob
const BOB_SPEED: float = 2.2             # bob cycles per second

var _coin: MeshInstance3D
var _label: Label3D
var _beam: MeshInstance3D
var _time: float = 0.0
var _base_y: float = 0.0


func _ready() -> void:
	_base_y = position.y
	_build_coin()
	_build_beam()
	_build_label()


func _process(delta: float) -> void:
	_time += delta
	if _coin != null:
		_coin.rotate_y(ROTATE_SPEED * delta)
		_coin.position.y = _base_y + 0.55 + sin(_time * BOB_SPEED) * BOB_AMPLITUDE
	if _beam != null and _beam.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = _beam.material_override
		mat.emission_energy_multiplier = 0.9 + 0.35 * sin(_time * 3.0)


## Populate from a GroundLootService drop dict.
func setup(drop: Dictionary) -> void:
	var items: Array = drop.get("items", [])
	var currency: Dictionary = drop.get("currency", {})

	var lines: PackedStringArray = PackedStringArray()
	var best_rarity: int = 0
	for item in items:
		if item == null:
			continue
		var display_name := "Item"
		var quantity := 1
		var rarity := 0
		if item is Item:
			display_name = str(item.display_name)
			rarity = int(item.rarity)
			if "stack_size" in item and int(item.stack_size) > 1:
				quantity = int(item.stack_size)
		elif item is Dictionary:
			display_name = str(item.get("display_name", item.get("item_id", "Item")))
			quantity = int(item.get("quantity", 1))
			rarity = int(item.get("rarity", 0))
		lines.append("%s x%d" % [display_name, quantity])
		best_rarity = max(best_rarity, rarity)

	var gold := 0
	for coin_id in currency:
		gold += int(currency[coin_id])
	if gold > 0:
		lines.append("%d gold" % gold)

	if _label != null:
		_label.text = "\n".join(lines)
	var tint: Color = RARITY_COLORS[best_rarity] if best_rarity < RARITY_COLORS.size() else RARITY_COLORS[0]
	if _label != null:
		_label.modulate = tint
	if _coin != null and _coin.material_override is StandardMaterial3D:
		(_coin.material_override as StandardMaterial3D).emission = tint
	if _beam != null and _beam.material_override is StandardMaterial3D:
		(_beam.material_override as StandardMaterial3D).emission = Color(tint.r, tint.g, tint.b, 0.25)


func _build_coin() -> void:
	_coin = MeshInstance3D.new()
	_coin.name = "Coin"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.22
	mesh.bottom_radius = 0.22
	mesh.height = 0.06
	_coin.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.3)
	mat.emission_energy_multiplier = 1.2
	mat.albedo_color = Color(0.9, 0.75, 0.3)
	_coin.material_override = mat
	_coin.position = Vector3(0, 0.55, 0)
	add_child(_coin)


func _build_beam() -> void:
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.45
	mesh.height = 2.2
	_beam.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.3, 0.25)
	mat.emission_energy_multiplier = 1.0
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.06)
	_beam.material_override = mat
	_beam.position = Vector3(0, 1.1, 0)
	add_child(_beam)


func _build_label() -> void:
	_label = Label3D.new()
	_label.name = "ItemsLabel"
	_label.text = ""
	_label.font_size = 40
	_label.pixel_size = 0.005
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.outline_size = 8
	_label.outline_modulate = Color(0, 0, 0, 0.9)
	_label.position = Vector3(0, 1.7, 0)
	add_child(_label)
