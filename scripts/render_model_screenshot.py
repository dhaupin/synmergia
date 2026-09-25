# Render a screenshot of a generated Synmergia model.
#
# Opens the generator's build pipeline, poses the model, adds a simple
# light rig + camera, and renders a PNG for the repo (docs/PRD previews).
#
# Usage:
#   blender --background --factory-startup --python scripts/render_model_screenshot.py -- [out.png]
#
# Default output: art/screenshots/npc_blacksmith_village.png

import bpy
import math
import os
import sys

OUT_DEFAULT = "art/screenshots/npc_blacksmith_village.png"


def _parse_out():
    argv = sys.argv
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
        if rest:
            return rest[0]
    return OUT_DEFAULT


def _mat(name, color, rough=0.85, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


def main():
    out_path = _parse_out()

    # Build the model using the generator's own pipeline (single source
    # of truth for the look). Import it as a module-level exec: the
    # generator is a flat script, so exec its build section in globals.
    gen_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "gen_blacksmith_model.py")
    src = open(gen_path, encoding="utf-8").read()
    # Strip its export() call site; we only want build_body/build_rig/etc.
    src = src.split("parts = build_body()")[0]
    exec(compile(src, gen_path, "exec"), globals())

    global MAT_SOOT, MAT_APRON, MAT_SKIN, MAT_IRON, MAT_COPPER, MAT_CLOTH
    MAT_SOOT = _mat("m_soot", COL_SOOT)
    MAT_APRON = _mat("m_apron", COL_APRON, rough=0.95)
    MAT_SKIN = _mat("m_skin", COL_SKIN, rough=0.7)
    MAT_IRON = _mat("m_iron", COL_IRON, rough=0.45, metal=0.8)
    MAT_COPPER = _mat("m_copper", COL_COPPER, rough=0.35, metal=0.9)
    MAT_CLOTH = _mat("m_cloth", COL_CLOTH, rough=0.95)

    parts = build_body()
    arm = build_rig()
    pose_arm(arm)
    assign_weights(parts, arm)

    # Pose: relaxed smithy stance (reuse the rig's rest pose; it is the
    # bind pose applied by pose_arm).

    # Ground + light + camera.
    bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.name = "ground"
    gm = _mat("m_ground", (0.18, 0.16, 0.13, 1.0), rough=1.0)
    ground.data.materials.append(gm)

    bpy.ops.object.light_add(type="SUN", location=(3, -4, 6))
    sun = bpy.context.active_object
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(35))

    bpy.ops.object.light_add(type="AREA", location=(-2.5, -3, 2.5))
    fill = bpy.context.active_object
    fill.data.energy = 120
    fill.data.size = 3
    fill.rotation_euler = (math.radians(65), 0, math.radians(-45))

    bpy.ops.object.camera_add(location=(1.4, -2.6, 1.5))
    cam = bpy.context.active_object
    cam.rotation_euler = (math.radians(72), 0, math.radians(28))
    cam.data.lens = 60
    bpy.context.scene.camera = cam

    # Render settings. NOTE: must be CYCLES on CPU -- EEVEE/Workbench
    # need an OpenGL display context and die with "Unable to open a
    # display" in headless sandboxes.
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 64
    sc.cycles.use_denoising = False
    sc.render.resolution_x = 1280
    sc.render.resolution_y = 960
    sc.render.image_settings.file_format = "PNG"
    sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.09, 0.10, 0.13, 1.0)
    bg.inputs[1].default_value = 1.0

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    sc.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    print("SCREENSHOT_OUT=" + os.path.abspath(out_path))


main()
