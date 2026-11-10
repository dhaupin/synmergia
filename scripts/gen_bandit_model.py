# Synmergia procedural model generator: bandit.
#
# A lean humanoid outlaw enemy (HitboxProfile hitbox_humanoid): a hooded
# head with the face in shadow, a ragged brown tunic, worn trousers and
# leather boots, and a rusty blade gripped in the right hand. Rides the
# blacksmith's biped meta-rig (spine + 2 arms + 2 legs) and bakes two
# clips through the shared export pipeline (model_export_lib:
# export-once-per-clip + stdlib merge + NLA slots):
#
#   idle  -- breathe + blade-hand micro sway (48f @ 30fps)
#   walk  -- a 32f gait cycle; enemy.gd swaps idle/walk with AI
#            movement, so the bandit strides when it chases.
#
# Usage:
#   blender --background --factory-startup --python scripts/gen_bandit_model.py
#
# Deterministic: no rng anywhere; same input -> same .glb geometry
# (byte-identical within one blender version).

import bpy
import math
import os
import sys
from mathutils import Euler

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Shared export pipeline (export-once-per-clip + merge + NLA slots).
sys.path.insert(0, os.path.join(_REPO_ROOT, "scripts"))
import model_export_lib

# Final artifact lands IN THE REPO (filename == EnemyData file id, the
# model registry per prd-3d-pipeline.md). Intermediates stay in /tmp.
OUT = os.path.join(_REPO_ROOT, "game", "models", "enemies", "enemy_bandit.glb")
RIG = "rig_bandit"

# Palette: muted brown tunic, dirty grey cloth, worn leather, muted
# skin, rusty steel with a little rust-orange bloom.
COL_TUNIC = (0.24, 0.16, 0.10, 1.0)
COL_CLOTH = (0.30, 0.29, 0.27, 1.0)
COL_HOOD = (0.15, 0.13, 0.11, 1.0)
COL_LEATHER = (0.13, 0.10, 0.08, 1.0)
COL_TROUSER = (0.19, 0.17, 0.15, 1.0)
COL_SKIN = (0.52, 0.36, 0.25, 1.0)
COL_STEEL = (0.34, 0.32, 0.30, 1.0)
COL_RUST = (0.48, 0.24, 0.09, 1.0)
COL_SHADOW = (0.045, 0.04, 0.04, 1.0)


def patch_gltf_exporter_for_blender4():
    # model_export_lib was written against Blender 3.0.1, whose glTF
    # exporter defaulted to ACTIVE_ACTIONS (only the action on
    # animation_data.action is written). Blender 4.x changed the default
    # to ACTIONS, which writes EVERY action in the file on every
    # per-clip export -- so the merged .glb ends up with idle/walk
    # duplicated, and each stray copy is sampled over the wrong scene
    # frame range. The shared lib is not ours to edit, so patch the
    # operator class here to restore the single-active-action behaviour
    # and name each clip after the action currently assigned.
    op_cls = bpy.types.EXPORT_SCENE_OT_gltf
    orig_execute = op_cls.execute

    def patched_execute(self, context):
        if self.export_animations:
            self.export_animation_mode = "ACTIVE_ACTIONS"
            # Blender 4.x also defaults gltf_export_anim_single_armature to
            # True, which force-includes EVERY armature action in each
            # per-clip export regardless of the mode.
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


