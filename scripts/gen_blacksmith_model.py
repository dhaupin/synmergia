# Synmergia procedural model generator: village blacksmith.
#
# Builds a stylized low-poly blacksmith from salvaged-block primitives
# (prd-world.md aesthetic: scarcity, assembled from salvage, no factory
# lines), parents it to a meta-rig skeleton, auto-weights, bakes two
# NLA clips (idle + walk), and exports .glb named after the NPCData id
# (the filename IS the model registry -- prd-3d-pipeline.md).
#
# Blender 3.0 glTF exporter constraints (all proven experimentally):
#   1. XYZ-euler bone-rotation FCurves are SILENTLY DROPPED -- key in
#      QUATERNION space or you export zero animations.
#   2. NLA strips are IGNORED on export.
#   3. ONLY the action currently assigned to animation_data.action is
#      exported -- one animation per export call.
# So: export the static model once, export once per clip, then merge
# the single-animation GLBs with a small stdlib merger below.
#
# Usage:
#   blender --background --factory-startup --python scripts/gen_blacksmith_model.py
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

# Final artifact lands IN THE REPO (filename == NPCData id, the model
# registry per prd-3d-pipeline.md). Intermediates stay in /tmp.
OUT = os.path.join(_REPO_ROOT, "game", "models", "npcs", "npc_blacksmith_village.glb")

# Palette: soot leather, forge-iron, hammered copper, old-world cloth.
COL_SOOT = (0.055, 0.05, 0.048, 1.0)
COL_APRON = (0.09, 0.075, 0.06, 1.0)
COL_SKIN = (0.55, 0.38, 0.26, 1.0)
COL_IRON = (0.20, 0.20, 0.22, 1.0)
COL_COPPER = (0.55, 0.32, 0.16, 1.0)
COL_CLOTH = (0.16, 0.13, 0.10, 1.0)


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

    # Boots (feet at y=0 ground plane).
    parts.append(box("boot_l", (0.16, 0.10, 0.16), (-0.12, 0.05, 0.08), MAT_SOOT))
    parts.append(box("boot_r", (0.16, 0.10, 0.16), (0.12, 0.05, 0.08), MAT_SOOT))
    # Lower legs.
    parts.append(box("leg_l", (0.14, 0.14, 0.42), (-0.12, 0, 0.37), MAT_CLOTH))
    parts.append(box("leg_r", (0.14, 0.14, 0.42), (0.12, 0, 0.37), MAT_CLOTH))
    # Hips block.
    parts.append(box("hips", (0.36, 0.22, 0.18), (0, 0, 0.67), MAT_CLOTH))
    # Torso: sturdy barrel chest.
    parts.append(box("torso", (0.44, 0.26, 0.50), (0, 0, 1.02), MAT_CLOTH))
    # Blacksmith's apron: the signature plate over the front.
    parts.append(box("apron", (0.34, 0.03, 0.52), (0, -0.155, 0.92), MAT_APRON))
    # Shoulders.
    parts.append(box("shoulder_l", (0.16, 0.18, 0.16), (-0.30, 0, 1.20), MAT_CLOTH))
    parts.append(box("shoulder_r", (0.16, 0.18, 0.16), (0.30, 0, 1.20), MAT_CLOTH))
    # Arms (upper + forearm) built straight down; the rig poses them.
    parts.append(box("arm_upper_l", (0.11, 0.11, 0.26), (-0.32, 0, 1.02), MAT_CLOTH))
    parts.append(box("arm_upper_r", (0.11, 0.11, 0.26), (0.32, 0, 1.02), MAT_CLOTH))
    parts.append(box("arm_fore_l", (0.10, 0.10, 0.24), (-0.32, 0, 0.78), MAT_SKIN))
    parts.append(box("arm_fore_r", (0.10, 0.10, 0.24), (0.32, 0, 0.78), MAT_SKIN))
    # Hands.
    parts.append(box("hand_l", (0.09, 0.09, 0.10), (-0.32, 0, 0.61), MAT_SKIN))
    parts.append(box("hand_r", (0.09, 0.09, 0.10), (0.32, 0, 0.61), MAT_SKIN))
    # Neck + head.
    parts.append(box("neck", (0.10, 0.10, 0.08), (0, 0, 1.31), MAT_SKIN))
    head = sph("head", 0.135, (0, 0, 1.45), MAT_SKIN)
    add_mod(head, "DECIMATE", ratio=0.35)
    parts.append(head)
    # Beard: the smith distinction.
    parts.append(box("beard", (0.16, 0.08, 0.16), (0, -0.10, 1.36), MAT_SOOT))
    # Heavy brows.
    parts.append(box("brow", (0.22, 0.05, 0.03), (0, -0.12, 1.50), MAT_SOOT))

    # Smithy details: copper wrist bands + shoulder pauldron plate.
    parts.append(cyl("band_wrist_l", 0.065, 0.05, (-0.32, 0, 0.68), rot=(math.pi / 2, 0, 0), material=MAT_COPPER))
    parts.append(cyl("band_wrist_r", 0.065, 0.05, (0.32, 0, 0.68), rot=(math.pi / 2, 0, 0), material=MAT_COPPER))
    parts.append(box("pauldron_l", (0.12, 0.20, 0.05), (-0.30, 0, 1.29), MAT_IRON))
    parts.append(box("pauldron_r", (0.12, 0.20, 0.05), (0.30, 0, 1.29), MAT_IRON))

    for p in parts:
        add_mod(p, "EDGE_SPLIT", split_angle=0.5)
    return parts


