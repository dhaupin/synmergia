# Synmergia procedural model generator: thistle boar.
#
# A low, broad QUADRUPED (same skeleton family as the wolf: spine chain
# + 4 two-bone legs) with a big wedge head, an upturned snout, two
# small upturned tusks, short sturdy legs, and a THISTLE MATTING ridge
# across the shoulders (a base mat plus a strip of purple-green spines).
# Ships an idle + a 32f trot, both through the shared export pipeline
# (model_export_lib: export-once-per-clip + stdlib merge + NLA slots).
#
# Usage:
#   blender --background --factory-startup --python scripts/gen_thistle_boar_model.py
#
# Deterministic: no rng anywhere; same input -> same .glb geometry.

import bpy
import math
import os
import sys

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(_REPO_ROOT, "scripts"))
import model_export_lib

OUT = os.path.join(_REPO_ROOT, "game", "models", "enemies", "enemy_thistle_boar.glb")
RIG = "rig_thistle_boar"

# Palette: dark bristly brown body, a lighter belly, a thistle
# purple-green mat with greener barbs, pale tusks, dark snout/hooves.
COL_BRISTLE = (0.19, 0.13, 0.09, 1.0)
COL_BELLY = (0.30, 0.22, 0.15, 1.0)
COL_THISTLE = (0.30, 0.27, 0.36, 1.0)
COL_BARB = (0.40, 0.46, 0.34, 1.0)
COL_TUSK = (0.88, 0.85, 0.74, 1.0)
COL_DARK = (0.07, 0.06, 0.07, 1.0)
COL_EYE = (0.05, 0.05, 0.06, 1.0)


def patch_gltf_exporter_for_blender4():
    # model_export_lib was written against Blender 3.0.1, whose glTF
    # exporter defaulted to ACTIVE_ACTIONS. Blender 4.x defaults to
    # ACTIONS (writes EVERY action per clip export -> duplicated clips
    # sampled over the wrong frame range) and sets
    # gltf_export_anim_single_armature True (force-includes every
    # armature action regardless of mode). Patch the operator class
    # (the ops attribute is regenerated per access) to restore the
    # single-active-action behaviour and name each clip after the
    # action currently assigned. Same shim the slime generator uses.
    op_cls = bpy.types.EXPORT_SCENE_OT_gltf
    orig_execute = op_cls.execute

    def patched_execute(self, context):
        if self.export_animations:
            self.export_animation_mode = "ACTIVE_ACTIONS"
            self.export_anim_single_armature = False
            clip_name = "Animation"
            for ob in bpy.data.objects:
                ad = getattr(ob, "animation_data", None)
                if ad is not None and ad.action is not None:
                    clip_name = ad.action.name
                    break
            self.export_nla_strips_merged_animation_name = clip_name
        return orig_execute(self, context)

    op_cls.execute = patched_execute


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


