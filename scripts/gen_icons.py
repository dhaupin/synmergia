#!/usr/bin/env python3
"""Generate the catalog's placeholder icons.

Every icon_path in data/*.tres points at res://icons/... but the pngs
never existed -- an aspirational law. This script MINTS the files for
real so the path law becomes honest: scan every `icon_path` in
game/data/**/*.tres, derive a deterministic silhouette icon per path
(family color + shape motif + id-hash jitter), and write a real RGBA
PNG at the matching on-disk location under game/icons/ (or ui/icons/).

No dependencies beyond Python stdlib (zlib + struct for the PNG
chunks). Re-runs are idempotent: the deterministic math produces the
exact same bytes for the same path.

The icons are PLACEHOLDER art: silhouettes, not finished pixels. Real
art may replace them later; this script refuses to overwrite an
existing PNG unless --force.
"""

import hashlib
import re
import struct
import sys
import zlib
from pathlib import Path

GAME = Path(__file__).resolve().parent.parent / "game"
SIZE = 32
FORCE = "--force" in sys.argv

FAMILY_COLORS = {
    "achievements": (200, 170, 40),
    "ankh": (240, 220, 140),
    "buffs": (120, 210, 130),
    "currency": (230, 200, 80),
    "furnishings": (170, 130, 90),
    "houses": (176, 138, 96),
    "enemies": (170, 60, 160),
    "events": (150, 110, 230),
    "factions": (110, 130, 240),
    "items": (180, 180, 190),
    "mounts": (200, 120, 60),
    "portals": (130, 80, 220),
    "quests": (230, 190, 90),
    "resources": (150, 130, 100),
    "species": (90, 190, 230),
    "status": (220, 80, 60),
    "vehicles": (110, 140, 200),
    "waypoint": (240, 200, 100),
    "classes": (120, 160, 220),
}
DEFAULT_COLOR = (170, 170, 170)


def png_chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def write_png(path: Path, w: int, h: int, px: list) -> None:
    raw = b""
    for y in range(h):
        raw += b"\x00"
        for x in range(w):
            raw += struct.pack("BBBB", *px[y * w + x])
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", zlib.compress(raw, 9))
        + png_chunk(b"IEND", b"")
    )


def hash01(name: str) -> float:
    return int(hashlib.sha256(name.encode()).hexdigest()[:8], 16) / 0xFFFFFFFF


def tint(base, name: str, amt: float = 0.14):
    """Deterministic hue jitter so same-family icons do not read as twins."""
    j = (hash01(name) - 0.5) * 2.0 * amt
    r = round(base[0] * (1 + j))
    g = round(base[1] * (1 - abs(j) * 0.5))
    b = round(base[2] * (1 - j))
    return (max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))


# --- shape predicates: (x, y) in [0,32) -> coverage 0..1 -------------
def disc(x, y, cx=16, cy=16, r=11.0, ring=False):
    d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
    if ring:
        return 1.0 if abs(d - r) < 2.5 else 0.0
    return 1.0 if d <= r else 0.0


def diamond(x, y, r=13.0):
    return 1.0 if abs(x - 16) + abs(y - 16) <= r else 0.0


def square(x, y, half=10.0, rr=4.0):
    dx = abs(x - 16) - (half - rr)
    dy = abs(y - 16) - (half - rr)
    if dx <= 0 or dy <= 0:
        return 1.0 if abs(x - 16) <= half and abs(y - 16) <= half else 0.0
    return 1.0 if (dx * dx + dy * dy) <= rr * rr else 0.0


def blade(x, y):
    """A diagonal blade: a slanted bar with a small cross guard."""
    u = (x - 6) * 0.707 + (y - 26) * 0.707
    v = -(x - 6) * 0.707 + (y - 26) * 0.707
    if 4 <= v <= 8 and 2 <= u <= 24:
        return 1.0
    return 0.0


def flask(x, y):
    if disc(x, y, cx=16, cy=18, r=8.0):
        return 1.0
    if abs(x - 16) <= 3 and 8 <= y <= 12:
        return 1.0
    return 0.0


def trophy(x, y):
    if disc(x, y, ring=True, r=9.0) or disc(x, y, r=5.0):
        return 1.0
    if 24 <= y <= 28 and abs(x - 16) <= 6:
        return 1.0
    return 0.0


