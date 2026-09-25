# Synmergia procedural model generator: quadruped wolf.
#
# Exercises the Movement Design System's QUADRUPED class end-to-end:
# a four-legged rig (spine chain + 4 legs), a real trot cycle
# (diagonal pairs alternate), and the shared export pipeline
# (model_export_lib: export-once-per-clip + stdlib merge + NLA slots).
#
# Usage:
#   blender --background --factory-startup --python scripts/gen_wolf_model.py
#
# Deterministic: no rng anywhere; same input -> same .glb geometry.

import bpy
import math
import os
import sys

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(_REPO_ROOT, "scripts"))
import model_export_lib

OUT = os.path.join(_REPO_ROOT, "game", "models", "enemies", "enemy_wolf.glb")
RIG = "rig_wolf"

# Palette: storm-grey coat, pale underbelly, dark muzzle/paws, amber eyes.
COL_COAT = (0.28, 0.27, 0.28, 1.0)
COL_BELLY = (0.52, 0.50, 0.47, 1.0)
COL_DARK = (0.10, 0.095, 0.09, 1.0)
COL_EYE = (0.85, 0.55, 0.15, 1.0)
COL_NOSE = (0.06, 0.06, 0.065, 1.0)


def mat(name, color, rough=0.9, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


def box(name, size, loc, material):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0] / 2.0, size[1] / 2.0, size[2] / 2.0)
    o.data.materials.append(material)
    return o


def sph(name, r, loc, material, segments=10, ring_count=6):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=segments, ring_count=ring_count)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(material)
    return o


def add_mod(obj, mod_type, **kw):
    m = obj.modifiers.new(kw.get("name", mod_type), mod_type)
    for k, v in kw.items():
        if k != "name" and hasattr(m, k):
            setattr(m, k, v)
    return m


def parent_keep(ob, par):
    mw = ob.matrix_world.copy()
    ob.parent = par
    ob.matrix_world = mw


def build_body():
    parts = []

    # Torso: lean barrel, angled down toward the shoulders (wolf
    # silhouette: high shoulders, low hips, tucked belly).
    parts.append(box("chest", (0.42, 0.44, 0.42), (0, 0, 0.78), MAT_COAT))
    parts.append(box("belly", (0.36, 0.40, 0.30), (0, 0, 0.58), MAT_BELLY))
    parts.append(box("rump", (0.36, 0.40, 0.36), (0, 0, 0.70), MAT_COAT))
    # Neck: thick, low and forward.
    parts.append(box("neck_fur", (0.20, 0.30, 0.26), (0, 0, 0.86), MAT_COAT))
    parts.append(box("neck", (0.16, 0.22, 0.20), (0, -0.14, 0.80), MAT_COAT))
    # Head: wedge muzzle, upright ears, dark nose.
    parts.append(box("skull", (0.20, 0.24, 0.20), (0, -0.32, 0.82), MAT_COAT))
    parts.append(box("muzzle", (0.12, 0.18, 0.12), (0, -0.48, 0.76), MAT_COAT))
    parts.append(sph("nose", 0.035, (0, -0.57, 0.76), MAT_NOSE, segments=8, ring_count=6))
    parts.append(box("jaw", (0.10, 0.16, 0.05), (0, -0.46, 0.68), MAT_DARK))
    parts.append(box("ear_l", (0.05, 0.08, 0.12), (-0.07, -0.28, 0.97), MAT_COAT))
    parts.append(box("ear_r", (0.05, 0.08, 0.12), (0.07, -0.28, 0.97), MAT_COAT))
    parts.append(box("eye_l", (0.04, 0.04, 0.04), (-0.09, -0.40, 0.86), MAT_EYE))
    parts.append(box("eye_r", (0.04, 0.04, 0.04), (0.09, -0.40, 0.86), MAT_EYE))
    # Tail: bushy, held low.
    parts.append(box("tail", (0.10, 0.34, 0.10), (0, 0.28, 0.72), MAT_DARK))
    # Legs: upper + lower pairs; paws dark. Four legs = quadruped.
    leg_specs = (
        ("leg_fl", "leg_fl_lower", "paw_fl", -0.16, -0.16, MAT_COAT),
        ("leg_fr", "leg_fr_lower", "paw_fr", 0.16, -0.16, MAT_COAT),
        ("leg_bl", "leg_bl_lower", "paw_bl", -0.16, 0.18, MAT_COAT),
        ("leg_br", "leg_br_lower", "paw_br", 0.16, 0.18, MAT_COAT),
    )
    for upper, lower, paw, lx, ly, m in leg_specs:
        parts.append(box(upper, (0.10, 0.12, 0.30), (lx, ly, 0.42), m))
        parts.append(box(lower, (0.08, 0.10, 0.28), (lx, ly, 0.15), m))
        parts.append(box(paw, (0.11, 0.14, 0.10), (lx, ly - 0.02, 0.05), MAT_DARK))
    # Mane ruff along the spine.
    parts.append(box("ruff", (0.30, 0.16, 0.10), (0, -0.06, 0.98), MAT_DARK))

    for p in parts:
        add_mod(p, "EDGE_SPLIT", split_angle=0.5)
    return parts


