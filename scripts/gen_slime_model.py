# Synmergia procedural model generator: slime.
#
# A blob-family enemy (HitboxProfile hitbox_blob): one squashed-sphere
# body, a lighter jelly crown, a drip, two eyes with specular glints,
# and a small mouth. Rides a minimal skeleton (root + body + two eye
# bones) and bakes two clips through the shared export pipeline
# (model_export_lib: export-once-per-clip + stdlib merge + NLA slots):
#
#   idle  -- a squash/bob breathing cycle (48f @ 30fps)
#   walk  -- a hop cycle (32f @ 30fps); enemy.gd swaps idle/walk with
#            AI movement, so the slime hops when it chases.
#
# The root bone carries BOTH the bob (local Y = world up on a vertical
# bone) and the squash (non-uniform local scale), pivoting at the
# ground so the body compresses downward.
#
# Usage:
#   blender --background --factory-startup --python scripts/gen_slime_model.py
#
# Deterministic: no rng anywhere; same input -> same .glb geometry.

import bpy
import math
import os
import sys
from mathutils import Matrix, Vector

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(_REPO_ROOT, "scripts"))
import model_export_lib


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
    # (bpy.ops.export_scene.gltf is regenerated per access, so the patch
    # must land on the operator class's execute, not the ops attribute.)
    op_cls = bpy.types.EXPORT_SCENE_OT_gltf
    orig_execute = op_cls.execute

    def patched_execute(self, context):
        if self.export_animations:
            self.export_animation_mode = "ACTIVE_ACTIONS"
            # Blender 4.x also defaults gltf_export_anim_single_armature to
            # True, which force-includes EVERY armature action in each
            # per-clip export regardless of the mode -- the clip then
            # carries the wrong action's keys. Off, the assigned action
            # alone is written.
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


OUT = os.path.join(_REPO_ROOT, "game", "models", "enemies", "enemy_slime.glb")
RIG = "rig_slime"

# Palette: meadow green body, bright jelly crown, near-black eyes with
# pale specular glints, dark mouth.
COL_BODY = (0.30, 0.70, 0.34, 1.0)
COL_CROWN = (0.55, 0.88, 0.45, 1.0)
COL_EYE = (0.05, 0.06, 0.07, 1.0)
COL_GLINT = (0.95, 0.97, 0.92, 1.0)
COL_MOUTH = (0.07, 0.06, 0.08, 1.0)

# Body ellipsoid: a sphere squashed on Z, resting its base on the ground.
BODY_CENTER = (0.0, 0.0, 0.35)
BODY_R = 0.46
BODY_ZS = 0.76


