# Render screenshots of generated Synmergia models.
#
# Reuses each generator's own build pipeline (single source of truth
# for the look), adds a light rig + camera, and renders PNGs for the
# repo (art/screenshots/). Cycles on CPU: EEVEE/Workbench need a
# display and die with "Unable to open a display" headless.
#
# Usage:
#   blender --background --factory-startup --python scripts/render_model_screenshot.py -- [model] [out.png]
#   model: blacksmith (default) | wolf
#
# Defaults:
#   blacksmith -> art/screenshots/npc_blacksmith_village.png
#   wolf       -> art/screenshots/enemy_wolf.png

import bpy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def _parse_args():
    argv = sys.argv
    rest = []
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
    model = rest[0] if rest else "blacksmith"
    out = rest[1] if len(rest) > 1 else {
        "blacksmith": "art/screenshots/npc_blacksmith_village.png",
        "wolf": "art/screenshots/enemy_wolf.png",
    }.get(model, "art/screenshots/%s.png" % model)
    return model, out


def _load_generator_globals(model):
    """Exec the generator's build section (everything before the build
    call site) so this script reuses the exact same body/rig/materials
    definitions -- single source of truth for the look."""
    gen_name = {
        "blacksmith": "gen_blacksmith_model.py",
        "wolf": "gen_wolf_model.py",
    }[model]
    gen_path = os.path.join(HERE, gen_name)
    src = open(gen_path, encoding="utf-8").read()
    src = src.split("parts = build_body()")[0]
    exec(compile(src, gen_path, "exec"), globals())


def _build_materials(model):
    global MAT_COAT, MAT_BELLY, MAT_DARK, MAT_EYE, MAT_NOSE
    if model == "blacksmith":
        global MAT_SOOT, MAT_APRON, MAT_SKIN, MAT_IRON, MAT_COPPER, MAT_CLOTH
        MAT_SOOT = _mat("m_soot", COL_SOOT)
        MAT_APRON = _mat("m_apron", COL_APRON, rough=0.95)
        MAT_SKIN = _mat("m_skin", COL_SKIN, rough=0.7)
        MAT_IRON = _mat("m_iron", COL_IRON, rough=0.45, metal=0.8)
        MAT_COPPER = _mat("m_copper", COL_COPPER, rough=0.35, metal=0.9)
        MAT_CLOTH = _mat("m_cloth", COL_CLOTH, rough=0.95)
    else:
        MAT_COAT = _mat("m_coat", COL_COAT)
        MAT_BELLY = _mat("m_belly", COL_BELLY, rough=0.95)
        MAT_DARK = _mat("m_dark", COL_DARK, rough=0.95)
        MAT_EYE = _mat("m_eye", COL_EYE, rough=0.3)
        MAT_NOSE = _mat("m_nose", COL_NOSE, rough=0.6)


def _mat(name, color, rough=0.85, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


def _stage(distance, height, lens=60):
    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0))
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

    bpy.ops.object.camera_add(location=(distance * 0.45, -distance, height))
    cam = bpy.context.active_object
    cam.rotation_euler = (math.radians(72), 0, math.radians(28))
    cam.data.lens = lens
    bpy.context.scene.camera = cam


def _render(out_path):
    sc = bpy.context.scene
    # NOTE: must be CYCLES on CPU -- EEVEE/Workbench need an OpenGL
    # display context and die headless.
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
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    sc.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    print("SCREENSHOT_OUT=" + os.path.abspath(out_path))


def main():
    model, out_path = _parse_args()
    _load_generator_globals(model)
    _build_materials(model)

    if model == "blacksmith":
        parts = build_body()
        arm = build_rig()
        pose_arm(arm)
        assign_weights(parts, arm)
        _stage(2.8, 1.5)
    else:
        # Wolf is long and low: wider framing, camera slightly lower.
        parts = build_body()
        arm = build_rig()
        pose_arm(arm)
        assign_weights(parts, arm)
        _stage(3.4, 1.1, lens=50)

    _render(out_path)


main()
