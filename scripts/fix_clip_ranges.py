#!/usr/bin/env python3
# Fix clip time ranges in a merged .glb.
#
# Background: Blender 3.0's glTF exporter only writes the action on
# animation_data.action (NLA strips ignored), so gen_blacksmith_model.py
# exports each clip separately and merges them. Inside each single-clip
# export the keys are compacted to time 0 (e.g. walk keys at frames
# 20..30 export as 0.0..0.33s). The merger concatenates them verbatim,
# so the imported Godot clips all start at 0 and overlap.
#
# This script rewrites each merged animation's input accessors to place
# it in its NLA slot: idle [0, 1.6]s, walk [1.6, 2.667]s. The original
# clip's duration is preserved (idle keys are sparse; walk keys span
# 1.067s at 30fps). stdlib only; run AFTER the generator.
#
# Usage: python3 scripts/fix_clip_ranges.py [path/to/model.glb]
# Default path: game/models/npcs/npc_blacksmith_village.glb

import json
import struct
import sys

# NLA slots must match the exporter's strip layout (idle 48f, walk 32f
# at 30 fps => idle starts 0.0, walk starts 1.6).
CLIP_STARTS = {"idle": 0.0, "walk": 1.6}
FPS = 30.0


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, _ver, _length = struct.unpack("<III", data[:12])
    if magic != 0x46546C67:
        raise ValueError("not a glb: " + path)
    chunk_len = struct.unpack("<I", data[12:16])[0]
    js = json.loads(data[20:20 + chunk_len])
    # Bin chunk layout: [8-byte header: length + type][payload]. Slice
    # AFTER the header; never trim trailing zeros (a real accessor can
    # legitimately end in 0x00 bytes).
    bin_chunk = bytearray()
    pos = 20 + chunk_len
    while pos + 8 <= len(data):
        bin_len, bin_type = struct.unpack("<II", data[pos:pos + 8])
        if bin_type == 0x004E4942:  # BIN
            bin_chunk = bytearray(data[pos + 8:pos + 8 + bin_len])
            break
        pos += 8 + bin_len
    return js, bin_chunk


def write_glb(path, js, bin_data):
    raw = json.dumps(js, separators=(",", ":")).encode("utf-8")
    while len(raw) % 4:
        raw += b" "
    bin_data = bytes(bin_data)
    while len(bin_data) % 4:
        bin_data += b"\x00"
    total = 12 + 8 + len(raw) + 8 + len(bin_data)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(raw), 0x4E4F534A))
        f.write(raw)
        f.write(struct.pack("<II", len(bin_data), 0x004E4942))
        f.write(bin_data)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else \
        "game/models/npcs/npc_blacksmith_village.glb"
    js, bin_data = read_glb(path)
    changed = 0
    for anim in js.get("animations", []):
        name = anim.get("name", "")
        if name not in CLIP_STARTS:
            print("skip (no slot):", name)
            continue
        offset = CLIP_STARTS[name]
        # Samplers SHARE input accessors (5 walk samplers -> 1 input).
        # Dedupe or each shared accessor gets shifted N times
        # (the 5x1.6=8.0s bug). Shift each UNIQUE accessor once.
        unique_inputs = sorted({s["input"] for s in anim.get("samplers", [])})
        for acc_idx in unique_inputs:
            acc = js["accessors"][acc_idx]
            if acc.get("componentType") != 5126:  # FLOAT
                raise ValueError("input accessor not FLOAT")
            bv = js["bufferViews"][acc["bufferView"]]
            off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
            count = acc["count"]
            vals = struct.unpack_from("<%df" % count, bin_data, off)
            new = [v + offset for v in vals]
            struct.pack_into("<%df" % count, bin_data, off, *new)
            acc["min"] = [min(new)]
            acc["max"] = [max(new)]
            changed += 1
        print("fixed:", name, "-> start", offset, "s,",
              len(unique_inputs), "unique input accessor(s)")
    write_glb(path, js, bin_data)
    print("done:", path, "(%d accessors rescaled)" % changed)


if __name__ == "__main__":
    main()