def mat(name, color, rough=0.85, metal=0.0):
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

    # Worn leather boots (feet on the y=0 ground plane).
    parts.append(box("boot_l", (0.16, 0.11, 0.16), (-0.12, 0.03, 0.08), MAT_LEATHER))
    parts.append(box("boot_r", (0.16, 0.11, 0.16), (0.12, 0.03, 0.08), MAT_LEATHER))
    # Worn trousers (shins).
    parts.append(box("leg_l", (0.14, 0.14, 0.42), (-0.12, 0, 0.37), MAT_TROUSER))
    parts.append(box("leg_r", (0.14, 0.14, 0.42), (0.12, 0, 0.37), MAT_TROUSER))
    # Hips / belt line. Mesh part names must NOT collide with bone names:
    # the glTF importer appends "_2" to whichever it meets second, which
    # would silently rename the skeleton bones (hips -> hips_2). Hence
    # the "_block" mesh names against the clean bone names.
    parts.append(box("hips_block", (0.36, 0.22, 0.18), (0, 0, 0.67), MAT_TROUSER))
    # Ragged tunic torso.
    parts.append(box("torso", (0.44, 0.26, 0.50), (0, 0, 1.02), MAT_TUNIC))
    # Torn hem strips hanging from the tunic (front + back).
    parts.append(box("rag_a", (0.10, 0.02, 0.18), (-0.14, -0.13, 0.74), MAT_TUNIC))
    parts.append(box("rag_b", (0.09, 0.02, 0.24), (0.02, -0.13, 0.71), MAT_TUNIC))
    parts.append(box("rag_c", (0.11, 0.02, 0.14), (0.15, -0.13, 0.76), MAT_TUNIC))
    parts.append(box("rag_back", (0.22, 0.02, 0.20), (0, 0.13, 0.73), MAT_TUNIC))
    # Shoulders.
    parts.append(box("shoulder_l", (0.16, 0.18, 0.16), (-0.30, 0, 1.20), MAT_TUNIC))
    parts.append(box("shoulder_r", (0.16, 0.18, 0.16), (0.30, 0, 1.20), MAT_TUNIC))
    # Arms: ragged sleeves over bare forearms.
    parts.append(box("arm_upper_l", (0.11, 0.11, 0.26), (-0.32, 0, 1.02), MAT_TUNIC))
    parts.append(box("arm_upper_r", (0.11, 0.11, 0.26), (0.32, 0, 1.02), MAT_TUNIC))
    parts.append(box("arm_fore_l", (0.10, 0.10, 0.24), (-0.32, 0, 0.78), MAT_SKIN))
    parts.append(box("arm_fore_r", (0.10, 0.10, 0.24), (0.32, 0, 0.78), MAT_SKIN))
    parts.append(box("hand_l", (0.09, 0.09, 0.10), (-0.32, 0, 0.61), MAT_SKIN))
    parts.append(box("hand_r", (0.09, 0.09, 0.10), (0.32, 0, 0.61), MAT_SKIN))
    # Neck + head (mesh names "_block" -- see the hips note above).
    parts.append(box("neck_block", (0.10, 0.10, 0.08), (0, 0, 1.31), MAT_SKIN))
    head = sph("head_block", 0.135, (0, 0, 1.45), MAT_SKIN)
    add_mod(head, "DECIMATE", ratio=0.35)
    parts.append(head)
    # Hood: a shell sitting back over the crown, a cowl on the shoulders,
    # and a brim shading the brow -- the face stays a dark void.
    hood = sph("hood", 0.175, (0, 0.06, 1.48), MAT_HOOD, segments=14, ring_count=9)
    add_mod(hood, "DECIMATE", ratio=0.35)
    parts.append(hood)
    parts.append(box("hood_brim", (0.30, 0.16, 0.06), (0, -0.05, 1.60), MAT_HOOD))
    parts.append(box("cowl", (0.26, 0.22, 0.12), (0, 0.03, 1.30), MAT_HOOD))
    # The face is shadow: a dark band across the eyes, a cloth mask below.
    parts.append(box("face_shadow", (0.20, 0.05, 0.10), (0, -0.11, 1.46), MAT_SHADOW))
    parts.append(box("mask", (0.17, 0.05, 0.07), (0, -0.11, 1.36), MAT_CLOTH))
    # A ragged shoulder scarf tied at the chest (outlaw trim).
    parts.append(box("scarf", (0.30, 0.05, 0.10), (0, -0.12, 1.22), MAT_CLOTH))

    # Rusty blade held in the right hand: grip at the hand, blade
    # hanging down past the knee, a couple of rust blooms on the steel.
    parts.append(cyl("blade_grip", 0.024, 0.16, (0.33, -0.03, 0.57), material=MAT_LEATHER))
    parts.append(box("blade_guard", (0.11, 0.04, 0.03), (0.33, -0.03, 0.47), MAT_STEEL))
    parts.append(box("blade_steel", (0.055, 0.016, 0.40), (0.33, -0.03, 0.28), MAT_STEEL))
    parts.append(box("blade_tip", (0.035, 0.014, 0.08), (0.33, -0.03, 0.06), MAT_STEEL))
    parts.append(box("rust_a", (0.058, 0.018, 0.06), (0.33, -0.03, 0.36), MAT_RUST))
    parts.append(box("rust_b", (0.058, 0.018, 0.05), (0.33, -0.03, 0.18), MAT_RUST))

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

    # Chain up: hips -> spine -> chest -> neck -> head.
    bone("root", (0, 0, 0), (0, 0.01, 0))
    bone("hips", (0, 0, 0.67), (0, 0, 0.80), "root")
    bone("spine", (0, 0, 0.80), (0, 0, 1.00), "hips")
    bone("chest", (0, 0, 1.00), (0, 0, 1.26), "spine")
    bone("neck", (0, 0, 1.26), (0, 0, 1.36), "chest")
    bone("head", (0, 0, 1.36), (0, 0, 1.58), "neck")
    # Arms: shoulder -> elbow -> wrist.
    bone("arm_l", (-0.30, 0, 1.20), (-0.32, 0, 0.92), "chest")
    bone("forearm_l", (-0.32, 0, 0.92), (-0.32, 0, 0.66), "arm_l")
    bone("arm_r", (0.30, 0, 1.20), (0.32, 0, 0.92), "chest")
    bone("forearm_r", (0.32, 0, 0.92), (0.32, 0, 0.66), "arm_r")
    # Legs: thigh -> shin.
    bone("thigh_l", (-0.12, 0, 0.64), (-0.12, 0, 0.34), "hips")
    bone("shin_l", (-0.12, 0, 0.34), (-0.12, 0, 0.10), "thigh_l")
    bone("thigh_r", (0.12, 0, 0.64), (0.12, 0, 0.34), "hips")
    bone("shin_r", (0.12, 0, 0.34), (0.12, 0, 0.10), "thigh_r")

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def assign_weights(parts, arm):
    # Explicit vertex groups beat auto-weights for block-bodies: every
    # part gets a deterministic binding, no envelope spill between
    # adjacent boxes (the classic auto-weight smear on low-poly).
    groups = {
        "boot_l": ["shin_l"], "leg_l": ["thigh_l", "shin_l"],
        "boot_r": ["shin_r"], "leg_r": ["thigh_r", "shin_r"],
        "hips_block": ["hips"],
        "torso": ["spine", "chest"],
        "rag_a": ["spine"], "rag_b": ["spine"], "rag_c": ["spine"], "rag_back": ["spine"],
        "shoulder_l": ["arm_l"], "shoulder_r": ["arm_r"],
        "arm_upper_l": ["arm_l"], "arm_upper_r": ["arm_r"],
        "arm_fore_l": ["forearm_l"], "arm_fore_r": ["forearm_r"],
        "hand_l": ["forearm_l"], "hand_r": ["forearm_r"],
        "neck_block": ["neck"], "head_block": ["head"], "mask": ["head"], "face_shadow": ["head"],
        "hood": ["head"], "hood_brim": ["head"],
        "cowl": ["chest"], "scarf": ["chest"],
        "blade_grip": ["forearm_r"], "blade_guard": ["forearm_r"],
        "blade_steel": ["forearm_r"], "blade_tip": ["forearm_r"],
        "rust_a": ["forearm_r"], "rust_b": ["forearm_r"],
    }
    for p in parts:
        for gname in groups.get(p.name, ["root"]):
            g = p.vertex_groups.new(name=gname)
            g.add(list(range(len(p.data.vertices))), 1.0, "REPLACE")
        parent_keep(p, arm)
        mod = p.modifiers.new("Armature", "ARMATURE")
        mod.object = arm


