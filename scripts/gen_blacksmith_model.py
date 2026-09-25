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
import json
import math
import os
import shutil
import struct
from mathutils import Euler

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Final artifact lands IN THE REPO (filename == NPCData id, the model
# registry per prd-3d-pipeline.md). Intermediates stay in /tmp.
OUT = os.path.join(_REPO_ROOT, "game", "models", "npcs", "npc_blacksmith_village.glb")
BASE_OUT = "/tmp/synmergia_models/_base.glb"
CLIP_DIR = "/tmp/synmergia_models/_clips"

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
    """Export the skinned model once per animation clip and merge the
    single-animation GLBs into one .glb. Returns the output path."""
    os.makedirs(os.path.dirname(BASE_OUT), exist_ok=True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in bpy.data.objects:
        if ob.type in {"ARMATURE", "MESH"}:
            ob.select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects["rig_blacksmith"]

    # 1) base export (no animations) -- the mesh/skin/material payload
    bpy.ops.export_scene.gltf(
        filepath=BASE_OUT,
        export_format="GLB",
        export_yup=True,
        export_animations=False,
        export_apply=True,
        export_skins=True,
        export_morph=False,
        export_current_frame=False,
    )

    # 2) one export per clip: the exporter only writes the action
    #    currently on animation_data.action (NLA strips are ignored).
    #    It also SAMPLES THE SCENE frame range, so clamp scene_start/end
    #    to the action's own range or clips balloon (walk 32f exported
    #    as 88f because a leftover scene_end=88 resampled everything).
    clip_paths = []
    adt = bpy.data.objects["rig_blacksmith"].animation_data
    scene = bpy.context.scene
    for clip in anim_clip_names:
        act = bpy.data.actions[clip]
        adt.action = act
        fr = act.frame_range
        scene.frame_start = int(math.floor(fr[0]))
        scene.frame_end = int(math.ceil(fr[1]))
        path = os.path.join(CLIP_DIR, clip + ".glb")
        os.makedirs(CLIP_DIR, exist_ok=True)
        bpy.ops.export_scene.gltf(
            filepath=path,
            export_format="GLB",
            export_yup=True,
            export_animations=True,
            export_apply=True,
            export_skins=True,
            export_morph=False,
            export_current_frame=False,
        )
        clip_paths.append(path)
    adt.action = None

    # 3) merge into the final .glb
    merge_glb(BASE_OUT, clip_paths, OUT)
    print("SMOKE_MODEL_OUT=" + OUT)
    return OUT


def _read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _ver, _length = struct.unpack("<III", data[:12])
    if magic != 0x46546C67:
        raise ValueError("not a glb: " + path)
    chunk_len = struct.unpack("<I", data[12:16])[0]
    js = json.loads(data[20:20 + chunk_len])
    # Bin chunk layout: [8-byte header: length + type][payload]. Slice
    # AFTER the header. Every file's payload offsets are relative to
    # the payload start; including the header here shifted every clip
    # buffer by 8 bytes and corrupted index buffers (Godot:
    # "indices_w out of bounds").
    bin_chunk = b""
    pos = 20 + chunk_len
    while pos + 8 <= len(data):
        bin_len, bin_type = struct.unpack("<II", data[pos:pos + 8])
        if bin_type == 0x004E4942:  # BIN
            bin_chunk = data[pos + 8:pos + 8 + bin_len]
            break
        pos += 8 + bin_len
    return js, bin_chunk


def _padded_json(s):
    raw = s.encode("utf-8")
    while len(raw) % 4:
        raw += b" "
    return raw


def _padded_bin(b):
    while len(b) % 4:
        b += b"\x00"
    return b


def merge_glb(base_path, clip_paths, out_path):
    """Merge clip animations into the base GLB. All exports come from
    the same scene, so node indices match 1:1; only the animation
    buffers/accessors/samplers need re-indexing."""
    base_js, base_bin = _read_glb(base_path)
    # NOTE: never strip trailing zeros from a binary chunk -- a real
    # accessor can end in 0x00 bytes (e.g. index 0). Stripping corrupts
    # buffers (Godot: "indices_w out of bounds"). The chunk length is
    # already 4-aligned; use it verbatim.
    if "animations" not in base_js:
        base_js["animations"] = []

    for clip_path in clip_paths:
        js, cbin = _read_glb(clip_path)
        anims = js.get("animations", [])
        if not anims:
            print("WARN: clip exported zero animations: " + clip_path)
            continue
        # re-index accessors/bufferViews from the clip into the base
        node_map = {}  # clip node idx -> base node idx (by name)
        base_by_name = {n.get("name", ""): i for i, n in enumerate(base_js["nodes"])}
        for ci, cn in enumerate(js["nodes"]):
            node_map[ci] = base_by_name.get(cn.get("name", ""), 0)
        acc_off = len(base_js["accessors"])
        bv_off = len(base_js["bufferViews"])
        bin_off = len(base_bin)
        for bv in js.get("bufferViews", []):
            nbv = dict(bv)
            nbv["buffer"] = 0
            nbv["byteOffset"] = bv.get("byteOffset", 0) + bin_off
            base_js["bufferViews"].append(nbv)
        for acc in js.get("accessors", []):
            nacc = dict(acc)
            nacc["bufferView"] = acc.get("bufferView", 0) + bv_off
            base_js["accessors"].append(nacc)
        base_bin += cbin
        for anim in anims:
            nanim = {"name": anim.get("name", "clip"), "samplers": [], "channels": []}
            for s in anim.get("samplers", []):
                ns = dict(s)
                ns["input"] = s["input"] + acc_off
                ns["output"] = s["output"] + acc_off
                nanim["samplers"].append(ns)
            for ch in anim.get("channels", []):
                nch = dict(ch)
                nch["sampler"] = ch["sampler"]  # sampler idx is local, stays
                nch["target"] = dict(ch["target"])
                if "node" in nch["target"]:
                    nch["target"]["node"] = node_map.get(nch["target"]["node"], 0)
                nanim["channels"].append(nch)
            base_js["animations"].append(nanim)
        print("MERGE: +", anims[0].get("name"), len(anims), "anim(s) from", os.path.basename(clip_path))

    _write_glb(out_path, base_js, base_bin)


def _write_glb(out_path, js, bin_data):
    js_bytes = _padded_json(json.dumps(js, separators=(",", ":")))
    bin_bytes = _padded_bin(bin_data)
    total = 12 + 8 + len(js_bytes) + 8 + len(bin_bytes)
    with open(out_path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js_bytes), 0x4E4F534A))
        f.write(js_bytes)
        f.write(struct.pack("<II", len(bin_bytes), 0x004E4942))
        f.write(bin_bytes)


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

# Post-process: put each clip in its NLA time slot. Single-clip exports
# compact keys to time 0 (walk frames 20..30 export as 0.0..0.33s), so
# without this every clip starts at 0 and they overlap in Godot.
import subprocess
import sys as _sys
_repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
try:
    subprocess.run([
        _sys.executable if _sys.executable else "python3",
        os.path.join(_repo_root, "scripts", "fix_clip_ranges.py"),
        OUT,
    ], check=True)
except Exception as e:
    print("WARN: fix_clip_ranges failed (%s) -- run it manually" % e)

print("GEN_BLACKSMITH_DONE -> " + OUT)