def chevron(x, y):
    if abs(y - 16) <= 7 and abs(x - 16) <= 11:
        return 1.0 if abs(x - 16) * 0.6 >= abs(y - 16) else 0.0
    return 0.0


def arch(x, y):
    if disc(x, y, cx=16, cy=20, r=11.0) and y >= 20:
        return 1.0
    if 8 <= y <= 20 and abs(x - 16) <= 2:
        return 1.0
    return 0.0


SHAPE_LADDER = (
    (("potion", "vial", "brew", "elixir", "tea", "draught"), flask),
    (("sword", "dagger", "spear", "axe"), blade),
    (("ore", "stone", "ingot", "timber", "scrap", "slag"), diamond),
    (("kelp", "pearl", "shell", "reed", "fiber"), lambda x, y: disc(x, y, r=10.0)),
    (
        ("helm", "boots", "legs", "gloves", "belt", "mail", "shield", "cloak"),
        square,
    ),
    (("coin", "sigil", "shard", "scrip", "favor", "gold", "gem"), lambda x, y: disc(x, y, ring=True)),
    (("bow", "staff"), chevron),
    (("quest", "writ", "seal", "collect", "hunter", "blood", "boss", "wolf",
      "wreck", "arena", "awaken", "herb", "explor"), trophy),
    (("mount", "gullwing", "pacer", "runner", "storm"), arch),
    (("house", "claim", "cottage", "hall"), arch),
    (("forge", "anvil", "workbench", "fireplace", "cauldron"), square),
)


def pick_shape(name: str):
    for keywords, shape in SHAPE_LADDER:
        for kw in keywords:
            if kw in name:
                return shape
    return diamond


def make_icon(path_str: str):
    if not (
        path_str.startswith("res://icons/") or path_str.startswith("res://ui/icons/")
    ):
        return None
    rel = path_str[len("res://") :]
    if "icons/" in rel:
        stem = rel.split("icons/", 1)[1].rsplit("/", 1)[0] if "/" in rel.split("icons/", 1)[1] else "waypoint"
        # res://icons/waypoint.png has no family dir
        if "/" not in rel.split("icons/", 1)[1]:
            stem = "waypoint"
    else:
        stem = "items"
    family = stem if stem in FAMILY_COLORS else "items"
    name = rel.rsplit("/", 1)[-1][:-4]
    col = tint(FAMILY_COLORS[family], path_str)
    shape = pick_shape(name)
    px = []
    for y in range(SIZE):
        for x in range(SIZE):
            a = shape(x, y)
            if a <= 0.0:
                on_edge = x in (0, 31) or y in (0, 31)
                px.append((20, 22, 26, 255) if on_edge else (0, 0, 0, 0))
            else:
                # Soft 1px edge: darker on the boundary row/column.
                edge = 0.62 if x in (0, 30, 31) or y in (0, 30, 31) else 1.0
                shear = 1.0 - 0.05 * abs(y - 16) / 16.0
                j = (hash01(name) - 0.5) * 2.0 * 0.06
                px.append(
                    (
                        max(0, min(255, round(col[0] * edge * shear * (1 + j * 0.4)))),
                        max(0, min(255, round(col[1] * edge * shear))),
                        max(0, min(255, round(col[2] * edge * shear * (1 - j * 0.4)))),
                        255,
                    )
                )
    write_png(GAME / rel, SIZE, SIZE, px)
    return rel


def main() -> None:
    pat = re.compile(r'icon_path\s*=\s*"([^"]+)"')
    paths: set = set()
    for tres in GAME.rglob("*.tres"):
        for m in pat.finditer("".join(tres.read_text(errors="ignore"))):
            p = m.group(1)
            if p.startswith("res://"):
                paths.add(p)
    written, kept, blocked = 0, 0, []
    for p in sorted(paths):
        f = GAME / p[len("res://") :]
        if f.exists() and not FORCE:
            kept += 1
            continue
        if make_icon(p) is None:
            blocked.append(p)
            continue
        written += 1
    residue = [p for p in sorted(paths) if not (GAME / p[len("res://") :]).exists()]
    print(
        f"gen_icons: {len(paths)} referenced, {written} mints, {kept} kept, "
        f"residue {len(residue)}"
    )
    for m in residue:
        print("  MISSING:", m)
    return 0 if not residue else 1


if __name__ == "__main__":
    sys.exit(main())