def pose_arm(arm, arm_l=(0, -0.5, 0), forearm_l=(0, 0.7, 0), arm_r=(0, 0.3, 0), forearm_r=(0, -0.5, 0)):
    # Rest pose with an outlaw's guarded stance: both arms slightly
    # forward, the blade hand turned in. Applied once so the bind pose
    # IS the character pose (no T-pose artifacts in-game).
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    for name, rot in (("arm_l", arm_l), ("forearm_l", forearm_l), ("arm_r", arm_r), ("forearm_r", forearm_r)):
        pb = arm.pose.bones[name]
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = rot
    bpy.ops.pose.armature_apply()
    bpy.ops.object.mode_set(mode="OBJECT")


def animate(arm):
    # Two NLA clips -> two glTF animation samplers -> Godot AnimationPlayers.
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")

    # --- idle: breathe + blade-hand micro sway (48f) ---
    # NOTE: key EVERYTHING in QUATERNION space. Blender's glTF exporter
    # silently DROPS XYZ-euler bone rotation FCurves (it only writes
    # quaternion rotation tracks -- euler keys vanish and the .glb
    # exports with zero animations). key_quat converts euler->quaternion.
    idle = model_export_lib.make_action(arm, "idle")
    idle_keys = (
        ("spine",     [(1, (0, 0, 0)), (24, (0.02, 0, 0)), (48, (0, 0, 0))]),
        ("chest",     [(1, (0, 0, 0)), (24, (-0.02, 0, 0)), (48, (0, 0, 0))]),
        ("head",      [(1, (0, 0, 0)), (24, (0.03, 0, 0)), (48, (0, 0, 0))]),
        ("arm_r",     [(1, (0, 0.3, 0)), (24, (0.04, 0.3, 0)), (48, (0, 0.3, 0))]),
        ("forearm_r", [(1, (0, -0.5, 0)), (24, (-0.04, -0.5, 0)), (48, (0, -0.5, 0))]),
    )
    for name, frames in idle_keys:
        model_export_lib.key_quat(arm, name, frames)
    for t in idle.fcurves:
        for kp in t.keyframe_points:
            kp.interpolation = "SINE"

    # --- walk: 32f cycle on a CLEAN action (no bake pollution) ---
    # Key phases SAMPLE the sine at meaningful points (0, pi/2, pi,
    # 3pi/2, 2pi); phases landing on zero-crossings would key a flat
    # curve and the legs would never move.
    walk = model_export_lib.make_action(arm, "walk")
    swing = 0.55
    walk_frames = ((1, 0.0), (9, math.pi / 2), (17, math.pi), (25, 3 * math.pi / 2), (32, 2 * math.pi))
    walk_keys = (
        ("thigh_l",  [(f, (swing * math.sin(p), 0, 0)) for f, p in walk_frames]),
        ("thigh_r",  [(f, (-swing * math.sin(p), 0, 0)) for f, p in walk_frames]),
        ("shin_l",   [(f, (max(0.0, -0.6 * math.sin(p + 0.6)), 0, 0)) for f, p in walk_frames]),
        ("shin_r",   [(f, (max(0.0, 0.6 * math.sin(p + 0.6)), 0, 0)) for f, p in walk_frames]),
        ("arm_l",    [(f, (-0.3 * math.sin(p), 0.5, 0)) for f, p in walk_frames]),
        ("arm_r",    [(f, (0.3 * math.sin(p), 0.3, 0)) for f, p in walk_frames]),
        ("hips",     [(f, (0, 0.04 * math.sin(p), 0)) for f, p in walk_frames]),
    )
    for name, frames in walk_keys:
        model_export_lib.key_quat(arm, name, frames)

    # The exporter writes ONLY the action currently assigned to
    # animation_data.action -- NLA strips are ignored and a cleared
    # action means zero animations. Leave the LAST clip assigned;
    # export_model swaps the active action per clip and merges after.
    for a in (idle, walk):
        a.use_fake_user = True  # survive without an ADT slot
    arm.animation_data.action = walk

    bpy.ops.object.mode_set(mode="OBJECT")