def build_rig():
    bpy.ops.object.armature_add(radius=0.1, location=(0, 0, 0))
    arm = bpy.context.active_object
    arm.name = RIG
    bpy.ops.object.mode_set(mode="EDIT")

    eb = arm.data.edit_bones

    def bone(name, head, tail, par=None):
        b = eb.new(name)
        b.head = head
        b.tail = tail
        if par:
            b.parent = eb[par]
        return b

    # Chain: root -> spine -> chest -> neck -> head. Four leg chains
    # hang off spine (back) and chest (front): the quadruped layout.
    bone("root", (0, 0, 0), (0, 0.01, 0))
    bone("spine", (0, 0.10, 0.70), (0, -0.06, 0.72), "root")
    bone("chest", (0, -0.06, 0.72), (0, -0.22, 0.78), "spine")
    bone("neck", (0, -0.22, 0.80), (0, -0.34, 0.82), "chest")
    bone("head", (0, -0.34, 0.84), (0, -0.50, 0.80), "neck")
    # Legs: hip/shoulder -> stifle/elbow -> paw. Two-bone chains keep
    # the trot cycle simple (upper swings, lower follows with drag).
    bone("thigh_bl", (-0.16, 0.18, 0.58), (-0.16, 0.18, 0.28), "spine")
    bone("shin_bl", (-0.16, 0.18, 0.28), (-0.16, 0.18, 0.06), "thigh_bl")
    bone("thigh_br", (0.16, 0.18, 0.58), (0.16, 0.18, 0.28), "spine")
    bone("shin_br", (0.16, 0.18, 0.28), (0.16, 0.18, 0.06), "thigh_br")
    bone("thigh_fl", (-0.16, -0.16, 0.58), (-0.16, -0.16, 0.28), "chest")
    bone("shin_fl", (-0.16, -0.16, 0.28), (-0.16, -0.16, 0.06), "thigh_fl")
    bone("thigh_fr", (0.16, -0.16, 0.58), (0.16, -0.16, 0.28), "chest")
    bone("shin_fr", (0.16, -0.16, 0.28), (0.16, -0.16, 0.06), "thigh_fr")
    bone("tail_b", (0, 0.26, 0.74), (0, 0.40, 0.72), "spine")

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def assign_weights(parts, arm):
    # Explicit vertex groups (same rationale as the blacksmith: no
    # auto-weight smear between adjacent boxes on low-poly bodies).
    groups = {
        "chest": ["chest"], "belly": ["spine", "chest"], "rump": ["spine"],
        "neck_fur": ["neck"], "neck": ["neck"], "skull": ["head"],
        "muzzle": ["head"], "nose": ["head"], "jaw": ["head"],
        "ear_l": ["head"], "ear_r": ["head"], "eye_l": ["head"], "eye_r": ["head"],
        "tail": ["tail_b"], "ruff": ["chest"],
        "leg_fl": ["thigh_fl"], "leg_fl_lower": ["shin_fl"], "paw_fl": ["shin_fl"],
        "leg_fr": ["thigh_fr"], "leg_fr_lower": ["shin_fr"], "paw_fr": ["shin_fr"],
        "leg_bl": ["thigh_bl"], "leg_bl_lower": ["shin_bl"], "paw_bl": ["shin_bl"],
        "leg_br": ["thigh_br"], "leg_br_lower": ["shin_br"], "paw_br": ["shin_br"],
    }
    for p in parts:
        for gname in groups.get(p.name, ["root"]):
            g = p.vertex_groups.new(name=gname)
            g.add(list(range(len(p.data.vertices))), 1.0, "REPLACE")
        parent_keep(p, arm)
        mod = p.modifiers.new("Armature", "ARMATURE")
        mod.object = arm


