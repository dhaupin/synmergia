## SurfacePad -- a terrain-conforming ground collider for conjured globes
## (the globe_world surface-pad law, shared by the underworld and the moon).
##
## A globe's base sphere collider is a perfect ball, but the clipmap draws
## the provider's displaced terrain, so a body on the sphere sinks into the
## drawn hills and floats over the dips. This re-anchors a small curved disc
## under the body every physics frame, baking the provider's WALK height at
## every vertex -- collision and the drawn ground are then the same law, by
## construction. Local coordinates stay <= PAD_RADIUS (physics wants SMALL
## shapes); only the transform and the baked shape change.
##
## Tabs, no class_name; instantiated by path.
extends RefCounted

const PAD_RADIUS: float = 64.0
const PAD_SEGMENTS: int = 16
const PAD_RINGS: int = 8

var _body: StaticBody3D = null
var _shape: ConcavePolygonShape3D = null
var _planet_radius: float = 100.0
var _provider = null
var _lift: float = 0.0
var _built_dir: Vector3 = Vector3.ZERO


## Build the pad under `parent`, reading walk heights from `provider`. `lift`
## is the renderer's draw lift (the pad origin rides planet_radius + lift +
## the centre's terrain, so vertex local +Y is relative to that origin).
func build(parent: Node3D, provider, planet_radius: float, lift: float) -> void:
        _provider = provider
        _planet_radius = planet_radius
        _lift = lift
        var body := StaticBody3D.new()
        body.name = "SurfacePad"
        body.physics_material_override = PhysicsMaterial.new()
        body.physics_material_override.friction = 1.0
        body.physics_material_override.bounce = 0.0
        var col := CollisionShape3D.new()
        var shape := ConcavePolygonShape3D.new()
        shape.backface_collision = true
        col.shape = shape
        body.add_child(col)
        parent.add_child(body)
        _body = body
        _shape = shape


## Re-anchor under `body_pos` (world) around `center` (the planet centre) and
## re-bake the shape when the body has moved a few metres.
func update(body_pos: Vector3, center: Vector3) -> void:
        if _body == null or _provider == null:
                return
        var dir: Vector3 = (body_pos - center).normalized()
        var lift_here: float = _lift + float(_provider.ground_height(dir))
        _body.position = center + dir * (_planet_radius + lift_here)
        var north: Vector3 = Vector3(0, 1, 0)
        if absf(dir.dot(north)) > 0.999:
                north = Vector3(0, 0, -1)
        north = (north - dir * north.dot(dir)).normalized()
        var east: Vector3 = north.cross(dir)
        var basis := Basis(east, dir, -north)
        _body.basis = basis
        var rebuild: bool = _built_dir == Vector3.ZERO \
                        or dir.angle_to(_built_dir) * _planet_radius > 3.0
        if not rebuild:
                return
        _built_dir = dir
        var terrain_center: float = float(_provider.ground_height(dir))
        var faces: PackedVector3Array = _terrain_faces(dir, basis)
        var i := 0
        while i < faces.size():
                faces[i].y -= terrain_center
                i += 1
        _shape.set_faces(faces)


func _terrain_faces(dir: Vector3, basis: Basis) -> PackedVector3Array:
        var faces: PackedVector3Array = PackedVector3Array()
        var cols: int = PAD_SEGMENTS
        var h_center: float = float(_provider.walk_height(dir))
        var center_v := Vector3(0.0, h_center, 0.0)
        var rings: Array = []
        for r in range(1, PAD_RINGS + 1):
                var d: float = PAD_RADIUS * float(r) / float(PAD_RINGS)
                var sag: float = _planet_radius - sqrt(maxf(_planet_radius * _planet_radius - d * d, 0.0))
                var ring: PackedVector3Array = PackedVector3Array()
                for i in range(cols):
                        var a: float = TAU * float(i) / float(cols)
                        var lx: float = cos(a) * d
                        var lz: float = sin(a) * d
                        var wdir: Vector3 = (dir * _planet_radius + basis * Vector3(lx, 0.0, lz)).normalized()
                        var h: float = float(_provider.walk_height(wdir))
                        ring.append(Vector3(lx, h - sag, lz))
                rings.append(ring)
        var first: PackedVector3Array = rings[0]
        for i in range(cols):
                var j: int = (i + 1) % cols
                faces.append(center_v)
                faces.append(first[i])
                faces.append(first[j])
        for r in range(1, PAD_RINGS):
                var inner: PackedVector3Array = rings[r - 1]
                var outer: PackedVector3Array = rings[r]
                for i in range(cols):
                        var j: int = (i + 1) % cols
                        faces.append(inner[i])
                        faces.append(outer[i])
                        faces.append(outer[j])
                        faces.append(inner[i])
                        faces.append(outer[j])
                        faces.append(inner[j])
        return faces
