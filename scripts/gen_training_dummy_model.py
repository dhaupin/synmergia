# Synmergia procedural model generator: training dummy.
#
# A static straw practice target: a wooden cross-base, an upright post,
# a burlap-wrapped barrel torso bound with rope bands, a horizontal
# arm peg (the classic melee dummy crossbar), and a rounded head. No
# rig and no animations -- the dummy never moves, so the mesh is
# exported flat (export_animations=False, one direct glTF write).
#
# Palette: pale straw yellow (burlap), wood brown (post + base),
# rope tan (bindings).
#
# Usage:
#   blender --background --factory-startup --python scripts/gen_training_dummy_model.py
#
# Deterministic: no rng anywhere; same input -> same .glb geometry.

import bpy
import math
import os

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Final artifact lands IN THE REPO (filename == EnemyData id, the model
# registry per prd-3d-pipeline.md).
OUT = os.path.join(_REPO_ROOT, "game", "models", "enemies", "enemy_training_dummy.glb")

# Palette.
COL_STRAW = (0.78, 0.68, 0.36, 1.0)   # burlap wrap, pale straw yellow
COL_WOOD = (0.40, 0.26, 0.13, 1.0)    # post + base, wood brown
COL_ROPE = (0.66, 0.52, 0.28, 1.0)    # rope bindings, tan


def mat(name, color, rough=0.85, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


def box(name, size, loc, material, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0] / 2.0, size[1] / 2.0, size[2] / 2.0)
    o.data.materials.append(material)
    return o


def cyl(name, r, depth, loc, rot=(0, 0, 0), verts=10, material=None):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, rotation=rot, vertices=verts)
    o = bpy.context.active_object
    o.name = name
    if material:
        o.data.materials.append(material)
    return o


def sph(name, r, loc, material, segments=12, ring_count=8):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=segments, ring_count=ring_count)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(material)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def torus(name, major_r, minor_r, depth, loc, material, major_seg=12, minor_seg=6):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_r, minor_radius=minor_r,
        major_segments=major_seg, minor_segments=minor_seg,
        location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = (1.0, 1.0, depth)
    o.data.materials.append(material)
    return o


def build():
    parts = []

    # Ground base: a squat wooden block the post stands on.
    parts.append(cyl("base", 0.42, 0.16, (0.0, 0.0, 0.08), verts=16, material=MAT_WOOD))

    # Upright post carrying the body.
    parts.append(cyl("post", 0.09, 1.15, (0.0, 0.0, 0.575), verts=10, material=MAT_WOOD))

    # Burlap barrel torso: a wide cylinder resting above the base.
    parts.append(cyl("torso", 0.30, 0.72, (0.0, 0.0, 0.95), verts=16, material=MAT_STRAW))

    # Rope bands binding the wrap: two tan rings around the torso.
    parts.append(torus("rope_low", 0.305, 0.035, 1.0, (0.0, 0.0, 0.72), MAT_ROPE))
    parts.append(torus("rope_high", 0.305, 0.035, 1.0, (0.0, 0.0, 1.16), MAT_ROPE))

    # Crossbar arms: one horizontal wooden peg through the shoulders.
    parts.append(cyl("arm", 0.055, 1.05, (0.0, 0.0, 1.16),
                     rot=(0.0, math.pi / 2.0, 0.0), verts=8, material=MAT_WOOD))

    # Rounded head on top of the post, straw-wrapped like the body.
    parts.append(sph("head", 0.20, (0.0, 0.0, 1.52), MAT_STRAW, segments=14, ring_count=10))

    return parts


def main():
    # Factory reset FIRST (materials created before this line get wiped).
    bpy.ops.wm.read_factory_settings(use_empty=True)

    global MAT_STRAW, MAT_WOOD, MAT_ROPE
    MAT_STRAW = mat("m_straw", COL_STRAW, rough=0.9)
    MAT_WOOD = mat("m_wood", COL_WOOD, rough=0.8)
    MAT_ROPE = mat("m_rope", COL_ROPE, rough=0.95)

    parts = build()

    # Join every primitive into one mesh so the export is a single
    # MeshInstance3D (no rig, no skeleton, no clips).
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    root = bpy.context.active_object
    root.name = "enemy_training_dummy"

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format="GLB",
        export_yup=True,
        export_animations=False,
        export_apply=True,
        export_skins=False,
        export_morph=False,
        export_current_frame=False,
    )

    print("GEN_TRAINING_DUMMY_DONE -> " + OUT)


main()