# --- build ---
# Factory reset FIRST: read_factory_settings wipes the scene and with
# it any materials created before this line.
bpy.ops.wm.read_factory_settings(use_empty=True)

MAT_TUNIC = mat("m_tunic", COL_TUNIC, rough=0.95)
MAT_CLOTH = mat("m_cloth", COL_CLOTH, rough=0.95)
MAT_HOOD = mat("m_hood", COL_HOOD, rough=0.95)
MAT_LEATHER = mat("m_leather", COL_LEATHER, rough=0.8)
MAT_TROUSER = mat("m_trouser", COL_TROUSER, rough=0.95)
MAT_SKIN = mat("m_skin", COL_SKIN, rough=0.7)
MAT_STEEL = mat("m_steel", COL_STEEL, rough=0.6, metal=0.7)
MAT_RUST = mat("m_rust", COL_RUST, rough=0.85)
MAT_SHADOW = mat("m_shadow", COL_SHADOW, rough=0.9)

parts = build_body()
arm = build_rig()
pose_arm(arm)
assign_weights(parts, arm)
animate(arm)
patch_gltf_exporter_for_blender4()
model_export_lib.export_model(
    RIG, OUT, ["idle", "walk"],
    {"idle": 0.0, "walk": 1.6},  # 48f + 32f @ 30fps, same slot layout as the blacksmith
    base_out="/tmp/synmergia_models/_bandit_base.glb",
    clip_dir="/tmp/synmergia_models/_bandit_clips",
)

print("GEN_BANDIT_DONE -> " + OUT)
