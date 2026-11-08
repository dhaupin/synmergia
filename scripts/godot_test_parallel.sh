#!/usr/bin/env bash
# DEPRECATED SHIM -- the parallel runner is now BUILT INTO the one runner.
#
# `scripts/godot_test_runner.sh` runs concurrently when that helps and
# serially when that is faster (single boot / JOBS=1), with the same laws
# this script used to own (warm import once, timing-sensitive probes on a
# JOBS=1 serial phase, --resume ledger, per-test logs, exit-iff-green).
#
# This file exists only so older callers (CI, docs, muscle memory) keep
# working: it forwards every argument to the one runner and exits with its
# status. Prefer calling `scripts/godot_test_runner.sh` directly.
#
# Usage (unchanged):
#   sh ./scripts/godot_test_parallel.sh [--all] [-j N] [--resume FILE] [names...]

set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "[runner] note: godot_test_parallel.sh is a shim; the parallel runner is built into godot_test_runner.sh" >&2
exec sh "${ROOT_DIR}/scripts/godot_test_runner.sh" "$@"
