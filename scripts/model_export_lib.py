# Shared Blender -> Godot glTF export library.
#
# Extracted from gen_blacksmith_model.py when the wolf joined: the
# export-once-per-clip + stdlib-merge + NLA-slot-fixup pipeline is
# model-agnostic. Generators build body + rig + actions, then call
# export_model(...) with their clip list.
#
# Blender 3.0 glTF exporter constraints (all proven experimentally --
# full writeup in labs/prd-3d-pipeline.md section 6):
#   1. XYZ-euler bone-rotation FCurves are SILENTLY DROPPED -- key in
#      QUATERNION space.
#   2. NLA strips are ignored; only the action on animation_data.action
#      is exported -> export once per clip, then merge.
#   3. The exporter SAMPLES THE SCENE frame range -- clamp scene
#      start/end to each action's own range or clips balloon.
#   4. Single-clip exports compact keys to time 0 ->
#      fix_clip_ranges.py rewrites input accessors into NLA slots
#      (shift each UNIQUE input accessor exactly once; never trim
#      trailing zero bytes from the binary chunk).

import json
import math
import os
import struct

import bpy  # blender-only module: this lib runs inside blender scripts

TMP_ROOT = "/tmp/synmergia_models"


def _padded_json(s):
	raw = s.encode("utf-8")
	while len(raw) % 4:
		raw += b" "
	return raw


def _padded_bin(b):
	while len(b) % 4:
		b += b"\x00"
	return b


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


def merge_glb(base_path, clip_paths, out_path):
	"""Merge clip animations into the base GLB. All exports come from
	the same scene, so node indices match 1:1; only the animation
	buffers/accessors/samplers need re-indexing."""
	base_js, base_bin = _read_glb(base_path)
	# NOTE: never strip trailing zeros from a binary chunk -- a real
	# accessor can end in 0x00 bytes (e.g. index 0). The chunk length
	# is already 4-aligned; use it verbatim.
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


def export_model(rig_name, out_path, clip_names, clip_starts, base_out=None, clip_dir=None):
	"""Export the skinned model once per animation clip, merge the
	single-animation GLBs, then place clips in their NLA time slots.

	rig_name:    name of the armature object in the scene
	out_path:    final .glb path (in-repo; the filename IS the registry)
	clip_names:  action names to export, e.g. ["idle", "walk"]
	clip_starts: {clip_name: start_seconds} NLA slot layout
	base_out/clip_dir: optional intermediate paths (default /tmp).

	Returns out_path.
	"""
	base_out = base_out or os.path.join(TMP_ROOT, "_base.glb")
	clip_dir = clip_dir or os.path.join(TMP_ROOT, "_clips")
	os.makedirs(os.path.dirname(base_out), exist_ok=True)
	os.makedirs(os.path.dirname(out_path), exist_ok=True)
	os.makedirs(clip_dir, exist_ok=True)

	bpy.ops.object.select_all(action="DESELECT")
	for ob in bpy.data.objects:
		if ob.type in {"ARMATURE", "MESH"}:
			ob.select_set(True)
	bpy.context.view_layer.objects.active = bpy.data.objects[rig_name]

	# 1) base export (no animations) -- the mesh/skin/material payload
	bpy.ops.export_scene.gltf(
		filepath=base_out,
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
	#    to the action's own range or clips balloon.
	clip_paths = []
	adt = bpy.data.objects[rig_name].animation_data
	scene = bpy.context.scene
	for clip in clip_names:
		act = bpy.data.actions[clip]
		adt.action = act
		fr = act.frame_range
		scene.frame_start = int(math.floor(fr[0]))
		scene.frame_end = int(math.ceil(fr[1]))
		path = os.path.join(clip_dir, clip + ".glb")
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
	merge_glb(base_out, clip_paths, out_path)

	# 4) place clips in their NLA time slots (stdlib post-processor;
	#    single-clip exports compact keys to time 0).
	import subprocess
	import sys as _sys
	repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
	try:
		subprocess.run([
			_sys.executable if _sys.executable else "python3",
			os.path.join(repo_root, "scripts", "fix_clip_ranges.py"),
			out_path,
		], check=True)
	except Exception as e:
		print("WARN: fix_clip_ranges failed (%s) -- run it manually" % e)

	print("EXPORT_MODEL_OUT=" + out_path)
	return out_path


def key_quat(arm, pb_name, frames):
	"""Key a pose bone's rotation in QUATERNION space (euler FCurves are
	dropped by the exporter). frames: [(frame, xyz_euler_radians)]."""
	from mathutils import Euler
	pb = arm.pose.bones[pb_name]
	pb.rotation_mode = "QUATERNION"
	for f, rot in frames:
		pb.rotation_quaternion = Euler(rot, "XYZ").to_quaternion()
		pb.keyframe_insert(data_path="rotation_quaternion", frame=f)


def make_action(arm, name):
	# Fresh action per clip. NEVER nla.bake between clips: baking
	# samples the evaluated pose and pollutes the next clip with the
	# previous clip's keys on every bone.
	if arm.animation_data is None:
		arm.animation_data_create()
	act = bpy.data.actions.new(name)
	arm.animation_data.action = act
	return act