def cone(name, r, depth, loc, material, rot=(0, 0, 0), vertices=8):
    bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=0.0, depth=depth, location=loc,
                                    vertices=vertices, rotation=rot)
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

    # Low broad barrel: wide chest + belly, rump behind.
    parts.append(box("body_chest", (0.52, 0.46, 0.42), (0, -0.08, 0.60), MAT_BRISTLE))
    parts.append(box("body_belly", (0.46, 0.44, 0.30), (0, -0.02, 0.40), MAT_BELLY))
    parts.append(box("body_rump", (0.50, 0.42, 0.40), (0, 0.30, 0.58), MAT_BRISTLE))
    # Short thick neck; big wedge head. Mesh part names must NOT collide
    # with bone names ("neck" bone vs this mesh) -- the glTF importer
    # appends "_2" to whichever it meets second, silently renaming the
    # skeleton bone. Hence "neck_mass".
    parts.append(box("neck_mass", (0.30, 0.24, 0.30), (0, -0.34, 0.62), MAT_BRISTLE))
    parts.append(box("skull", (0.30, 0.30, 0.26), (0, -0.56, 0.60), MAT_BRISTLE))
    # Upturned snout: a wedge box plus a raised nose disc (a small cone
    # pointing forward -- UV spheres export nondeterministically in this
    # Blender build, boxes/cones do not, so the boar is sphere-free).
    parts.append(box("snout", (0.24, 0.24, 0.16), (0, -0.80, 0.58), MAT_BRISTLE))
    parts.append(cone("snout_tip", 0.06, 0.10, (0, -0.95, 0.62), MAT_DARK, rot=(math.pi / 2, 0, 0)))
    parts.append(box("jaw", (0.20, 0.20, 0.06), (0, -0.78, 0.48), MAT_DARK))
    # Two small upturned tusks.
    parts.append(cone("tusk_l", 0.032, 0.16, (-0.09, -0.86, 0.52), MAT_TUSK, rot=(0.35, 0, 0.12)))
    parts.append(cone("tusk_r", 0.032, 0.16, (0.09, -0.86, 0.52), MAT_TUSK, rot=(0.35, 0, -0.12)))
    # Ears + eyes.
    parts.append(box("ear_l", (0.06, 0.06, 0.10), (-0.13, -0.46, 0.74), MAT_BRISTLE))
    parts.append(box("ear_r", (0.06, 0.06, 0.10), (0.13, -0.46, 0.74), MAT_BRISTLE))
    parts.append(box("eye_l", (0.045, 0.045, 0.045), (-0.135, -0.66, 0.64), MAT_EYE))
    parts.append(box("eye_r", (0.045, 0.045, 0.045), (0.135, -0.66, 0.64), MAT_EYE))
    # Short tail.
    parts.append(box("tail", (0.07, 0.22, 0.07), (0, 0.44, 0.62), MAT_BRISTLE))

    # Short sturdy legs: upper + lower + hoof, 4 legs = quadruped.
    leg_specs = (
        ("leg_fl", "leg_fl_lower", "hoof_fl", -0.19, -0.26),
        ("leg_fr", "leg_fr_lower", "hoof_fr", 0.19, -0.26),
        ("leg_bl", "leg_bl_lower", "hoof_bl", -0.19, 0.32),
        ("leg_br", "leg_br_lower", "hoof_br", 0.19, 0.32),
    )
    for upper, lower, hoof, lx, ly in leg_specs:
        parts.append(box(upper, (0.15, 0.17, 0.26), (lx, ly, 0.34), MAT_BRISTLE))
        parts.append(box(lower, (0.13, 0.14, 0.22), (lx, ly, 0.14), MAT_BRISTLE))
        parts.append(box(hoof, (0.16, 0.18, 0.10), (lx, ly - 0.01, 0.05), MAT_DARK))

    # Thistle matting across the shoulders: a base mat plus a strip of
    # purple-green spines (deterministic grid -- no rng).
    parts.append(box("thistle_mat", (0.36, 0.62, 0.10), (0, 0.02, 0.82), MAT_THISTLE))
    spine_y = (-0.26, -0.13, 0.0, 0.13, 0.26)
    spine_x = (-0.11, 0.11)
    idx = 0
    for sy in spine_y:
        for sx in spine_x:
            # Deterministic per-index tilt so the ridge reads as barbs.
            lean = 0.10 if (idx % 2 == 0) else -0.10
            parts.append(cone("thistle_spine_%d" % idx, 0.045, 0.18,
                              (sx, sy, 0.90), MAT_BARB, rot=(lean, 0.0, 0.0)))
            idx += 1

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
    # hang off spine (back) and chest (front).
    bone("root", (0, 0, 0), (0, 0.01, 0))
    bone("spine", (0, 0.16, 0.56), (0, -0.06, 0.60), "root")
    bone("chest", (0, -0.06, 0.60), (0, -0.30, 0.62), "spine")
    bone("neck", (0, -0.30, 0.62), (0, -0.46, 0.62), "chest")
    bone("head", (0, -0.46, 0.62), (0, -0.72, 0.58), "neck")
    bone("thigh_bl", (-0.19, 0.32, 0.46), (-0.19, 0.32, 0.24), "spine")
    bone("shin_bl", (-0.19, 0.32, 0.24), (-0.19, 0.32, 0.04), "thigh_bl")
    bone("thigh_br", (0.19, 0.32, 0.46), (0.19, 0.32, 0.24), "spine")
    bone("shin_br", (0.19, 0.32, 0.24), (0.19, 0.32, 0.04), "thigh_br")
    bone("thigh_fl", (-0.19, -0.26, 0.46), (-0.19, -0.26, 0.24), "chest")
    bone("shin_fl", (-0.19, -0.26, 0.24), (-0.19, -0.26, 0.04), "thigh_fl")
    bone("thigh_fr", (0.19, -0.26, 0.46), (0.19, -0.26, 0.24), "chest")
    bone("shin_fr", (0.19, -0.26, 0.24), (0.19, -0.26, 0.04), "thigh_fr")
    bone("tail_b", (0, 0.40, 0.60), (0, 0.52, 0.58), "spine")

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def assign_weights(parts, arm):
    # Explicit vertex groups (no auto-weight smear between adjacent
    # boxes on low-poly bodies). Mesh part names never collide with
    # bone names (leg_* meshes vs thigh_*/shin_* bones), so the
    # importer cannot rename the skeleton.
    groups = {
        "body_chest": ["chest"], "body_belly": ["spine", "chest"], "body_rump": ["spine"],
        "neck_mass": ["neck"], "skull": ["head"], "snout": ["head"],
        "snout_tip": ["head"], "jaw": ["head"],
        "tusk_l": ["head"], "tusk_r": ["head"],
        "ear_l": ["head"], "ear_r": ["head"], "eye_l": ["head"], "eye_r": ["head"],
        "tail": ["tail_b"], "thistle_mat": ["chest"],
        "leg_fl": ["thigh_fl"], "leg_fl_lower": ["shin_fl"], "hoof_fl": ["shin_fl"],
        "leg_fr": ["thigh_fr"], "leg_fr_lower": ["shin_fr"], "hoof_fr": ["shin_fr"],
        "leg_bl": ["thigh_bl"], "leg_bl_lower": ["shin_bl"], "hoof_bl": ["shin_bl"],
        "leg_br": ["thigh_br"], "leg_br_lower": ["shin_br"], "hoof_br": ["shin_br"],
    }
    for p in parts:
        gnames = groups.get(p.name)
        if gnames is None and p.name.startswith("thistle_spine_"):
            gnames = ["chest"]
        if gnames is None:
            gnames = ["root"]
        for gname in gnames:
            g = p.vertex_groups.new(name=gname)
            g.add(list(range(len(p.data.vertices))), 1.0, "REPLACE")
        parent_keep(p, arm)
        mod = p.modifiers.new("Armature", "ARMATURE")
        mod.object = arm