def pose_arm(arm):
    # Rest pose = relaxed stand. Everything zeroed stays zero; the
    # trot keys provide the motion.
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="OBJECT")


def animate(arm):
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")

    # --- idle: breathing + ear twitch + tail sway (48f) ---
    idle = model_export_lib.make_action(arm, "idle")
    model_export_lib.key_quat(arm, "spine", [(1, (0, 0, 0)), (24, (0.015, 0, 0)), (48, (0, 0, 0))])
    model_export_lib.key_quat(arm, "chest", [(1, (0, 0, 0)), (24, (-0.015, 0, 0)), (48, (0, 0, 0))])
    model_export_lib.key_quat(arm, "tail_b", [(1, (0, 0, 0.2)), (24, (0, 0, -0.2)), (48, (0, 0, 0.2))])
    model_export_lib.key_quat(arm, "head", [
        (1, (0, 0, 0)), (12, (0, 0, 0.06)), (18, (0, 0, 0)), (30, (0, -0.05, 0)), (48, (0, 0, 0))])

    # --- walk: 32f TROT cycle at 30fps. Diagonal pairs move together
    #     (front-left + back-right, then front-right + back-left) --
    #     the defining quadruped gait. Phases sampled at meaningful
    #     sine points (0, pi/2, pi, 3pi/2, 2pi) -- the zero-crossing
    #     keying mistake from the blacksmith's first walk attempt.
    walk = model_export_lib.make_action(arm, "walk")
    swing = 0.6
    phases = ((1, 0.0), (9, math.pi / 2), (17, math.pi), (25, 3 * math.pi / 2), (32, 2 * math.pi))

    def cycle(phase_offset):
        return [(f, (swing * math.sin(p + phase_offset), 0, 0)) for f, p in phases]

    model_export_lib.key_quat(arm, "thigh_fl", cycle(0.0))          # diagonal pair A
    model_export_lib.key_quat(arm, "thigh_br", cycle(0.0))
    model_export_lib.key_quat(arm, "thigh_fr", cycle(math.pi))      # diagonal pair B
    model_export_lib.key_quat(arm, "thigh_bl", cycle(math.pi))
    model_export_lib.key_quat(arm, "shin_fl", [(f, (max(0.0, -0.7 * math.sin(p + 0.6)), 0, 0)) for f, p in phases])
    model_export_lib.key_quat(arm, "shin_fr", [(f, (max(0.0, 0.7 * math.sin(p + 0.6)), 0, 0)) for f, p in phases])
    model_export_lib.key_quat(arm, "shin_bl", [(f, (max(0.0, 0.7 * math.sin(p + 0.6)), 0, 0)) for f, p in phases])
    model_export_lib.key_quat(arm, "shin_br", [(f, (max(0.0, -0.7 * math.sin(p + 0.6)), 0, 0)) for f, p in phases])
    model_export_lib.key_quat(arm, "spine", [(f, (0, 0, 0.03 * math.sin(p))) for f, p in phases])
    model_export_lib.key_quat(arm, "head", [(f, (0, 0, 0.02 * math.sin(p + math.pi))) for f, p in phases])

    for a in (idle, walk):
        a.use_fake_user = True
    arm.animation_data.action = walk

    bpy.ops.object.mode_set(mode="OBJECT")


# --- build ---
# Factory reset FIRST (materials before this line get wiped --
# "StructRNA of type Material has been removed").
bpy.ops.wm.read_factory_settings(use_empty=True)

MAT_COAT = mat("m_coat", COL_COAT)
MAT_BELLY = mat("m_belly", COL_BELLY, rough=0.95)
MAT_DARK = mat("m_dark", COL_DARK, rough=0.95)
MAT_EYE = mat("m_eye", COL_EYE, rough=0.3)
MAT_NOSE = mat("m_nose", COL_NOSE, rough=0.6)

parts = build_body()
arm = build_rig()
pose_arm(arm)
assign_weights(parts, arm)
animate(arm)
model_export_lib.export_model(
    RIG, OUT, ["idle", "walk"],
    {"idle": 0.0, "walk": 1.6},  # same slot layout as the blacksmith (48f + 32f @ 30fps)
    base_out="/tmp/synmergia_models/_wolf_base.glb",
    clip_dir="/tmp/synmergia_models/_wolf_clips",
)

print("GEN_WOLF_DONE -> " + OUT)