def build_rig():
    bpy.ops.object.armature_add(radius=0.1, location=(0, 0, 0))
    arm = bpy.context.active_object
    arm.name = "rig_blacksmith"
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
        "hips": ["hips"],
        "torso": ["spine", "chest"],
        "apron": ["spine", "chest"],
        "shoulder_l": ["arm_l"], "shoulder_r": ["arm_r"],
        "arm_upper_l": ["arm_l"], "arm_upper_r": ["arm_r"],
        "arm_fore_l": ["forearm_l"], "arm_fore_r": ["forearm_r"],
        "hand_l": ["forearm_l"], "hand_r": ["forearm_r"],
        "neck": ["neck"], "head": ["head"], "beard": ["head"], "brow": ["head"],
        "band_wrist_l": ["forearm_l"], "band_wrist_r": ["forearm_r"],
        "pauldron_l": ["arm_l"], "pauldron_r": ["arm_r"],
    }
    for p in parts:
        for gname in groups.get(p.name, ["root"]):
            g = p.vertex_groups.new(name=gname)
            g.add(list(range(len(p.data.vertices))), 1.0, "REPLACE")
        parent_keep(p, arm)
        mod = p.modifiers.new("Armature", "ARMATURE")
        mod.object = arm


def pose_arm(arm, arm_l=(0, -0.5, 0), forearm_l=(0, 0.7, 0), arm_r=(0, 0.3, 0), forearm_r=(0, -0.5, 0)):
    # Rest pose with a smithy stance: arms slightly forward, right
    # forearm raised mid-grip. Applied once so the bind pose IS the
    # character pose (no T-pose artifacts in-game).
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    for name, rot in (("arm_l", arm_l), ("forearm_l", forearm_l), ("arm_r", arm_r), ("forearm_r", forearm_r)):
        pb = arm.pose.bones[name]
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = rot
    bpy.ops.pose.armature_apply()
    bpy.ops.object.mode_set(mode="OBJECT")


def make_action(arm, name):
    # Fresh action per clip. NEVER nla.bake between clips: baking
    # samples the evaluated pose and pollutes the next clip with the
    # previous clip's keys on every bone (the walk clip came out 48
    # frames long with idle keys baked into spine/chest/forearm).
    if arm.animation_data is None:
        arm.animation_data_create()
    act = bpy.data.actions.new(name)
    arm.animation_data.action = act
    return act


