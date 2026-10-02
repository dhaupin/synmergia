## PropCollider - the one-law attachment for world props.
##
## Play-day feedback: "stuff shouldn't be walk-through; make a handler
## we can easily attach to stuff, or that default-attaches in case we
## miss it." This is that handler. Any visual prop (tree, feature,
## building part) gets a StaticBody3D sized from its own meshes, joins
## the "climbable" group (the climb law's grab target), and reports
## its top height so the climb law can cap grabs.
##
## Usage (the two-line attach):
##   PropCollider.attach(tree_node)        # sized from its meshes
##   PropCollider.attach_all(world_root)   # default-wire missed props
##
## Frame rules: the body is added as a CHILD of the prop, so it moves
## and streams with it. Collision layer 2 (world props), never the
## player's layer. Climbable objects also join the "climbable" group.
extends RefCounted
class_name PropCollider

const CLIMBABLE_GROUP := "climbable"

## Attach a collision body to `prop`, sized from its MeshInstance3D
## children (AABB union, prop-local). Returns the StaticBody3D.
## Idempotent: a prop that already carries a PropCollider body is
## returned untouched.

## Named collision bits (round 10): data/physics_layers/ LayerProfile.
## The prop law: props ride the solid layer, block entities, and are
## never seen by other props (mask 0).
const Layers = preload("res://core/schemas/layer_profile.gd")
static func attach(prop: Node3D) -> StaticBody3D:
	if prop == null or not is_instance_valid(prop):
		return null
	var existing := prop.get_node_or_null("PropBody") as StaticBody3D
	if existing != null:
		return existing
	var body := StaticBody3D.new()
	body.name = "PropBody"
	body.collision_layer = Layers.layer_bit("solid")
	body.collision_mask = 0
	body.add_to_group(CLIMBABLE_GROUP)
	var aabb := _union_aabb(prop)
	var col := CollisionShape3D.new()
	if aabb.size.length_squared() > 0.000001:
		var shape := BoxShape3D.new()
		shape.size = aabb.size
		col.shape = shape
		col.position = aabb.get_center()
	else:
		# No meshes found: 1 m stub so the prop is never intangible.
		var shape := BoxShape3D.new()
		shape.size = Vector3.ONE
		col.shape = shape
	body.add_child(col)
	prop.add_child(body)
	return body

## Trunk-only variant for trees: a slim box around the trunk cylinder
## (the prop's own x/z footprint, trunk height tall). The canopy stays
## intangible -- walking under a crown must not hit a ceiling.
static func attach_trunk(tree: Node3D) -> StaticBody3D:
	if tree == null or not is_instance_valid(tree):
		return null
	var existing := tree.get_node_or_null("PropBody") as StaticBody3D
	if existing != null:
		return existing
	var body := StaticBody3D.new()
	body.name = "PropBody"
	body.collision_layer = Layers.layer_bit("solid")
	body.collision_mask = 0
	body.add_to_group(CLIMBABLE_GROUP)
	var trunk := tree.get_node_or_null("*trunk*")
	if trunk == null:
		for child in tree.get_children():
			if child is MeshInstance3D and str(child.name).to_lower().contains("trunk"):
				trunk = child
				break
	var col := CollisionShape3D.new()
	# CYLINDER, not a box: a sphere body slides smoothly around the
	# round trunk (a box corner exhausts move_and_slide's slide budget
	# and wedges the walker -- probe-caught).
	var shape := CylinderShape3D.new()
	if trunk != null:
		var aabb: AABB = (trunk as MeshInstance3D).get_aabb()
		shape.radius = maxf(maxf(aabb.size.x, aabb.size.z) * 0.5, 0.18)
		shape.height = maxf(aabb.size.y, 1.0)
		col.position = aabb.get_center()
	else:
		shape.radius = 0.22
		shape.height = 2.0
		col.position = Vector3(0, 1.0, 0)
	col.shape = shape
	body.add_child(col)
	tree.add_child(body)
	return body

## Default wiring for missed props: attach to every MeshInstance3D
## under `root` that neither IS a prop body's parent nor already has
## one. Designed for after-build sweeps; skips tiny decorative meshes
## (below MIN_VOL m^3) so grass tufts never become walls.
const MIN_VOL := 0.15

static func attach_all(root: Node) -> int:
	var count := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D and node.get_parent() is not StaticBody3D:
			var mi := node as MeshInstance3D
			if mi.get_node_or_null("../PropBody") == null:
				var aabb := mi.get_aabb()
				if aabb.size.x * aabb.size.y * aabb.size.z >= MIN_VOL:
					attach(mi.get_parent() as Node3D)
					count += 1
	return count

## Height of the prop's top surface above its origin (climb cap).
static func top_height(prop: Node3D) -> float:
	if prop == null or not is_instance_valid(prop):
		return 0.0
	var aabb := _union_aabb(prop)
	return aabb.get_center().y + aabb.size.y * 0.5 if aabb.size.length_squared() > 0.000001 else 0.0

## AABB union of all mesh instances under `prop` (including `prop`
## itself when it IS a mesh), in prop-local space.
static func _union_aabb(prop: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [prop]
	while not stack.is_empty():
		var node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			# Mesh AABB transformed into the PROP's space.
			var rel: Transform3D = prop.global_transform.affine_inverse() * mi.global_transform
			var box: AABB = rel * mi.get_aabb()
			if first:
				out = box
				first = false
			else:
				out = out.merge(box)
	return out
