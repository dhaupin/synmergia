#!/usr/bin/env bash
# lane_setup.sh -- make a fresh lane worktree ready. RUN THIS FIRST in any lane.
#
# A lane gets its own git worktree off the parent HEAD, and `node_modules/`
# is gitignored -- so a fresh worktree has NO installed deps and `import
# 'gamestruct'` from the repo root FAILS (ERR_MODULE_NOT_FOUND), even though
# the sibling source repos are readable on this machine. This script closes
# that gap and warms the Godot import cache (a fresh worktree has no
# .godot/, and a receipt that runs before the import hangs on a type it
# cannot resolve).
#
# What it does (all idempotent, all best-effort):
#   1. symlinks node_modules/gamestruct -> /workspace/gamestruct (the npm
#      dep pinned in package.json; the source repo IS the package).
#   2. warms the Godot import (godot --headless --path game --import).
#   3. prints what it found so a lane can prove its own readiness.
#
# The vant sibling is read at /workspace/vant (not an npm dep of synmergia);
# a lane that needs it reads that path directly.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 1. the gamestruct npm dep (gitignored node_modules is empty in a worktree).
mkdir -p node_modules
if [ ! -e node_modules/gamestruct ]; then
    ln -s /workspace/gamestruct node_modules/gamestruct 2>/dev/null || true
fi
if [ -e node_modules/gamestruct/package.json ]; then
    GS_VER="$(grep -m1 '"version"' node_modules/gamestruct/package.json | cut -d'"' -f4)"
else
    GS_VER="MISSING"
fi

# 2. warm the Godot import cache (a fresh worktree has no .godot/).
if command -v godot >/dev/null 2>&1; then
    godot --headless --path game --import >/dev/null 2>&1 || true
fi
GODOT_STATE="cold"
[ -d game/.godot ] && GODOT_STATE="warm"

echo "[lane_setup] root:      $ROOT"
echo "[lane_setup] gamestruct: $GS_VER (node_modules/gamestruct -> $(readlink node_modules/gamestruct 2>/dev/null || echo 'no symlink'))"
echo "[lane_setup] vant:       $( [ -d /workspace/vant ] && echo 'readable at /workspace/vant' || echo MISSING )"
echo "[lane_setup] godot cache: $GODOT_STATE"
echo "[lane_setup] ready"