def animate(arm):
    # Two NLA clips -> two glTF animation samplers -> Godot AnimationPlayers.
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")

    # --- idle: breathe + hammer-hand micro sway (48f) ---
    # NOTE: key EVERYTHING in QUATERNION space. Blender 3.0's glTF
    # exporter silently DROPS XYZ-euler bone rotation FCurves (it only
    # writes quaternion rotation tracks -- euler keys vanish and the
    # .glb exports with zero animations). Pose math is identical; the
    # only change is euler->quaternion conversion per frame.
    idle = make_action(arm, "idle")

    def key_quat(pb_name, frames):
        pb = arm.pose.bones[pb_name]
        pb.rotation_mode = "QUATERNION"
        for f, rot in frames:
            pb.rotation_quaternion = Euler(rot, "XYZ").to_quaternion()
            pb.keyframe_insert(data_path="rotation_quaternion", frame=f)

    idle_keys = (
        ("spine",     [(1, (0, 0, 0)), (24, (0.02, 0, 0)), (48, (0, 0, 0))]),
        ("chest",     [(1, (0, 0, 0)), (24, (-0.02, 0, 0)), (48, (0, 0, 0))]),
        ("arm_r",     [(1, (0, 0.3, 0)), (24, (0.04, 0.3, 0)), (48, (0, 0.3, 0))]),
        ("forearm_r", [(1, (0, -0.5, 0)), (24, (-0.04, -0.5, 0)), (48, (0, -0.5, 0))]),
    )
    for name, frames in idle_keys:
        key_quat(name, frames)
    for t in idle.fcurves:
        for kp in t.keyframe_points:
            kp.interpolation = "SINE"

    # --- walk: 32f cycle on a CLEAN action (no bake pollution) ---
    walk = make_action(arm, "walk")
    swing = 0.55
    # NOTE: same QUATERNION keying as idle -- see the note above.
    # Key phases must SAMPLE the sine at meaningful points (0, pi/2, pi,
    # 3pi/2, 2pi). The original multipliers-of-pi phases (0, pi, 2pi, ...)
    # landed on zero-crossings, so sin(phase) was ~0 at EVERY key and the
    # legs never moved. (Flat curves + remove_immutable_tracks = dead
    # clips.)
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
        key_quat(name, frames)

    # Blender 3.0 glTF exporter exports ONLY the action currently
    # assigned to arm.animation_data.action -- NLA strips are ignored
    # and a cleared action means zero animations. So: leave the LAST
    # clip assigned here; export() swaps the active action per clip
    # and merges the single-anim GLBs afterwards.
    for a in (idle, walk):
        a.use_fake_user = True  # survive without an ADT slot
    arm.animation_data.action = walk

    bpy.ops.object.mode_set(mode="OBJECT")


def export(anim_clip_names):
    """Thin wrapper over the shared pipeline. NLA slots: idle 48f,
    walk 32f at 30 fps -> idle starts 0.0s, walk 1.6s."""
    return model_export_lib.export_model(
        "rig_blacksmith", OUT, anim_clip_names,
        {"idle": 0.0, "walk": 1.6},
        base_out=os.path.join(model_export_lib.TMP_ROOT, "_base.glb"),
        clip_dir=os.path.join(model_export_lib.TMP_ROOT, "_clips"),
    )


# --- build ---
# Factory reset FIRST: read_factory_settings wipes the scene and with
# it any materials created before this line (learned the hard way:
# "StructRNA of type Material has been removed").
bpy.ops.wm.read_factory_settings(use_empty=True)

MAT_SOOT = mat("m_soot", COL_SOOT)
MAT_APRON = mat("m_apron", COL_APRON, rough=0.95)
MAT_SKIN = mat("m_skin", COL_SKIN, rough=0.7)
MAT_IRON = mat("m_iron", COL_IRON, rough=0.45, metal=0.8)
MAT_COPPER = mat("m_copper", COL_COPPER, rough=0.35, metal=0.9)
MAT_CLOTH = mat("m_cloth", COL_CLOTH, rough=0.95)

parts = build_body()
arm = build_rig()
pose_arm(arm)
assign_weights(parts, arm)
animate(arm)
export(["idle", "walk"])

print("GEN_BLACKSMITH_DONE -> " + OUT)
