## GMIndicator - Floating star indicator above GM players
## Add this as a child of a PlayerController to show the GM star
class_name GMIndicator
extends Node3D

@export var star_size: float = 0.3
@export var float_height: float = 2.0
@export var bob_speed: float = 2.0
@export var bob_amount: float = 0.1

var _base_y: float
var _time: float = 0.0

func _ready() -> void:
	_base_y = float_height
	
	# Create the star sprite
	var star := Sprite3D.new()
	star.name = "Star"
	star.texture = _create_star_texture()
	star.pixel_size = 0.01
	star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	star.modulate = Color(1.0, 0.84, 0.0)  # Gold color
	star.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	add_child(star)
	
	# Create a glow effect (larger, semi-transparent)
	var glow := Sprite3D.new()
	glow.name = "Glow"
	glow.texture = _create_star_texture()
	glow.pixel_size = 0.015
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glow.modulate = Color(1.0, 0.84, 0.0, 0.3)  # Semi-transparent gold
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.scale = Vector3(1.5, 1.5, 1.5)
	add_child(glow)
	
	# Rotate to face up (toward camera)
	rotation_degrees.x = -90  # Face upward

func _create_star_texture() -> ImageTexture:
	# Create a simple star shape
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	
	# Fill with transparent
	for y in size:
		for x in size:
			image.set_pixel(x, y, Color(0, 0, 0, 0))
	
	# Draw a simple 5-pointed star
	var cx := size / 2.0
	var cy := size / 2.0
	var outer_r := size * 0.45
	var inner_r := size * 0.2
	var points := 5
	
	for i in range(points * 2):
		var angle := PI * 2.0 * float(i) / float(points * 2) - PI / 2.0
		var r := outer_r if i % 2 == 0 else inner_r
		var px := cx + r * cos(angle)
		var py := cy + r * sin(angle)
		
		# Draw line to this point
		var prev_i := i - 1 if i > 0 else (points * 2 - 1)
		var prev_angle := PI * 2.0 * float(prev_i) / float(points * 2) - PI / 2.0
		var prev_r := outer_r if prev_i % 2 == 0 else inner_r
		var ppx := cx + prev_r * cos(prev_angle)
		var ppy := cy + prev_r * sin(prev_angle)
		
		# Simple line drawing
		var steps := int(max(abs(px - ppx), abs(py - ppy))) * 2
		for s in range(steps):
			var t := float(s) / float(steps)
			var lx := int(ppx + (px - ppx) * t)
			var ly := int(ppy + (py - ppy) * t)
			if lx >= 0 and lx < size and ly >= 0 and ly < size:
				# Golden color with soft edge
				var dist: float = sqrt(pow(lx - cx, 2) + pow(ly - cy, 2))
				var alpha: float = clamp(1.0 - (dist - inner_r) / (outer_r - inner_r), 0.0, 1.0)
				image.set_pixel(lx, ly, Color(1.0, 0.84, 0.0, alpha))
	
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	return texture

func _process(delta: float) -> void:
	_time += delta
	
	# Bob up and down
	var new_y: float = _base_y + sin(_time * bob_speed) * bob_amount
	position.y = lerpf(position.y, new_y, 0.1)
	
	# Slow rotation
	rotation_degrees.y += delta * 30.0