def animate(arm):
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")

    # --- idle: breathing + head bob + tail sway (48f) ---
    idle = model_export_lib.make_action(arm, "idle")
    model_export_lib.key_quat(arm, "spine", [(1, (0, 0, 0)), (24, (0.015, 0, 0)), (48, (0, 0, 0))])
    model_export_lib.key_quat(arm, "chest", [(1, (0, 0, 0)), (24, (-0.015, 0, 0)), (48, (0, 0, 0))])
    model_export_lib.key_quat(arm, "tail_b", [(1, (0, 0, 0.18)), (24, (0, 0, -0.18)), (48, (0, 0, 0.18))])
    model_export_lib.key_quat(arm, "head", [
        (1, (0, 0, 0)), (12, (0.05, 0, 0)), (18, (0, 0, 0)), (30, (-0.04, 0, 0)), (48, (0, 0, 0))])

    # --- walk: 32f TROT cycle at 30fps. Diagonal pairs move together
    #     (front-left + back-right, then front-right + back-left).
    #     Phases sampled at meaningful sine points (0, pi/2, pi,
    #     3pi/2, 2pi) so the cycle loops seamlessly.
    walk = model_export_lib.make_action(arm, "walk")
    swing = 0.55
    phases = ((1, 0.0), (9, math.pi / 2), (17, math.pi), (25, 3 * math.pi / 2), (32, 2 * math.pi))

    def cycle(phase_offset):
        return [(f, (swing * math.sin(p + phase_offset), 0, 0)) for f, p in phases]

    model_export_lib.key_quat(arm, "thigh_fl", cycle(0.0))          # diagonal pair A
    model_export_lib.key_quat(arm, "thigh_br", cycle(0.0))
    model_export_lib.key_quat(arm, "thigh_fr", cycle(math.pi))      # diagonal pair B
    model_export_lib.key_quat(arm, "thigh_bl", cycle(math.pi))
    model_export_lib.key_quat(arm, "shin_fl", [(f, (max(0.0, -0.6 * math.sin(p + 0.6)), 0, 0)) for f, p in phases])
    model_export_lib.key_quat(arm, "shin_fr", [(f, (max(0.0, 0.6 * math.sin(p + 0.6)), 0, 0)) for f, p in phases])
    model_export_lib.key_quat(arm, "shin_bl", [(f, (max(0.0, 0.6 * math.sin(p + 0.6)), 0, 0)) for f, p in phases])
    model_export_lib.key_quat(arm, "shin_br", [(f, (max(0.0, -0.6 * math.sin(p + 0.6)), 0, 0)) for f, p in phases])
    model_export_lib.key_quat(arm, "spine", [(f, (0, 0, 0.03 * math.sin(p))) for f, p in phases])
    model_export_lib.key_quat(arm, "head", [(f, (0, 0, 0.025 * math.sin(p + math.pi))) for f, p in phases])

    for a in (idle, walk):
        a.use_fake_user = True
    arm.animation_data.action = walk

    bpy.ops.object.mode_set(mode="OBJECT")


# --- build ---
# Factory reset FIRST (materials created before this line get wiped).
bpy.ops.wm.read_factory_settings(use_empty=True)

MAT_BRISTLE = mat("m_bristle", COL_BRISTLE, rough=0.95)
MAT_BELLY = mat("m_belly", COL_BELLY, rough=0.95)
MAT_THISTLE = mat("m_thistle", COL_THISTLE, rough=0.7)
MAT_BARB = mat("m_barb", COL_BARB, rough=0.6)
MAT_TUSK = mat("m_tusk", COL_TUSK, rough=0.35)
MAT_DARK = mat("m_dark", COL_DARK, rough=0.6)
MAT_EYE = mat("m_eye", COL_EYE, rough=0.3)

parts = build_body()
arm = build_rig()
assign_weights(parts, arm)
animate(arm)
patch_gltf_exporter_for_blender4()
model_export_lib.export_model(
    RIG, OUT, ["idle", "walk"],
    {"idle": 0.0, "walk": 1.6},  # 48f + 32f @ 30fps, same slot layout as the wolf
    base_out="/tmp/synmergia_models/_thistle_boar_base.glb",
    clip_dir="/tmp/synmergia_models/_thistle_boar_clips",
)

print("GEN_THISTLE_BOAR_DONE -> " + OUT)