def mat(name, color, rough=0.5, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


def sph(name, r, loc, material, segments=12, ring_count=8, squash=(1.0, 1.0, 1.0)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=segments, ring_count=ring_count)
    o = bpy.context.active_object
    o.name = name
    if squash != (1.0, 1.0, 1.0):
        # Squash in MESH space: a skinned mesh's object transform is not
        # reliable across exporters, so bake the shape into the data.
        o.data.transform(Matrix.Diagonal(Vector((squash[0], squash[1], squash[2], 1.0))))
    o.data.materials.append(material)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def body_surface(dx, dy, dz, pull=1.0):
    # Point on the body ellipsoid along a direction (local dir, then the
    # Z squash is applied, then the object centre offset).
    length = math.sqrt(dx * dx + dy * dy + dz * dz)
    ux, uy, uz = dx / length, dy / length, dz / length
    return (BODY_CENTER[0] + ux * BODY_R * pull,
            BODY_CENTER[1] + uy * BODY_R * pull,
            BODY_CENTER[2] + uz * BODY_R * BODY_ZS * pull)


def parent_keep(ob, par):
    mw = ob.matrix_world.copy()
    ob.parent = par
    ob.matrix_world = mw


def build_body():
    # Mesh part names must NOT collide with bone names: the glTF importer
    # appends "_2" to whichever of the two it meets second, which would
    # silently rename the skeleton bones (body -> body_2). Hence the
    # "_orb"/"shell" mesh names against the clean "body"/"eye_*" bones.
    parts = []
    parts.append(sph("shell", BODY_R, BODY_CENTER, MAT_BODY, segments=16, ring_count=10, squash=(1.0, 1.0, BODY_ZS)))
    parts.append(sph("crown", 0.14, (0.0, 0.0, 0.66), MAT_CROWN, segments=12, ring_count=8, squash=(1.0, 1.0, 0.5)))
    parts.append(sph("drip", 0.08, (0.34, 0.04, 0.09), MAT_BODY, segments=10, ring_count=6))
    parts.append(sph("mouth", 0.07, body_surface(0.0, -0.90, -0.45, 0.93), MAT_MOUTH,
                     segments=10, ring_count=6, squash=(1.5, 0.6, 0.55)))

    eye_r = body_surface(0.34, -0.86, 0.28, 0.95)
    eye_l = body_surface(-0.34, -0.86, 0.28, 0.95)
    parts.append(sph("eye_r_orb", 0.085, eye_r, MAT_EYE, segments=12, ring_count=8))
    parts.append(sph("eye_l_orb", 0.085, eye_l, MAT_EYE, segments=12, ring_count=8))
    # Glints ride the same side (one light source): both shifted +X.
    parts.append(sph("glint_r", 0.03, (eye_r[0] + 0.03, eye_r[1] - 0.055, eye_r[2] + 0.045),
                     MAT_GLINT, segments=8, ring_count=6))
    parts.append(sph("glint_l", 0.03, (eye_l[0] + 0.03, eye_l[1] - 0.055, eye_l[2] + 0.045),
                     MAT_GLINT, segments=8, ring_count=6))
    return parts, eye_l, eye_r


def build_rig(eye_l, eye_r):
    bpy.ops.object.armature_add(radius=0.1, location=(0, 0, 0))
    arm = bpy.context.active_object
    arm.name = RIG
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones

    # The default "Bone" becomes the root: a short VERTICAL bone at the
    # ground so local Y is world up (bob) and local scale squashes the
    # whole blob from the floor.
    root = eb[0]
    root.name = "root"
    root.head = (0, 0, 0)
    root.tail = (0, 0, 0.14)

    def bone(name, head, tail, par):
        b = eb.new(name)
        b.head = head
        b.tail = tail
        b.parent = eb[par]
        return b

    bone("body", (0, 0, 0.10), (0, 0, 0.70), "root")
    bone("eye_l", eye_l, (eye_l[0], eye_l[1], eye_l[2] + 0.07), "root")
    bone("eye_r", eye_r, (eye_r[0], eye_r[1], eye_r[2] + 0.07), "root")

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def assign_weights(parts, arm):
    # Explicit vertex groups (no auto-weight smear on low-poly blobs).
    groups = {
        "shell": ["body"], "crown": ["body"], "drip": ["body"], "mouth": ["body"],
        "eye_l_orb": ["eye_l"], "glint_l": ["eye_l"],
        "eye_r_orb": ["eye_r"], "glint_r": ["eye_r"],
    }
    for p in parts:
        for gname in groups.get(p.name, ["body"]):
            g = p.vertex_groups.new(name=gname)
            g.add(list(range(len(p.data.vertices))), 1.0, "REPLACE")
        parent_keep(p, arm)
        mod = p.modifiers.new("Armature", "ARMATURE")
        mod.object = arm


def key_loc(arm, pb_name, frames):
    pb = arm.pose.bones[pb_name]
    for f, loc in frames:
        pb.location = loc
        pb.keyframe_insert(data_path="location", frame=f)


def key_scale(arm, pb_name, frames):
    pb = arm.pose.bones[pb_name]
    for f, sc in frames:
        pb.scale = sc
        pb.keyframe_insert(data_path="scale", frame=f)


def animate(arm):
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")

    # --- idle: 48f breathe -- rise + stretch, settle + squash, pivot at
    #     the ground (root local Y = up, local X/Z = the two ground axes).
    idle = model_export_lib.make_action(arm, "idle")
    key_loc(arm, "root", [
        (1, (0, 0.0, 0)), (12, (0, 0.05, 0)), (24, (0, 0.0, 0)),
        (36, (0, 0.035, 0)), (48, (0, 0.0, 0))])
    key_scale(arm, "root", [
        (1, (1.0, 1.0, 1.0)), (12, (0.94, 1.09, 0.94)), (24, (1.06, 0.90, 1.06)),
        (36, (0.97, 1.04, 0.97)), (48, (1.0, 1.0, 1.0))])
    model_export_lib.key_quat(arm, "root", [
        (1, (0, 0, 0)), (12, (0.02, 0, 0)), (24, (0, 0, 0)), (36, (-0.02, 0, 0)), (48, (0, 0, 0))])
    # Eyes drift left/right (local Y = yaw on a vertical bone).
    model_export_lib.key_quat(arm, "eye_l", [
        (1, (0, 0, 0)), (18, (0, 0.12, 0)), (30, (0, -0.12, 0)), (48, (0, 0, 0))])
    model_export_lib.key_quat(arm, "eye_r", [
        (1, (0, 0, 0)), (18, (0, 0.12, 0)), (30, (0, -0.12, 0)), (48, (0, 0, 0))])

    # --- walk: 32f HOP cycle -- load, launch, apex, fall, land squash,
    #     recover. Frame 32 returns to frame 1 so the loop is seamless.
    hop = model_export_lib.make_action(arm, "walk")
    key_loc(arm, "root", [
        (1, (0, 0.0, 0)), (5, (0, 0.02, 0)), (9, (0, 0.20, 0)), (16, (0, 0.30, 0)),
        (23, (0, 0.18, 0)), (27, (0, 0.0, 0)), (32, (0, 0.0, 0))])
    key_scale(arm, "root", [
        (1, (1.15, 0.85, 1.15)), (5, (1.02, 1.04, 1.02)), (9, (0.86, 1.24, 0.86)),
        (16, (1.0, 1.0, 1.0)), (23, (0.92, 1.12, 0.92)), (27, (1.18, 0.82, 1.18)),
        (32, (1.15, 0.85, 1.15))])
    model_export_lib.key_quat(arm, "root", [
        (1, (0.10, 0, 0)), (9, (-0.08, 0, 0)), (16, (0, 0, 0)),
        (27, (0.12, 0, 0)), (32, (0.10, 0, 0))])

    for a in (idle, hop):
        a.use_fake_user = True
    arm.animation_data.action = hop

    bpy.ops.object.mode_set(mode="OBJECT")


# --- build ---
# Factory reset FIRST (materials created before this line get wiped).
bpy.ops.wm.read_factory_settings(use_empty=True)

MAT_BODY = mat("m_body", COL_BODY, rough=0.35)
MAT_CROWN = mat("m_crown", COL_CROWN, rough=0.30)
MAT_EYE = mat("m_eye", COL_EYE, rough=0.20)
MAT_GLINT = mat("m_glint", COL_GLINT, rough=0.10)
MAT_MOUTH = mat("m_mouth", COL_MOUTH, rough=0.55)

parts, eye_l, eye_r = build_body()
arm = build_rig(eye_l, eye_r)
assign_weights(parts, arm)
animate(arm)
patch_gltf_exporter_for_blender4()
model_export_lib.export_model(
    RIG, OUT, ["idle", "walk"],
    {"idle": 0.0, "walk": 1.6},  # 48f + 32f @ 30fps, same slot layout as the wolf
    base_out="/tmp/synmergia_models/_slime_base.glb",
    clip_dir="/tmp/synmergia_models/_slime_clips",
)

print("GEN_SLIME_DONE -> " + OUT)
